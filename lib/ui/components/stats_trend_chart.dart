import 'dart:math';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../data/store.dart';
import '../../logic/format.dart';
import '../../logic/l10n.dart';
import '../../logic/period_stats.dart';
import '../app_font.dart';
import 'stats_common.dart';

/// Dönemin dağılımı: günde saat saat, haftada ve ayda gün gün, yılda ay ay.
///
/// Hangi ölçütlerin seçilebileceğini veri belirler ([metrics]): koşu kayıtlarında mesafe, su kayıtlarında
/// hacim çıkar. Sabit "kayıt / süre / hacim" üçlüsü, bunlardan hiçbiri olmayan aktivitede boş grafik
/// çiziyor, mesafe ya da kalori gibi ölçüleri ise hiç gösteremiyordu.
class StatsTrendChart extends StatelessWidget {
  final PeriodStats stats;

  /// Çizilen ölçüt: null = kayıt sayısı, değilse boyut.
  final String? metric;
  final List<String?> metrics;
  final ValueChanged<String?> onMetricChanged;
  final DateTime now;

  const StatsTrendChart({
    super.key,
    required this.stats,
    required this.metric,
    required this.metrics,
    required this.onMetricChanged,
    required this.now,
  });

  /// Eksen yalın sayılarla yazılır: sayının birimi ve temel birimden o birime çarpan.
  (double scale, String unit) _axisUnit(double maxBase) {
    final isTr = strings.value.isTr;
    switch (metric) {
      case null:
        return (1, strings.value.entriesCountSuffix);
      case 'time':
        return maxBase >= 120 ? (1 / 60, isTr ? 'saat' : 'hours') : (1, isTr ? 'dakika' : 'minutes');
      case 'volume':
        return maxBase >= 1 ? (1, isTr ? 'litre' : 'litres') : (1000, 'ml');
      case 'mass':
        return maxBase >= 1000 ? (1 / 1000, 'kg') : (1, 'g');
      case 'distance':
        return maxBase >= 1000 ? (1 / 1000, 'km') : (1, 'm');
      case 'energy':
        return (1, 'kcal');
      case 'count':
        return (1, isTr ? 'adet' : 'pcs');
      default:
        return (1, store.unit(metric!).symbol);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = strings.value;
    final scheme = Theme.of(context).colorScheme;
    final period = stats.period;
    // Aktivitenin kendi rengi kullanılmaz: koyu renkli bir aktivitenin çubukları koyu temada görünmüyor.
    final barColor = scheme.primary;

    final values = [for (final b in stats.buckets) b.value(metric)];
    final maxBase = values.fold(0.0, max);
    final (scale, unit) = _axisUnit(maxBase);
    final (top, step) = niceAxis(maxBase * scale, integers: metric == null || metric == 'count');
    final barWidth = values.length <= 7 ? 22.0 : (values.length <= 12 ? 14.0 : (values.length <= 24 ? 7.0 : 5.0));
    final current = period.buckets.indexWhere((b) => !now.isBefore(b.$1) && now.isBefore(b.$2));

    final title = switch (period.range) {
      StatRange.day => s.isTr ? 'Saatlere Göre' : 'By Hour',
      StatRange.week || StatRange.month => s.isTr ? 'Günlere Göre' : 'By Day',
      StatRange.year => s.isTr ? 'Aylara Göre' : 'By Month',
    };

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.bar_chart_rounded, size: 20, color: scheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: AppFont.subtitle),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // Eksendeki sayıların birimi; kayıt sayısında söylemeye gerek yoktur.
                if (metric != null)
                  Text(unit, style: TextStyle(fontSize: AppFont.caption, color: scheme.onSurfaceVariant)),
              ],
            ),
            if (metrics.length > 1) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final m in metrics)
                    ChoiceChip(
                      showCheckmark: false,
                      visualDensity: VisualDensity.compact,
                      avatar: Icon(metricIcon(m), size: 16),
                      label: Text(metricName(m)),
                      selected: m == metric,
                      onSelected: (_) => onMetricChanged(m),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 14),
            SizedBox(
              height: 170,
              child: BarChart(
                BarChartData(
                  maxY: top,
                  barGroups: [
                    for (var i = 0; i < values.length; i++)
                      BarChartGroupData(
                        x: i,
                        barRods: [
                          BarChartRodData(
                            toY: values[i] * scale,
                            color: barColor,
                            width: barWidth,
                            borderRadius: BorderRadius.vertical(top: Radius.circular(min(6, barWidth / 2))),
                          ),
                        ],
                      ),
                  ],
                  borderData: FlBorderData(show: false),
                  barTouchData: BarTouchData(
                    enabled: true,
                    touchTooltipData: BarTouchTooltipData(
                      tooltipBorderRadius: BorderRadius.circular(10),
                      getTooltipColor: (_) => scheme.inverseSurface,
                      fitInsideHorizontally: true,
                      fitInsideVertically: true,
                      getTooltipItem: (group, groupIndex, rod, rodIndex) => BarTooltipItem(
                        '${bucketName(period, group.x, withDate: true)}\n',
                        TextStyle(
                          color: scheme.onInverseSurface,
                          fontWeight: FontWeight.bold,
                          fontSize: AppFont.caption,
                        ),
                        children: [
                          TextSpan(
                            text: fmtMetric(values[group.x], metric),
                            style: TextStyle(
                              color: scheme.inversePrimary,
                              fontWeight: FontWeight.w600,
                              fontSize: AppFont.small,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval: step,
                    getDrawingHorizontalLine: (_) => FlLine(
                      color: scheme.outlineVariant.withValues(alpha: 0.3),
                      strokeWidth: 1,
                    ),
                  ),
                  titlesData: FlTitlesData(
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 34,
                        interval: step,
                        getTitlesWidget: (value, _) => value <= 0
                            ? const SizedBox.shrink()
                            : Text(
                                fmtNum(value),
                                style: TextStyle(
                                  fontSize: AppFont.micro,
                                  color: scheme.onSurfaceVariant.withValues(alpha: 0.8),
                                ),
                              ),
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 24,
                        getTitlesWidget: (value, _) {
                          final index = value.toInt();
                          if (index < 0 || index >= values.length) return const SizedBox.shrink();
                          final label = bucketAxisLabel(period, index);
                          if (label.isEmpty) return const SizedBox.shrink();
                          // İçinde bulunulan saat, gün ya da ay vurgulanır.
                          final isCurrent = index == current;
                          return Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              label,
                              style: TextStyle(
                                fontSize: values.length == 12 ? 9.5 : AppFont.micro,
                                fontWeight: isCurrent ? FontWeight.w800 : FontWeight.w500,
                                color: isCurrent ? scheme.primary : scheme.onSurfaceVariant,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
