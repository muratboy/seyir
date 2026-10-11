import 'dart:math';
import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../../data/store.dart';
import '../../logic/l10n.dart';
import '../common.dart';
import '../contribution_heatmap.dart';

class HabitsTab extends StatelessWidget {
  const HabitsTab({super.key});

  static Future<void> pickAndAddHabit(BuildContext context) async {
    final s = strings.value;
    final picked = await showActivityPicker(
      context,
      title: s.isTr ? 'Alışkanlık Yapılacak Aktiviteyi Seç' : 'Select Activity as Habit',
      exclude: store.habitActivities.map((a) => a.id).toSet(),
    );
    if (picked != null) {
      await store.setActivityHabit(picked.id, true);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              s.isTr
                  ? '"${picked.name}" artık bir alışkanlık! Zinciri kırma 🔥'
                  : '"${picked.name}" is now a habit! Keep the streak 🔥',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = strings.value;
    final scheme = Theme.of(context).colorScheme;
    final habits = store.habitActivities;

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
                onPressed: () => pickAndAddHabit(context),
              ),
            ],
          ),
        ),
      );
    }

    final habitActivities = habits;
    final totalHabits = habitActivities.length;
    final doneTodayCount = habitActivities.where((h) => store.habitStreakInfo(h.id).isDoneToday).length;
    final maxStreak = habitActivities.fold<int>(
      0,
      (prev, h) => max(prev, store.habitStreakInfo(h.id).longestStreak),
    );

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
        const SizedBox(height: 12),
        for (final habit in habitActivities)
          _buildHabitCard(context, habit),
      ],
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
                    context: context,
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
                    context: context,
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
                    context: context,
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

  Widget _buildStreakBadge({
    required BuildContext context,
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
}
