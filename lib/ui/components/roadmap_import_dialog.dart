import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../data/models.dart';
import '../../data/store.dart';
import '../../logic/l10n.dart';
import '../../services/roadmap_parser.dart';

class RoadmapImportDialog extends StatefulWidget {
  const RoadmapImportDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const RoadmapImportDialog(),
    );
  }

  @override
  State<RoadmapImportDialog> createState() => _RoadmapImportDialogState();
}

class _RoadmapImportDialogState extends State<RoadmapImportDialog> {
  final _textController = TextEditingController();
  Roadmap? _previewRoadmap;
  String? _errorMessage;

  void _copyTemplate() {
    Clipboard.setData(const ClipboardData(text: RoadmapParser.promptTemplate));
    final s = strings.value;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          s.isTr
              ? '📋 LLM Kalıbı kopyalandı! Şimdi ChatGPT, Claude veya Gemini\'ye yapıştırabilirsin.'
              : '📋 LLM Template copied! Now paste it into ChatGPT, Claude or Gemini.',
        ),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null && data!.text!.isNotEmpty) {
      _textController.text = data.text!;
      _tryParse();
    }
  }

  void _fillExample() {
    _textController.text = r'''```json
{
  "title": "Eski Radyo Tamiri & Elektronik",
  "description": "Bozuk bir lambalı radyoyu teşhis edip çalışır hale getirme yolculuğu",
  "category": "Tamirat & Hobi",
  "emoji": "📻",
  "steps": [
    {
      "order": 1,
      "title": "Havya, lehim teli ve multimetre temin et",
      "description": "Gerekli güvenlik ve tamir ekipmanlarını hazırla",
      "type": "task"
    },
    {
      "order": 2,
      "title": "Radyonun kasasını aç ve devre kartını temizle",
      "description": "Elektronik parçalara zarar vermeden fırça ile temizlik yap",
      "type": "task"
    },
    {
      "order": 3,
      "title": "Güç katındaki arızalı kondansatörü değiştir",
      "description": "Eski lehimleri söküp yeni parçayı lehimle",
      "type": "task"
    },
    {
      "order": 4,
      "title": "Hoparlör ve anten bağlantısını test et",
      "description": "İlk çalıştırmada cızırtısız temiz frekans yakala",
      "type": "task"
    }
  ]
}
```''';
    _tryParse();
  }

  void _tryParse() {
    setState(() {
      _errorMessage = null;
      _previewRoadmap = null;
    });

    final text = _textController.text.trim();
    if (text.isEmpty) return;

    final parsed = RoadmapParser.parse(text);
    if (parsed == null) {
      setState(() {
        _errorMessage = strings.value.isTr
            ? 'Geçerli bir yol haritası JSON çıktısı bulunamadı. Lütfen kalıba uygun yanıtı yapıştırın.'
            : 'Could not parse a valid roadmap JSON. Please paste the response formatted according to the template.';
      });
    } else {
      setState(() {
        _previewRoadmap = parsed;
      });
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = strings.value;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 680),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Başlık
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text('🗺️', style: TextStyle(fontSize: 24)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        s.isTr ? 'Yapay Zekâ ile Yol Haritası' : 'AI Roadmap Generator',
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        s.isTr ? 'Kalıbı kopyala, LLM çıktısını yapıştır' : 'Copy template, paste LLM output',
                        style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // 1. Adım: Kalıbı Kopyala Kartı
            Card(
              elevation: 0,
              color: scheme.primaryContainer.withValues(alpha: 0.35),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    const Icon(Icons.auto_awesome, color: Colors.amber, size: 22),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        s.isTr
                            ? '1. Adım: Hazır kalıbı kopyalayıp konunu belirterek ChatGPT/Claude/Gemini\'ye yaz.'
                            : 'Step 1: Copy template and send to ChatGPT/Claude/Gemini.',
                        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.tonalIcon(
                      onPressed: _copyTemplate,
                      icon: const Icon(Icons.copy_rounded, size: 16),
                      label: Text(s.isTr ? 'Kalıbı Kopyala' : 'Copy Template'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // 2. Adım: Çıktıyı Yapıştır Metin Kutusu
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    s.isTr ? '2. Adım: Çıktıyı Yapıştır:' : 'Step 2: Paste Output:',
                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
                  ),
                ),
                TextButton.icon(
                  onPressed: _fillExample,
                  icon: const Icon(Icons.auto_fix_high_rounded, size: 14),
                  label: Text(s.isTr ? 'Örnek' : 'Example'),
                  style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                ),
                TextButton.icon(
                  onPressed: _pasteFromClipboard,
                  icon: const Icon(Icons.paste_rounded, size: 14),
                  label: Text(s.isTr ? 'Yapıştır' : 'Paste'),
                  style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                ),
              ],
            ),
            const SizedBox(height: 6),

            Expanded(
              child: _previewRoadmap != null
                  ? _buildPreview(scheme, s.isTr)
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _textController,
                            maxLines: null,
                            expands: true,
                            textAlignVertical: TextAlignVertical.top,
                            decoration: InputDecoration(
                              hintText: s.isTr
                                  ? 'Yapay zekânın verdiği yanıtı (tüm metni veya JSON kodunu) buraya yapıştırın...'
                                  : 'Paste AI response (text or JSON block) here...',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                              contentPadding: const EdgeInsets.all(12),
                            ),
                            onChanged: (_) => setState(() => _errorMessage = null),
                          ),
                        ),
                        if (_errorMessage != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            _errorMessage!,
                            style: const TextStyle(color: Colors.red, fontSize: 12),
                          ),
                        ],
                      ],
                    ),
            ),
            const SizedBox(height: 16),

            // Alt Butonlar
            Row(
              children: [
                if (_previewRoadmap != null)
                  TextButton.icon(
                    onPressed: () => setState(() => _previewRoadmap = null),
                    icon: const Icon(Icons.edit_note_rounded),
                    label: Text(s.isTr ? 'Metni Düzenle' : 'Edit Text'),
                  ),
                const Spacer(),
                if (_previewRoadmap == null)
                  FilledButton.icon(
                    onPressed: _tryParse,
                    icon: const Icon(Icons.preview_rounded),
                    label: Text(s.isTr ? 'Yolu Önizle' : 'Preview Roadmap'),
                  )
                else
                  FilledButton.icon(
                    onPressed: () async {
                      await store.createRoadmap(_previewRoadmap!);
                      if (context.mounted) {
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              s.isTr
                                  ? '🎉 "${_previewRoadmap!.title}" yol haritalarına eklendi!'
                                  : '🎉 "${_previewRoadmap!.title}" added to roadmaps!',
                            ),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      }
                    },
                    icon: const Icon(Icons.check_rounded),
                    label: Text(s.isTr ? 'Yol Haritasını Yükle' : 'Save Roadmap'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreview(ColorScheme scheme, bool isTr) {
    final r = _previewRoadmap!;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.green.withValues(alpha: 0.4)),
      ),
      child: ListView(
        children: [
          Row(
            children: [
              Text(r.emoji, style: const TextStyle(fontSize: 26)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      r.title,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    Text(
                      '${r.category} • ${r.steps.length} ${isTr ? "Adım" : "Steps"}',
                      style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (r.description.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(r.description, style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant)),
          ],
          const Divider(height: 20),
          Text(
            isTr ? 'Adımlar / Duraklar:' : 'Steps / Waypoints:',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          ),
          const SizedBox(height: 8),
          ...r.steps.map((st) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${st.order}. ', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            st.title,
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                          ),
                          if (st.description.isNotEmpty)
                            Text(
                              st.description,
                              style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
                            ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: st.isGoal ? scheme.primaryContainer : scheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        st.isGoal
                            ? (st.target != null ? '${st.target} ${st.unit ?? ""}' : (isTr ? "Hedef" : "Goal"))
                            : (isTr ? "Görev" : "Task"),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: st.isGoal ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }
}
