import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../../data/store.dart';
import '../../logic/format.dart';
import '../../logic/l10n.dart';
import '../common.dart';
import '../roadmap_detail_page.dart';

/// Günün Akışı (TodayPage) üzerinde yer alan, aktif yol haritalarının SADECE sıradaki
/// hedef veya aktivitelerini gösteren dinamik panel. Sık Yapılanlar ile Günün Akışı arasında konumlanır.
class TodayRoadmapPanel extends StatelessWidget {
  final Future<void> Function(Activity)? onStartTimer;

  const TodayRoadmapPanel({
    super.key,
    this.onStartTimer,
  });

  @override
  Widget build(BuildContext context) {
    final activeRoadmaps = store.activeRoadmaps;
    final roadmapsWithStep = activeRoadmaps.where((r) => r.currentPendingStep != null).toList();
    if (roadmapsWithStep.isEmpty) return const SizedBox.shrink();

    final s = strings.value;
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionTitle(
            s.activeRoadmapTargets,
            trailing: roadmapsWithStep.length > 1
                ? Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: scheme.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${roadmapsWithStep.length} ${s.isTr ? "Aktif Harita" : "Active"}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: scheme.primary,
                      ),
                    ),
                  )
                : null,
          ),
          for (final roadmap in roadmapsWithStep)
            _buildActiveStepCard(context, roadmap, roadmap.currentPendingStep!),
        ],
      ),
    );
  }

  Widget _buildActiveStepCard(BuildContext context, Roadmap roadmap, RoadmapStep step) {
    final s = strings.value;
    final scheme = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.45)),
      ),
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.25),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => RoadmapDetailPage(roadmapId: roadmap.id)),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Üst Bilgi: Harita İkonu, Harita Adı, Adım Sırası ve Detay Oku
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: scheme.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(roadmap.emoji, style: const TextStyle(fontSize: 16)),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      roadmap.title,
                      style: TextStyle(
                        fontSize: 13,
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
                        fontSize: 10.5,
                        fontWeight: FontWeight.bold,
                        color: Colors.orange,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.chevron_right_rounded, size: 18, color: scheme.onSurfaceVariant),
                ],
              ),
              const SizedBox(height: 10),

              // Sıradaki Tek Adım Satırı: Checkbox, Başlık, Açıklama / Hedef ve Aktivite Kısayolu
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 28,
                    height: 28,
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
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          step.title,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            decoration: step.isCompleted ? TextDecoration.lineThrough : null,
                          ),
                        ),
                        if (step.description.isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Text(
                            step.description,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
                          ),
                        ],
                        if (step.isGoal && step.target != null) ...[
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
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                                color: scheme.primary,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (step.linkedActivityId != null) ...[
                    const SizedBox(width: 6),
                    _buildLinkedActivityAction(context, step),
                  ],
                ],
              ),
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
      mainAxisSize: MainAxisSize.min,
      children: [
        ActionChip(
          visualDensity: VisualDensity.compact,
          avatar: Text(act.emoji ?? '⚡', style: const TextStyle(fontSize: 12)),
          label: Text(act.name, style: const TextStyle(fontSize: 11)),
          onPressed: () async {
            await store.quickLogHabit(act.id);
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
