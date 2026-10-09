import 'dart:math';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/store.dart';
import '../logic/format.dart';
import '../logic/l10n.dart';
import '../services/export_service.dart';
import 'common.dart';
import 'contribution_heatmap.dart';

enum StatViewRange { day, week, month, year }

class StatsPage extends StatefulWidget {
  const StatsPage({super.key});

  @override
  State<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends State<StatsPage> {
  StatViewRange _range = StatViewRange.week;
  DateTime _anchorDate = DateTime.now();
  int? _selectedActivityId; // null = all

  (DateTime, DateTime) _calculateDateRange() {
    switch (_range) {
      case StatViewRange.day:
        final s = dayStart(_anchorDate);
        return (s, DateTime(s.year, s.month, s.day + 1));
      case StatViewRange.week:
        final s = weekStart(_anchorDate);
        return (s, DateTime(s.year, s.month, s.day + 7));
      case StatViewRange.month:
        final s = monthStart(_anchorDate);
        return (s, DateTime(s.year, s.month + 1, 1));
      case StatViewRange.year:
        final s = yearStart(_anchorDate);
        return (s, DateTime(s.year + 1, 1, 1));
    }
  }

  void _stepDate(int delta) {
    setState(() {
      switch (_range) {
        case StatViewRange.day:
          _anchorDate = _anchorDate.add(Duration(days: delta));
        case StatViewRange.week:
          _anchorDate = _anchorDate.add(Duration(days: delta * 7));
        case StatViewRange.month:
          _anchorDate = DateTime(_anchorDate.year, _anchorDate.month + delta, 1);
        case StatViewRange.year:
          _anchorDate = DateTime(_anchorDate.year + delta, 1, 1);
      }
    });
  }

  bool _isCurrentPeriod() {
    final now = DateTime.now();
    switch (_range) {
      case StatViewRange.day:
        return now.year == _anchorDate.year &&
            now.month == _anchorDate.month &&
            now.day == _anchorDate.day;
      case StatViewRange.week:
        final currentWeekStart = weekStart(now);
        final anchorWeekStart = weekStart(_anchorDate);
        return currentWeekStart.year == anchorWeekStart.year &&
            currentWeekStart.month == anchorWeekStart.month &&
            currentWeekStart.day == anchorWeekStart.day;
      case StatViewRange.month:
        return now.year == _anchorDate.year && now.month == _anchorDate.month;
      case StatViewRange.year:
        return now.year == _anchorDate.year;
    }
  }

  String _rangeTitle() {
    final s = strings.value;
    switch (_range) {
      case StatViewRange.day:
        return fmtDayTitle(_anchorDate);
      case StatViewRange.week:
        final (start, end) = _calculateDateRange();
        final prevEnd = end.subtract(const Duration(days: 1));
        return '${fmtDateShort(start)} - ${fmtDateShort(prevEnd)}';
      case StatViewRange.month:
        const trMonths = [
          'Ocak', 'Şubat', 'Mart', 'Nisan', 'Mayıs', 'Haziran',
          'Temmuz', 'Ağustos', 'Eylül', 'Ekim', 'Kasım', 'Aralık'
        ];
        const enMonths = [
          'January', 'February', 'March', 'April', 'May', 'June',
          'July', 'August', 'September', 'October', 'November', 'December'
        ];
        final mName = s.isTr
            ? trMonths[_anchorDate.month - 1]
            : enMonths[_anchorDate.month - 1];
        return '$mName ${_anchorDate.year}';
      case StatViewRange.year:
        return '${_anchorDate.year}';
    }
  }

  IconData _dimIcon(String dim) {
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

  @override
  Widget build(BuildContext context) {
    final s = strings.value;
    final scheme = Theme.of(context).colorScheme;

    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final (from, to) = _calculateDateRange();
        final rawEntries = store.entriesIn(from, to).toList();
        final filteredEntries = rawEntries.where((e) {
          if (_selectedActivityId == null) return true;
          return e.activityId == _selectedActivityId;
        }).toList();

        final allActivities = store.activities.values.toList();
        final byActivity = store.totalsByActivity(from, to);

        // Map of activityId -> entry count in current period
        final activityCounts = <int, int>{};
        for (final e in rawEntries) {
          activityCounts[e.activityId] = (activityCounts[e.activityId] ?? 0) + 1;
        }

        // Sort activities: active ones first
        allActivities.sort((a, b) {
          final ca = activityCounts[a.id] ?? 0;
          final cb = activityCounts[b.id] ?? 0;
          if (ca != cb) return cb.compareTo(ca);
          return a.name.compareTo(b.name);
        });

        return Scaffold(
          appBar: AppBar(
            title: Text(
              s.statsTitle,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.table_chart_outlined),
                tooltip: s.isTr ? 'CSV Dışa Aktar' : 'Export CSV',
                onPressed: () => ExportService.exportCsv(context, store),
              ),
              IconButton(
                icon: const Icon(Icons.picture_as_pdf_outlined),
                tooltip: s.isTr ? 'PDF Raporu Oluştur' : 'Export PDF',
                onPressed: () => ExportService.exportPdf(context, store),
              ),
            ],
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 48),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 1. Range Selector (Day, Week, Month, Year)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: SegmentedButton<StatViewRange>(
                    showSelectedIcon: false,
                    style: ButtonStyle(
                      visualDensity: VisualDensity.compact,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      padding: WidgetStateProperty.all(
                        const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                      ),
                      textStyle: WidgetStateProperty.all(
                        const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                      ),
                    ),
                    segments: [
                      ButtonSegment(value: StatViewRange.day, label: Text(s.viewDay)),
                      ButtonSegment(value: StatViewRange.week, label: Text(s.viewWeek)),
                      ButtonSegment(value: StatViewRange.month, label: Text(s.viewMonth)),
                      ButtonSegment(value: StatViewRange.year, label: Text(s.viewYear)),
                    ],
                    selected: {_range},
                    onSelectionChanged: (set) => setState(() => _range = set.first),
                  ),
                ),

                // 2. Date Navigation Bar (< Date Range > [Bugün])
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: scheme.outlineVariant.withValues(alpha: 0.25),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.chevron_left_rounded),
                        visualDensity: VisualDensity.compact,
                        tooltip: s.isTr ? 'Önceki' : 'Previous',
                        onPressed: () => _stepDate(-1),
                      ),
                      InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: () => setState(() => _anchorDate = DateTime.now()),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.calendar_today_rounded,
                                size: 15,
                                color: scheme.primary,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                _rangeTitle(),
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              if (!_isCurrentPeriod()) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: scheme.primaryContainer,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    s.isTr ? 'Bugün' : 'Today',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: scheme.onPrimaryContainer,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.chevron_right_rounded),
                        visualDensity: VisualDensity.compact,
                        tooltip: s.isTr ? 'Sonraki' : 'Next',
                        onPressed: () => _stepDate(1),
                      ),
                    ],
                  ),
                ),

                // 3. Activity Filter Chips
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Row(
                    children: [
                      FilterChip(
                        showCheckmark: _selectedActivityId == null,
                        avatar: _selectedActivityId == null
                            ? null
                            : const Icon(Icons.apps_rounded, size: 16),
                        label: Text(
                          _selectedActivityId == null
                              ? '${s.filterAll} (${rawEntries.length})'
                              : s.filterAll,
                        ),
                        selected: _selectedActivityId == null,
                        onSelected: (_) => setState(() => _selectedActivityId = null),
                      ),
                      for (final act in allActivities) ...[
                        const SizedBox(width: 8),
                        FilterChip(
                          avatar: act.emoji != null && act.emoji!.isNotEmpty
                              ? Text(act.emoji!, style: const TextStyle(fontSize: 14))
                              : ActivityAvatar(act.id, size: 20),
                          label: Text(
                            (activityCounts[act.id] ?? 0) > 0
                                ? '${act.name} (${activityCounts[act.id]})'
                                : act.name,
                          ),
                          selected: _selectedActivityId == act.id,
                          onSelected: (_) {
                            setState(() {
                              if (_selectedActivityId == act.id) {
                                _selectedActivityId = null;
                              } else {
                                _selectedActivityId = act.id;
                              }
                            });
                          },
                        ),
                      ],
                    ],
                  ),
                ),

                const SizedBox(height: 6),

                // Active filter banner (if an activity is filtered)
                if (_selectedActivityId != null) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: Material(
                      color: scheme.primaryContainer.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(14),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        child: Row(
                          children: [
                            ActivityAvatar(_selectedActivityId!, size: 30),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                s.isTr
                                    ? '"${store.activity(_selectedActivityId!).name}" filtresi aktif'
                                    : 'Filtered by "${store.activity(_selectedActivityId!).name}"',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                  color: scheme.onSurface,
                                ),
                              ),
                            ),
                            TextButton.icon(
                              style: TextButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                padding: const EdgeInsets.symmetric(horizontal: 8),
                              ),
                              icon: const Icon(Icons.close_rounded, size: 16),
                              label: Text(
                                s.isTr ? 'Filtreyi Kaldır' : 'Clear',
                                style: const TextStyle(fontSize: 12),
                              ),
                              onPressed: () => setState(() => _selectedActivityId = null),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],

                // 4. Main Stats KPI Overview Card
                _buildOverviewCard(filteredEntries, from, to),

                const SizedBox(height: 8),

                // 5. Trend Bar Chart (fl_chart)
                _buildTrendBarChart(filteredEntries, from, to, _range),

                // 6. Category Pie Chart (fl_chart)
                if (_selectedActivityId == null && filteredEntries.isNotEmpty)
                  _buildCategoryPieChart(filteredEntries),

                const SizedBox(height: 8),

                // 7. Measure breakdown or activity ranking
                if (_selectedActivityId != null) ...[
                  _buildSingleActivityHeatmapAndStreakCard(_selectedActivityId!),
                  const SizedBox(height: 8),
                  _buildSingleActivityBreakdown(filteredEntries, _selectedActivityId!),
                ] else
                  _buildAllActivitiesRanking(byActivity, rawEntries.length),

                const SizedBox(height: 12),

                // 8. Reporting and export card
                _buildExportCard(),
              ],
            ),
          ),
        );
      },
    );
  }

  // ---------------------------------------------------------------- KPI Overview Card
  Widget _buildOverviewCard(List<Entry> entries, DateTime from, DateTime to) {
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
    switch (_range) {
      case StatViewRange.day:
        periodDays = 1;
        break;
      case StatViewRange.week:
        periodDays = 7;
        break;
      case StatViewRange.month:
        periodDays = DateTime(from.year, from.month + 1, 0).day;
        break;
      case StatViewRange.year:
        periodDays = (to.difference(from).inHours / 24).round();
        break;
    }
    if (periodDays <= 0) periodDays = 1;

    final avgPerDay = (totalLogs / periodDays).toStringAsFixed(1);

    // Peak active hour or day
    String peakText = '-';
    if (entries.isNotEmpty) {
      if (_range == StatViewRange.day) {
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
      } else if (_range == StatViewRange.week) {
        final dayNames = s.isTr
            ? ['Pzt', 'Sal', 'Çar', 'Per', 'Cum', 'Cmt', 'Paz']
            : ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
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
          peakText = '${dayNames[maxIdx]} (${counts[maxIdx]})';
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
                  child: _buildKpiBox(
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
                  child: _buildKpiBox(
                    title: mainDim != null
                        ? store.dimName(mainDim)
                        : (s.isTr ? 'Toplam Süre' : 'Total Duration'),
                    value: mainDim != null && periodTotal.byDim[mainDim] != null
                        ? store.fmtBase(periodTotal.byDim[mainDim]!, mainDim)
                        : (totalLogs > 0 ? '$totalLogs' : '0'),
                    subtitle: mainDim != null
                        ? (s.isTr ? 'Ana odak' : 'Main focus')
                        : (s.isTr ? 'Kayıt adedi' : 'Log count'),
                    icon: _dimIcon(mainDim ?? 'time'),
                    color: Colors.amber.shade700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _buildKpiBox(
                    title: s.isTr ? 'Günlük Ortalama' : 'Daily Average',
                    value: avgPerDay,
                    subtitle: s.isTr ? 'Kayıt / gün' : 'Logs / day',
                    icon: Icons.trending_up_rounded,
                    color: Colors.teal.shade600,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _buildKpiBox(
                    title: s.isTr ? 'Zirve Noktası' : 'Peak Activity',
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
                              _dimIcon(entry.key),
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

  Widget _buildKpiBox({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color color,
  }) {
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

  // ---------------------------------------------------------------- Trend Bar Chart
  Widget _buildTrendBarChart(
    List<Entry> entries,
    DateTime from,
    DateTime to,
    StatViewRange range,
  ) {
    final s = strings.value;
    final scheme = Theme.of(context).colorScheme;

    final barGroups = <BarChartGroupData>[];
    final titles = <String>[];
    double barWidth = 16;

    if (range == StatViewRange.week) {
      barWidth = 18;
      final dayNames = s.isTr
          ? ['Pzt', 'Sal', 'Çar', 'Per', 'Cum', 'Cmt', 'Paz']
          : ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      for (var i = 0; i < 7; i++) {
        final currentDay = from.add(Duration(days: i));
        final dayEntries = entries.where((e) {
          final dt = DateTime.fromMillisecondsSinceEpoch(e.ts);
          return dt.year == currentDay.year &&
              dt.month == currentDay.month &&
              dt.day == currentDay.day;
        }).length;
        barGroups.add(
          BarChartGroupData(
            x: i,
            barRods: [
              BarChartRodData(
                toY: dayEntries.toDouble(),
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: dayEntries > 0
                      ? [scheme.primary, scheme.secondary]
                      : [
                          scheme.outlineVariant.withValues(alpha: 0.2),
                          scheme.outlineVariant.withValues(alpha: 0.2),
                        ],
                ),
                width: barWidth,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(7)),
              ),
            ],
          ),
        );
        titles.add(dayNames[i]);
      }
    } else if (range == StatViewRange.day) {
      barWidth = 24;
      final blockNames = ['00-04', '04-08', '08-12', '12-16', '16-20', '20-24'];
      for (var b = 0; b < 6; b++) {
        final startH = b * 4;
        final endH = startH + 4;
        final count = entries.where((e) {
          final h = DateTime.fromMillisecondsSinceEpoch(e.ts).hour;
          return h >= startH && h < endH;
        }).length;
        barGroups.add(
          BarChartGroupData(
            x: b,
            barRods: [
              BarChartRodData(
                toY: count.toDouble(),
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: count > 0
                      ? [scheme.primary, scheme.secondary]
                      : [
                          scheme.outlineVariant.withValues(alpha: 0.2),
                          scheme.outlineVariant.withValues(alpha: 0.2),
                        ],
                ),
                width: barWidth,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(7)),
              ),
            ],
          ),
        );
        titles.add(blockNames[b]);
      }
    } else if (range == StatViewRange.year) {
      barWidth = 12;
      final monthLabels = s.isTr
          ? ['Oca', 'Şub', 'Mar', 'Nis', 'May', 'Haz', 'Tem', 'Ağu', 'Eyl', 'Eki', 'Kas', 'Ara']
          : ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      for (var m = 1; m <= 12; m++) {
        final count = entries.where((e) {
          final dt = DateTime.fromMillisecondsSinceEpoch(e.ts);
          return dt.year == from.year && dt.month == m;
        }).length;
        barGroups.add(
          BarChartGroupData(
            x: m - 1,
            barRods: [
              BarChartRodData(
                toY: count.toDouble(),
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: count > 0
                      ? [scheme.primary, scheme.secondary]
                      : [
                          scheme.outlineVariant.withValues(alpha: 0.2),
                          scheme.outlineVariant.withValues(alpha: 0.2),
                        ],
                ),
                width: barWidth,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(5)),
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
        final startD = from.add(Duration(days: w * 7));
        final endD = from.add(Duration(days: min((w + 1) * 7, daysInMonth)));
        final count = entries.where((e) {
          final dt = DateTime.fromMillisecondsSinceEpoch(e.ts);
          return !dt.isBefore(startD) && dt.isBefore(endD);
        }).length;
        barGroups.add(
          BarChartGroupData(
            x: w,
            barRods: [
              BarChartRodData(
                toY: count.toDouble(),
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: count > 0
                      ? [scheme.primary, scheme.secondary]
                      : [
                          scheme.outlineVariant.withValues(alpha: 0.2),
                          scheme.outlineVariant.withValues(alpha: 0.2),
                        ],
                ),
                width: barWidth,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(7)),
              ),
            ],
          ),
        );
        titles.add('${w + 1}.Hft');
      }
    }

    final maxY = barGroups.map((g) => g.barRods.first.toY).fold(0.0, max);
    final topY = maxY < 5 ? 5.0 : (maxY * 1.25).ceilToDouble();

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
                          '${titles[peakGroup.x]} (${peakVal.toInt()})',
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
            const SizedBox(height: 20),
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
                              text: '${rod.toY.toInt()} ${s.isTr ? "kayıt" : "logs"}',
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
                        reservedSize: 28,
                        interval: topY > 10 ? (topY / 4).roundToDouble() : 1,
                        getTitlesWidget: (val, _) => Text(
                          val.toInt().toString(),
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w500,
                            color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
                          ),
                        ),
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (val, _) {
                          final idx = val.toInt();
                          if (idx >= 0 && idx < titles.length) {
                            return Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text(
                                titles[idx],
                                style: TextStyle(
                                  fontSize: range == StatViewRange.year ? 9.5 : 11,
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

  // ---------------------------------------------------------------- Category Donut Chart
  Widget _buildCategoryPieChart(List<Entry> entries) {
    final s = strings.value;
    final scheme = Theme.of(context).colorScheme;

    if (entries.isEmpty) return const SizedBox.shrink();

    final catCounts = <String, (CategoryDef def, int count)>{};
    for (final e in entries) {
      final act = store.activities[e.activityId];
      final def = act?.categoryDef ?? getCategoryDef(null);
      final prev = catCounts[def.id] ?? (def, 0);
      catCounts[def.id] = (def, prev.$2 + 1);
    }

    final total = entries.length;
    final sortedCats = catCounts.values.toList()
      ..sort((a, b) => b.$2.compareTo(a.$2));

    final sections = sortedCats.map((item) {
      final pct = (item.$2 / total) * 100;
      return PieChartSectionData(
        value: item.$2.toDouble(),
        title: pct >= 12 ? '%${pct.round()}' : '',
        color: Color(item.$1.colorValue),
        radius: 34,
        titleStyle: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      );
    }).toList();

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
                  child: Icon(Icons.pie_chart_rounded, size: 18, color: scheme.primary),
                ),
                const SizedBox(width: 10),
                Text(
                  s.isTr ? 'Kategori Dağılımı' : 'Category Distribution',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const Spacer(),
                Text(
                  '${sortedCats.length} ${s.isTr ? "Kategori" : "Categories"}',
                  style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                // Donut Chart with centered total logs count
                SizedBox(
                  width: 124,
                  height: 124,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      PieChart(
                        PieChartData(
                          sections: sections,
                          centerSpaceRadius: 30,
                          sectionsSpace: 2.5,
                        ),
                      ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '$total',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: scheme.onSurface,
                            ),
                          ),
                          Text(
                            s.isTr ? 'Kayıt' : 'Logs',
                            style: TextStyle(
                              fontSize: 10,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                // Categories breakdown list with proportional bars
                Expanded(
                  child: Column(
                    children: sortedCats.map((item) {
                      final ratio = item.$2 / total;
                      final pctStr = (ratio * 100).toStringAsFixed(0);
                      final catColor = Color(item.$1.colorValue);

                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: catColor,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    '${item.$1.emoji} ${item.$1.name(s.isTr)}',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Text(
                                  '${item.$2} (%$pctStr)',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.bold,
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 3),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(3),
                              child: LinearProgressIndicator(
                                value: ratio,
                                minHeight: 4,
                                backgroundColor:
                                    scheme.surfaceContainerHighest.withValues(alpha: 0.4),
                                valueColor: AlwaysStoppedAnimation<Color>(catColor),
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- Activity Leaderboard / Ranking
  Widget _buildAllActivitiesRanking(
    Map<int, PeriodTotal> byActivity,
    int totalLogsInPeriod,
  ) {
    final s = strings.value;
    final scheme = Theme.of(context).colorScheme;
    final sortedActivities = byActivity.entries.toList()
      ..sort((a, b) => b.value.count.compareTo(a.value.count));

    final maxCount = sortedActivities.isEmpty ? 1 : sortedActivities.first.value.count;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionTitle(
            s.isTr ? 'Aktivite Sıralaması' : 'Activity Ranking',
            trailing: sortedActivities.isNotEmpty
                ? Text(
                    '${sortedActivities.length} ${s.isTr ? "aktivite" : "activities"}',
                    style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                  )
                : null,
          ),
          if (sortedActivities.isEmpty)
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
                side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.3)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Center(
                  child: Column(
                    children: [
                      Icon(
                        Icons.analytics_outlined,
                        size: 40,
                        color: scheme.outlineVariant,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        s.isTr
                            ? 'Bu dönemde kayıt bulunamadı.'
                            : 'No entries found in this period.',
                        style: TextStyle(
                          color: scheme.onSurfaceVariant,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else
            for (var i = 0; i < sortedActivities.length; i++) ...[
              Builder(builder: (c) {
                final item = sortedActivities[i];
                final act = store.activity(item.key);
                final total = item.value;
                final totalStr = store.totalText(total);
                final ratio = total.count / maxCount;
                final pctOfTotal = totalLogsInPeriod > 0
                    ? ((total.count / totalLogsInPeriod) * 100).round()
                    : 0;

                // Rank styling
                Widget rankBadge;
                if (i == 0) {
                  rankBadge = Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.amber.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.amber.shade600.withValues(alpha: 0.5)),
                    ),
                    child: Text(
                      '🥇 #1',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.amber.shade800,
                      ),
                    ),
                  );
                } else if (i == 1) {
                  rankBadge = Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.blueGrey.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blueGrey.shade400.withValues(alpha: 0.5)),
                    ),
                    child: Text(
                      '🥈 #2',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.blueGrey.shade700,
                      ),
                    ),
                  );
                } else if (i == 2) {
                  rankBadge = Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.brown.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.brown.shade400.withValues(alpha: 0.5)),
                    ),
                    child: Text(
                      '🥉 #3',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.brown.shade700,
                      ),
                    ),
                  );
                } else {
                  rankBadge = Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '#${i + 1}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  );
                }

                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                    side: BorderSide(
                      color: scheme.outlineVariant.withValues(alpha: 0.25),
                    ),
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(18),
                    onTap: () => setState(() => _selectedActivityId = act.id),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              rankBadge,
                              const SizedBox(width: 8),
                              ActivityAvatar(act.id, size: 36),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Flexible(
                                          child: Text(
                                            act.name,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 14.5,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        if (act.isHabit) ...[
                                          const SizedBox(width: 4),
                                          const Text('🔥', style: TextStyle(fontSize: 12)),
                                        ],
                                      ],
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      totalStr,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: scheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    '${total.count} ${s.isTr ? "giriş" : "logs"}',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      color: scheme.primary,
                                    ),
                                  ),
                                  Text(
                                    '%$pctOfTotal',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: scheme.onSurfaceVariant.withValues(alpha: 0.8),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(width: 4),
                              Icon(
                                Icons.chevron_right_rounded,
                                size: 18,
                                color: scheme.onSurfaceVariant.withValues(alpha: 0.6),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          // Relative volume progress bar
                          ClipRRect(
                            borderRadius: BorderRadius.circular(3),
                            child: LinearProgressIndicator(
                              value: ratio,
                              minHeight: 5,
                              backgroundColor:
                                  scheme.surfaceContainerHighest.withValues(alpha: 0.4),
                              valueColor: AlwaysStoppedAnimation<Color>(act.displayColor),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ],
        ],
      ),
    );
  }

  // ---------------------------------------------------------------- Single Activity Heatmap & Streak Card
  Widget _buildSingleActivityHeatmapAndStreakCard(int activityId) {
    final s = strings.value;
    final act = store.activity(activityId);
    final scheme = Theme.of(context).colorScheme;
    final streakInfo = store.habitStreakInfo(activityId);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: act.displayColor.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.grid_on_rounded, size: 18, color: act.displayColor),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              s.isTr ? '${act.name} Katkı Haritası' : '${act.name} Contributions',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (act.isHabit) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.orange.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                '🔥 ${s.tabHabits}',
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.orange,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '🔥 ${s.currentStreak}: ${streakInfo.currentStreak} ${s.isTr ? "Gün" : "Days"} · 🏆 ${s.longestStreak}: ${streakInfo.longestStreak} ${s.isTr ? "Gün" : "Days"}',
                        style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: act.isHabit
                      ? (s.isTr ? 'Alışkanlık takibi devrede' : 'Habit tracking active')
                      : (s.isTr ? 'Alışkanlık olarak aç' : 'Enable habit tracking'),
                  icon: Icon(
                    act.isHabit ? Icons.local_fire_department_rounded : Icons.local_fire_department_outlined,
                    color: act.isHabit ? Colors.orange : scheme.onSurfaceVariant,
                  ),
                  onPressed: () async {
                    await store.setActivityHabit(act.id, !act.isHabit);
                  },
                ),
              ],
            ),
            const SizedBox(height: 14),
            ContributionHeatmap(
              dailyCounts: streakInfo.dailyCounts,
              baseColor: act.displayColor,
              weekCount: 20,
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- Single Activity Breakdown
  Widget _buildSingleActivityBreakdown(List<Entry> entries, int activityId) {
    final s = strings.value;
    final act = store.activity(activityId);
    final scheme = Theme.of(context).colorScheme;

    final measureCounts = <int?, (int count, double totalValue)>{};
    for (final e in entries) {
      final prev = measureCounts[e.measureId] ?? (0, 0.0);
      measureCounts[e.measureId] = (prev.$1 + 1, prev.$2 + (e.value ?? 0.0));
    }

    final maxCount = measureCounts.values.fold<int>(
      1,
      (prev, curr) => curr.$1 > prev ? curr.$1 : prev,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionTitle(
            s.isTr ? '${act.name} Ölçü Dağılımı' : '${act.name} Breakdown',
            trailing: TextButton.icon(
              icon: const Icon(Icons.arrow_back_rounded, size: 16),
              label: Text(s.isTr ? 'Tümüne Dön' : 'Back to All'),
              onPressed: () => setState(() => _selectedActivityId = null),
            ),
          ),
          if (measureCounts.isEmpty)
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
                side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.3)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Center(
                  child: Text(
                    s.isTr
                        ? 'Bu dönemde kayıt bulunamadı.'
                        : 'No entries found in this period.',
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                ),
              ),
            )
          else
            for (final entry in measureCounts.entries) ...[
              Builder(builder: (c) {
                final m = store.measureById(entry.key);
                final measureName =
                    m?.name ?? (s.isTr ? 'Ölçüsüz / Standart' : 'Standard count');
                final count = entry.value.$1;
                final val = entry.value.$2;
                final ratio = count / maxCount;

                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                    side: BorderSide(
                      color: scheme.outlineVariant.withValues(alpha: 0.25),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: scheme.primaryContainer.withValues(alpha: 0.4),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                m != null ? Icons.straighten_rounded : Icons.tag_rounded,
                                size: 18,
                                color: scheme.primary,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    measureName,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14.5,
                                    ),
                                  ),
                                  Text(
                                    '$count ${s.isTr ? "kez kullanıldı" : "times"}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: scheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (m != null && val > 0)
                              Text(
                                store.fmtBase(
                                  val * store.unit(m.unitId).factor,
                                  store.unit(m.unitId).dim,
                                ),
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  color: scheme.primary,
                                ),
                              )
                            else
                              Text(
                                '$count ${s.isTr ? "adet" : "items"}',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: scheme.primary,
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: LinearProgressIndicator(
                            value: ratio,
                            minHeight: 4,
                            backgroundColor:
                                scheme.surfaceContainerHighest.withValues(alpha: 0.4),
                            valueColor: AlwaysStoppedAnimation<Color>(scheme.primary),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ],
        ],
      ),
    );
  }

  // ---------------------------------------------------------------- Export Card
  Widget _buildExportCard() {
    final s = strings.value;
    final scheme = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.3)),
      ),
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.25),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.ios_share_rounded, size: 18, color: scheme.primary),
                ),
                const SizedBox(width: 10),
                Text(
                  s.isTr ? 'Raporlama & Veri Paylaşımı' : 'Reporting & Export',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              s.isTr
                  ? 'Seçili döneme ait kayıtlarınızı PDF raporu veya Excel uyumlu CSV tablosu olarak cihazınıza aktarın.'
                  : 'Export all records for the selected period as a PDF report or Excel-compatible CSV table.',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    icon: const Icon(Icons.picture_as_pdf_rounded, size: 18),
                    label: Text(s.isTr ? 'PDF Raporu' : 'PDF Report'),
                    onPressed: () => ExportService.exportPdf(context, store),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.tonalIcon(
                    icon: const Icon(Icons.table_chart_rounded, size: 18),
                    label: Text(s.isTr ? 'Excel (CSV)' : 'Excel (CSV)'),
                    onPressed: () => ExportService.exportCsv(context, store),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
