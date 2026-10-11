import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../../data/store.dart';
import '../../logic/l10n.dart';
import '../components/roadmap_card.dart';
import '../components/roadmap_import_dialog.dart';
import '../roadmap_detail_page.dart';

class RoadmapsTab extends StatelessWidget {
  const RoadmapsTab({super.key});

  static void showCreateOptions(BuildContext context) {
    final s = strings.value;
    final scheme = Theme.of(context).colorScheme;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  s.newRoadmap,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.auto_awesome_rounded, color: scheme.primary),
                ),
                title: Text(
                  s.isTr ? 'AI Kalıbı ile İçe Aktar (Önerilen)' : 'Import with AI Prompt (Recommended)',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  s.isTr
                      ? 'Kalıbı kopyala, ChatGPT veya Claude çıktısını yapıştırıp anında yükle.'
                      : 'Copy template, paste LLM output and create in seconds.',
                  style: const TextStyle(fontSize: 12),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  RoadmapImportDialog.show(context);
                },
              ),
              const Divider(height: 20),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.edit_note_rounded, color: scheme.onSurfaceVariant),
                ),
                title: Text(
                  s.isTr ? 'Manuel Boş Harita Başlat' : 'Create Manually',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  s.isTr
                      ? 'Adımları ve hedefleri kendin tek tek belirle.'
                      : 'Define steps and goals completely on your own.',
                  style: const TextStyle(fontSize: 12),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  showManualRoadmapDialog(context);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Future<void> showManualRoadmapDialog(BuildContext context) async {
    final s = strings.value;
    final titleCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    String emoji = '🗺️';

    final created = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(s.isTr ? 'Manuel Yol Haritası' : 'Manual Roadmap'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () {
                      final emojis = ['🗺️', '🎯', '🏃', '📚', '💪', '🛠️', '🎓', '💼', '🚀', '⭐'];
                      final next = emojis[(emojis.indexOf(emoji) + 1) % emojis.length];
                      setDialogState(() => emoji = next);
                    },
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(emoji, style: const TextStyle(fontSize: 24)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: titleCtrl,
                      autofocus: true,
                      decoration: InputDecoration(
                        labelText: s.isTr ? 'Harita Başlığı' : 'Roadmap Title',
                        hintText: s.isTr ? 'Örn: Sınava Hazırlık' : 'e.g. Exam Prep',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              TextField(
                controller: descCtrl,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: s.isTr ? 'Açıklama (İsteğe bağlı)' : 'Description (Optional)',
                  hintText: s.isTr ? 'Bu yolculuğun nihai amacı nedir?' : 'What is the goal of this journey?',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(s.cancel)),
            FilledButton(
              onPressed: () {
                if (titleCtrl.text.trim().isNotEmpty) {
                  Navigator.pop(ctx, true);
                }
              },
              child: Text(s.save),
            ),
          ],
        ),
      ),
    );

    if (created == true && titleCtrl.text.trim().isNotEmpty) {
      final newRoadmap = Roadmap(
        title: titleCtrl.text.trim(),
        description: descCtrl.text.trim(),
        emoji: emoji,
        status: 'not_started',
        steps: [],
      );
      final saved = await store.createRoadmap(newRoadmap);
      if (context.mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => RoadmapDetailPage(roadmapId: saved.id)),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = strings.value;
    final scheme = Theme.of(context).colorScheme;
    final roadmaps = store.roadmaps;

    if (roadmaps.isEmpty) {
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.alt_route_rounded, size: 64, color: scheme.primary),
              ),
              const SizedBox(height: 20),
              Text(
                s.isTr ? 'Henüz Bir Yol Haritası Yok' : 'No Roadmaps Yet',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              Text(
                s.isTr
                    ? 'Büyük hedeflerine adım adım ulaşmak için yapay zeka ile veya kendin bir yolculuk planı oluşturabilirsin.'
                    : 'Create a step-by-step roadmap to achieve your big goals, powered by AI or manually.',
                textAlign: TextAlign.center,
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 14, height: 1.4),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                icon: const Icon(Icons.auto_awesome_rounded),
                label: Text(s.isTr ? 'AI Kalıbı ile İçe Aktar' : 'Import with AI Prompt'),
                onPressed: () => RoadmapImportDialog.show(context),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                icon: const Icon(Icons.add),
                label: Text(s.isTr ? 'Manuel Harita Oluştur' : 'Create Manually'),
                onPressed: () => showManualRoadmapDialog(context),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
      itemCount: roadmaps.length,
      itemBuilder: (context, index) {
        final r = roadmaps[index];
        return RoadmapCard(
          roadmap: r,
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => RoadmapDetailPage(roadmapId: r.id)),
            );
          },
        );
      },
    );
  }
}
