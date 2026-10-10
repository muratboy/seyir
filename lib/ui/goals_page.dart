import 'dart:math';
import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/store.dart';
import '../logic/format.dart';
import '../logic/l10n.dart';
import '../logic/text_match.dart';
import 'common.dart';
import 'contribution_heatmap.dart';

enum GoalsPageTab { goals, habits }

class GoalsPage extends StatefulWidget {
  const GoalsPage({super.key});

  @override
  State<GoalsPage> createState() => _GoalsPageState();
}

class _GoalsPageState extends State<GoalsPage> {
  GoalsPageTab _currentTab = GoalsPageTab.goals;
  GoalPeriod? _filterPeriod;
  final Set<int> _expandedGoalHeatmapIds = {};
  String _habitFilter = 'all';

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
        final habitGoals = store.habitGoals;
        final totalHabitsCount = habits.length + habitGoals.length;

        return Scaffold(
          appBar: AppBar(
            title: Text(
              _currentTab == GoalsPageTab.goals ? (s.isTr ? 'Hedefler' : 'Goals') : s.habitTitle,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          body: Column(
            children: [
              // Segmented switcher: [ Hedefler & Limitler | 🔥 Zinciri Kırma (N) ]
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
                child: SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<GoalsPageTab>(
                    style: const ButtonStyle(
                      visualDensity: VisualDensity.compact,
                    ),
                    segments: [
                      ButtonSegment(
                        value: GoalsPageTab.goals,
                        label: Text(s.goalsTitle),
                        icon: const Icon(Icons.flag_outlined, size: 18),
                      ),
                      ButtonSegment(
                        value: GoalsPageTab.habits,
                        label: Text(
                          totalHabitsCount == 0 ? s.tabHabits : '${s.tabHabits} ($totalHabitsCount)',
                        ),
                        icon: const Icon(Icons.local_fire_department_rounded, size: 18),
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
                                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 16),
                              ),
                              const SizedBox(height: 12),
                              FilledButton.icon(
                                icon: const Icon(Icons.add),
                                label: Text(s.newGoal),
                                onPressed: () => _showGoalEditDialog(context),
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
              ] else ...[
                // Habits (Zinciri Kırma) List
                Expanded(
                  child: _buildHabitsView(context, habits),
                ),
              ],
            ],
          ),
          floatingActionButton: _currentTab == GoalsPageTab.goals
              ? FloatingActionButton(
                  onPressed: () => _showGoalEditDialog(context),
                  child: const Icon(Icons.add),
                )
              : FloatingActionButton.extended(
                  onPressed: () => _pickAndAddHabit(context),
                  icon: const Icon(Icons.add),
                  label: Text(s.addHabit),
                ),
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

    final linkedActivities = goal.links
        .map((l) => store.activities[l.activityId])
        .whereType<Activity>()
        .toList();
    final nonHabitLinkedActivities = linkedActivities.where((a) => !a.isHabit).toList();

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
        onTap: () => _showGoalEditDialog(context, existing: goal),
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
                                fontSize: 17,
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
                                      fontSize: 11,
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
                                      fontSize: 11,
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
                              goal.isLimit ? '🛡️ Limit' : '🎯 Hedef',
                              style: TextStyle(
                                fontSize: 11,
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
                              periodNames[goal.period] ?? goal.period.name,
                              style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
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
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.orange.shade900,
                                ),
                              ),
                            ),
                          ],
                          if (goal.isHabit) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.deepOrange.shade100,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                '🔥 Zinciri Kırma',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.deepOrange.shade900,
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
                      _showGoalEditDialog(context, existing: goal);
                    } else if (val == 'delete') {
                      final ok = await confirm(
                        context,
                        s.deleteConfirmTitle,
                        '${goal.name} ${s.deleteConfirmDesc}',
                      );
                      if (ok) store.deleteGoal(goal);
                    } else if (val == 'add_to_habits') {
                      await store.setGoalHabit(goal.id, true);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              s.isTr
                                  ? '🔥 "${goal.name}" Zinciri Kırma\'ya eklendi!'
                                  : '🔥 "${goal.name}" added to Habits!',
                            ),
                            behavior: SnackBarBehavior.floating,
                            action: SnackBarAction(
                              label: s.isTr ? 'Görüntüle' : 'View',
                              onPressed: () {
                                setState(() => _currentTab = GoalsPageTab.habits);
                              },
                            ),
                          ),
                        );
                      }
                    } else if (val == 'view_in_habits') {
                      setState(() => _currentTab = GoalsPageTab.habits);
                    } else if (val == 'remove_from_habits') {
                      await store.setGoalHabit(goal.id, false);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              s.isTr
                                  ? '"${goal.name}" Zinciri Kırma\'dan çıkarıldı.'
                                  : '"${goal.name}" removed from Habits.',
                            ),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      }
                    } else if (val == 'add_linked_activities') {
                      if (nonHabitLinkedActivities.length == 1) {
                        final act = nonHabitLinkedActivities.first;
                        await store.setActivityHabit(act.id, true);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                s.isTr
                                    ? '🔥 "${act.name}" Zinciri Kırma\'ya eklendi!'
                                    : '🔥 "${act.name}" added to Habits!',
                              ),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        }
                      } else if (nonHabitLinkedActivities.length > 1) {
                        await _showSelectActivitiesForHabitDialog(context, goal, nonHabitLinkedActivities);
                      }
                    }
                  },
                  itemBuilder: (c) => [
                    if (goal.isHabit) ...[
                      PopupMenuItem(
                        value: 'view_in_habits',
                        child: Row(
                          children: [
                            const Text('🔥', style: TextStyle(fontSize: 16)),
                            const SizedBox(width: 8),
                            Expanded(child: Text(s.viewInHabits)),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'remove_from_habits',
                        child: Row(
                          children: [
                            const Icon(Icons.remove_circle_outline, size: 18, color: Colors.red),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                s.removeFromHabits,
                                style: const TextStyle(color: Colors.red),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ] else ...[
                      PopupMenuItem(
                        value: 'add_to_habits',
                        child: Row(
                          children: [
                            const Text('🔥', style: TextStyle(fontSize: 16)),
                            const SizedBox(width: 8),
                            Expanded(child: Text(s.addToHabits)),
                          ],
                        ),
                      ),
                    ],
                    if (nonHabitLinkedActivities.isNotEmpty)
                      PopupMenuItem(
                        value: 'add_linked_activities',
                        child: Row(
                          children: [
                            const Icon(Icons.playlist_add_rounded, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                s.isTr ? 'Aktiviteleri de Alışkanlık Yap' : 'Make Activities Habits Too',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
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
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  goal.isLimit
                      ? (status.isExceeded
                          ? '${fmtNum(status.value)} / ${fmtNum(goal.target)} $unitSym (+${fmtNum(status.exceededAmount)} ${s.exceededAmount})'
                          : '${fmtNum(status.value)} / ${fmtNum(goal.target)} $unitSym (${s.remainingLimit}: ${fmtNum(status.remaining)})')
                      : '${fmtNum(status.value)} / ${fmtNum(goal.target)} $unitSym',
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                ),
                Text(
                  '%${(status.ratio * 100).floor()}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
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
                        '${s.endDate}: ${fmtDate(DateTime.fromMillisecondsSinceEpoch(goal.endDate!))} (${fmtDaysLeft(status.daysLeft ?? 0)})',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                    if (status.perDayNeeded != null && status.perDayNeeded! > 0)
                      Text(
                        '~${fmtNum1(status.perDayNeeded!)} $unitSym/${s.isTr ? "gün" : "day"}',
                        style: TextStyle(
                          fontSize: 12,
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
                  fontSize: 12,
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
                            Text(act.emoji ?? '🔹', style: const TextStyle(fontSize: 12)),
                            const SizedBox(width: 4),
                            Text(
                              act.name,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: act.displayColor,
                              ),
                            ),
                            if (link.pct != 100) ...[
                              const SizedBox(width: 2),
                              Text(
                                ' (%${fmtNum(link.pct)})',
                                style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant),
                              ),
                            ],
                            if (contribVal > 0) ...[
                              const SizedBox(width: 4),
                              Text(
                                '• ${fmtNum(contribVal)} $unitSym',
                                style: TextStyle(
                                  fontSize: 11,
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
                          fontSize: 12.5,
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
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: _buildMiniStat(
                              '🔥 ${s.isTr ? "Seri" : "Streak"}',
                              '${streakInfo.currentStreak} ${s.isTr ? "Gün" : "d"}',
                              Colors.orange,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: _buildMiniStat(
                              '🏆 ${s.longestStreak}',
                              '${streakInfo.longestStreak} ${s.isTr ? "Gün" : "d"}',
                              Colors.amber,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: _buildMiniStat(
                              '📈 ${s.isTr ? "30G Başarı" : "30d Rate"}',
                              '%${streakInfo.consistencyLast30.round()}',
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

  void _showGoalEditDialog(BuildContext context, {Goal? existing}) async {
    final s = strings.value;
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final targetCtrl = TextEditingController(text: existing != null ? fmtNum(existing.target) : '2.5');
    var type = existing?.type ?? 'target'; // target or limit
    var mode = existing?.mode ?? 'amount'; // amount or count
    var unitId = existing?.unitId ?? (mode == 'amount' ? 'l' : 'adet');
    var period = existing?.period ?? GoalPeriod.day;
    var hasEndDate = existing?.endDate != null;
    DateTime? endDate = existing?.endDate != null
        ? DateTime.fromMillisecondsSinceEpoch(existing!.endDate!)
        : DateTime.now().add(const Duration(days: 30));

    final links = existing != null
        ? List<GoalLink>.from(existing.links.map((l) => GoalLink(activityId: l.activityId, pct: l.pct)))
        : <GoalLink>[];

    await showDialog<void>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setS) => AlertDialog(
          title: Text(existing == null ? s.newGoal : s.editGoal),
          content: SingleChildScrollView(
            padding: const EdgeInsets.only(top: 12, bottom: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: nameCtrl,
                  autofocus: existing == null,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    labelText: s.goalName,
                    hintText: s.isTr ? 'örn: Günlük Sıvı Alımı veya Kafein Limiti' : 'e.g. Daily Fluid Intake or Caffeine Limit',
                  ),
                ),
                const SizedBox(height: 12),

                // Goal Kind: Target vs Limit
                Text(
                  s.goalKind,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(c).colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 4),
                SegmentedButton<String>(
                  showSelectedIcon: false,
                  segments: [
                    ButtonSegment(
                      value: 'target',
                      label: Text(s.goalKindTarget),
                      icon: const Icon(Icons.track_changes, size: 18),
                    ),
                    ButtonSegment(
                      value: 'limit',
                      label: Text(s.goalKindLimit),
                      icon: const Icon(Icons.shield_outlined, size: 18),
                    ),
                  ],
                  selected: {type},
                  onSelectionChanged: (set) => setS(() {
                    type = set.first;
                  }),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 10, left: 4),
                  child: Text(
                    type == 'limit' ? s.goalKindLimitDesc : s.goalKindTargetDesc,
                    style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(c).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),

                // Goal Mode: Amount vs Count
                Text(
                  s.goalType,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(c).colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 4),
                SegmentedButton<String>(
                  showSelectedIcon: false,
                  segments: [
                    ButtonSegment(
                      value: 'amount',
                      label: Text(s.isTr ? 'Miktar' : 'Amount'),
                      icon: const Icon(Icons.scale_outlined, size: 18),
                    ),
                    ButtonSegment(
                      value: 'count',
                      label: Text(s.isTr ? 'Adet' : 'Count'),
                      icon: const Icon(Icons.numbers_outlined, size: 18),
                    ),
                  ],
                  selected: {mode},
                  onSelectionChanged: (set) => setS(() {
                    mode = set.first;
                    if (mode == 'count') unitId = 'adet';
                  }),
                ),

                const SizedBox(height: 12),

                // Target & Unit
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: targetCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(
                          labelText: type == 'limit' ? s.limitTarget : s.goalTarget,
                          hintText: type == 'limit' ? '400' : '2.5',
                        ),
                      ),
                    ),
                    if (mode == 'amount') ...[
                      const SizedBox(width: 8),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: unitId,
                          isExpanded: true,
                          decoration: InputDecoration(labelText: s.unit),
                          items: [
                            for (final u in store.allUnits)
                              DropdownMenuItem(
                                value: u.id,
                                child: Text('${u.name} (${u.symbol})', overflow: TextOverflow.ellipsis),
                              ),
                          ],
                          onChanged: (val) {
                            if (val != null) setS(() => unitId = val);
                          },
                        ),
                      ),
                    ],
                  ],
                ),

                const SizedBox(height: 12),

                // Period
                DropdownButtonFormField<GoalPeriod>(
                  initialValue: period,
                  isExpanded: true,
                  decoration: InputDecoration(labelText: s.period),
                  items: [
                    DropdownMenuItem(
                      value: GoalPeriod.day,
                      child: Text(s.periodDaily, overflow: TextOverflow.ellipsis),
                    ),
                    DropdownMenuItem(
                      value: GoalPeriod.week,
                      child: Text(s.periodWeekly, overflow: TextOverflow.ellipsis),
                    ),
                    DropdownMenuItem(
                      value: GoalPeriod.month,
                      child: Text(s.periodMonthly, overflow: TextOverflow.ellipsis),
                    ),
                    DropdownMenuItem(
                      value: GoalPeriod.total,
                      child: Text(s.periodTotal, overflow: TextOverflow.ellipsis),
                    ),
                  ],
                  onChanged: (val) {
                    if (val != null) setS(() => period = val);
                  },
                ),

                const SizedBox(height: 10),

                // End Date Switch
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(s.hasEndDate),
                  value: hasEndDate,
                  onChanged: (v) => setS(() => hasEndDate = v),
                ),

                if (hasEndDate && endDate != null) ...[
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.calendar_month),
                    title: Text(fmtDate(endDate!)),
                    subtitle: Text(fmtDaysLeft(daysBetween(DateTime.now(), endDate!))),
                    trailing: const Icon(Icons.edit),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: c,
                        initialDate: endDate!,
                        firstDate: DateTime.now(),
                        lastDate: DateTime.now().add(const Duration(days: 3650)),
                      );
                      if (picked != null) setS(() => endDate = picked);
                    },
                  ),
                ],

                const Divider(height: 24),

                // Connected Activities
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        s.linkedActivities,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Theme.of(c).colorScheme.primary,
                        ),
                      ),
                    ),
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                      icon: const Icon(Icons.add, size: 18),
                      label: Text(s.addActivityToGoal),
                      onPressed: () async {
                        final act = await showActivityPicker(
                          c,
                          title: s.addActivityToGoal,
                          exclude: {for (final l in links) l.activityId},
                        );
                        if (act != null) {
                          setS(() => links.add(GoalLink(activityId: act.id, pct: 100)));
                        }
                      },
                    ),
                  ],
                ),

                if (links.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      s.isTr
                          ? 'Henüz aktivite bağlanmadı. Yukarıdan ekleyin (örn: Çay, Su, Yoğurt).'
                          : 'No activities linked yet. Add above.',
                      style: TextStyle(color: Theme.of(c).colorScheme.onSurfaceVariant, fontSize: 13),
                    ),
                  )
                else
                  for (var i = 0; i < links.length; i++) ...[
                    Builder(builder: (c) {
                      final link = links[i];
                      final act = store.activity(link.activityId);
                      return Card(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        color: Theme.of(c).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  Text(act.emoji ?? '🔹', style: const TextStyle(fontSize: 16)),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      act.name,
                                      style: const TextStyle(fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                  Text(
                                    '%${link.pct.round()}',
                                    style: const TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.close, size: 18),
                                    onPressed: () => setS(() => links.removeAt(i)),
                                  ),
                                ],
                              ),
                              Slider(
                                value: link.pct.clamp(1.0, 100.0),
                                min: 5,
                                max: 100,
                                divisions: 19,
                                label: '%${link.pct.round()}',
                                onChanged: (val) => setS(() => link.pct = val),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                  ],
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: Text(s.cancel)),
            FilledButton(
              onPressed: () async {
                final name = nameCtrl.text.trim();
                final targetVal = parseNum(targetCtrl.text);
                if (name.isEmpty || targetVal == null || targetVal <= 0) return;

                final goal = existing ??
                    Goal(
                      id: 0,
                      name: name,
                      type: type,
                      mode: mode,
                      unitId: mode == 'amount' ? unitId : null,
                      target: targetVal,
                      period: period,
                      startDate: DateTime.now().millisecondsSinceEpoch,
                      endDate: hasEndDate && endDate != null ? endDate!.millisecondsSinceEpoch : null,
                      createdAt: DateTime.now().millisecondsSinceEpoch,
                      links: links,
                    );

                goal.name = name;
                goal.type = type;
                goal.mode = mode;
                goal.unitId = mode == 'amount' ? unitId : null;
                goal.target = targetVal;
                goal.period = period;
                goal.endDate = hasEndDate && endDate != null ? endDate!.millisecondsSinceEpoch : null;
                goal.links = links;

                await store.saveGoal(goal);
                if (c.mounted) Navigator.pop(c);
              },
              child: Text(s.save),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- Zinciri Kırma (Habit Tracker) View

  Widget _buildHabitsView(BuildContext context, List<Activity> habits) {
    final s = strings.value;
    final scheme = Theme.of(context).colorScheme;

    if (habits.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.local_fire_department_rounded, size: 54, color: Colors.orange),
              ),
              const SizedBox(height: 18),
              Text(
                s.noHabitsTitle,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                s.noHabitsDesc,
                textAlign: TextAlign.center,
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13.5),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                icon: const Icon(Icons.add),
                label: Text(s.addHabit),
                onPressed: () => _pickAndAddHabit(context),
              ),
            ],
          ),
        ),
      );
    }

    final habitActivities = habits;
    final habitGoals = store.habitGoals;
    final totalHabits = habitActivities.length + habitGoals.length;

    if (totalHabits == 0) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.local_fire_department_rounded, size: 54, color: Colors.orange),
              ),
              const SizedBox(height: 18),
              Text(
                s.noHabitsTitle,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                s.noHabitsDesc,
                textAlign: TextAlign.center,
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13.5),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                icon: const Icon(Icons.add),
                label: Text(s.addHabit),
                onPressed: () => _pickAndAddHabit(context),
              ),
            ],
          ),
        ),
      );
    }

    final doneTodayCount = habitActivities.where((h) => store.habitStreakInfo(h.id).isDoneToday).length +
        habitGoals.where((g) => store.goalStreakInfo(g).isDoneToday).length;
    final maxActivityStreak = habitActivities.fold<int>(
      0,
      (prev, h) => max(prev, store.habitStreakInfo(h.id).longestStreak),
    );
    final maxGoalStreak = habitGoals.fold<int>(
      0,
      (prev, g) => max(prev, store.goalStreakInfo(g).longestStreak),
    );
    final maxStreak = max(maxActivityStreak, maxGoalStreak);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 80),
      children: [
        // KPI Summary Header
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.35)),
          ),
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.3),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    children: [
                      Text(
                        '$totalHabits',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: scheme.primary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        s.isTr ? 'Alışkanlık' : 'Habits',
                        style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                Container(
                  width: 1,
                  height: 28,
                  color: scheme.outlineVariant.withValues(alpha: 0.4),
                ),
                Expanded(
                  child: Column(
                    children: [
                      Text(
                        '$maxStreak ${s.isTr ? "Gün" : "Days"}',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.orange,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        s.longestStreak,
                        style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                Container(
                  width: 1,
                  height: 28,
                  color: scheme.outlineVariant.withValues(alpha: 0.4),
                ),
                Expanded(
                  child: Column(
                    children: [
                      Text(
                        '$doneTodayCount / $totalHabits',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: doneTodayCount == totalHabits ? Colors.green : scheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        s.doneToday,
                        style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),

        // Filter Chips (All, Goals, Activities)
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              FilterChip(
                label: Text('${s.allHabits} ($totalHabits)'),
                selected: _habitFilter == 'all',
                onSelected: (_) => setState(() => _habitFilter = 'all'),
              ),
              if (habitGoals.isNotEmpty) ...[
                const SizedBox(width: 8),
                FilterChip(
                  label: Text('${s.habitGoalsTitle} (${habitGoals.length})'),
                  selected: _habitFilter == 'goals',
                  onSelected: (_) => setState(() => _habitFilter = 'goals'),
                ),
              ],
              if (habitActivities.isNotEmpty) ...[
                const SizedBox(width: 8),
                FilterChip(
                  label: Text('${s.habitActivitiesTitle} (${habitActivities.length})'),
                  selected: _habitFilter == 'activities',
                  onSelected: (_) => setState(() => _habitFilter = 'activities'),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Habit Goal Cards
        if (_habitFilter == 'all' || _habitFilter == 'goals') ...[
          for (final goal in habitGoals) ...[
            _buildGoalHabitCard(context, goal),
          ],
        ],

        // Habit Activity Cards
        if (_habitFilter == 'all' || _habitFilter == 'activities') ...[
          for (final habit in habitActivities) ...[
            _buildHabitCard(context, habit),
          ],
        ],
      ],
    );
  }

  Widget _buildGoalHabitCard(BuildContext context, Goal goal) {
    final s = strings.value;
    final scheme = Theme.of(context).colorScheme;
    final streakInfo = store.goalStreakInfo(goal);
    final status = store.goalStatus(goal);
    final unitSym = store.goalUnitSymbol(goal);
    final isSuccessToday = streakInfo.isDoneToday;

    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: isSuccessToday
              ? Colors.green.withValues(alpha: 0.45)
              : scheme.outlineVariant.withValues(alpha: 0.35),
          width: isSuccessToday ? 1.5 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Top Row: Avatar, Title, Goal Type Badge, Today Status, Menu
            Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: goal.isLimit
                      ? Colors.orange.withValues(alpha: 0.2)
                      : scheme.primary.withValues(alpha: 0.15),
                  child: Text(
                    goal.isLimit ? '🛡️' : '🎯',
                    style: const TextStyle(fontSize: 20),
                  ),
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
                              goal.name,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: goal.isLimit
                                  ? Colors.orange.withValues(alpha: 0.15)
                                  : scheme.primary.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              goal.isLimit
                                  ? '🛡️ Limit (${fmtNum(goal.target)} $unitSym)'
                                  : '🎯 Hedef (${fmtNum(goal.target)} $unitSym)',
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                                color: goal.isLimit ? Colors.orange.shade900 : scheme.primary,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        goal.isLimit
                            ? (status.isExceeded
                                ? (s.isTr
                                    ? '⚠️ Bugün limit aşıldı (+${fmtNum(status.value - goal.target)} $unitSym)'
                                    : '⚠️ Limit exceeded (+${fmtNum(status.value - goal.target)} $unitSym)')
                                : (s.isTr
                                    ? '✓ Bugün limit dahilinde (${fmtNum(status.value)} / ${fmtNum(goal.target)} $unitSym)'
                                    : '✓ Within limit (${fmtNum(status.value)} / ${fmtNum(goal.target)} $unitSym)'))
                            : (status.done
                                ? (s.isTr
                                    ? '✓ Bugün tamamlandı (${fmtNum(status.value)} / ${fmtNum(goal.target)} $unitSym)'
                                    : '✓ Completed today (${fmtNum(status.value)} / ${fmtNum(goal.target)} $unitSym)')
                                : (s.isTr
                                    ? '⏳ Bugün: ${fmtNum(status.value)} / ${fmtNum(goal.target)} $unitSym (%${(status.ratio * 100).round()})'
                                    : '⏳ Today: ${fmtNum(status.value)} / ${fmtNum(goal.target)} $unitSym (%${(status.ratio * 100).round()})')),
                        style: TextStyle(
                          fontSize: 12,
                          color: isSuccessToday
                              ? Colors.green.shade700
                              : (goal.isLimit ? Colors.red.shade700 : Colors.orange.shade800),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, size: 20),
                  itemBuilder: (c) => [
                    PopupMenuItem(
                      value: 'edit',
                      child: Row(
                        children: [
                          const Icon(Icons.edit_outlined, size: 18),
                          const SizedBox(width: 8),
                          Text(s.edit),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'remove_habit',
                      child: Row(
                        children: [
                          const Icon(Icons.close_rounded, size: 18, color: Colors.red),
                          const SizedBox(width: 8),
                          Text(
                            s.removeFromHabits,
                            style: const TextStyle(color: Colors.red),
                          ),
                        ],
                      ),
                    ),
                  ],
                  onSelected: (val) {
                    if (val == 'edit') {
                      _showGoalEditDialog(context, existing: goal);
                    } else if (val == 'remove_habit') {
                      store.setGoalHabit(goal.id, false);
                    }
                  },
                ),
              ],
            ),

            // Linked activities row
            if (goal.links.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final link in goal.links) ...[
                    Builder(builder: (c) {
                      final act = store.activity(link.activityId);
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: act.displayColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: act.displayColor.withValues(alpha: 0.25), width: 0.7),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(act.emoji ?? '🔹', style: const TextStyle(fontSize: 11)),
                            const SizedBox(width: 4),
                            Text(
                              act.name,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: act.displayColor,
                              ),
                            ),
                            if (link.pct != 100) ...[
                              const SizedBox(width: 2),
                              Text(
                                ' (%${fmtNum(link.pct)})',
                                style: TextStyle(fontSize: 9.5, color: scheme.onSurfaceVariant),
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

            // Streak Badges Row (3 KPI cards)
            Row(
              children: [
                Expanded(
                  child: _buildStreakBadge(
                    icon: '🔥',
                    title: s.currentStreak,
                    value: '${streakInfo.currentStreak} ${s.isTr ? "Gün" : "Days"}',
                    color: Colors.orange,
                    isHighlighted: streakInfo.currentStreak > 0,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildStreakBadge(
                    icon: '🏆',
                    title: s.longestStreak,
                    value: '${streakInfo.longestStreak} ${s.isTr ? "Gün" : "Days"}',
                    color: Colors.amber,
                    isHighlighted: streakInfo.longestStreak > 0,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildStreakBadge(
                    icon: '📈',
                    title: s.consistency30,
                    value: '%${streakInfo.consistencyLast30.round()}',
                    color: Colors.blue,
                    isHighlighted: streakInfo.consistencyLast30 > 0,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // GitHub Contributions Heatmap for Goal
            ContributionHeatmap(
              dailyCounts: streakInfo.dailyCounts,
              dailyLevels: streakInfo.dailyLevels,
              dailyTooltips: streakInfo.dailyTooltips,
              baseColor: goal.isLimit ? const Color(0xFF10B981) : const Color(0xFF3B82F6),
              weekCount: 20,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHabitCard(BuildContext context, Activity habit) {
    final s = strings.value;
    final scheme = Theme.of(context).colorScheme;
    final streakInfo = store.habitStreakInfo(habit.id);

    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: streakInfo.isDoneToday
              ? Colors.green.withValues(alpha: 0.45)
              : scheme.outlineVariant.withValues(alpha: 0.35),
          width: streakInfo.isDoneToday ? 1.5 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Top Row: Avatar, Title, Category, Today Status, Menu
            Row(
              children: [
                ActivityAvatar(habit.id, size: 40),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              habit.name,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: habit.displayColor.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '${habit.categoryDef.emoji} ${habit.categoryDef.name(s.isTr)}',
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                                color: habit.displayColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        streakInfo.isDoneToday
                            ? (s.isTr
                                ? '✓ Bugün yapıldı (${streakInfo.todayCount} kayıt)'
                                : '✓ Done today (${streakInfo.todayCount} logs)')
                            : (s.isTr
                                ? '⏳ Bugün henüz yapılmadı'
                                : '⏳ Not done yet today'),
                        style: TextStyle(
                          fontSize: 12,
                          color: streakInfo.isDoneToday ? Colors.green.shade700 : Colors.orange.shade800,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, size: 20),
                  itemBuilder: (c) => [
                    PopupMenuItem(
                      value: 'edit',
                      child: Row(
                        children: [
                          const Icon(Icons.edit_outlined, size: 18),
                          const SizedBox(width: 8),
                          Text(s.edit),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'remove_habit',
                      child: Row(
                        children: [
                          const Icon(Icons.close_rounded, size: 18, color: Colors.red),
                          const SizedBox(width: 8),
                          Text(
                            s.isTr ? 'Alışkanlıktan Çıkar' : 'Remove from habits',
                            style: const TextStyle(color: Colors.red),
                          ),
                        ],
                      ),
                    ),
                  ],
                  onSelected: (val) {
                    if (val == 'edit') {
                      showActivityEditDialog(context, habit);
                    } else if (val == 'remove_habit') {
                      store.setActivityHabit(habit.id, false);
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Streak Badges Row (3 KPI cards)
            Row(
              children: [
                Expanded(
                  child: _buildStreakBadge(
                    icon: '🔥',
                    title: s.currentStreak,
                    value: '${streakInfo.currentStreak} ${s.isTr ? "Gün" : "Days"}',
                    color: Colors.orange,
                    isHighlighted: streakInfo.currentStreak > 0,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildStreakBadge(
                    icon: '🏆',
                    title: s.longestStreak,
                    value: '${streakInfo.longestStreak} ${s.isTr ? "Gün" : "Days"}',
                    color: Colors.amber,
                    isHighlighted: streakInfo.longestStreak > 0,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildStreakBadge(
                    icon: '📈',
                    title: s.consistency30,
                    value: '%${streakInfo.consistencyLast30.round()}',
                    color: Colors.blue,
                    isHighlighted: streakInfo.consistencyLast30 > 0,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // GitHub Contributions Heatmap
            ContributionHeatmap(
              dailyCounts: streakInfo.dailyCounts,
              dailyLevels: streakInfo.dailyLevels,
              dailyTooltips: streakInfo.dailyTooltips,
              baseColor: habit.displayColor,
              weekCount: 20,
            ),
            const SizedBox(height: 12),

            // Bottom Action Button
            streakInfo.isDoneToday
                ? OutlinedButton.icon(
                    icon: const Icon(Icons.add_circle_outline, size: 18),
                    label: Text(s.isTr ? 'Tekrar Kaydet (+1)' : 'Log Again (+1)'),
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () async {
                      await store.quickLogHabit(habit.id);
                    },
                  )
                : FilledButton.icon(
                    icon: const Icon(Icons.bolt_rounded, size: 20),
                    label: Text(
                      s.isTr ? 'Bugün Tamamla & Seriyi Koru' : 'Complete Today & Keep Streak',
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: habit.displayColor,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () async {
                      await store.quickLogHabit(habit.id);
                      if (context.mounted) {
                        final updatedStreak = store.habitStreakInfo(habit.id).currentStreak;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              s.isTr
                                  ? '🔥 Harika! ${habit.name} serisi: $updatedStreak Gün!'
                                  : '🔥 Great! ${habit.name} streak: $updatedStreak Days!',
                            ),
                            behavior: SnackBarBehavior.floating,
                            duration: const Duration(seconds: 2),
                          ),
                        );
                      }
                    },
                  ),
          ],
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
            style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant, fontWeight: FontWeight.w600),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            val,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color.shade800),
          ),
        ],
      ),
    );
  }

  Widget _buildStreakBadge({
    required String icon,
    required String title,
    required String value,
    required MaterialColor color,
    required bool isHighlighted,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: isHighlighted
            ? color.withValues(alpha: 0.12)
            : scheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isHighlighted
              ? color.withValues(alpha: 0.35)
              : scheme.outlineVariant.withValues(alpha: 0.25),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(icon, style: const TextStyle(fontSize: 12)),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            value,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.bold,
              color: isHighlighted ? color.shade700 : scheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickAndAddHabit(BuildContext context) async {
    final s = strings.value;
    final nonHabitGoals = store.goals.where((g) => !g.isHabit).toList();
    final nonHabitActivities = store.activities.values.where((a) => !a.isHabit && !a.isArchived).toList();

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.6,
          maxChildSize: 0.85,
          minChildSize: 0.4,
          builder: (context, scrollController) {
            return DefaultTabController(
              length: 2,
              child: Column(
                children: [
                  const SizedBox(height: 8),
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.outlineVariant,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  TabBar(
                    tabs: [
                      Tab(text: '${s.habitGoalsTitle} (${nonHabitGoals.length})'),
                      Tab(text: '${s.habitActivitiesTitle} (${nonHabitActivities.length})'),
                    ],
                  ),
                  Expanded(
                    child: TabBarView(
                      children: [
                        // Goals Tab
                        nonHabitGoals.isEmpty
                            ? Center(
                                child: Text(
                                  s.isTr ? 'Eklenebilecek hedef bulunmuyor.' : 'No goals available to add.',
                                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                                ),
                              )
                            : ListView.builder(
                                controller: scrollController,
                                itemCount: nonHabitGoals.length,
                                itemBuilder: (c, i) {
                                  final g = nonHabitGoals[i];
                                  return ListTile(
                                    leading: Text(g.isLimit ? '🛡️' : '🎯', style: const TextStyle(fontSize: 24)),
                                    title: Text(g.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                                    subtitle: Text(
                                      '${g.isLimit ? (s.isTr ? "Limit" : "Limit") : (s.isTr ? "Hedef" : "Goal")} • ${fmtNum(g.target)} ${store.goalUnitSymbol(g)}',
                                    ),
                                    trailing: const Icon(Icons.add_circle_outline, color: Colors.orange),
                                    onTap: () async {
                                      Navigator.pop(ctx);
                                      await store.setGoalHabit(g.id, true);
                                    },
                                  );
                                },
                              ),
                        // Activities Tab
                        nonHabitActivities.isEmpty
                            ? Center(
                                child: Text(
                                  s.isTr ? 'Eklenebilecek aktivite bulunmuyor.' : 'No activities available.',
                                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                                ),
                              )
                            : ListView.builder(
                                controller: scrollController,
                                itemCount: nonHabitActivities.length,
                                itemBuilder: (c, i) {
                                  final a = nonHabitActivities[i];
                                  return ListTile(
                                    leading: ActivityAvatar(a.id, size: 36),
                                    title: Text(a.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                                    subtitle: Text(a.categoryDef.name(s.isTr)),
                                    trailing: const Icon(Icons.add_circle_outline, color: Colors.green),
                                    onTap: () async {
                                      Navigator.pop(ctx);
                                      await store.setActivityHabit(a.id, true);
                                    },
                                  );
                                },
                              ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _showSelectActivitiesForHabitDialog(
    BuildContext context,
    Goal goal,
    List<Activity> activities,
  ) async {
    final s = strings.value;
    final selectedIds = <int>{...activities.map((a) => a.id)};

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Row(
                children: [
                  const Text('🔥', style: TextStyle(fontSize: 20)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      s.isTr ? 'Zinciri Kırma\'ya Ekle' : 'Add to Habits',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.isTr
                        ? '"${goal.name}" hedefine bağlı aktiviteler:'
                        : 'Activities linked to "${goal.name}":',
                    style: TextStyle(
                      fontSize: 13,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ...activities.map((act) {
                    final isChecked = selectedIds.contains(act.id);
                    return CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      value: isChecked,
                      title: Row(
                        children: [
                          ActivityAvatar(act.id, size: 24),
                          const SizedBox(width: 8),
                          Expanded(child: Text(act.name)),
                        ],
                      ),
                      onChanged: (val) {
                        setDialogState(() {
                          if (val == true) {
                            selectedIds.add(act.id);
                          } else {
                            selectedIds.remove(act.id);
                          }
                        });
                      },
                    );
                  }),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: Text(s.cancel),
                ),
                FilledButton(
                  onPressed: selectedIds.isEmpty ? null : () => Navigator.pop(ctx, true),
                  child: Text(s.isTr ? 'Ekle (${selectedIds.length})' : 'Add (${selectedIds.length})'),
                ),
              ],
            );
          },
        );
      },
    );

    if (confirmed == true && selectedIds.isNotEmpty) {
      for (final id in selectedIds) {
        await store.setActivityHabit(id, true);
      }
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              s.isTr
                  ? '🔥 Seçilen aktiviteler Zinciri Kırma\'ya eklendi!'
                  : '🔥 Selected activities added to Habits!',
            ),
            behavior: SnackBarBehavior.floating,
            action: SnackBarAction(
              label: s.isTr ? 'Görüntüle' : 'View',
              onPressed: () {
                setState(() => _currentTab = GoalsPageTab.habits);
              },
            ),
          ),
        );
      }
    }
  }
}
