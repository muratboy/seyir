import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/store.dart';
import '../../logic/format.dart';
import '../../logic/l10n.dart';
import '../../logic/period_stats.dart';

/// İstatistiklerde bir "ölçüt", ya kayıt sayısıdır (null) ya da bir boyuttur ('time', 'volume'...).
/// Bu dosya ölçütlerin ve grafik dilimlerinin adlarını tek yerde tutar; özet kutuları, grafik ve aktivite
/// listesi aynı sözcükleri kullanır.

IconData dimIcon(String dim) {
  switch (dim) {
    case 'volume':
      return Icons.water_drop_rounded;
    case 'mass':
      return Icons.fitness_center_rounded;
    case 'time':
      return Icons.schedule_rounded;
    case 'count':
      return Icons.tag_rounded;
    case 'distance':
      return Icons.route_rounded;
    case 'energy':
      return Icons.bolt_rounded;
    default:
      return Icons.interests_rounded;
  }
}

String get _locale => strings.value.isTr ? 'tr_TR' : 'en_US';

String metricName(String? dim) => dim == null ? strings.value.metricCount : store.dimName(dim);

IconData metricIcon(String? dim) => dim == null ? Icons.format_list_bulleted_rounded : dimIcon(dim);

/// Ölçütün değeri, birimiyle: "5 kayıt", "1 sa 20 dk", "2,4 L".
String fmtMetric(double value, String? dim) => dim == null ? entriesText(value.round()) : store.fmtBase(value, dim);

/// Farklı aktiviteler arasında toplanması anlamlı olan boyutlar. "Adet" ve kullanıcının kendi birimleri
/// aktiviteye özeldir: şınav adediyle elma adedi toplanınca ortaya bir şey çıkmaz.
const _summableDims = ['time', 'volume', 'distance', 'mass', 'energy'];

/// Bu toplamda gösterilebilecek ölçütler; ilk sırada kayıt sayısı (null) vardır.
List<String?> availableMetrics(PeriodTotal total, {required bool singleActivity}) => [
      null,
      for (final dim in _summableDims)
        if (total.byDim.containsKey(dim)) dim,
      if (singleActivity)
        for (final dim in total.byDim.keys)
          if (!_summableDims.contains(dim)) dim,
    ];

/// Grafiğin altına yazılan kısa etiket; boşsa o dilime etiket yazılmaz (24 saat ya da 31 gün sığmaz).
String bucketAxisLabel(StatPeriod period, int index) {
  final start = period.buckets[index].$1;
  switch (period.range) {
    case StatRange.day:
      return index % 6 == 0 ? start.hour.toString().padLeft(2, '0') : '';
    case StatRange.week:
      return DateFormat.E(_locale).format(start);
    case StatRange.month:
      return index % 7 == 0 ? '${start.day}' : '';
    case StatRange.year:
      return DateFormat.MMM(_locale).format(start);
  }
}

/// Dilimin adı: "09:00–10:00", "Salı", "13 Ekim", "Ekim". [withDate] ise haftanın günü tarihiyle yazılır.
String bucketName(StatPeriod period, int index, {bool withDate = false}) {
  final (start, end) = period.buckets[index];
  switch (period.range) {
    case StatRange.day:
      String hour(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:00';
      // Günün son dilimi gece yarısında biter.
      return '${hour(start)}–${index == 23 ? '24:00' : hour(end)}';
    case StatRange.week:
      return DateFormat(withDate ? 'EEEE, d MMM' : 'EEEE', _locale).format(start);
    case StatRange.month:
      return DateFormat(withDate ? 'd MMMM, EEEE' : 'd MMMM', _locale).format(start);
    case StatRange.year:
      return DateFormat.MMMM(_locale).format(start);
  }
}

/// Dönemin başlığı: "Bugün", "12 – 18 Eki", "Ekim 2026", "2026".
String periodTitle(StatPeriod period) {
  final isTr = strings.value.isTr;
  switch (period.range) {
    case StatRange.day:
      return fmtDayTitle(period.from, isTr: isTr);
    case StatRange.week:
      final last = subDays(period.to, 1);
      final sameMonth = last.month == period.from.month;
      final first = sameMonth ? '${period.from.day}' : fmtDateShort(period.from, isTr: isTr);
      return '$first – ${fmtDateShort(last, isTr: isTr)}';
    case StatRange.month:
      return DateFormat('MMMM yyyy', _locale).format(period.from);
    case StatRange.year:
      return '${period.from.year}';
  }
}
