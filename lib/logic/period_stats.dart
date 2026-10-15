import 'dart:math';

import '../data/models.dart';
import '../data/store.dart' show PeriodTotal;
import 'format.dart';

/// İstatistik sekmesinin dönem türleri.
enum StatRange { day, week, month, year }

/// Bir istatistik dönemi: [from] dahil, [to] hariç.
class StatPeriod {
  final StatRange range;
  final DateTime from;
  final DateTime to;

  const StatPeriod._(this.range, this.from, this.to);

  /// [anchor] anını içeren dönem.
  factory StatPeriod.containing(StatRange range, DateTime anchor) {
    switch (range) {
      case StatRange.day:
        final s = dayStart(anchor);
        return StatPeriod._(range, s, addDays(s, 1));
      case StatRange.week:
        final s = weekStart(anchor);
        return StatPeriod._(range, s, addDays(s, 7));
      case StatRange.month:
        final s = monthStart(anchor);
        return StatPeriod._(range, s, DateTime(s.year, s.month + 1));
      case StatRange.year:
        final s = yearStart(anchor);
        return StatPeriod._(range, s, DateTime(s.year + 1));
    }
  }

  /// [delta] dönem ileri (negatifse geri) kaydırılmış dönem. Takvimle hesaplanır: gün sayısı kadar süre
  /// eklemek, yaz saatine geçilen haftada bir saat kayar ve gece yarısına yakın bir anı komşu güne taşır.
  StatPeriod shifted(int delta) => switch (range) {
        StatRange.day => StatPeriod.containing(range, addDays(from, delta)),
        StatRange.week => StatPeriod.containing(range, addDays(from, 7 * delta)),
        StatRange.month => StatPeriod.containing(range, DateTime(from.year, from.month + delta)),
        StatRange.year => StatPeriod.containing(range, DateTime(from.year + delta)),
      };

  StatPeriod get previous => shifted(-1);

  bool contains(DateTime t) => !t.isBefore(from) && t.isBefore(to);

  /// Grafiğin dilimleri: günde saatler, haftada ve ayda günler, yılda aylar.
  List<(DateTime, DateTime)> get buckets => switch (range) {
        StatRange.day => [
            for (var h = 0; h < 24; h++)
              (DateTime(from.year, from.month, from.day, h), DateTime(from.year, from.month, from.day, h + 1)),
          ],
        StatRange.week || StatRange.month => [
            for (var d = from; d.isBefore(to); d = addDays(d, 1)) (d, addDays(d, 1)),
          ],
        StatRange.year => [
            for (var m = 1; m <= 12; m++) (DateTime(from.year, m), DateTime(from.year, m + 1)),
          ],
      };
}

/// Bir dönemin istatistikleri. Arayüz yalnızca gösterir; hesapların tamamı burada durur.
class PeriodStats {
  final StatPeriod period;
  final PeriodTotal total;

  /// Grafiğin her dilimi için toplam; [StatPeriod.buckets] ile aynı sırada.
  final List<PeriodTotal> buckets;

  /// Karşılaştırma için önceki dönemin toplamı. Dönem henüz sürüyorsa önceki dönemin de aynı ana kadarki
  /// bölümüdür ([comparesPartial]); yoksa salı günü, bitmiş bir haftanın tamamıyla kıyaslanırdı.
  final PeriodTotal previous;
  final bool comparesPartial;

  /// Karşılaştırılan zaman aralığında takip başlamış mıydı. Başlamadıysa "öncekine göre arttı" demek
  /// anlamsızdır: ortada kıyaslanacak veri yoktur.
  final bool hasComparison;

  /// En az bir kaydı olan gün sayısı.
  final int activeDays;

  /// Ortalamaların paydası: dönemin geçmiş gün sayısı. Bugünden sonrası ve ilk kayıttan öncesi sayılmaz;
  /// sayılırsa ekimde başlanan takip, yıl görünümünde "günde 0,1 kayıt" diye çıkar.
  final int elapsedDays;

  /// Dönemdeki ilk ve son kaydın zamanı.
  final DateTime? firstEntry;
  final DateTime? lastEntry;

  const PeriodStats._({
    required this.period,
    required this.total,
    required this.buckets,
    required this.previous,
    required this.comparesPartial,
    required this.hasComparison,
    required this.activeDays,
    required this.elapsedDays,
    required this.firstEntry,
    required this.lastEntry,
  });

  /// [entriesIn] verilen aralıktaki (gerekiyorsa aktiviteye göre süzülmüş) kayıtları zaman sırasıyla
  /// döndürür. [trackingSince] aynı süzgeçteki ilk kaydın zamanıdır; hiç kayıt yoksa null.
  factory PeriodStats.compute({
    required StatPeriod period,
    required Iterable<Entry> Function(DateTime from, DateTime to) entriesIn,
    required Unit? Function(String unitId) unitOf,
    required DateTime now,
    DateTime? trackingSince,
  }) {
    PeriodTotal totalOf(Iterable<Entry> entries) {
      final t = PeriodTotal();
      for (final e in entries) {
        t.add(e, e.unitId == null ? null : unitOf(e.unitId!));
      }
      return t;
    }

    final entries = entriesIn(period.from, period.to).toList();
    final spans = period.buckets;
    final buckets = [for (final _ in spans) PeriodTotal()];
    final days = <DateTime>{};
    var i = 0;
    for (final e in entries) {
      final t = e.time;
      while (i < spans.length - 1 && !t.isBefore(spans[i].$2)) {
        i++;
      }
      buckets[i].add(e, e.unitId == null ? null : unitOf(e.unitId!));
      days.add(dayStart(t));
    }

    final prev = period.previous;
    final ongoing = period.contains(now);
    var prevTo = prev.to;
    if (ongoing) {
      final sameMoment = prev.from.add(now.difference(period.from));
      if (sameMoment.isBefore(prevTo)) prevTo = sameMoment;
    }

    final tomorrow = addDays(dayStart(now), 1);
    final since = trackingSince == null ? period.from : dayStart(trackingSince);
    final countFrom = since.isAfter(period.from) ? since : period.from;
    final countTo = tomorrow.isBefore(period.to) ? tomorrow : period.to;

    return PeriodStats._(
      period: period,
      total: totalOf(entries),
      buckets: buckets,
      previous: totalOf(entriesIn(prev.from, prevTo)),
      comparesPartial: ongoing,
      hasComparison: trackingSince != null && trackingSince.isBefore(prevTo),
      activeDays: days.length,
      elapsedDays: max(1, calendarDaysBetween(countFrom, countTo)),
      firstEntry: entries.isEmpty ? null : entries.first.time,
      lastEntry: entries.isEmpty ? null : entries.last.time,
    );
  }

  /// [dim] ölçütüne göre en yüksek dilimin indeksi (eşitlikte ilki); hepsi sıfırsa null.
  /// [dim] null ise kayıt sayısına bakılır.
  int? busiestBucket(String? dim) {
    int? best;
    var bestValue = 0.0;
    for (var i = 0; i < buckets.length; i++) {
      final v = buckets[i].value(dim);
      if (v > bestValue) {
        bestValue = v;
        best = i;
      }
    }
    return best;
  }
}

/// Grafiğin dikey ekseni için yuvarlak bir üst sınır ve adım: 37 için (40, 10), 0,7 için (0,8, 0,2).
/// En büyük değerin dörtte biri adım yapılınca eksen "12, 24, 36, 46" gibi okunmaz sayılarla doluyordu.
/// [integers] ise adım 1'den küçük olmaz (kayıt sayısı yarım olamaz).
(double top, double step) niceAxis(double maxValue, {bool integers = false}) {
  if (maxValue <= 0) return integers ? (4, 1) : (1, 0.25);
  final rough = maxValue / 4;
  final magnitude = pow(10, (log(rough) / ln10).floor()).toDouble();
  final residual = rough / magnitude;
  var step = (residual <= 1 ? 1 : (residual <= 2.5 ? 2 : (residual <= 5 ? 5 : 10))) * magnitude;
  if (integers && step < 1) step = 1;
  final top = (maxValue / step).ceil() * step;
  return (top, step);
}
