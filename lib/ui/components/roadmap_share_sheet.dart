import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../data/models.dart';
import '../../logic/l10n.dart';
import '../../services/roadmap_parser.dart';
import '../app_font.dart';

/// Yol haritasını paylaşma: bir uygulamayla gönderme ya da metni kopyalama. Metin "Yapay Zekâ Kalıbıyla İçe
/// Aktar"a yapıştırılarak eklenir; bir siteye konursa oluşan bağlantı "Bağlantıdan Ekle" ile okunur.
Future<void> showRoadmapShareSheet(BuildContext context, Roadmap roadmap) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _RoadmapShareSheet(roadmap: roadmap),
    );

class _RoadmapShareSheet extends StatelessWidget {
  final Roadmap roadmap;

  const _RoadmapShareSheet({required this.roadmap});

  @override
  Widget build(BuildContext context) {
    final isTr = strings.value.isTr;
    final scheme = Theme.of(context).colorScheme;
    final text = RoadmapParser.shareText(roadmap, isTr: isTr);
    final note = TextStyle(fontSize: AppFont.caption, color: scheme.onSurfaceVariant, height: 1.35);

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              isTr ? 'Yol Haritasını Paylaş' : 'Share Roadmap',
              style: const TextStyle(fontSize: AppFont.title, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              isTr
                  ? 'Yalnızca plan paylaşılır: başlık, açıklama ve adımlar. İlerlemen ve adımlara bağladığın '
                      'aktiviteler sende kalır.'
                  : 'Only the plan is shared: title, description and steps. Your progress and the activities '
                      'linked to steps stay with you.',
              style: note,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              icon: const Icon(Icons.share_outlined),
              label: Text(isTr ? 'Uygulamayla Paylaş' : 'Share with an App'),
              onPressed: () async {
                Navigator.pop(context);
                await SharePlus.instance.share(ShareParams(text: text, subject: roadmap.title));
              },
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.copy_rounded),
              label: Text(isTr ? 'Metni Kopyala' : 'Copy the Text'),
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                await Clipboard.setData(ClipboardData(text: text));
                if (!context.mounted) return;
                Navigator.pop(context);
                messenger.showSnackBar(
                  SnackBar(content: Text(isTr ? 'Yol haritası metni kopyalandı' : 'Roadmap text copied')),
                );
              },
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.link_rounded, size: 18, color: scheme.onSurfaceVariant),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    isTr
                        ? 'Bağlantı olarak paylaşmak için metni GitHub Gist ya da Pastebin gibi bir siteye yapıştır '
                            've oluşan bağlantıyı gönder. Alan kişi Yol Haritası Ekle › Bağlantıdan Ekle ile ekler.'
                        : 'To share it as a link, paste the text into a site such as GitHub Gist or Pastebin and '
                            'send the link. The other person adds it with Add Roadmap › Add from a Link.',
                    style: note,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
