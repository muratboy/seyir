import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../../data/store.dart';
import '../../logic/format.dart';
import '../../logic/l10n.dart';

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

class StatsOverviewCard extends StatelessWidget {
  final List<Entry> entries;
  final DateTime from;
  final DateTime to;
  final String rangeMode; // 'day', 'week', 'month', 'year'

  const StatsOverviewCard({
    super.key,
    required this.entries,
    required this.from,
    required this.to,
    required this.rangeMode,
  });

  @override
  Widget build(BuildContext context) {
    final s = strings.value;
    final scheme = Theme.of(context).colorScheme;

    final periodTotal = PeriodTotal();
    for (final e in entries) {
      periodTotal.add(e, e.unitId != null ? store.unit(e.unitId!) : null);
    }

    final totalLogs = entries.length;
    final mainDim = periodTotal.mainDim;
    final uniqueActivities = entries.map((e) => e.activityId).toSet().length;

    // Period days calculation
    int periodDays;
    switch (rangeMode) {
      case 'day':
        periodDays = 1;
        break;
      case 'week':
        periodDays = 7;
        break;
      case 'month':
        periodDays = DateTime(from.year, from.month + 1, 0).day;
        break;
      case 'year':
        periodDays = (to.difference(from).inHours / 24).round();
        break;
      default:
        periodDays = 7;
    }
    if (periodDays <= 0) periodDays = 1;

    final avgPerDay = fmtNum1(totalLogs / periodDays);

    // Peak active hour or day
    String peakText = '-';
    if (entries.isNotEmpty) {
      if (rangeMode == 'day') {
        // Group by 4-hour blocks
        final counts = List.filled(6, 0);
        for (final e in entries) {
          final h = DateTime.fromMillisecondsSinceEpoch(e.ts).hour;
          counts[h ~/ 4]++;
        }
        var maxIdx = 0;
        for (var i = 1; i < 6; i++) {
          if (counts[i] > counts[maxIdx]) maxIdx = i;
        }
        final startH = maxIdx * 4;
        peakText = '${startH.toString().padLeft(2, '0')}:00 - ${(startH + 4).toString().padLeft(2, '0')}:00';
      } else if (rangeMode == 'week') {
        final dayNames = s.isTr
            ? ['Pazartesi', 'Salı', 'Çarşamba', 'Perşembe', 'Cuma', 'Cumartesi', 'Pazar']
            : ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
        final counts = List.filled(7, 0);
        for (final e in entries) {
          final dt = DateTime.fromMillisecondsSinceEpoch(e.ts);
          final diff = dt.difference(from).inDays;
          if (diff >= 0 && diff < 7) counts[diff]++;
        }
        var maxIdx = 0;
        for (var i = 1; i < 7; i++) {
          if (counts[i] > counts[maxIdx]) maxIdx = i;
        }
        if (counts[maxIdx] > 0) {
          peakText = '${dayNames[maxIdx]} · ${counts[maxIdx]} ${s.entriesCountSuffix}';
        }
      } else {
        // Most logged activity name
        final actCounts = <int, int>{};
        for (final e in entries) {
          actCounts[e.activityId] = (actCounts[e.activityId] ?? 0) + 1;
        }
        var topActId = entries.first.activityId;
        var maxC = 0;
        for (final entry in actCounts.entries) {
          if (entry.value > maxC) {
            maxC = entry.value;
            topActId = entry.key;
          }
        }
        final a = store.activity(topActId);
        peakText = '${a.name} ($maxC)';
      }
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.3)),
      ),
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.25),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // KPI Grid 2x2
            Row(
              children: [
                Expanded(
                  child: KpiBox(
                    title: s.totalCount,
                    value: '$totalLogs',
                    subtitle: s.isTr
                        ? '$uniqueActivities aktivite çeşidi'
                        : '$uniqueActivities activity types',
                    icon: Icons.playlist_add_check_rounded,
                    color: scheme.primary,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: KpiBox(
                    title: mainDim != null
                        ? store.dimName(mainDim)
                        : (s.isTr ? 'Toplam Süre' : 'Total Duration'),
                    value: mainDim != null && periodTotal.byDim[mainDim] != null
                        ? store.fmtBase(periodTotal.byDim[mainDim]!, mainDim)
                        : (totalLogs > 0 ? '$totalLogs' : '0'),
                    subtitle: mainDim != null
                        ? (s.isTr ? 'Ana odak' : 'Main focus')
                        : s.metricCount,
                    icon: dimIcon(mainDim ?? 'time'),
                    color: Colors.amber.shade700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: KpiBox(
                    title: s.dailyAverage,
                    value: avgPerDay,
                    subtitle: s.entriesPerDay,
                    icon: Icons.trending_up_rounded,
                    color: Colors.teal.shade600,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: KpiBox(
                    title: s.peakPoint,
                    value: peakText,
                    subtitle: s.isTr ? 'En yüksek hacim' : 'Highest volume',
                    icon: Icons.local_fire_department_rounded,
                    color: Colors.deepOrange.shade600,
                  ),
                ),
              ],
            ),

            // Secondary dimensions pill badges
            if (periodTotal.byDim.length > 1) ...[
              const SizedBox(height: 12),
              Divider(
                height: 1,
                thickness: 0.5,
                color: scheme.outlineVariant.withValues(alpha: 0.3),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  for (final entry in periodTotal.byDim.entries)
                    if (entry.key != mainDim)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: scheme.outlineVariant.withValues(alpha: 0.25),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              dimIcon(entry.key),
                              size: 14,
                              color: scheme.primary,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '${store.dimName(entry.key)}: ',
                              style: TextStyle(
                                fontSize: 12,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                            Text(
                              store.fmtBase(entry.value, entry.key),
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class KpiBox extends StatelessWidget {
  final String title;
  final String value;
  final String subtitle;
  final IconData icon;
  final Color color;

  const KpiBox({
    super.key,
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.2),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 16, color: color),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurfaceVariant,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.bold,
              color: scheme.onSurface,
              letterSpacing: -0.5,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 10.5,
              color: scheme.onSurfaceVariant.withValues(alpha: 0.8),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
