import 'package:flutter/material.dart';
import '../../data/store.dart';
import '../../logic/l10n.dart';
import '../roadmap_detail_page.dart';

/// Günün Akışı (TodayPage) üzerinde yer alan, başlatılmış yolculuğun hedeflerini gösteren dinamik panel
class TodayRoadmapPanel extends StatelessWidget {
  const TodayRoadmapPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final active = store.activeRoadmap;
    if (active == null) return const SizedBox.shrink();

    final s = strings.value;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final pendingSteps = active.steps.where((st) => !st.isCompleted).toList()
      ..sort((a, b) => a.order.compareTo(b.order));

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: scheme.primary.withValues(alpha: 0.35), width: 1.2),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Üst Başlık ve İlerleme
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(active.emoji, style: const TextStyle(fontSize: 22)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              active.title,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.amber.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              s.isTr ? '🚀 Yolculukta' : '🚀 In Journey',
                              style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Colors.orange),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${active.completedStepsCount}/${active.totalSteps} ${s.isTr ? "adım tamamlandı" : "steps completed"} (%${active.progressPercent})',
                        style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
                  tooltip: s.isTr ? 'Yol Haritasına Git' : 'Go to Roadmap',
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => RoadmapDetailPage(roadmapId: active.id)),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),

            // İlerleme Çubuğu
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: active.progressRatio,
                minHeight: 7,
                backgroundColor: scheme.surfaceContainerHighest,
                valueColor: AlwaysStoppedAnimation<Color>(scheme.primary),
              ),
            ),
            const SizedBox(height: 14),

            // Sıradaki Hedefler / Yapılacaklar Listesi
            if (pendingSteps.isEmpty) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle_rounded, color: Colors.green, size: 22),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        s.isTr
                            ? '🎉 Tebrikler! Bu yol haritasındaki tüm hedefleri tamamladın!'
                            : '🎉 Congratulations! You completed all steps in this roadmap!',
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Colors.green),
                      ),
                    ),
                  ],
                ),
              ),
            ] else ...[
              Text(
                s.isTr ? 'Sıradaki Hedeflerin:' : 'Your Next Steps:',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.bold,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              // Öncelikli ilk 3 bekleyen adımı listele
              ...pendingSteps.take(3).map((step) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Material(
                    color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(12),
                    clipBehavior: Clip.antiAlias,
                    child: ListTile(
                    dense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                    onTap: () async {
                      final nextVal = !step.isCompleted;
                      await store.toggleRoadmapStep(step.id, completed: nextVal);
                      if (nextVal == true && context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(s.isTr ? '✓ "${step.title}" tamamlandı!' : '✓ "${step.title}" completed!'),
                            duration: const Duration(seconds: 2),
                          ),
                        );
                      }
                    },
                    leading: Checkbox(
                      value: step.isCompleted,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                      onChanged: (val) async {
                        await store.toggleRoadmapStep(step.id, completed: val);
                        if (val == true && context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(s.isTr ? '✓ "${step.title}" tamamlandı!' : '✓ "${step.title}" completed!'),
                              duration: const Duration(seconds: 2),
                            ),
                          );
                        }
                      },
                    ),
                    title: Text(
                      step.title,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        decoration: step.isCompleted ? TextDecoration.lineThrough : null,
                      ),
                    ),
                    subtitle: step.description.isNotEmpty
                        ? Text(
                            step.description,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
                          )
                        : (step.isGoal && step.target != null
                            ? Text(
                                '${s.isTr ? "Hedef:" : "Target:"} ${step.target} ${step.unit ?? ""}',
                                style: TextStyle(fontSize: 11.5, color: scheme.primary),
                              )
                            : null),
                    trailing: step.isGoal
                        ? Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: scheme.primaryContainer,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              s.isTr ? 'Ölçülü' : 'Goal',
                              style: TextStyle(fontSize: 10, color: scheme.onPrimaryContainer, fontWeight: FontWeight.bold),
                            ),
                          )
                        : Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: scheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              s.isTr ? 'Görev' : 'Task',
                              style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant),
                            ),
                          ),
                  ),
                ),
              );
            }),
            ],
          ],
        ),
      ),
    );
  }
}
