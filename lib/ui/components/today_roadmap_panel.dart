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
                    child: Text(roadmap.emoji, style: const TextStyle(fontSize: AppFont.subtitle)),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      roadmap.title,
                      style: TextStyle(
                        fontSize: AppFont.small,
                        fontWeight: FontWeight.bold,
                        color: scheme.onSurface,
                      ),
                      maxLines: 2,
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
                            fontSize: AppFont.body,
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
                            style: TextStyle(fontSize: AppFont.caption, color: scheme.onSurfaceVariant),
                          ),
                        ],
                        // Aktiviteye bağlı adımın hedefi aşağıdaki ilerleme satırında yazar.
                        if (!linked && step.isGoal && step.target != null) ...[
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
              // Aktiviteye bağlı adım kayıtlarla ilerler: ne kadarının dolduğu ve aktiviteyi kaydetme kısayolu,
              // başlığın hizasında ve kartın bütün genişliğinde gösterilir. Başlığın yanına konduklarında uzun
              // bir aktivite adı başlığı birkaç harflik bir sütuna sıkıştırıyordu.
              if (linked) ...[
                Padding(
                  padding: const EdgeInsets.only(left: 38, top: 8),
                  child: StepProgressLine(roadmap: roadmap, step: step),
                ),
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
