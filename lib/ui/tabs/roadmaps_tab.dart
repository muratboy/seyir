import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../../data/store.dart';
import '../../logic/l10n.dart';
import '../components/roadmap_ai_dialog.dart';
import '../components/roadmap_card.dart';
import '../components/roadmap_import_dialog.dart';
import '../components/roadmap_link_dialog.dart';
import '../roadmap_detail_page.dart';
import '../app_font.dart';

class RoadmapsTab extends StatelessWidget {
  const RoadmapsTab({super.key});

  static void showCreateOptions(BuildContext context) {
    final s = strings.value;
    final scheme = Theme.of(context).colorScheme;

    showModalBottomSheet(
      context: context,
      // Sayfa içeriği kadar uzar: küçük telefonda varsayılan yükseklik üç seçeneğe yetmiyordu.
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        // Üç seçenek, küçük telefonda büyük yazıyla sayfanın yüksekliğine sığmayabilir.
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  s.newRoadmap,
                  style: const TextStyle(fontSize: AppFont.title, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 16),
              if (store.hasLlmKey) ...[
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.purple.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.auto_awesome_rounded, color: Colors.purpleAccent),
                  ),
                  title: Text(
                    s.isTr ? 'Yapay Zekâ ile Anında Üret (Önerilen)' : 'Generate with AI Instantly (Recommended)',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    s.isTr
                        ? 'Konunu yaz, ${store.llmProviderDisplayName} ile saniyeler içinde yol haritan hazırlansın.'
                        : 'Enter your topic, generated in seconds with ${store.llmProviderDisplayName}.',
                    style: const TextStyle(fontSize: AppFont.caption),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    RoadmapAiDialog.show(context);
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
                    child: Icon(Icons.copy_rounded, color: scheme.onSurfaceVariant),
                  ),
                  title: Text(
                    s.isTr ? 'Kalıpla İçe Aktar (Kopyala/Yapıştır)' : 'Import with Template (Copy/Paste)',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    s.isTr
                        ? 'Kalıbı kopyala, yapay zekâ asistanının yanıtını yapıştırıp yükle.'
                        : 'Copy the template, paste the AI assistant\'s answer and create.',
                    style: const TextStyle(fontSize: AppFont.caption),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    RoadmapImportDialog.show(context);
                  },
                ),
              ] else ...[
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
                    s.isTr ? 'Yapay Zekâ Kalıbıyla İçe Aktar (Önerilen)' : 'Import with AI Prompt (Recommended)',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    s.isTr
                        ? 'Kalıbı kopyala, yapay zekâ asistanının yanıtını yapıştırıp anında yükle.'
                        : 'Copy the template, paste the AI assistant\'s answer and create in seconds.',
                    style: const TextStyle(fontSize: AppFont.caption),
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
                      color: Colors.purple.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.bolt_rounded, color: Colors.purpleAccent),
                  ),
                  title: Text(
                    s.isTr ? 'Tek Tuşla AI Üretimi (BYOK)' : 'One-Tap AI Generation (BYOK)',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    s.isTr
                        ? 'Kendi ücretsiz Gemini veya OpenAI anahtarını ekleyerek doğrudan üret.'
                        : 'Add your own free Gemini or OpenAI key to generate directly.',
                    style: const TextStyle(fontSize: AppFont.caption),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    RoadmapAiDialog.show(context);
                  },
                ),
              ],
              const Divider(height: 20),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.link_rounded, color: scheme.onSurfaceVariant),
                ),
                title: Text(
                  s.isTr ? 'Bağlantıdan Ekle' : 'Add from a Link',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  s.isTr
                      ? 'Birinin internette paylaştığı yol haritasını bağlantısıyla ekle.'
                      : 'Add a roadmap someone shared online by its link.',
                  style: const TextStyle(fontSize: AppFont.caption),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  RoadmapLinkDialog.show(context);
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
                  style: const TextStyle(fontSize: AppFont.caption),
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
                      child: Text(emoji, style: const TextStyle(fontSize: AppFont.display)),
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

  // Hedefler sayfası bu listeyi sabit (const) olarak gömer; sayfa yeniden çizilse de sabit bir bileşen
  // yeniden çizilmez. Liste bu yüzden store'u kendisi dinler: yoksa eklenen ya da silinen öğe, sekmeden
  // çıkıp geri gelinene kadar ekranda değişmiyordu.
  @override
  Widget build(BuildContext context) => AnimatedBuilder(animation: store, builder: (context, _) => _list(context));

  Widget _list(BuildContext context) {
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
                style: const TextStyle(fontSize: AppFont.headline, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              Text(
                s.isTr
                    ? 'Büyük hedeflerine adım adım ulaşmak için yapay zekâ ile ya da kendin bir yolculuk planı oluşturabilir, '
                        'birinin paylaştığı bir planı bağlantısından ekleyebilirsin.'
                    : 'Create a step-by-step roadmap to reach your big goals with AI or on your own, or add one '
                        'someone shared by its link.',
                textAlign: TextAlign.center,
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: AppFont.body, height: 1.4),
              ),
              const SizedBox(height: 24),
              if (store.hasLlmKey) ...[
                FilledButton.icon(
                  icon: const Icon(Icons.auto_awesome_rounded),
                  label: Text(s.isTr ? 'Yapay Zekâ ile Anında Üret' : 'Generate with AI'),
                  onPressed: () => RoadmapAiDialog.show(context),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  icon: const Icon(Icons.copy_rounded),
                  label: Text(s.isTr ? 'Kalıpla İçe Aktar' : 'Import with Template'),
                  onPressed: () => RoadmapImportDialog.show(context),
                ),
              ] else ...[
                FilledButton.icon(
                  icon: const Icon(Icons.auto_awesome_rounded),
                  label: Text(s.isTr ? 'Yapay Zekâ Kalıbıyla İçe Aktar' : 'Import with AI Prompt'),
                  onPressed: () => RoadmapImportDialog.show(context),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  icon: const Icon(Icons.bolt_rounded, color: Colors.purpleAccent),
                  label: Text(s.isTr ? 'Tek Tuşla AI Üretimi (BYOK)' : 'One-Tap AI Generation (BYOK)'),
                  onPressed: () => RoadmapAiDialog.show(context),
                ),
              ],
              const SizedBox(height: 10),
              OutlinedButton.icon(
                icon: const Icon(Icons.link_rounded),
                label: Text(s.isTr ? 'Bağlantıdan Ekle' : 'Add from a Link'),
                onPressed: () => RoadmapLinkDialog.show(context),
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
