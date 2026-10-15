import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/models.dart';
import '../../data/store.dart';
import '../../logic/l10n.dart';
import '../app_font.dart';
import '../common.dart';

/// "Bugün" Özet Kartı: Kalan hedef miktarları, yapılmamış alışkanlıklar ve
/// sıradaki yol haritası adımlarını tek bir odaklanmış alanda sunar ve tek
/// dokunuşla doğrudan kayıt imkanı sağlar.
class TodaySummaryCard extends StatelessWidget {
  final DateTime currentDay;
  final void Function(Activity activity)? onStartTimer;

  const TodaySummaryCard({
    super.key,
    required this.currentDay,
    this.onStartTimer,
  });

  @override
  Widget build(BuildContext context) {
    final s = strings.value;
    final isTr = s.isTr;
    final scheme = Theme.of(context).colorScheme;

    // 1. Günlük hedefler ve limitler
    final dailyGoals = store.goals.where((g) => g.period == GoalPeriod.day).toList();

    // 2. Alışkanlıklar
    final allHabits = store.activities.values.where((a) => a.isHabit && !a.isArchived).toList();
    final todayEntries = store.entriesOfDay(currentDay);
    final todayActivityIds = todayEntries.map((e) => e.activityId).toSet();

    final uncompletedHabits = allHabits.where((a) => !todayActivityIds.contains(a.id)).toList();
    final completedHabitsCount = allHabits.length - uncompletedHabits.length;

    // 3. Sıradaki yol haritası adımları
    final nextRoadmapSteps = <({Roadmap roadmap, RoadmapStep step})>[];
    for (final r in store.activeRoadmaps) {
      final step = r.steps.where((st) => !st.isCompleted).firstOrNull;
      if (step != null) {
        nextRoadmapSteps.add((roadmap: r, step: step));
      }
    }

    // Hiç hedef, alışkanlık veya yol haritası yoksa gösterme
    if (dailyGoals.isEmpty && allHabits.isEmpty && nextRoadmapSteps.isEmpty) {
      return const SizedBox.shrink();
    }

    final allGoalsDone = dailyGoals.isNotEmpty && dailyGoals.every((g) => store.goalStatus(g, at: currentDay).done);
    final allHabitsDone = allHabits.isNotEmpty && uncompletedHabits.isEmpty;
    final isEverythingDone = (dailyGoals.isEmpty || allGoalsDone) && (allHabits.isEmpty || allHabitsDone);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isEverythingDone
              ? Colors.green.withValues(alpha: 0.35)
              : scheme.outlineVariant.withValues(alpha: 0.35),
          width: isEverythingDone ? 1.5 : 1.0,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Kart Başlığı ve Özet İlerleme
            Row(
              children: [
                Icon(
                  isEverythingDone ? Icons.check_circle_rounded : Icons.flare_rounded,
                  size: 18,
                  color: isEverythingDone ? Colors.green : scheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    isTr ? 'Bugünün Özeti' : "Today's Focus",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: AppFont.body,
                      color: isEverythingDone ? Colors.green : scheme.onSurface,
                    ),
                  ),
                ),
                if (allHabits.isNotEmpty) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: (allHabitsDone ? Colors.green : Colors.orange).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.local_fire_department_rounded,
                          size: 13,
                          color: allHabitsDone ? Colors.green : Colors.orange,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          '$completedHabitsCount/${allHabits.length}',
                          style: TextStyle(
                            fontSize: AppFont.micro,
                            fontWeight: FontWeight.bold,
                            color: allHabitsDone ? Colors.green : Colors.orange,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),

            // Tebrik Kartı (Tümü bittiyse)
            if (isEverythingDone && (dailyGoals.isNotEmpty || allHabits.isNotEmpty)) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Text('🎉', style: TextStyle(fontSize: AppFont.subtitle)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        isTr
                            ? 'Harika! Bugünkü hedeflerin ve alışkanlıkların tamamı tamamlandı.'
                            : 'Awesome! All daily goals and habits are completed for today.',
                        style: TextStyle(
                          fontSize: AppFont.small,
                          fontWeight: FontWeight.w600,
                          color: Colors.green.shade800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // 1. Kalan Hedef Miktarları & Limitler
            if (dailyGoals.isNotEmpty) ...[
              const SizedBox(height: 12),
              for (final g in dailyGoals) ...[
                Builder(builder: (context) {
                  final st = store.goalStatus(g, at: currentDay);
                  final isLimit = g.isLimit;
                  final isDone = st.done;
                  final isExceeded = st.isExceeded;
                  final firstLinkedActId = g.links.firstOrNull?.activityId;

                  final Color statusColor = isLimit
                      ? (isExceeded ? Colors.red : Colors.teal)
                      : (isDone ? Colors.green : scheme.primary);

                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: statusColor.withValues(alpha: 0.25)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              isLimit ? Icons.shield_outlined : Icons.track_changes_rounded,
                              size: 16,
                              color: statusColor,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                g.name,
                                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: AppFont.small),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (!isLimit && !isDone && firstLinkedActId != null) ...[
                              InkWell(
                                borderRadius: BorderRadius.circular(8),
                                onTap: () async {
                                  HapticFeedback.lightImpact();
                                  final msg = await store.repeatLastEntry(firstLinkedActId);
                                  if (msg != null && context.mounted) {
                                    showSnack(context, msg);
                                  }
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: scheme.primary.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.add_rounded, size: 14, color: scheme.primary),
                                      const SizedBox(width: 2),
                                      Text(
                                        isTr ? 'Kaydet' : 'Log',
                                        style: TextStyle(
                                          fontSize: AppFont.micro,
                                          fontWeight: FontWeight.bold,
                                          color: scheme.primary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: LinearProgressIndicator(
                            value: isLimit ? (isExceeded ? 1.0 : st.ratio.clamp(0.0, 1.0)) : st.ratio.clamp(0.0, 1.0),
                            minHeight: 5,
                            backgroundColor: scheme.surfaceContainerHighest,
                            valueColor: AlwaysStoppedAnimation<Color>(statusColor),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                isLimit
                                    ? (isExceeded
                                        ? (isTr ? 'Limit aşıldı!' : 'Limit exceeded!')
                                        : (isTr ? 'Limit güvende' : 'Within limit'))
                                    : (isDone
                                        ? (isTr ? 'Hedefe ulaşıldı ✓' : 'Goal achieved ✓')
                                        : '${isTr ? "Kalan:" : "Remaining:"} ${store.goalValueText(g, st.remaining)}'),
                                style: TextStyle(
                                  fontSize: AppFont.micro,
                                  fontWeight: FontWeight.w600,
                                  color: statusColor,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '${store.goalValueText(g, st.value)} / ${store.goalValueText(g, g.target)}',
                              style: TextStyle(
                                fontSize: AppFont.micro,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ],

            // 2. Yapılmamış Alışkanlıklar
            if (uncompletedHabits.isNotEmpty) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(Icons.local_fire_department_rounded, size: 15, color: Colors.orange),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      isTr ? 'Kalan Alışkanlıklar' : 'Pending Habits',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: AppFont.caption),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final habit in uncompletedHabits)
                    InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () async {
                        HapticFeedback.mediumImpact();
                        final msg = await store.repeatLastEntry(habit.id);
                        if (msg != null && context.mounted) {
                          showSnack(context, msg);
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (habit.emoji != null) ...[
                              Text(habit.emoji!, style: const TextStyle(fontSize: AppFont.caption)),
                              const SizedBox(width: 4),
                            ],
                            Flexible(
                              child: Text(
                                habit.name,
                                style: const TextStyle(fontSize: AppFont.caption, fontWeight: FontWeight.w500),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 5),
                            Icon(Icons.add_circle_outline_rounded, size: 15, color: scheme.primary),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ],

            // 3. Sıradaki Yol Haritası Adımları
            if (nextRoadmapSteps.isNotEmpty) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(Icons.alt_route_rounded, size: 15, color: Colors.blue),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      isTr ? 'Sıradaki Yol Haritası Adımları' : 'Next Roadmap Steps',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: AppFont.caption),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              for (final item in nextRoadmapSteps.take(2)) ...[
                Builder(builder: (context) {
                  final step = item.step;
                  final roadmap = item.roadmap;
                  final linkedAct = step.linkedActivityId != null ? store.activities[step.linkedActivityId] : null;

                  return Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${roadmap.title} › ${step.title}',
                                style: const TextStyle(fontSize: AppFont.small, fontWeight: FontWeight.w600),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (linkedAct != null) ...[
                                const SizedBox(height: 2),
                                Text(
                                  linkedAct.name,
                                  style: TextStyle(fontSize: AppFont.micro, color: scheme.onSurfaceVariant),
                                ),
                              ],
                            ],
                          ),
                        ),
                        if (linkedAct != null) ...[
                          const SizedBox(width: 6),
                          IconButton(
                            icon: const Icon(Icons.add_circle_outline_rounded, size: 20),
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            tooltip: isTr ? 'Kayıt Ekle' : 'Add Entry',
                            onPressed: () async {
                              HapticFeedback.lightImpact();
                              final msg = await store.repeatLastEntry(linkedAct.id);
                              if (msg != null && context.mounted) {
                                showSnack(context, msg);
                              }
                            },
                          ),
                          if (onStartTimer != null) ...[
                            IconButton(
                              icon: const Icon(Icons.play_circle_outline_rounded, size: 20),
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                              tooltip: isTr ? 'Sayaç Başlat' : 'Start Timer',
                              onPressed: () => onStartTimer!(linkedAct),
                            ),
                          ],
                        ],
                      ],
                    ),
                  );
                }),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
