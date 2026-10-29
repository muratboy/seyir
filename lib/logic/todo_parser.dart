import 'dart:math';

import 'package:intl/intl.dart';

import '../data/models.dart';
import '../logic/text_match.dart';
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
  /// Haftanın gün adları haritası (1 = Pazartesi, 7 = Pazar).
  static const Map<String, int> _weekdays = {
    'pazartesi': 1,
    'monday': 1,
    'mon': 1,
    'salı': 2,
    'sali': 2,
    'tuesday': 2,
    'tue': 2,
    'çarşamba': 3,
    'carsamba': 3,
    'wednesday': 3,
    'wed': 3,
    'perşembe': 4,
    'persembe': 4,
    'thursday': 4,
    'thu': 4,
    'cuma': 5,
    'friday': 5,
    'fri': 5,
    'cumartesi': 6,
    'saturday': 6,
    'sat': 6,
    'pazar': 7,
    'sunday': 7,
    'sun': 7,
  };

  /// Metinden tarih ifadesini, bağlı aktiviteyi ve hedef miktarı ayrıştırır.
  static TodoParsedResult parse(
    String input, {
    required List<Activity> activities,
    required List<Measure> measures,
    DateTime? now,
  }) {
    final currentNow = now ?? DateTime.now();
    final today = DateTime(currentNow.year, currentNow.month, currentNow.day);

    final raw = input.trim();
    if (raw.isEmpty) {
      return const TodoParsedResult(cleanTitle: '');
    }

    DateTime? detectedDate;
    String? matchedKeyword;

    // 1. Çok kelimeli tarih ifadeleri ("öbür gün", "hafta sonu", "day after tomorrow", vb.)
    final multiWordPatterns = <(RegExp, int Function(DateTime), String)>[
      (
        RegExp(r'(^|\s)(öbür\s+gün|obur\s+gun|oburgun|day\s+after\s+tomorrow)($|\s)', caseSensitive: false),
        (d) => 2,
        'öbür gün',
      ),
      (
        RegExp(r'(^|\s)(hafta\s*sonu|haftasonu|weekend)($|\s)', caseSensitive: false),
        (d) {
          final wd = d.weekday;
          if (wd == 6 || wd == 7) return 0;
          return 6 - wd;
        },
        'hafta sonu',
      ),
      (
        RegExp(r'(^|\s)(haftaya|next\s+week)($|\s)', caseSensitive: false),
        (d) => 7,
        'haftaya',
      ),
    ];

    String workingText = raw;
    for (final (regex, getOffset, keyword) in multiWordPatterns) {
      final match = regex.firstMatch(workingText);
      if (match != null) {
        matchedKeyword = keyword;
        detectedDate = today.add(Duration(days: getOffset(today)));
        final captured = match.group(2)!;
        workingText = workingText.replaceFirst(captured, ' ').trim();
        break;
      }
    }

    // 2. Tek kelimeli tarih ifadeleri ("bugün", "yarın", "today", "tomorrow" ve gün adları)
    final words = workingText.split(RegExp(r'\s+'));
    final remainingWords = <String>[];

    for (var i = 0; i < words.length; i++) {
      final w = words[i];
      final norm = normalizeTr(w).toLowerCase();

      if (detectedDate == null) {
        if (norm == 'bugun' || norm == 'bugün' || norm == 'today') {
          detectedDate = today;
          matchedKeyword = 'bugün';
          continue;
        } else if (norm == 'yarin' || norm == 'yarın' || norm == 'tomorrow') {
          detectedDate = today.add(const Duration(days: 1));
          matchedKeyword = 'yarın';
          continue;
        } else if (_weekdays.containsKey(norm)) {
          final targetWeekday = _weekdays[norm]!;
          final currentWeekday = today.weekday;
          int offset;
          if (targetWeekday == currentWeekday) {
            offset = 0; // Bugünün adıysa bugün!
          } else if (targetWeekday > currentWeekday) {
            offset = targetWeekday - currentWeekday;
          } else {
            offset = 7 - (currentWeekday - targetWeekday);
          }
          detectedDate = today.add(Duration(days: offset));
          matchedKeyword = norm;
          continue;
        }
      }
      remainingWords.add(w);
    }

    String cleaned = remainingWords.join(' ').trim();
    if (cleaned.isEmpty) {
      cleaned = raw;
    }

    // 3. Aktivite ve miktar çıkarımı
    Activity? matchedAct;
    double? suggestedAmount;
    String? suggestedUnit;

    if (activities.isNotEmpty) {
      final nlResult = NaturalLanguageParser.parse(
        cleaned,
        activities: activities,
        measures: measures,
        allowCommands: true,
      );

      if (nlResult.matchedActivity != null) {
        matchedAct = nlResult.matchedActivity;
      } else {
        // text_match matchScore ile mevcut aktiviteler taranır
        final cleanWords = cleaned
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

      final wordsLower = cleaned.toLowerCase().split(RegExp(r'\s+'));
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
      cleanTitle: cleaned,
      date: detectedDate,
      dateKeyword: matchedKeyword,
      suggestedActivity: matchedAct,
      suggestedAmount: suggestedAmount,
      suggestedUnit: suggestedUnit,
    );
  }
}
