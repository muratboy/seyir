import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../../data/store.dart';
import '../../logic/format.dart';
import '../../logic/l10n.dart';
import '../common.dart';
import '../roadmap_detail_page.dart';
import 'roadmap_step_progress.dart';
import '../app_font.dart';

/// Günün Akışı (TodayPage) üzerinde yer alan, aktif yol haritalarının SADECE sıradaki
/// hedef veya aktivitelerini gösteren dinamik panel. Sık yapılanlar ile Günün Akışı arasında konumlanır.
class TodayRoadmapPanel extends StatelessWidget {
  final DateTime? currentDay;
  final Future<void> Function(Activity)? onStartTimer;

  const TodayRoadmapPanel({
    super.key,
    this.currentDay,
    this.onStartTimer,
  });

  @override
  Widget build(BuildContext context) {
    final activeRoadmaps = store.activeRoadmaps;
    final roadmapsWithStep = activeRoadmaps.where((r) => r.currentPendingStep != null).toList();
    if (roadmapsWithStep.isEmpty) return const SizedBox.shrink();

    final s = strings.value;
    final scheme = Theme.of(context).colorScheme;
    final collapsed = store.isSectionCollapsed('roadmap');

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionTitle(
            s.activeRoadmapTargets,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (roadmapsWithStep.length > 1 || collapsed)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: scheme.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${roadmapsWithStep.length} ${s.isTr ? "Aktif Harita" : "Active"}',
                      style: TextStyle(
                        fontSize: AppFont.micro,
                        fontWeight: FontWeight.bold,
                        color: scheme.primary,
                      ),
                    ),
                  ),
                const SectionToggle('roadmap'),
              ],
            ),
          ),
          if (!collapsed)
            for (final roadmap in roadmapsWithStep)
              _buildActiveStepCard(context, roadmap, roadmap.currentPendingStep!),
        ],
      ),
    );
  }

  Widget _buildActiveStepCard(BuildContext context, Roadmap roadmap, RoadmapStep step) {
    final s = strings.value;
    final scheme = Theme.of(context).colorScheme;
    final linked = store.activities.containsKey(step.linkedActivityId);
    final linkedGoal = store.goals.where((g) => g.id == step.linkedGoalId).firstOrNull;
    final hasProgress = linked || linkedGoal != null || step.startedAt != null;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.45)),
      ),
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.25),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => RoadmapDetailPage(roadmapId: roadmap.id)),
          );
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Üst Bilgi: Harita İkonu, Harita Adı, Adım Sırası ve Detay Oku
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: scheme.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: Text(roadmap.emoji, style: const TextStyle(fontSize: AppFont.small)),
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      roadmap.title,
                      style: TextStyle(
                        fontSize: AppFont.small,
                        fontWeight: FontWeight.bold,
                        color: scheme.onSurface,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.amber.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${s.nextStep} ${step.order}/${roadmap.totalSteps}',
                      style: const TextStyle(
                        fontSize: AppFont.micro,
                        fontWeight: FontWeight.bold,
                        color: Colors.orange,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.chevron_right_rounded, size: 18, color: scheme.onSurfaceVariant),
                ],
              ),
              const SizedBox(height: 4),

              // Sıradaki Tek Adım Satırı: Checkbox, Başlık ve Hedef Rozeti
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: Checkbox(
                      value: step.isCompleted,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                      onChanged: (val) async {
                        await store.toggleRoadmapStep(step.id, completed: val);
                        if (val == true && context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(s.isTr ? '✓ "${step.title}" tamamlandı!' : '✓ "${step.title}" completed!'),
                              duration: const Duration(seconds: 2),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          step.title,
                          style: TextStyle(
                            fontSize: AppFont.small,
                            fontWeight: FontWeight.w600,
                            decoration: step.isCompleted ? TextDecoration.lineThrough : null,
                          ),
                        ),
                        if (!hasProgress && step.isGoal && step.target != null) ...[
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: scheme.primary.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '${s.isTr ? "🎯 Hedef:" : "🎯 Target:"} ${fmtNum(step.target!)} ${step.unit ?? ""}',
                              style: TextStyle(
                                fontSize: AppFont.micro,
                                fontWeight: FontWeight.w600,
                                color: scheme.primary,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              if (linkedGoal != null) ...[
                Padding(
                  padding: const EdgeInsets.only(left: 38, top: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.track_changes_rounded, size: 14, color: Colors.teal),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          '${s.isTr ? "Hedef:" : "Goal:"} ${linkedGoal.name} (${store.goalValueText(linkedGoal, linkedGoal.target)})',
                          style: const TextStyle(fontSize: AppFont.caption, fontWeight: FontWeight.w600, color: Colors.teal),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (hasProgress) ...[
                Padding(
                  padding: const EdgeInsets.only(left: 38, top: 8),
                  child: StepProgressLine(roadmap: roadmap, step: step),
                ),
              ],
              if (linked) ...[
                Padding(
                  padding: const EdgeInsets.only(left: 38, top: 6),
                  child: _buildLinkedActivityAction(context, step),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLinkedActivityAction(BuildContext context, RoadmapStep step) {
    final s = strings.value;
    final act = store.activity(step.linkedActivityId!);

    return Row(
      children: [
        // Uzun bir aktivite adı kısaltılır; satırı taşırmaz.
        Flexible(
          child: ActionChip(
            visualDensity: VisualDensity.compact,
            avatar: Text(act.emoji ?? '⚡', style: const TextStyle(fontSize: AppFont.caption)),
            label: Text(
              act.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: AppFont.micro),
            ),
            onPressed: () async {
              final targetTime = currentDay != null
                  ? (sameDay(currentDay!, DateTime.now())
                      ? DateTime.now()
                      : DateTime(currentDay!.year, currentDay!.month, currentDay!.day, 12, 0))
                  : null;
              await store.quickLogHabit(act.id, date: targetTime);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(s.isTr ? '✓ "${act.name}" kaydedildi!' : '✓ "${act.name}" logged!'),
                    duration: const Duration(seconds: 2),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            },
          ),
        ),
        if (onStartTimer != null) ...[
          const SizedBox(width: 2),
          IconButton(
            icon: const Icon(Icons.timer_outlined, size: 18),
            visualDensity: VisualDensity.compact,
            tooltip: s.startStopwatch,
            onPressed: () => onStartTimer!(act),
          ),
        ],
      ],
    );
  }
}
