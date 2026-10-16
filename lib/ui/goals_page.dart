import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/store.dart';
import '../logic/format.dart';
import '../logic/l10n.dart';
import 'common.dart';
import 'components/goal_edit_dialog.dart';
import 'contribution_heatmap.dart';
import 'tabs/habits_tab.dart';
import 'tabs/roadmaps_tab.dart';
import 'app_font.dart';

enum GoalsPageTab { goals, habits, roadmaps }

class GoalsPage extends StatefulWidget {
  const GoalsPage({super.key});

  @override
  State<GoalsPage> createState() => _GoalsPageState();
}

class _GoalsPageState extends State<GoalsPage> {
  GoalsPageTab _currentTab = GoalsPageTab.goals;
  GoalPeriod? _filterPeriod;
  final Set<int> _expandedGoalHeatmapIds = {};

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final s = strings.value;
        final scheme = Theme.of(context).colorScheme;
        final allGoals = store.goals;
        final filteredGoals = _filterPeriod == null
            ? allGoals
            : allGoals.where((g) => g.period == _filterPeriod).toList();
        final habits = store.habitActivities;
        final totalHabitsCount = habits.length;
        final roadmapsCount = store.roadmaps.length;

        return Scaffold(
          appBar: AppBar(
            title: Text(
              _currentTab == GoalsPageTab.goals
                  ? (s.isTr ? 'Hedefler' : 'Goals')
                  : (_currentTab == GoalsPageTab.habits
                      ? s.habitTitle
                      : s.roadmapsTitle),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          body: Column(
            children: [
              // Segmented switcher: [ Hedefler | 🔥 Zinciri Kırma | 🗺️ Yol Haritası ]
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 6, 6, 8),
                child: SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<GoalsPageTab>(
                    showSelectedIcon: false,
                    style: SegmentedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 6),
                    ),
                    segments: [
                      ButtonSegment(
                        value: GoalsPageTab.goals,
                        // Dar ekranda kesilmek yerine sığacak kadar küçülür.
                        label: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            s.isTr ? 'Hedefler' : 'Goals',
                            style: const TextStyle(fontSize: AppFont.micro, fontWeight: FontWeight.w600, letterSpacing: -0.2),
                            maxLines: 1,
                          ),
                        ),
                        icon: const Icon(Icons.flag_outlined, size: 14),
                      ),
                      ButtonSegment(
                        value: GoalsPageTab.habits,
                        label: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            totalHabitsCount == 0
                                ? (s.isTr ? 'Zinciri Kırma' : 'Habits')
                                : '${s.isTr ? "Zinciri Kırma" : "Habits"} ($totalHabitsCount)',
                            style: const TextStyle(fontSize: AppFont.micro, fontWeight: FontWeight.w600, letterSpacing: -0.2),
                            maxLines: 1,
                          ),
                        ),
                        icon: const Icon(Icons.local_fire_department_rounded, size: 14),
                      ),
                      ButtonSegment(
                        value: GoalsPageTab.roadmaps,
                        label: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            roadmapsCount == 0
                                ? s.tabRoadmaps
                                : '${s.tabRoadmaps} ($roadmapsCount)',
                            style: const TextStyle(fontSize: AppFont.micro, fontWeight: FontWeight.w600, letterSpacing: -0.2),
                            maxLines: 1,
                          ),
                        ),
                        icon: const Icon(Icons.alt_route_rounded, size: 14),
                      ),
                    ],
                    selected: {_currentTab},
                    onSelectionChanged: (set) => setState(() => _currentTab = set.first),
                  ),
                ),
              ),

              if (_currentTab == GoalsPageTab.goals) ...[
                // Period Filter Chips
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Row(
                    children: [
                      FilterChip(
                        label: Text(s.isTr ? 'Tümü' : 'All'),
                        selected: _filterPeriod == null,
                        onSelected: (_) => setState(() => _filterPeriod = null),
                      ),
                      const SizedBox(width: 8),
                      FilterChip(
                        label: Text(s.isTr ? 'Günlük' : 'Daily'),
                        selected: _filterPeriod == GoalPeriod.day,
                        onSelected: (_) => setState(() => _filterPeriod = GoalPeriod.day),
                      ),
                      const SizedBox(width: 8),
                      FilterChip(
                        label: Text(s.isTr ? 'Haftalık' : 'Weekly'),
                        selected: _filterPeriod == GoalPeriod.week,
                        onSelected: (_) => setState(() => _filterPeriod = GoalPeriod.week),
                      ),
                      const SizedBox(width: 8),
                      FilterChip(
                        label: Text(s.isTr ? 'Aylık' : 'Monthly'),
                        selected: _filterPeriod == GoalPeriod.month,
                        onSelected: (_) => setState(() => _filterPeriod = GoalPeriod.month),
                      ),
                      const SizedBox(width: 8),
                      FilterChip(
                        label: Text(s.isTr ? 'Toplam / Bitişli' : 'Total / Cumulative'),
                        selected: _filterPeriod == GoalPeriod.total,
                        onSelected: (_) => setState(() => _filterPeriod = GoalPeriod.total),
                      ),
                    ],
                  ),
                ),

                // Goals List
                Expanded(
                  child: filteredGoals.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.flag_outlined, size: 54, color: scheme.outline),
                              const SizedBox(height: 12),
                              Text(
                                s.isTr ? 'Henüz hedef eklenmedi.' : 'No goals created yet.',
                                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: AppFont.subtitle),
                              ),
                              const SizedBox(height: 12),
                              FilledButton.icon(
                                icon: const Icon(Icons.add),
                                label: Text(s.newGoal),
                                onPressed: () => GoalEditDialog.show(context),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          itemCount: filteredGoals.length,
                          itemBuilder: (context, i) {
                            final goal = filteredGoals[i];
                            return _buildGoalCard(context, goal);
                          },
                        ),
                ),
              ] else if (_currentTab == GoalsPageTab.habits) ...[
                // Habits (Zinciri Kırma) List
                const Expanded(
                  child: HabitsTab(),
                ),
              ] else ...[
                // Roadmaps (Yol Haritaları) List
                const Expanded(
                  child: RoadmapsTab(),
                ),
              ],
            ],
          ),
          floatingActionButton: _currentTab == GoalsPageTab.goals
              ? FloatingActionButton(
                  onPressed: () => GoalEditDialog.show(context),
                  child: const Icon(Icons.add),
                )
              : (_currentTab == GoalsPageTab.habits
                  ? FloatingActionButton.extended(
                      onPressed: () => HabitsTab.pickAndAddHabit(context),
                      icon: const Icon(Icons.add),
                      label: Text(s.addHabit),
                    )
                  : FloatingActionButton.extended(
                      onPressed: () => RoadmapsTab.showCreateOptions(context),
                      icon: const Icon(Icons.add_road_rounded),
                      label: Text(s.isTr ? 'Yol Haritası Ekle' : 'Add Roadmap'),
                    )),
        );
      },
    );
  }

  Widget _buildGoalCard(BuildContext context, Goal goal) {
    final s = strings.value;
    final scheme = Theme.of(context).colorScheme;
    final activityBreakdown = <int, double>{};
    final status = store.goalStatus(goal, byActivity: activityBreakdown);
    final unitSym = store.goalUnitSymbol(goal);
    final isDone = status.done;
    final streak = store.goalStreak(goal);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: isDone ? 2 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: goal.isLimit
            ? (status.isExceeded
                ? BorderSide(color: Colors.red.shade400, width: 1.5)
                : BorderSide(color: Colors.green.shade500, width: 1.5))
            : (isDone
                ? BorderSide(color: Colors.green.shade500, width: 1.5)
                : BorderSide(color: scheme.outlineVariant, width: 0.8)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => GoalEditDialog.show(context, existing: goal),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
            // Title & Status header
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              goal.name,
                              style: const TextStyle(
                                fontSize: AppFont.subtitle,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          if (goal.isLimit) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: status.isExceeded ? Colors.red.shade100 : Colors.green.shade100,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    status.isExceeded ? Icons.warning_amber_rounded : Icons.check,
                                    size: 14,
                                    color: status.isExceeded ? Colors.red.shade900 : Colors.green.shade800,
                                  ),
                                  const SizedBox(width: 2),
                                  Text(
                                    status.isExceeded ? s.limitExceeded : s.limitWithin,
                                    style: TextStyle(
                                      fontSize: AppFont.micro,
                                      fontWeight: FontWeight.bold,
                                      color: status.isExceeded ? Colors.red.shade900 : Colors.green.shade900,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ] else if (isDone) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.green.shade100,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.check, size: 14, color: Colors.green.shade800),
                                  const SizedBox(width: 2),
                                  Text(
                                    s.isTr ? 'Tamamlandı' : 'Achieved',
                                    style: TextStyle(
                                      fontSize: AppFont.micro,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.green.shade900,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: goal.isLimit
                                  ? Colors.orange.withValues(alpha: 0.15)
                                  : scheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              goal.isLimit ? '🛡️ Limit' : (strings.value.isTr ? '🎯 Hedef' : '🎯 Goal'),
                              style: TextStyle(
                                fontSize: AppFont.micro,
                                fontWeight: FontWeight.bold,
                                color: goal.isLimit ? Colors.orange.shade900 : scheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: scheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              periodName(goal.period, isTr: strings.value.isTr),
                              style: TextStyle(fontSize: AppFont.micro, color: scheme.onSurfaceVariant),
                            ),
                          ),
                          if (streak > 1) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.orange.shade100,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                '🔥 $streak ${s.isTr ? "seri" : "streak"}',
                                style: TextStyle(
                                  fontSize: AppFont.micro,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.orange.shade900,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert),
                  onSelected: (val) async {
                    if (val == 'edit') {
                      GoalEditDialog.show(context, existing: goal);
                    } else if (val == 'delete') {
                      final ok = await confirm(
                        context,
                        s.deleteConfirmTitle,
                        '${goal.name} ${s.deleteConfirmDesc}',
                      );
                      if (ok) store.deleteGoal(goal);
                    }
                  },
                  itemBuilder: (c) => [
                    PopupMenuItem(value: 'edit', child: Text(s.edit)),
                    PopupMenuItem(
                      value: 'delete',
                      child: Text(s.delete, style: TextStyle(color: scheme.error)),
                    ),
                  ],
                ),
              ],
            ),

            const SizedBox(height: 12),

            // Progress bar and numbers
            LinearProgressIndicator(
              value: status.ratio.clamp(0.0, 1.0),
              minHeight: 8,
              borderRadius: BorderRadius.circular(4),
              color: goal.isLimit
                  ? (status.isExceeded
                      ? Colors.red.shade600
                      : (status.ratio > 0.8 ? Colors.orange.shade600 : Colors.green.shade600))
                  : (isDone ? Colors.green.shade600 : scheme.primary),
              backgroundColor: scheme.surfaceContainerHighest,
            ),
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Limit hedefinde metin uzundur; dar ekranda ya da büyük yazıda ikinci satıra geçer.
                Expanded(
                  child: Text(
                    goal.isLimit
                        ? (status.isExceeded
                            ? '${fmtNum(status.value)} / ${fmtNum(goal.target)} $unitSym (+${fmtNum(status.exceededAmount)} ${s.exceededAmount})'
                            : '${fmtNum(status.value)} / ${fmtNum(goal.target)} $unitSym (${s.remainingLimit}: ${fmtNum(status.remaining)})')
                        : '${fmtNum(status.value)} / ${fmtNum(goal.target)} $unitSym',
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: AppFont.small),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  fmtPercent((status.ratio * 100).floor()),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: AppFont.small,
                    color: goal.isLimit
                        ? (status.isExceeded
                            ? Colors.red.shade700
                            : (status.ratio > 0.8 ? Colors.orange.shade700 : Colors.green.shade700))
                        : (isDone ? Colors.green.shade700 : scheme.primary),
                  ),
                ),
              ],
            ),

            // End Date & Remaining info
            if (goal.endDate != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Icon(Icons.calendar_today, size: 16, color: scheme.primary),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '${s.endDate}: ${fmtDate(DateTime.fromMillisecondsSinceEpoch(goal.endDate!), isTr: s.isTr)} (${fmtDaysLeft(status.daysLeft ?? 0, isTr: s.isTr)})',
                        style: const TextStyle(fontSize: AppFont.caption),
                      ),
                    ),
                    if (status.perDayNeeded != null && status.perDayNeeded! > 0)
                      Text(
                        '~${fmtNum1(status.perDayNeeded!)} $unitSym/${s.isTr ? "gün" : "day"}',
                        style: TextStyle(
                          fontSize: AppFont.caption,
                          fontWeight: FontWeight.bold,
                          color: scheme.primary,
                        ),
                      ),
                  ],
                ),
              ),
            ],

            // Connected Activities with contribution % and current breakdown
            if (goal.links.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                s.linkedActivities,
                style: TextStyle(
                  fontSize: AppFont.caption,
                  fontWeight: FontWeight.bold,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final link in goal.links) ...[
                    Builder(builder: (c) {
                      final act = store.activity(link.activityId);
                      final contribVal = activityBreakdown[act.id] ?? 0.0;
                      final prop = store.findActivityProperty(link.propertyId);
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: act.displayColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: act.displayColor.withValues(alpha: 0.3), width: 0.8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(act.emoji ?? '🔹', style: const TextStyle(fontSize: AppFont.caption)),
                            const SizedBox(width: 4),
                            Text(
                              prop != null ? '${act.name} (${prop.name})' : act.name,
                              style: TextStyle(
                                fontSize: AppFont.caption,
                                fontWeight: FontWeight.w600,
                                color: act.displayColor,
                              ),
                            ),
                            if (link.pct != 100) ...[
                              const SizedBox(width: 2),
                              Text(
                                ' (${fmtPercent(fmtNum(link.pct))})',
                                style: TextStyle(fontSize: AppFont.micro, color: scheme.onSurfaceVariant),
                              ),
                            ],
                            if (contribVal > 0) ...[
                              const SizedBox(width: 4),
                              Text(
                                '• ${fmtNum(contribVal)} $unitSym',
                                style: TextStyle(
                                  fontSize: AppFont.micro,
                                  fontWeight: FontWeight.bold,
                                  color: scheme.primary,
                                ),
                              ),
                            ],
                          ],
                        ),
                      );
                    }),
                  ],
                ],
              ),
            ],
            const SizedBox(height: 12),
            InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () {
                setState(() {
                  if (_expandedGoalHeatmapIds.contains(goal.id)) {
                    _expandedGoalHeatmapIds.remove(goal.id);
                  } else {
                    _expandedGoalHeatmapIds.add(goal.id);
                  }
                });
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.calendar_month_rounded,
                      size: 16,
                      color: goal.isLimit ? Colors.orange.shade800 : scheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        s.timeSpreadView,
                        style: TextStyle(
                          fontSize: AppFont.small,
                          fontWeight: FontWeight.w600,
                          color: scheme.onSurface,
                        ),
                      ),
                    ),
                    Icon(
                      _expandedGoalHeatmapIds.contains(goal.id)
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                      size: 20,
                      color: scheme.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),
            if (_expandedGoalHeatmapIds.contains(goal.id)) ...[
              const SizedBox(height: 10),
              Builder(
                builder: (c) {
                  final streakInfo = store.goalStreakInfo(goal);
                  // Seriler hedefin dönemini sayar: haftalık hedefte hafta, aylık hedefte ay.
                  final (streakUnit, rateLabel) = switch (streakInfo.streakPeriod) {
                    GoalPeriod.week => (s.isTr ? 'Hafta' : 'wk', s.isTr ? '12H Başarı' : '12 wk Rate'),
                    GoalPeriod.month => (s.isTr ? 'Ay' : 'mo', s.isTr ? '12A Başarı' : '12 mo Rate'),
                    _ => (s.isTr ? 'Gün' : 'd', s.isTr ? '30G Başarı' : '30d Rate'),
                  };
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: _buildMiniStat(
                              '🔥 ${s.isTr ? "Seri" : "Streak"}',
                              '${streakInfo.currentStreak} $streakUnit',
                              Colors.orange,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: _buildMiniStat(
                              '🏆 ${s.longestStreak}',
                              '${streakInfo.longestStreak} $streakUnit',
                              Colors.amber,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: _buildMiniStat(
                              '📈 $rateLabel',
                              fmtPercent(streakInfo.consistencyLast30.round()),
                              Colors.blue,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      ContributionHeatmap(
                        dailyCounts: streakInfo.dailyCounts,
                        dailyLevels: streakInfo.dailyLevels,
                        dailyTooltips: streakInfo.dailyTooltips,
                        baseColor: goal.isLimit ? const Color(0xFF10B981) : const Color(0xFF3B82F6),
                        weekCount: 20,
                      ),
                    ],
                  );
                },
              ),
            ],
          ],
        ),
      ),
    ),
  );
  }

  Widget _buildMiniStat(String title, String val, MaterialColor color) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.25), width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(fontSize: AppFont.micro, color: scheme.onSurfaceVariant, fontWeight: FontWeight.w600),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            val,
            style: TextStyle(fontSize: AppFont.caption, fontWeight: FontWeight.bold, color: color.shade800),
          ),
        ],
      ),
    );
  }
}


