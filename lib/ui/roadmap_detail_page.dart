import 'package:flutter/material.dart';
import '../data/models.dart';
import '../data/store.dart';
import '../logic/format.dart';
import '../logic/l10n.dart';
import 'common.dart';
import 'components/roadmap_share_sheet.dart';
import 'components/roadmap_step_progress.dart';
import 'app_font.dart';

class RoadmapDetailPage extends StatefulWidget {
  final int roadmapId;
  const RoadmapDetailPage({super.key, required this.roadmapId});

  @override
  State<RoadmapDetailPage> createState() => _RoadmapDetailPageState();
}

class _RoadmapDetailPageState extends State<RoadmapDetailPage> {
  Roadmap? _getRoadmap() => store.roadmaps.where((r) => r.id == widget.roadmapId).firstOrNull;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final r = _getRoadmap();
        final s = strings.value;
        final theme = Theme.of(context);
        final scheme = theme.colorScheme;

        if (r == null) {
          return Scaffold(
            appBar: AppBar(title: Text(s.isTr ? 'Yol Haritası' : 'Roadmap')),
            body: Center(
              child: Text(s.isTr ? 'Yol haritası bulunamadı.' : 'Roadmap not found.'),
            ),
          );
        }

        final sortedSteps = [...r.steps]..sort((a, b) => a.order.compareTo(b.order));

        return Scaffold(
          appBar: AppBar(
            title: Text(r.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: AppFont.title)),
            actions: [
              IconButton(
                tooltip: s.isTr ? 'Paylaş' : 'Share',
                icon: const Icon(Icons.share_outlined),
                onPressed: () => showRoadmapShareSheet(context, r),
              ),
              PopupMenuButton<String>(
                onSelected: (val) async {
                  if (val == 'reset') {
                    await store.resetRoadmapProgress(r.id);
                  } else if (val == 'delete') {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: Text(s.isTr ? 'Yol Haritasını Sil' : 'Delete Roadmap'),
                        content: Text(s.isTr
                            ? '"${r.title}" haritasını ve tüm adımlarını silmek istediğinize emin misiniz?'
                            : 'Are you sure you want to delete "${r.title}" and all its steps?'),
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
                      await store.deleteRoadmap(r.id);
                      if (context.mounted) {
                        Navigator.pop(context);
                      }
                    }
                  }
                },
                itemBuilder: (ctx) => [
                  PopupMenuItem(
                    value: 'reset',
                    child: Row(
                      children: [
                        const Icon(Icons.restart_alt_rounded, size: 20),
                        const SizedBox(width: 8),
                        Text(s.isTr ? 'İlerlemeyi Sıfırla' : 'Reset Progress'),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        const Icon(Icons.delete_outline, size: 20, color: Colors.red),
                        const SizedBox(width: 8),
                        Text(s.isTr ? 'Sil' : 'Delete', style: const TextStyle(color: Colors.red)),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
            children: [
              // Üst Özet ve Rota Bilgisi Kartı
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                  side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.4)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: scheme.primary.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Text(r.emoji, style: const TextStyle(fontSize: AppFont.hero)),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 4,
                                  children: [
                                    if (r.category.isNotEmpty)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: scheme.surfaceContainerHighest,
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          r.category,
                                          style: TextStyle(
                                            fontSize: AppFont.micro,
                                            fontWeight: FontWeight.w600,
                                            color: scheme.onSurfaceVariant,
                                          ),
                                        ),
                                      ),
                                    _buildStatusBadge(r, s.isTr),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  r.title,
                                  style: const TextStyle(fontSize: AppFont.title, fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      if (r.description.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Text(
                          r.description,
                          style: TextStyle(fontSize: AppFont.small, color: scheme.onSurfaceVariant, height: 1.4),
                        ),
                      ],
                      const SizedBox(height: 16),

                      // İlerleme Alanı
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            s.isTr ? 'Rota İlerlemesi' : 'Route Progress',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: AppFont.small),
                          ),
                          Text(
                            '${fmtPercent(r.progressPercent)} (${r.completedStepsCount}/${r.totalSteps})',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: AppFont.small, color: scheme.primary),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: LinearProgressIndicator(
                          value: r.progressRatio,
                          minHeight: 10,
                          backgroundColor: scheme.surfaceContainerHighest,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            r.isCompleted ? Colors.green : scheme.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Yolculuk Başlat / Duraklat Aksiyon Butonu
              _buildJourneyActionButton(r, s.isTr),
              const SizedBox(height: 20),

              // Rota Adımları Başlığı
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Dar ekranda ya da büyük yazıda düğmeyle yan yana sığmaz: taşmak yerine kısalır.
                  Expanded(
                    child: Text(
                      s.isTr ? '🗺️ Rota Durakları & Hedefler' : '🗺️ Route Waypoints & Goals',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: AppFont.subtitle),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  TextButton.icon(
                    icon: const Icon(Icons.add, size: 18),
                    label: Text(s.isTr ? 'Adım Ekle' : 'Add Step'),
                    onPressed: () => _showAddStepDialog(context, r),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Rota Timeline / Metro Hatları
              if (sortedSteps.isEmpty)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 30),
                    child: Text(
                      s.isTr ? 'Bu haritada henüz bir adım bulunmuyor.' : 'No steps in this roadmap yet.',
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                  ),
                )
              else
                ...List.generate(sortedSteps.length, (idx) {
                  final step = sortedSteps[idx];
                  final isLast = idx == sortedSteps.length - 1;
                  return _buildStepTimelineItem(r, step, idx + 1, isLast, scheme, s.isTr);
                }),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStatusBadge(Roadmap r, bool isTr) {
    if (r.isCompleted) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.green.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          isTr ? '🏆 Tamamlandı' : '🏆 Completed',
          style: const TextStyle(fontSize: AppFont.micro, fontWeight: FontWeight.bold, color: Colors.green),
        ),
      );
    }
    if (r.isActive) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.grey.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        isTr ? '⏳ Başlatılmadı' : '⏳ Not Started',
        style: const TextStyle(fontSize: AppFont.micro, fontWeight: FontWeight.w600, color: Colors.grey),
      ),
    );
  }

  Widget _buildJourneyActionButton(Roadmap r, bool isTr) {
    if (r.isCompleted) {
      return FilledButton.tonalIcon(
        onPressed: () => store.setRoadmapStatus(r.id, 'active'),
        icon: const Icon(Icons.replay_rounded),
        label: Text(isTr ? 'Yolculuğu Tekrar Başlat' : 'Restart Journey'),
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      );
    }

    if (r.isActive) {
      return Row(
        children: [
          Expanded(
            child: FilledButton.icon(
              onPressed: () => store.setRoadmapStatus(r.id, 'paused'),
              icon: const Icon(Icons.pause_circle_outline_rounded),
              label: Text(isTr ? 'Yolculuğu Duraklat' : 'Pause Journey'),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.amber.shade700,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
          const SizedBox(width: 10),
          IconButton.filledTonal(
            tooltip: isTr ? 'Yolculuğu Tamamla' : 'Finish Journey',
            onPressed: () => store.setRoadmapStatus(r.id, 'completed'),
            icon: const Icon(Icons.check_circle_outline_rounded),
            style: IconButton.styleFrom(
              padding: const EdgeInsets.all(14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ],
      );
    }

    return FilledButton.icon(
      onPressed: () async {
        await store.setRoadmapStatus(r.id, 'active');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(isTr
                  ? '🚀 "${r.title}" yolculuğu başladı! Hedeflerin Günlük ekranına eklendi.'
                  : '🚀 Journey started! Steps added to Today page.'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      },
      icon: const Icon(Icons.rocket_launch_rounded),
      label: Text(isTr ? '🚀 Yolculuğu Başlat' : '🚀 Start Journey'),
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }

  Widget _buildStepTimelineItem(
    Roadmap roadmap,
    RoadmapStep step,
    int displayIndex,
    bool isLast,
    ColorScheme scheme,
    bool isTr,
  ) {
    final isDone = step.isCompleted;
    final linked = store.activities[step.linkedActivityId];

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Sol Timeline Çizgisi ve Durak Baloncuğu
          Column(
            children: [
              GestureDetector(
                onTap: () => store.toggleRoadmapStep(step.id),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: isDone ? Colors.green : scheme.surfaceContainerHighest,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isDone ? Colors.green : scheme.outlineVariant,
                      width: 2,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: isDone
                      ? const Icon(Icons.check, color: Colors.white, size: 20)
                      : Text(
                          '$displayIndex',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: AppFont.small,
                            color: scheme.onSurface,
                          ),
                        ),
                ),
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2.5,
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    color: isDone ? Colors.green.withValues(alpha: 0.5) : scheme.outlineVariant.withValues(alpha: 0.5),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 14),

          // Sağ İçerik Kartı
          Expanded(
            child: Container(
              margin: const EdgeInsets.only(bottom: 14),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: isDone
                    ? Colors.green.withValues(alpha: 0.06)
                    : scheme.surfaceContainerHighest.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isDone ? Colors.green.withValues(alpha: 0.3) : scheme.outlineVariant.withValues(alpha: 0.3),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          step.title,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: AppFont.body,
                            decoration: isDone ? TextDecoration.lineThrough : null,
                            color: isDone ? scheme.onSurface.withValues(alpha: 0.6) : scheme.onSurface,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: step.isGoal ? scheme.primaryContainer : scheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          step.isGoal
                              ? (step.target != null
                                  ? '${fmtNum(step.target!)} ${step.unit ?? ""}'.trim()
                                  : (isTr ? "Hedef" : "Goal"))
                              : (isTr ? '✓ Görev' : '✓ Task'),
                          style: TextStyle(
                            fontSize: AppFont.micro,
                            fontWeight: FontWeight.bold,
                            color: step.isGoal ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      _buildStepMenu(step, linked, isTr),
                    ],
                  ),
                  if (linked != null) ...[
                    const SizedBox(height: 6),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.link_rounded, size: 14, color: scheme.primary),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            store.activityLabel(linked.id),
                            style: TextStyle(fontSize: AppFont.caption, fontWeight: FontWeight.w600, color: scheme.primary),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    // Bağlı aktivitenin kayıtları bu adımı doldurur ve tamamlar.
                    const SizedBox(height: 6),
                    StepProgressLine(roadmap: roadmap, step: step),
                  ],
                  if (step.description.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      step.description,
                      style: TextStyle(
                        fontSize: AppFont.small,
                        color: scheme.onSurfaceVariant,
                        height: 1.35,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Adımın menüsü: aktivite bağlama ve silme.
  Widget _buildStepMenu(RoadmapStep step, Activity? linked, bool isTr) {
    return PopupMenuButton<String>(
      // Varsayılan 48 dp'lik düğme kartları gereksiz uzatır.
      padding: EdgeInsets.zero,
      tooltip: isTr ? 'Adım seçenekleri' : 'Step options',
      child: const Padding(
        padding: EdgeInsets.fromLTRB(8, 4, 0, 4),
        child: Icon(Icons.more_vert, size: 20),
      ),
      onSelected: (value) async {
        if (value == 'link') {
          final act = await showActivityPicker(
            context,
            title: isTr ? 'Adıma Bağlanacak Aktivite' : 'Activity for This Step',
          );
          if (act != null) await store.setRoadmapStepActivity(step.id, act.id);
        } else if (value == 'unlink') {
          await store.setRoadmapStepActivity(step.id, null);
        } else if (value == 'delete') {
          final ok = await confirm(
            context,
            isTr ? 'Adımı Sil' : 'Delete Step',
            isTr ? '"${step.title}" adımı silinsin mi?' : 'Delete the step "${step.title}"?',
            ok: isTr ? 'Sil' : 'Delete',
          );
          if (ok) await store.deleteRoadmapStep(step.roadmapId, step.id);
        }
      },
      itemBuilder: (_) => [
        PopupMenuItem(
          value: 'link',
          child: Text(linked == null
              ? (isTr ? 'Aktivite bağla' : 'Link an activity')
              : (isTr ? 'Bağlı aktiviteyi değiştir' : 'Change linked activity')),
        ),
        if (linked != null)
          PopupMenuItem(value: 'unlink', child: Text(isTr ? 'Bağlantıyı kaldır' : 'Remove link')),
        PopupMenuItem(value: 'delete', child: Text(isTr ? 'Adımı sil' : 'Delete step')),
      ],
    );
  }

  Future<void> _showAddStepDialog(BuildContext context, Roadmap r) async {
    final s = strings.value;
    final titleController = TextEditingController();
    final descController = TextEditingController();
    String type = 'task';
    final targetController = TextEditingController();
    final unitController = TextEditingController();
    Activity? linkedActivity;

    await showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(s.isTr ? 'Yeni Durak / Adım Ekle' : 'Add Route Step'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: titleController,
                      decoration: InputDecoration(
                        labelText: s.isTr ? 'Adım Başlığı *' : 'Step Title *',
                        hintText: s.isTr ? 'Örn: Radyoyu tamir et' : 'e.g. Fix the radio',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: descController,
                      maxLines: 2,
                      decoration: InputDecoration(
                        labelText: s.isTr ? 'Açıklama / İpuçları' : 'Description / Tips',
                      ),
                    ),
                    const SizedBox(height: 12),
                    SegmentedButton<String>(
                      // Onay işareti "Ölçüsüz Görev"i iki satıra bölüyordu; seçim dolgu rengiyle görünür.
                      showSelectedIcon: false,
                      segments: [
                        ButtonSegment(value: 'task', label: Text(s.isTr ? 'Ölçüsüz Görev' : 'Task')),
                        ButtonSegment(value: 'goal', label: Text(s.isTr ? 'Ölçülü Hedef' : 'Goal')),
                      ],
                      selected: {type},
                      onSelectionChanged: (val) => setDialogState(() => type = val.first),
                    ),
                    const SizedBox(height: 8),
                    // İsteğe bağlı: bağlanan aktivitenin kayıtları adımı doldurur ve tamamlar.
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        icon: const Icon(Icons.link_rounded, size: 18),
                        label: Text(
                          linkedActivity == null
                              ? (s.isTr ? 'Aktivite bağla (isteğe bağlı)' : 'Link an activity (optional)')
                              : store.activityLabel(linkedActivity!.id),
                        ),
                        onPressed: () async {
                          final act = await showActivityPicker(
                            context,
                            title: s.isTr ? 'Adıma Bağlanacak Aktivite' : 'Activity for This Step',
                          );
                          if (act != null) setDialogState(() => linkedActivity = act);
                        },
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: const EdgeInsets.only(left: 12),
                        child: Text(
                          s.isTr
                              ? 'Bağlı aktivitenin kayıtları bu adımı kendiliğinden doldurur ve tamamlar.'
                              : 'Entries of the linked activity fill and complete this step on their own.',
                          style: TextStyle(
                            fontSize: AppFont.micro,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                    if (type == 'goal') ...[
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: targetController,
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(labelText: s.isTr ? 'Toplam Miktar' : 'Total Target'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: unitController,
                              decoration: InputDecoration(labelText: s.isTr ? 'Birim' : 'Unit'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: Text(s.cancel)),
                FilledButton(
                  onPressed: () async {
                    final title = titleController.text.trim();
                    if (title.isEmpty) return;
                    final targetVal = double.tryParse(targetController.text.trim());
                    final unitVal = unitController.text.trim();

                    final newStep = RoadmapStep(
                      id: 0,
                      roadmapId: r.id,
                      order: r.steps.length + 1,
                      title: title,
                      description: descController.text.trim(),
                      type: type,
                      target: targetVal,
                      unit: unitVal.isEmpty ? null : unitVal,
                      isCompleted: false,
                      linkedActivityId: linkedActivity?.id,
                    );

                    await store.addRoadmapStep(r.id, newStep);
                    if (ctx.mounted) Navigator.pop(ctx);
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
