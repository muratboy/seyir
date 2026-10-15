import 'dart:math';

import '../data/models.dart';
import 'activity_rhythm.dart';
import 'format.dart';

/// Bir aktivitenin kayıt biçimi.
enum ActivityFormat {
  /// Süre odaklı: Oturumlar, toplam çalışma/okuma/spor süresi, ortalama oturum.
  duration,

  /// Miktar odaklı: Hacim, mesafe, ağırlık, adet, kalori vb. (L, km, kg...).
  quantity,

  /// Olay odaklı: Baş ağrısı, ilaç, elektrik kesintisi, belirti, anlık alışkanlık.
  event,
}

/// Şiddet eğiliminin yönü.
enum SeverityTrendDirection {
  /// Şiddet zamanla azalıyor (iyileşme).
  decreasing,

  /// Şiddet zamanla artıyor.
  increasing,

  /// Belirgin bir artış veya azalış yok, durağan.
  stable,

  /// Karşılaştırma yapacak yeterli veri yok.
  unknown,
}

/// Olay kayıtlarındaki şiddet/derece bilgisi.
class SeverityAnalysis {
  /// Şiddet bilgisi olan kayıt sayısı.
  final int count;

  /// Ortalama şiddet (1-10 ölçeğinde).
  final double? avgScore;

  /// Son kayıttaki şiddet (1-10 ölçeğinde).
  final double? lastScore;

  /// Şiddetin genel gidişat yönü.
  final SeverityTrendDirection direction;

  /// Hafif (1-3), Orta (4-6), Şiddetli (7-10) dağılımı.
  final Map<String, int> distribution;

  const SeverityAnalysis({
    required this.count,
    required this.avgScore,
    required this.lastScore,
    required this.direction,
    required this.distribution,
  });

  bool get hasData => count > 0 && avgScore != null;
}

/// Süre biçimindeki aktivitenin analiz sonuçları.
class DurationMetrics {
  /// Dönemdeki toplam süre (dakika cinsinden).
  final double totalMinutes;

  /// Oturum sayısı (süreli kayıtların sayısı).
  final int sessionCount;

  /// Oturum başına ortalama süre (dakika).
  final double avgSessionMinutes;

  /// En uzun oturum süresi (dakika) ve gerçekleştiği zaman.
  final double? longestSessionMinutes;
  final DateTime? longestSessionTime;

  /// En kısa oturum süresi (dakika).
  final double? shortestSessionMinutes;

  /// Son oturum süresi (dakika) ve zamanı.
  final double? lastSessionMinutes;
  final DateTime? lastSessionTime;

  /// Günlük ortalama süre (dönemin geçen tüm günlerine bölünür).
  final double dailyAvgMinutes;

  /// Aktif günlerdeki günlük ortalama süre (yalnızca kayıt olan günlere bölünür).
  final double activeDayAvgMinutes;

  const DurationMetrics({
    required this.totalMinutes,
    required this.sessionCount,
    required this.avgSessionMinutes,
    required this.longestSessionMinutes,
    required this.longestSessionTime,
    required this.shortestSessionMinutes,
    required this.lastSessionMinutes,
    required this.lastSessionTime,
    required this.dailyAvgMinutes,
    required this.activeDayAvgMinutes,
  });
}

/// Miktar biçimindeki aktivitenin analiz sonuçları.
class QuantityMetrics {
  /// Temel birimdeki toplam miktar (L, g, m, adet...).
  final double totalBase;

  /// Boyut adı ('volume', 'mass', 'distance', 'count', 'energy'...).
  final String dim;

  /// En çok kullanılan birim simgesi (örn. "L", "km", "bardak").
  final String unitSymbol;

  /// Toplam kayıt sayısı.
  final int entryCount;

  /// Kayıt başına ortalama miktar (temel birimde).
  final double avgPerEntry;

  /// En yüksek tekil kayıt miktarı ve zamanı.
  final double? maxEntryBase;
  final DateTime? maxEntryTime;

  /// Günlük ortalama miktar (dönemin geçen günlerine bölünür).
  final double dailyAvgBase;

  /// Aktif günlerdeki ortalama miktar.
  final double activeDayAvgBase;

  /// Ölçülere / birimlere göre kırılım [(ölçü adı, kayıt sayısı, toplam temel miktar)].
  final List<(String, int, double)> measureBreakdown;

  const QuantityMetrics({
    required this.totalBase,
    required this.dim,
    required this.unitSymbol,
    required this.entryCount,
    required this.avgPerEntry,
    required this.maxEntryBase,
    required this.maxEntryTime,
    required this.dailyAvgBase,
    required this.activeDayAvgBase,
    required this.measureBreakdown,
  });
}

/// Olay biçimindeki aktivitenin analiz sonuçları.
class EventMetrics {
  /// Toplam olay sayısı.
  final int totalCount;

  /// Olayın gerçekleştiği farklı gün sayısı.
  final int activeDaysCount;

  /// Ritim metni (örn. "ortalama 4 günde bir").
  final String cadenceText;

  /// Olaylar arasındaki ortalama süre / aralık.
  final Duration? avgInterval;

  /// En kısa aralık.
  final Duration? minInterval;

  /// En uzun aralık.
  final Duration? maxInterval;

  /// Son olaydan bu yana geçen süre.
  final Duration? timeSinceLast;

  /// Son olayın zamanı.
  final DateTime? lastTime;

  /// Şiddet analizi (belirti, ağrı, derece takibi).
  final SeverityAnalysis severity;

  const EventMetrics({
    required this.totalCount,
    required this.activeDaysCount,
    required this.cadenceText,
    required this.avgInterval,
    required this.minInterval,
    required this.maxInterval,
    required this.timeSinceLast,
    required this.lastTime,
    required this.severity,
  });
}

/// Bir aktivitenin kayıt biçimine göre tüm hesaplanmış metriklerini tutan kapsayıcı sınıf.
class ActivityFormatAnalysis {
  final ActivityFormat format;
  final DurationMetrics? durationMetrics;
  final QuantityMetrics? quantityMetrics;
  final EventMetrics? eventMetrics;

  const ActivityFormatAnalysis._({
    required this.format,
    this.durationMetrics,
    this.quantityMetrics,
    this.eventMetrics,
  });

  /// Bir aktivitenin kayıt biçimini otomatik tespit eder.
  static ActivityFormat detectFormat({
    required Activity activity,
    required Iterable<Entry> entries,
    required Unit? Function(String unitId) unitOf,
  }) {
    var durationCount = 0;
    var quantityCount = 0;

    for (final e in entries) {
      if (e.duration != null && e.duration!.inMinutes > 0) {
        durationCount++;
        continue;
      }
      if (e.unitId != null) {
        final u = unitOf(e.unitId!);
        if (u != null) {
          if (u.dim == 'time') {
            durationCount++;
            continue;
          } else if (u.dim != 'count' || (e.value != null && e.value! > 1)) {
            quantityCount++;
            continue;
          }
        }
      }
      if (e.measureId != null) {
        quantityCount++;
      }
    }

    if (durationCount > 0 && durationCount >= quantityCount) {
      return ActivityFormat.duration;
    }
    if (quantityCount > 0) {
      return ActivityFormat.quantity;
    }
    return ActivityFormat.event;
  }

  /// Verilen aktivite ve kayıt kümesi için analiz yapar.
  /// [overrideFormat] verilirse o biçime zorlanır; verilmezse otomatik tespit edilir.
  factory ActivityFormatAnalysis.compute({
    required Activity activity,
    required Iterable<Entry> entries,
    required Unit? Function(String unitId) unitOf,
    required String? Function(int measureId) measureNameOf,
    required DateTime now,
    required int elapsedDays,
    required bool isTr,
    ActivityFormat? overrideFormat,
  }) {
    final entryList = entries.toList()..sort((a, b) => a.ts.compareTo(b.ts));
    final format = overrideFormat ??
        detectFormat(
          activity: activity,
          entries: entryList,
          unitOf: unitOf,
        );

    final safeElapsedDays = max(1, elapsedDays);

    switch (format) {
      case ActivityFormat.duration:
        final durationMetrics = _computeDuration(
          entries: entryList,
          unitOf: unitOf,
          elapsedDays: safeElapsedDays,
        );
        return ActivityFormatAnalysis._(
          format: ActivityFormat.duration,
          durationMetrics: durationMetrics,
        );

      case ActivityFormat.quantity:
        final quantityMetrics = _computeQuantity(
          entries: entryList,
          unitOf: unitOf,
          measureNameOf: measureNameOf,
          elapsedDays: safeElapsedDays,
        );
        return ActivityFormatAnalysis._(
          format: ActivityFormat.quantity,
          quantityMetrics: quantityMetrics,
        );

      case ActivityFormat.event:
        final eventMetrics = _computeEvent(
          entries: entryList,
          now: now,
          isTr: isTr,
        );
        return ActivityFormatAnalysis._(
          format: ActivityFormat.event,
          eventMetrics: eventMetrics,
        );
    }
  }

  static DurationMetrics _computeDuration({
    required List<Entry> entries,
    required Unit? Function(String unitId) unitOf,
    required int elapsedDays,
  }) {
    var totalMinutes = 0.0;
    var sessionCount = 0;
    double? longest;
    DateTime? longestTime;
    double? shortest;
    double? lastSession;
    DateTime? lastSessionTime;
    final activeDays = <String>{};

    for (final e in entries) {
      double? mins;
      if (e.duration != null && e.duration!.inSeconds > 0) {
        mins = e.duration!.inMilliseconds / 60000.0;
      } else if (e.unitId != null && e.value != null) {
        final u = unitOf(e.unitId!);
        if (u != null && u.dim == 'time') {
          // u.factor dakika cinsinden çarpan verir
          mins = e.value! * u.factor;
        }
      }

      if (mins != null && mins > 0) {
        totalMinutes += mins;
        sessionCount++;
        activeDays.add(dayKey(e.time));

        if (longest == null || mins > longest) {
          longest = mins;
          longestTime = e.time;
        }
        if (shortest == null || mins < shortest) {
          shortest = mins;
        }
        lastSession = mins;
        lastSessionTime = e.time;
      }
    }

    final activeDaysCount = max(1, activeDays.length);
    final avgSession = sessionCount > 0 ? (totalMinutes / sessionCount) : 0.0;
    final dailyAvg = totalMinutes / elapsedDays;
    final activeDayAvg = totalMinutes / activeDaysCount;

    return DurationMetrics(
      totalMinutes: totalMinutes,
      sessionCount: sessionCount,
      avgSessionMinutes: avgSession,
      longestSessionMinutes: longest,
      longestSessionTime: longestTime,
      shortestSessionMinutes: shortest,
      lastSessionMinutes: lastSession,
      lastSessionTime: lastSessionTime,
      dailyAvgMinutes: dailyAvg,
      activeDayAvgMinutes: activeDayAvg,
    );
  }

  static QuantityMetrics _computeQuantity({
    required List<Entry> entries,
    required Unit? Function(String unitId) unitOf,
    required String? Function(int measureId) measureNameOf,
    required int elapsedDays,
  }) {
    var totalBase = 0.0;
    double? maxEntry;
    DateTime? maxEntryTime;
    final dimCounts = <String, int>{};
    final unitCounts = <String, int>{};
    final breakdown = <String, (int, double)>{};
    final activeDays = <String>{};

    for (final e in entries) {
      final u = e.unitId != null ? unitOf(e.unitId!) : null;
      final val = e.value;
      if (u != null && val != null) {
        final base = val * u.factor;
        totalBase += base;
        dimCounts[u.dim] = (dimCounts[u.dim] ?? 0) + 1;
        unitCounts[u.symbol] = (unitCounts[u.symbol] ?? 0) + 1;
        activeDays.add(dayKey(e.time));

        if (maxEntry == null || base > maxEntry) {
          maxEntry = base;
          maxEntryTime = e.time;
        }

        // Kırılım etiketi: ölçü adı varsa o, yoksa birim adı
        String label;
        if (e.measureId != null) {
          label = measureNameOf(e.measureId!) ?? u.name;
        } else {
          label = u.name;
        }

        final prev = breakdown[label] ?? (0, 0.0);
        breakdown[label] = (prev.$1 + 1, prev.$2 + base);
      }
    }

    final dominantDim = dimCounts.isEmpty
        ? 'count'
        : dimCounts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;

    final dominantSymbol = unitCounts.isEmpty
        ? ''
        : unitCounts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;

    final count = entries.length;
    final avgPerEntry = count > 0 ? (totalBase / count) : 0.0;
    final dailyAvg = totalBase / elapsedDays;
    final activeDaysCount = max(1, activeDays.length);
    final activeDayAvg = totalBase / activeDaysCount;

    final sortedBreakdown = breakdown.entries
        .map((entry) => (entry.key, entry.value.$1, entry.value.$2))
        .toList()
      ..sort((a, b) => b.$2.compareTo(a.$2));

    return QuantityMetrics(
      totalBase: totalBase,
      dim: dominantDim,
      unitSymbol: dominantSymbol,
      entryCount: count,
      avgPerEntry: avgPerEntry,
      maxEntryBase: maxEntry,
      maxEntryTime: maxEntryTime,
      dailyAvgBase: dailyAvg,
      activeDayAvgBase: activeDayAvg,
      measureBreakdown: sortedBreakdown,
    );
  }

  static EventMetrics _computeEvent({
    required List<Entry> entries,
    required DateTime now,
    required bool isTr,
  }) {
    final rhythm = ActivityRhythm.compute(
      entries: entries,
      now: now,
      isTr: isTr,
    );

    Duration? avgInterval;
    Duration? minInterval;
    Duration? maxInterval;

    if (entries.length >= 2) {
      var totalIntervalMs = 0;
      final intervalCount = entries.length - 1;

      for (var i = 0; i < intervalCount; i++) {
        final diffMs = (entries[i + 1].ts - entries[i].ts).abs();
        totalIntervalMs += diffMs;

        final d = Duration(milliseconds: diffMs);
        if (minInterval == null || d < minInterval) minInterval = d;
        if (maxInterval == null || d > maxInterval) maxInterval = d;
      }

      avgInterval = Duration(milliseconds: totalIntervalMs ~/ intervalCount);
    }

    DateTime? lastTime;
    Duration? timeSinceLast;
    if (entries.isNotEmpty) {
      lastTime = entries.last.time;
      if (!now.isBefore(lastTime)) {
        timeSinceLast = now.difference(lastTime);
      }
    }

    final severity = extractSeverityAnalysis(entries);

    return EventMetrics(
      totalCount: entries.length,
      activeDaysCount: rhythm.activeDaysCount,
      cadenceText: rhythm.cadenceText,
      avgInterval: avgInterval,
      minInterval: minInterval,
      maxInterval: maxInterval,
      timeSinceLast: timeSinceLast,
      lastTime: lastTime,
      severity: severity,
    );
  }

  /// Kayıtlardan şiddet/derece analizini çıkarır.
  static SeverityAnalysis extractSeverityAnalysis(List<Entry> entries) {
    final scores = <double>[];
    final distribution = <String, int>{'hafif': 0, 'orta': 0, 'şiddetli': 0};

    for (final e in entries) {
      final score = extractSeverityScore(e);
      if (score != null) {
        scores.add(score);
        if (score <= 3.5) {
          distribution['hafif'] = (distribution['hafif'] ?? 0) + 1;
        } else if (score <= 6.5) {
          distribution['orta'] = (distribution['orta'] ?? 0) + 1;
        } else {
          distribution['şiddetli'] = (distribution['şiddetli'] ?? 0) + 1;
        }
      }
    }

    if (scores.isEmpty) {
      return const SeverityAnalysis(
        count: 0,
        avgScore: null,
        lastScore: null,
        direction: SeverityTrendDirection.unknown,
        distribution: {'hafif': 0, 'orta': 0, 'şiddetli': 0},
      );
    }

    final sum = scores.fold<double>(0.0, (prev, s) => prev + s);
    final avg = sum / scores.length;
    final last = scores.last;

    SeverityTrendDirection direction;
    if (scores.length < 2) {
      direction = SeverityTrendDirection.unknown;
    } else {
      final mid = scores.length ~/ 2;
      final firstHalf = scores.sublist(0, mid);
      final secondHalf = scores.sublist(mid);

      final firstAvg = firstHalf.fold<double>(0.0, (p, s) => p + s) / firstHalf.length;
      final secondAvg = secondHalf.fold<double>(0.0, (p, s) => p + s) / secondHalf.length;

      final diff = secondAvg - firstAvg;
      if (diff >= 0.75) {
        direction = SeverityTrendDirection.increasing;
      } else if (diff <= -0.75) {
        direction = SeverityTrendDirection.decreasing;
      } else {
        direction = SeverityTrendDirection.stable;
      }
    }

    return SeverityAnalysis(
      count: scores.length,
      avgScore: avg,
      lastScore: last,
      direction: direction,
      distribution: distribution,
    );
  }

  /// Tek bir kayıttan 1.0 - 10.0 arasında şiddet puanı çıkarır.
  static double? extractSeverityScore(Entry e) {
    if (e.note != null && e.note!.isNotEmpty) {
      final note = e.note!.toLowerCase();

      // "7/10", "8.5/10", "9 / 10"
      final matchFraction = RegExp(r'(\d+(?:\.\d+)?)\s*\/\s*10').firstMatch(note);
      if (matchFraction != null) {
        final v = double.tryParse(matchFraction.group(1)!);
        if (v != null) return v.clamp(1.0, 10.0);
      }

      // "şiddet: 8", "şiddeti 7", "derece: 9", "seviye: 6"
      final matchWord = RegExp(r'(?:şiddet(?:i)?|seviye(?:si)?|derece(?:si)?)\s*[:=]?\s*(\d+(?:\.\d+)?)')
          .firstMatch(note);
      if (matchWord != null) {
        final v = double.tryParse(matchWord.group(1)!);
        if (v != null) return v.clamp(1.0, 10.0);
      }

      // Kelime bazlı niteleyiciler
      if (note.contains('çok şiddetli') || note.contains('dayanılmaz') || note.contains('aşırı şiddetli')) {
        return 9.0;
      }
      if (note.contains('şiddetli') || note.contains('ağır')) {
        return 8.0;
      }
      if (note.contains('orta şiddetli') || note.contains('orta')) {
        return 5.0;
      }
      if (note.contains('hafif') || note.contains('az')) {
        return 2.5;
      }
    }

    // Birimsiz 1-10 arası doğrudan sayısal değer
    if (e.unitId == null && e.value != null && e.value! >= 1.0 && e.value! <= 10.0) {
      return e.value!;
    }

    return null;
  }
}

/// Aralık süresini okunaklı metne çevirir (örn. "2 gün 14 sa" / "18 sa 30 dk").
String fmtInterval(Duration d, {required bool isTr}) {
  if (d.inDays >= 2) {
    final days = d.inDays;
    final hours = d.inHours % 24;
    if (hours > 0) {
      return isTr ? '$days gün $hours sa' : '$days d $hours h';
    }
    return isTr ? '$days gün' : '$days days';
  } else if (d.inHours >= 1) {
    final hours = d.inHours;
    final mins = d.inMinutes % 60;
    if (mins > 0) {
      return isTr ? '$hours sa $mins dk' : '$hours h $mins min';
    }
    return isTr ? '$hours saat' : '$hours hours';
  } else {
    final mins = max(1, d.inMinutes);
    return isTr ? '$mins dk' : '$mins min';
  }
}
