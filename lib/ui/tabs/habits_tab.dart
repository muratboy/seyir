import 'dart:math';
import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../../data/store.dart';
import '../../logic/l10n.dart';
import '../common.dart';
import '../contribution_heatmap.dart';
import '../../logic/format.dart';
import '../app_font.dart';

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

  // Hedefler sayfası bu listeyi sabit (const) olarak gömer; sayfa yeniden çizilse de sabit bir bileşen
  // yeniden çizilmez. Liste bu yüzden store'u kendisi dinler: yoksa eklenen ya da silinen öğe, sekmeden
  // çıkıp geri gelinene kadar ekranda değişmiyordu.
  @override
  Widget build(BuildContext context) => AnimatedBuilder(animation: store, builder: (context, _) => _list(context));

  Widget _list(BuildContext context) {
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
                style: const TextStyle(fontSize: AppFont.title, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                s.noHabitsDesc,
                textAlign: TextAlign.center,
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: AppFont.body),
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
                          fontSize: AppFont.title,
                          fontWeight: FontWeight.bold,
                          color: scheme.primary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        s.isTr ? 'Alışkanlık' : 'Habits',
                        style: TextStyle(fontSize: AppFont.micro, color: scheme.onSurfaceVariant),
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
                          fontSize: AppFont.title,
                          fontWeight: FontWeight.bold,
                          color: Colors.orange,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        s.longestStreak,
                        style: TextStyle(fontSize: AppFont.micro, color: scheme.onSurfaceVariant),
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
                          fontSize: AppFont.title,
                          fontWeight: FontWeight.bold,
                          color: doneTodayCount == totalHabits ? Colors.green : scheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        s.doneToday,
                        style: TextStyle(fontSize: AppFont.micro, color: scheme.onSurfaceVariant),
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
                      NameWithCategory(
                        activity: habit,
                        nameStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: AppFont.subtitle),
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
                          fontSize: AppFont.caption,
                          color: streakInfo.isDoneToday ? Colors.green.shade700 : Colors.orange.shade800,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      InkWell(
                        onTap: () => _showHabitScheduleDialog(context, habit),
                        borderRadius: BorderRadius.circular(6),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.event_repeat_rounded, size: 13, color: scheme.primary),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  store.habitScheduleText(habit.id, isTr: s.isTr),
                                  style: TextStyle(
                                    fontSize: AppFont.caption,
                                    color: scheme.primary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 2),
                              Icon(Icons.arrow_drop_down, size: 14, color: scheme.primary),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, size: 20),
                  itemBuilder: (c) => [
                    PopupMenuItem(
                      value: 'schedule',
                      child: Row(
                        children: [
                          const Icon(Icons.event_repeat_rounded, size: 18),
                          const SizedBox(width: 8),
                          Text(s.isTr ? 'Hedef Günler / Sıklık' : 'Schedule / Days'),
                        ],
                      ),
                    ),
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
                    if (val == 'schedule') {
                      _showHabitScheduleDialog(context, habit);
                    } else if (val == 'edit') {
                      showActivityEditDialog(context, habit);
                    } else if (val == 'remove_habit') {
                      store.setActivityHabit(habit.id, false);
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Streak Badges Row (3 KPI cards): başlıklar iki satıra geçebilir, kutular aynı boyda kalır.
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
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
                      value: fmtPercent(streakInfo.consistencyLast30.round()),
                      color: Colors.blue,
                      isHighlighted: streakInfo.consistencyLast30 > 0,
                    ),
                  ),
                ],
              ),
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
          // Başlık kutunun bütün genişliğini kullanır (simge değerin yanındadır): üç kutu yan yana dururken
          // simgenin yanında "Mevcut Seri" bile tek kelimesi sığmadan bölünüyordu.
          Text(
            title,
            style: TextStyle(
              fontSize: AppFont.micro,
              fontWeight: FontWeight.w600,
              color: scheme.onSurfaceVariant,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const Spacer(),
          const SizedBox(height: 3),
          Row(
            children: [
              Text(icon, style: const TextStyle(fontSize: AppFont.caption)),
              const SizedBox(width: 4),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    value,
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: AppFont.body,
                      fontWeight: FontWeight.bold,
                      color: isHighlighted ? color.shade700 : scheme.onSurface,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static Future<void> _showHabitScheduleDialog(BuildContext context, Activity habit) async {
    final s = strings.value;
    final currentTargetDays = store.habitTargetDays(habit.id);
    var selectedDays = currentTargetDays == null || currentTargetDays.isEmpty
        ? {1, 2, 3, 4, 5, 6, 7}
        : Set<int>.from(currentTargetDays);

    final dayLabels = s.isTr
        ? {1: 'Pazartesi', 2: 'Salı', 3: 'Çarşamba', 4: 'Perşembe', 5: 'Cuma', 6: 'Cumartesi', 7: 'Pazar'}
        : {1: 'Monday', 2: 'Tuesday', 3: 'Wednesday', 4: 'Thursday', 5: 'Friday', 6: 'Saturday', 7: 'Sunday'};

    final dayShortLabels = s.isTr
        ? {1: 'Pzt', 2: 'Sal', 3: 'Çar', 4: 'Per', 5: 'Cum', 6: 'Cmt', 7: 'Paz'}
        : {1: 'Mon', 2: 'Tue', 3: 'Wed', 4: 'Thu', 5: 'Fri', 6: 'Sat', 7: 'Sun'};

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            final scheme = Theme.of(ctx).colorScheme;
            final isEveryDay = selectedDays.length == 7;
            final isWeekdays = selectedDays.length == 5 &&
                selectedDays.contains(1) &&
                selectedDays.contains(2) &&
                selectedDays.contains(3) &&
                selectedDays.contains(4) &&
                selectedDays.contains(5);
            final isWeekends = selectedDays.length == 2 && selectedDays.contains(6) && selectedDays.contains(7);

            return AlertDialog(
              title: Row(
                children: [
                  Icon(Icons.event_repeat_rounded, color: scheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      s.isTr ? 'Alışkanlık Sıklığı' : 'Habit Frequency',
                      style: const TextStyle(fontSize: AppFont.title),
                    ),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      habit.name,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: AppFont.subtitle),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        ChoiceChip(
                          label: Text(s.isTr ? 'Her gün' : 'Every day'),
                          selected: isEveryDay,
                          onSelected: (_) {
                            setDialogState(() {
                              selectedDays = {1, 2, 3, 4, 5, 6, 7};
                            });
                          },
                        ),
                        ChoiceChip(
                          label: Text(s.isTr ? 'Hafta içi' : 'Weekdays'),
                          selected: isWeekdays,
                          onSelected: (_) {
                            setDialogState(() {
                              selectedDays = {1, 2, 3, 4, 5};
                            });
                          },
                        ),
                        ChoiceChip(
                          label: Text(s.isTr ? 'Hafta sonu' : 'Weekends'),
                          selected: isWeekends,
                          onSelected: (_) {
                            setDialogState(() {
                              selectedDays = {6, 7};
                            });
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      s.isTr ? 'Hangi günlerde yapılacak?' : 'Which days to do?',
                      style: TextStyle(
                        fontSize: AppFont.caption,
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (int d = 1; d <= 7; d++)
                          FilterChip(
                            label: Text(dayShortLabels[d]!),
                            selected: selectedDays.contains(d),
                            tooltip: dayLabels[d],
                            onSelected: (selected) {
                              setDialogState(() {
                                if (selected) {
                                  selectedDays.add(d);
                                } else {
                                  if (selectedDays.length > 1) {
                                    selectedDays.remove(d);
                                  }
                                }
                              });
                            },
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.info_outline, size: 16, color: scheme.onSurfaceVariant),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              s.isTr
                                  ? 'Planlanmayan günler seriyi bozmaz. Başarı oranı yalnızca seçilen günlere göre hesaplanır.'
                                  : 'Off-days will not break your streak. Consistency is calculated based on selected days only.',
                              style: TextStyle(fontSize: AppFont.micro, color: scheme.onSurfaceVariant),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(s.cancel),
                ),
                FilledButton(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    await store.setHabitTargetDays(
                      habit.id,
                      selectedDays.length == 7 ? null : selectedDays,
                    );
                  },
                  child: Text(s.save),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
