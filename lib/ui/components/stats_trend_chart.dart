import 'dart:math';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../../data/store.dart';
import '../../logic/format.dart';
import '../../logic/l10n.dart';

enum StatMetric { count, time, volume }

class StatsTrendChart extends StatelessWidget {
  final List<Entry> entries;
  final DateTime from;
  final DateTime to;
  final String rangeMode; // 'week', 'month', 'year'
  final StatMetric selectedMetric;
  final ValueChanged<StatMetric> onMetricChanged;

  const StatsTrendChart({
    super.key,
    required this.entries,
    required this.from,
    required this.to,
    required this.rangeMode,
    required this.selectedMetric,
    required this.onMetricChanged,
  });

  @override
  Widget build(BuildContext context) {
    final s = strings.value;
    final scheme = Theme.of(context).colorScheme;

    double calcMetric(Iterable<Entry> list) {
      double sum = 0;
      for (final e in list) {
        if (selectedMetric == StatMetric.count) {
          sum += 1.0;
        } else if (selectedMetric == StatMetric.time) {
          final u = e.unitId != null ? store.unit(e.unitId!) : null;
          if (u != null && e.value != null && u.dim == 'time') {
            sum += (e.value! * u.factor) / 60.0; // in hours
          }
        } else if (selectedMetric == StatMetric.volume) {
          final u = e.unitId != null ? store.unit(e.unitId!) : null;
          if (u != null && e.value != null && u.dim == 'volume') {
            sum += e.value! * u.factor; // in liters
          }
        }
      }
      return sum;
    }

    String formatMetric(double v) {
      if (selectedMetric == StatMetric.count) {
        return '${v.round()} ${s.entriesCountSuffix}';
      } else if (selectedMetric == StatMetric.time) {
        if (v <= 0) return '0 ${s.isTr ? "dk" : "min"}';
        if (v < 1.0) {
          return '${(v * 60).round()} ${s.isTr ? "dk" : "min"}';
        }
        final h = v.floor();
        final m = ((v - h) * 60).round();
        if (m == 0) return '$h ${s.isTr ? "sa" : "h"}';
        return '$h ${s.isTr ? "sa" : "h"} $m ${s.isTr ? "dk" : "min"}';
      } else {
        if (v < 1.0 && v > 0) {
          return '${fmtNum1(v * 1000)} ml';
        }
        return '${fmtNum1(v)} L';
      }
    }

    final barGroups = <BarChartGroupData>[];
    final titles = <String>[];
    double barWidth = 16;

    if (rangeMode == 'week') {
      // 7 days
      barWidth = 18;
      final fullDayNames = s.isTr
          ? ['Pazartesi', 'Salı', 'Çarşamba', 'Perşembe', 'Cuma', 'Cumartesi', 'Pazar']
          : ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

      for (var i = 0; i < 7; i++) {
        final d = DateTime(from.year, from.month, from.day + i);
        final nextD = DateTime(d.year, d.month, d.day + 1);
        final val = calcMetric(entries.where((e) {
          final dt = DateTime.fromMillisecondsSinceEpoch(e.ts);
          return !dt.isBefore(d) && dt.isBefore(nextD);
        }));

        barGroups.add(
          BarChartGroupData(
            x: i,
            barRods: [
              BarChartRodData(
                toY: val,
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: val > 0
                      ? [scheme.primary, scheme.secondary]
                      : [
                          scheme.outlineVariant.withValues(alpha: 0.2),
                          scheme.outlineVariant.withValues(alpha: 0.2),
                        ],
                ),
                width: barWidth,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
              ),
            ],
          ),
        );
        titles.add(fullDayNames[i]);
      }
    } else if (rangeMode == 'year') {
      // 12 months
      barWidth = 12;
      final monthLabels = s.isTr
          ? ['Oca', 'Şub', 'Mar', 'Nis', 'May', 'Haz', 'Tem', 'Ağu', 'Eyl', 'Eki', 'Kas', 'Ara']
          : ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      for (var m = 1; m <= 12; m++) {
        final startM = DateTime(from.year, m);
        final endM = DateTime(from.year, m + 1);
        final val = calcMetric(entries.where((e) {
          final dt = DateTime.fromMillisecondsSinceEpoch(e.ts);
          return !dt.isBefore(startM) && dt.isBefore(endM);
        }));
        barGroups.add(
          BarChartGroupData(
            x: m - 1,
            barRods: [
              BarChartRodData(
                toY: val,
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: val > 0
                      ? [scheme.primary, scheme.secondary]
                      : [
                          scheme.outlineVariant.withValues(alpha: 0.2),
                          scheme.outlineVariant.withValues(alpha: 0.2),
                        ],
                ),
                width: barWidth,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
              ),
            ],
          ),
        );
        titles.add(monthLabels[m - 1]);
      }
    } else {
      // Month (weeks)
      barWidth = 26;
      final daysInMonth = DateTime(from.year, from.month + 1, 0).day;
      final weeksCount = (daysInMonth / 7).ceil();
      for (var w = 0; w < weeksCount; w++) {
        final startD = DateTime(from.year, from.month, from.day + w * 7);
        final endD = DateTime(from.year, from.month, from.day + min((w + 1) * 7, daysInMonth));
        final val = calcMetric(entries.where((e) {
          final dt = DateTime.fromMillisecondsSinceEpoch(e.ts);
          return !dt.isBefore(startD) && dt.isBefore(endD);
        }));
        barGroups.add(
          BarChartGroupData(
            x: w,
            barRods: [
              BarChartRodData(
                toY: val,
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: val > 0
                      ? [scheme.primary, scheme.secondary]
                      : [
                          scheme.outlineVariant.withValues(alpha: 0.2),
                          scheme.outlineVariant.withValues(alpha: 0.2),
                        ],
                ),
                width: barWidth,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
              ),
            ],
          ),
        );
        titles.add('${w + 1}. Hafta');
      }
    }

    final maxY = barGroups.map((g) => g.barRods.first.toY).fold(0.0, max);
    final minTop = selectedMetric == StatMetric.count ? 5.0 : (selectedMetric == StatMetric.time ? 2.0 : 1.0);
    final topY = maxY < minTop ? minTop : (maxY * 1.25);

    // Attach background full track to rods
    final enrichedGroups = barGroups.map((g) {
      final rod = g.barRods.first;
      return BarChartGroupData(
        x: g.x,
        barRods: [
          rod.copyWith(
            backDrawRodData: BackgroundBarChartRodData(
              show: true,
              toY: topY,
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.25),
            ),
          ),
        ],
      );
    }).toList();

    // Peak active bar badge
    final peakGroup = barGroups.fold<BarChartGroupData?>(
      null,
      (prev, curr) =>
          curr.barRods.first.toY > (prev?.barRods.first.toY ?? 0) ? curr : prev,
    );
    final peakVal = peakGroup?.barRods.first.toY ?? 0;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.insights_rounded, size: 18, color: scheme.primary),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    s.isTr ? 'Aktivite Eğilimi (Trend)' : 'Activity Trend',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
                if (peakVal > 0 && peakGroup != null && peakGroup.x < titles.length)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: scheme.secondaryContainer.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.local_fire_department_rounded,
                          size: 13,
                          color: scheme.onSecondaryContainer,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${titles[peakGroup.x]} · ${formatMetric(peakVal)}',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: scheme.onSecondaryContainer,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<StatMetric>(
                style: const ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                segments: [
                  ButtonSegment(
                    value: StatMetric.count,
                    icon: const Icon(Icons.tag_rounded, size: 16),
                    label: Text(s.metricCount),
                  ),
                  ButtonSegment(
                    value: StatMetric.time,
                    icon: const Icon(Icons.schedule_rounded, size: 16),
                    label: Text(s.metricTime),
                  ),
                  ButtonSegment(
                    value: StatMetric.volume,
                    icon: const Icon(Icons.water_drop_outlined, size: 16),
                    label: Text(s.metricVolume),
                  ),
                ],
                selected: {selectedMetric},
                onSelectionChanged: (set) => onMetricChanged(set.first),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 180,
              child: BarChart(
                BarChartData(
                  maxY: topY,
                  barGroups: enrichedGroups,
                  borderData: FlBorderData(show: false),
                  barTouchData: BarTouchData(
                    enabled: true,
                    touchTooltipData: BarTouchTooltipData(
                      tooltipBorderRadius: BorderRadius.circular(10),
                      getTooltipColor: (_) => scheme.inverseSurface,
                      fitInsideHorizontally: true,
                      fitInsideVertically: true,
                      getTooltipItem: (group, groupIndex, rod, rodIndex) {
                        final title = (group.x >= 0 && group.x < titles.length)
                            ? titles[group.x]
                            : '';
                        return BarTooltipItem(
                          '$title\n',
                          TextStyle(
                            color: scheme.onInverseSurface,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                          children: [
                            TextSpan(
                              text: formatMetric(rod.toY),
                              style: TextStyle(
                                color: scheme.inversePrimary,
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval: topY > 10 ? (topY / 4).roundToDouble() : 1,
                    getDrawingHorizontalLine: (val) => FlLine(
                      color: scheme.outlineVariant.withValues(alpha: 0.2),
                      strokeWidth: 1,
                      dashArray: [4, 4],
                    ),
                  ),
                  titlesData: FlTitlesData(
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 32,
                        interval: topY > 10 ? (topY / 4).roundToDouble() : 1,
                        getTitlesWidget: (val, _) {
                          if (val <= 0) return const SizedBox.shrink();
                          String label;
                          if (selectedMetric == StatMetric.count) {
                            label = val.toInt().toString();
                          } else if (selectedMetric == StatMetric.time) {
                            label = '${fmtNum1(val)}h';
                          } else {
                            label = '${fmtNum1(val)}L';
                          }
                          return Text(
                            label,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                              color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
                            ),
                          );
                        },
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (val, _) {
                          final idx = val.toInt();
                          if (idx >= 0 && idx < titles.length) {
                            final shortTitle = rangeMode == 'week'
                                ? (s.isTr
                                    ? ['Pzt', 'Sal', 'Çar', 'Per', 'Cum', 'Cmt', 'Paz'][idx]
                                    : ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][idx])
                                : titles[idx];
                            return Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text(
                                shortTitle,
                                style: TextStyle(
                                  fontSize: rangeMode == 'year' ? 9.5 : 11,
                                  fontWeight: FontWeight.w600,
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            );
                          }
                          return const SizedBox.shrink();
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
