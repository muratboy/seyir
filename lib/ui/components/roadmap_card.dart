import 'package:flutter/material.dart';
import '../../data/models.dart';
import '../../data/store.dart';
import '../../logic/l10n.dart';
import '../roadmap_detail_page.dart';
import 'roadmap_share_sheet.dart';
import 'roadmap_step_progress.dart';
import '../../logic/format.dart';
import '../app_font.dart';

class RoadmapCard extends StatelessWidget {
  final Roadmap roadmap;
  final VoidCallback? onTap;
  const RoadmapCard({super.key, required this.roadmap, this.onTap});

  @override
  Widget build(BuildContext context) {
    final s = strings.value;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final nextStep = roadmap.currentPendingStep;
    final nextProgress = nextStep == null ? null : store.stepProgress(roadmap, nextStep);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: roadmap.isActive ? 2 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: roadmap.isActive
            ? BorderSide(color: Colors.orange.shade400, width: 1.5)
            : (roadmap.isCompleted
                ? BorderSide(color: Colors.green.shade400, width: 1.5)
                : BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.35))),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap ??
            () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => RoadmapDetailPage(roadmapId: roadmap.id)),
              );
            },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Üst Satır: Emoji, Başlık, Durum, 3-nokta Menü
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: scheme.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(roadmap.emoji, style: const TextStyle(fontSize: AppFont.display)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Dar ekranda ya da büyük yazıda iki etiket yan yana sığmazsa alt alta geçer.
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            if (roadmap.category.isNotEmpty)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: scheme.surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  roadmap.category,
                                  style: TextStyle(
                                    fontSize: AppFont.micro,
                                    fontWeight: FontWeight.w600,
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            _buildBadge(roadmap, s.isTr),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          roadmap.title,
                          style: const TextStyle(fontSize: AppFont.subtitle, fontWeight: FontWeight.bold),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert, size: 20),
                    onSelected: (val) async {
                      if (val == 'open') {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => RoadmapDetailPage(roadmapId: roadmap.id)),
                        );
                      } else if (val == 'share') {
                        await showRoadmapShareSheet(context, roadmap);
                      } else if (val == 'reset') {
                        await store.resetRoadmapProgress(roadmap.id);
                      } else if (val == 'delete') {
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: Text(s.isTr ? 'Yol Haritasını Sil' : 'Delete Roadmap'),
                            content: Text(s.isTr
                                ? '"${roadmap.title}" yol haritasını silmek istediğinize emin misiniz?'
                                : 'Are you sure you want to delete "${roadmap.title}"?'),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(s.cancel)),
                              FilledButton(
                                style: FilledButton.styleFrom(backgroundColor: Colors.red),
                                onPressed: () => Navigator.pop(ctx, true),
                                child: Text(s.delete),
                              ),
                            ],
                          ),
                        );
                        if (confirm == true) {
                          await store.deleteRoadmap(roadmap.id);
                        }
                      }
                    },
                    itemBuilder: (ctx) => [
                      PopupMenuItem(
                        value: 'open',
                        child: Row(
                          children: [
                            const Icon(Icons.open_in_new_rounded, size: 18),
                            const SizedBox(width: 8),
                            Text(s.isTr ? 'Ayrıntılar' : 'Details'),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'share',
                        child: Row(
                          children: [
                            const Icon(Icons.share_outlined, size: 18),
                            const SizedBox(width: 8),
                            Text(s.isTr ? 'Paylaş' : 'Share'),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'reset',
                        child: Row(
                          children: [
                            const Icon(Icons.restart_alt_rounded, size: 18),
                            const SizedBox(width: 8),
                            Text(s.isTr ? 'İlerlemeyi Sıfırla' : 'Reset Progress'),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                            const SizedBox(width: 8),
                            Text(s.isTr ? 'Sil' : 'Delete', style: const TextStyle(color: Colors.red)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // İlerleme Çubuğu ve Metin
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${roadmap.completedStepsCount}/${roadmap.totalSteps} ${s.isTr ? "Adım Tamamlandı" : "Steps Done"}',
                    style: TextStyle(fontSize: AppFont.caption, color: scheme.onSurfaceVariant, fontWeight: FontWeight.w500),
                  ),
                  Text(
                    fmtPercent(roadmap.progressPercent),
                    style: TextStyle(
                      fontSize: AppFont.small,
                      fontWeight: FontWeight.bold,
                      color: roadmap.isCompleted ? Colors.green : scheme.primary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: roadmap.progressRatio,
                  minHeight: 6,
                  backgroundColor: scheme.surfaceContainerHighest,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    roadmap.isCompleted ? Colors.green : (roadmap.isActive ? Colors.orange : scheme.primary),
                  ),
                ),
              ),

              // Sıradaki Durak / Bekleyen Adım
              if (nextStep != null) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        nextStep.isGoal ? Icons.flag_outlined : Icons.check_box_outline_blank_rounded,
                        size: 16,
                        color: scheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${s.isTr ? "Sıradaki:" : "Next:"} ${nextStep.title}',
                          style: TextStyle(fontSize: AppFont.caption, fontWeight: FontWeight.w600, color: scheme.onSurface),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      // Bağlı aktivitenin kayıtlarıyla ne kadarının dolduğu.
                      if (nextProgress != null && (nextStep.target ?? 0) > 0) ...[
                        const SizedBox(width: 8),
                        // Uzun bir birim ya da büyük yazı satırı taşırmasın: sayıya ayrılan yer sınırlıdır.
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 150),
                          child: Text(
                            stepProgressText(nextProgress),
                            style: TextStyle(fontSize: AppFont.micro, fontWeight: FontWeight.w700, color: scheme.primary),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 12),

              // Alt Aksiyon Butonu
              Row(
                children: [
                  Expanded(
                    child: roadmap.isActive
                        ? FilledButton.tonalIcon(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => RoadmapDetailPage(roadmapId: roadmap.id)),
                              );
                            },
                            icon: const Icon(Icons.explore_rounded, size: 18),
                            label: Text(s.isTr ? 'Yolculuğa Devam Et' : 'Continue Journey'),
                            style: FilledButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(vertical: 8),
                            ),
                          )
                        : (roadmap.isCompleted
                            ? OutlinedButton.icon(
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(builder: (_) => RoadmapDetailPage(roadmapId: roadmap.id)),
                                  );
                                },
                                icon: const Icon(Icons.check_circle_outline, size: 18, color: Colors.green),
                                label: Text(
                                  s.isTr ? 'Tamamlanan Rotayı Gör' : 'View Completed Route',
                                  style: const TextStyle(color: Colors.green),
                                ),
                                style: OutlinedButton.styleFrom(
                                  side: BorderSide(color: Colors.green.withValues(alpha: 0.5)),
                                  visualDensity: VisualDensity.compact,
                                  padding: const EdgeInsets.symmetric(vertical: 8),
                                ),
                              )
                            : FilledButton.icon(
                                onPressed: () async {
                                  await store.setRoadmapStatus(roadmap.id, 'active');
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          s.isTr
                                              ? '🚀 "${roadmap.title}" yolculuğu başladı!'
                                              : '🚀 Journey started for "${roadmap.title}"!',
                                        ),
                                        behavior: SnackBarBehavior.floating,
                                      ),
                                    );
                                  }
                                },
                                icon: const Icon(Icons.rocket_launch_rounded, size: 18),
                                label: Text(s.isTr ? 'Yolculuğu Başlat' : 'Start Journey'),
                                style: FilledButton.styleFrom(
                                  visualDensity: VisualDensity.compact,
                                  padding: const EdgeInsets.symmetric(vertical: 8),
                                ),
                              )),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBadge(Roadmap r, bool isTr) {
    if (r.isCompleted) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.green.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          isTr ? '🏆 Tamamlandı' : '🏆 Done',
          style: const TextStyle(fontSize: AppFont.micro, fontWeight: FontWeight.bold, color: Colors.green),
        ),
      );
    }
    if (r.isActive) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.orange.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          isTr ? '🚀 Yolculukta' : '🚀 In Journey',
          style: const TextStyle(fontSize: AppFont.micro, fontWeight: FontWeight.bold, color: Colors.orange),
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.grey.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        isTr ? '⏳ Başlatılmadı' : '⏳ Ready',
        style: const TextStyle(fontSize: AppFont.micro, fontWeight: FontWeight.w600, color: Colors.grey),
      ),
    );
  }
}
