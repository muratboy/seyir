import 'dart:math';

import 'package:intl/intl.dart';

import '../data/models.dart';
import '../logic/text_match.dart';
import '../logic/time_parser.dart';
import '../services/nl_parser.dart';

/// Hızlı Todo ekleme sırasında metinden çıkarılan tarih ve aktivite önerileri.
class TodoParsedResult {
  final String cleanTitle;
  final DateTime? date;
  final String? dateKeyword;
  final Activity? suggestedActivity;
  final double? suggestedAmount;
  final String? suggestedUnit;

  const TodoParsedResult({
    required this.cleanTitle,
    this.date,
    this.dateKeyword,
    this.suggestedActivity,
    this.suggestedAmount,
    this.suggestedUnit,
  });

  String? get dueDateString => date != null ? DateFormat('yyyy-MM-dd').format(date!) : null;
}

class TodoInputParser {
  /// Metinden tarih ifadesini, bağlı aktiviteyi ve hedef miktarı ayrıştırır.
  static TodoParsedResult parse(
    String input, {
    required List<Activity> activities,
    required List<Measure> measures,
    DateTime? now,
  }) {
    final currentNow = now ?? DateTime.now();

    final trimmed = input.trim();
    if (trimmed.isEmpty) {
      return const TodoParsedResult(cleanTitle: '');
    }

    final timeResult = TimeParser.parse(
      trimmed,
      direction: TemporalDirection.future,
      now: currentNow,
    );

    final detectedDate = timeResult.hasExplicitDate
        ? DateTime(timeResult.dateTime.year, timeResult.dateTime.month, timeResult.dateTime.day)
        : null;
    final matchedKeyword = timeResult.dateKeyword;
    String cleanTitle = timeResult.cleanedText;
    if (cleanTitle.isEmpty) {
      cleanTitle = trimmed;
    }

    // 3. Aktivite ve miktar çıkarımı: hedef miktar hesabı için süreler birleştirilir
    Activity? matchedAct;
    double? suggestedAmount;
    String? suggestedUnit;

    final analysisText = TimeParser.collapseCompoundDurations(cleanTitle);

    if (activities.isNotEmpty) {
      final nlResult = NaturalLanguageParser.parse(
        analysisText,
        activities: activities,
        measures: measures,
        allowCommands: true,
      );

      if (nlResult.matchedActivity != null) {
        matchedAct = nlResult.matchedActivity;
      } else {
        // text_match matchScore ile mevcut aktiviteler taranır
        final cleanWords = analysisText
            .toLowerCase()
            .split(' ')
            .where((w) => !w.contains(RegExp(r'\d')) && w != 'dk' && w != 'dakika' && w != 'saat' && w != 'sa')
            .toList();

        double bestScore = 0.0;
        for (final act in activities) {
          final actNorm = act.norm;
          for (final cw in cleanWords) {
            final cwNorm = normalizeTr(cw);
            if (cwNorm.length < 2) continue;
            var s = matchScore(cwNorm, actNorm);
            if (actNorm.startsWith(cwNorm)) s = max(s, 85.0);
            if (cwNorm.startsWith(actNorm)) s = max(s, 85.0);
            if (cwNorm.length >= 3 && actNorm.contains(cwNorm)) s = max(s, 75.0);
            if (s > 40 && s > bestScore) {
              bestScore = s;
              matchedAct = act;
            }
          }
        }
      }

      final m = nlResult.matchedMeasure;
      final mUnitId = m?.unitId;
      final mUnit = mUnitId != null ? builtinUnits.where((u) => u.id == mUnitId).firstOrNull : null;

      final wordsLower = analysisText.toLowerCase().split(RegExp(r'\s+'));
      final hasSecond = wordsLower.any((w) => w.contains('saniye') || w == 'sn' || w.startsWith('sn'));
      final hasMinute = wordsLower.any((w) => w.contains('dakika') || w == 'dk' || w.startsWith('dk'));
      final hasHour = wordsLower.any((w) => w.contains('saat') || w == 'sa');

      if (mUnit != null && mUnit.id == 'sn') {
        suggestedAmount = nlResult.quantity;
        suggestedUnit = 'sn';
      } else if (hasSecond) {
        suggestedAmount = nlResult.hasExplicitQuantity ? nlResult.quantity : 60.0;
        suggestedUnit = 'sn';
      } else if (mUnit != null && mUnit.dim == 'time') {
        // Süre birimleri dakikaya normalize edilir (1 sa -> 60 dk, 30 dk -> 30 dk)
        suggestedAmount = mUnitId == 'sa' ? (nlResult.quantity * 60) : nlResult.quantity;
        suggestedUnit = 'dk';
      } else if (hasMinute) {
        suggestedAmount = nlResult.hasExplicitQuantity ? nlResult.quantity : 30.0;
        suggestedUnit = 'dk';
      } else if (hasHour) {
        suggestedAmount = (nlResult.hasExplicitQuantity ? nlResult.quantity : 1.0) * 60;
        suggestedUnit = 'dk';
      } else if (nlResult.targetMinutes != null) {
        suggestedAmount = nlResult.targetMinutes!.toDouble();
        suggestedUnit = 'dk';
      } else if (nlResult.hasExplicitQuantity) {
        suggestedAmount = nlResult.quantity;
        suggestedUnit = mUnit?.id ?? m?.unitId ?? mUnit?.symbol ?? m?.name;
      }
    }

    return TodoParsedResult(
      cleanTitle: cleanTitle,
      date: detectedDate,
      dateKeyword: matchedKeyword,
      suggestedActivity: matchedAct,
      suggestedAmount: suggestedAmount,
      suggestedUnit: suggestedUnit,
    );
  }
}
