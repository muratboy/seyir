import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../data/models.dart';
import '../../logic/l10n.dart';
import '../../services/roadmap_parser.dart';
import '../app_font.dart';
import 'roadmap_preview.dart';

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
    final s = strings.value;
    Clipboard.setData(ClipboardData(text: RoadmapParser.promptFor(isTr: s.isTr)));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          s.isTr
              ? '📋 Kalıp kopyalandı! Şimdi kullandığın yapay zekâ asistanına yapıştırabilirsin.'
              : '📋 Template copied! Now paste it into the AI assistant you use.',
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
    _textController.text = strings.value.isTr ? _exampleTr : _exampleEn;
    _tryParse();
  }

  // Örnek, kalıbı izleyen bir yapay zekâ yanıtı gibidir ve iki adım türünü de içerir: tiklenen görevler
  // ve miktarı olan hedefler. Hedeflerin miktarı toplamdır: adıma bağlanan aktivitenin kayıtları birikir.
  static const _exampleEn = r'''```json
{
  "title": "Conversational Spanish in 3 Months",
  "description": "A plan of short daily sessions to hold everyday conversations with ease",
  "category": "Language Learning",
  "emoji": "🗣️",
  "steps": [
    {
      "order": 1,
      "title": "Check your level and write down your aim",
      "description": "Take a free placement test; write in one sentence what you want to be able to do in three months",
      "type": "task",
      "target": null,
      "unit": null
    },
    {
      "order": 2,
      "title": "Study vocabulary",
      "description": "Twenty minutes a day; repeat new words inside sentences, not one by one",
      "type": "goal",
      "target": 600,
      "unit": "min"
    },
    {
      "order": 3,
      "title": "Watch a series with Spanish subtitles",
      "description": "Pause and note the phrases you did not catch",
      "type": "goal",
      "target": 12,
      "unit": "episodes"
    },
    {
      "order": 4,
      "title": "Find a conversation partner or club",
      "description": "Someone you can talk with out loud at least once a week",
      "type": "task",
      "target": null,
      "unit": null
    },
    {
      "order": 5,
      "title": "Practise speaking out loud",
      "description": "Do not fear mistakes; record yourself and listen back",
      "type": "goal",
      "target": 240,
      "unit": "min"
    },
    {
      "order": 6,
      "title": "Hold a ten-minute conversation entirely in Spanish",
      "description": "Test yourself with this conversation at the end of the three months",
      "type": "task",
      "target": null,
      "unit": null
    }
  ]
}
```''';

  static const _exampleTr = r'''```json
{
  "title": "3 Ayda İngilizce Konuşma Pratiği",
  "description": "Her gün kısa çalışmalarla günlük konuşmaları rahatça sürdürebilecek düzeye gelme planı",
  "category": "Dil Öğrenme",
  "emoji": "🗣️",
  "steps": [
    {
      "order": 1,
      "title": "Seviyeni ölç ve hedefini yaz",
      "description": "Ücretsiz bir seviye testi çöz; üç ay sonra ne yapabilmek istediğini tek cümleyle yaz",
      "type": "task",
      "target": null,
      "unit": null
    },
    {
      "order": 2,
      "title": "Kelime çalış",
      "description": "Günde yirmi dakika; yeni kelimeleri tek tek değil, cümle içinde tekrar et",
      "type": "goal",
      "target": 600,
      "unit": "dk"
    },
    {
      "order": 3,
      "title": "İngilizce altyazılı dizi izle",
      "description": "Anlamadığın kalıpları durdurup not al",
      "type": "goal",
      "target": 12,
      "unit": "bölüm"
    },
    {
      "order": 4,
      "title": "Bir konuşma arkadaşı ya da kulübü bul",
      "description": "Haftada en az bir kez sesli konuşabileceğin biri olsun",
      "type": "task",
      "target": null,
      "unit": null
    },
    {
      "order": 5,
      "title": "Sesli konuşma pratiği yap",
      "description": "Hata yapmaktan çekinme; konuşmanı kaydedip dinle",
      "type": "goal",
      "target": 240,
      "unit": "dk"
    },
    {
      "order": 6,
      "title": "On dakikalık bir sohbeti baştan sona İngilizce sürdür",
      "description": "Üç ayın sonunda kendini bu sohbetle sına",
      "type": "task",
      "target": null,
      "unit": null
    }
  ]
}
```''';

  void _tryParse() {
    setState(() {
      _errorMessage = null;
      _previewRoadmap = null;
    });

    final text = _textController.text.trim();
    if (text.isEmpty) return;

    final parsed = RoadmapParser.parse(text, isTr: strings.value.isTr);
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

    // 1. adım: kalıbı kopyala
    final templateStep = Card(
      elevation: 0,
      color: scheme.primaryContainer.withValues(alpha: 0.35),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      // Metin bütün genişliği kullanır, düğme altındadır: yan yana konduklarında dar ekranda metin her satıra
      // bir kelime düşen bir sütuna sıkışıyordu.
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.auto_awesome, color: Colors.amber, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    s.isTr
                        ? '1. Adım: Hazır kalıbı kopyala, konunu yazıp bir yapay zekâ asistanına gönder.'
                        : 'Step 1: Copy the template, add your topic and send it to an AI assistant.',
                    style: const TextStyle(fontSize: AppFont.small, fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
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
    );

    // 2. adım: yanıtı yapıştır
    // Başlık ve iki düğme yan yana sığmazsa düğmeler alt satıra geçer; başlık dar bir sütuna sıkışmaz.
    final answerHeader = Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          s.isTr ? '2. Adım: Yanıtı Yapıştır:' : 'Step 2: Paste the Answer:',
          style: const TextStyle(fontSize: AppFont.small, fontWeight: FontWeight.bold),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
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
      ],
    );

    // Yanıtın yazıldığı kutu ya da okunan yol haritasının önizlemesi
    final answerBox = _previewRoadmap != null
        ? RoadmapPreview(roadmap: _previewRoadmap!)
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
                  style: const TextStyle(color: Colors.red, fontSize: AppFont.caption),
                ),
              ],
            ],
          );

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
                  child: const Text('🗺️', style: TextStyle(fontSize: AppFont.display)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        s.isTr ? 'Yapay Zekâ ile Yol Haritası' : 'AI Roadmap Generator',
                        style: const TextStyle(fontSize: AppFont.subtitle, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        s.isTr
                            ? 'Kalıbı kopyala, yapay zekânın yanıtını yapıştır'
                            : 'Copy the template, paste the AI answer',
                        style: TextStyle(fontSize: AppFont.caption, color: scheme.onSurfaceVariant),
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

            // İki adım ve yanıt kutusu kalan yeri doldurur. Klavye açıkken küçük telefonda sığmazlarsa bu bölüm
            // kayar; yanıt kutusu en az 160 px yüksekliğinde kalır.
            Expanded(
              child: LayoutBuilder(
                builder: (context, box) => SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: box.maxHeight),
                    child: IntrinsicHeight(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          templateStep,
                          const SizedBox(height: 12),
                          answerHeader,
                          const SizedBox(height: 6),
                          Expanded(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(minHeight: 160),
                              // Stack içindekinin doğal yüksekliğini sormaz: kutu kalan yeri doldurur, uzun bir
                              // yanıt ya da önizleme kendi içinde kayar.
                              child: Stack(children: [Positioned.fill(child: answerBox)]),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Alt düğmeler: yan yana sığmazlarsa alt alta dizilir ("Metni Düzenle" ile "Yol Haritasını
            // Yükle" 412 dp genişlikte satıra sığmıyordu).
            OverflowBar(
              alignment: _previewRoadmap != null ? MainAxisAlignment.spaceBetween : MainAxisAlignment.end,
              overflowAlignment: OverflowBarAlignment.end,
              spacing: 8,
              overflowSpacing: 4,
              children: [
                // Simgesiz: iki düğme 412 dp genişlikte ancak böyle yan yana sığıyor.
                if (_previewRoadmap != null)
                  TextButton(
                    onPressed: () => setState(() => _previewRoadmap = null),
                    child: Text(s.isTr ? 'Metni Düzenle' : 'Edit Text'),
                  ),
                if (_previewRoadmap == null)
                  FilledButton.icon(
                    onPressed: _tryParse,
                    icon: const Icon(Icons.preview_rounded),
                    label: Text(s.isTr ? 'Yolu Önizle' : 'Preview Roadmap'),
                  )
                else
                  FilledButton.icon(
                    onPressed: () => saveImportedRoadmap(context, _previewRoadmap!),
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
}
