import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/models.dart';
import '../../logic/l10n.dart';
import '../../services/roadmap_link_service.dart';
import '../../services/roadmap_parser.dart';
import '../app_font.dart';
import 'roadmap_preview.dart';

/// Birinin internette paylaştığı yol haritasını bağlantısından ekler: adres yapıştırılır, metin indirilir,
/// yapay zekâ kalıbıyla aynı biçimde okunur ve kaydedilmeden önce önizlenir.
class RoadmapLinkDialog extends StatefulWidget {
  /// Testler indirmeyi değiştirebilsin diye; verilmezse [RoadmapLinkService.fetch].
  final RoadmapLinkFetcher? fetcher;

  const RoadmapLinkDialog({super.key, this.fetcher});

  static Future<void> show(BuildContext context, {RoadmapLinkFetcher? fetcher}) =>
      showDialog<void>(context: context, builder: (_) => RoadmapLinkDialog(fetcher: fetcher));

  @override
  State<RoadmapLinkDialog> createState() => _RoadmapLinkDialogState();
}

class _RoadmapLinkDialogState extends State<RoadmapLinkDialog> {
  final _controller = TextEditingController();
  bool _loading = false;
  String? _error;
  Roadmap? _preview;
  String? _source;

  /// Sonucu beklenen son istek; daha eski bir isteğin geç gelen yanıtı ekrana yazılmaz.
  int _request = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (text == null || text.isEmpty || !mounted) return;
    setState(() {
      _controller.text = text;
      _error = null;
    });
  }

  Future<void> _fetch() async {
    final isTr = strings.value.isTr;
    final Uri uri;
    try {
      uri = RoadmapLinkService.normalize(_controller.text);
    } on RoadmapLinkException catch (e) {
      setState(() => _error = _problemText(e, isTr));
      return;
    }
    FocusScope.of(context).unfocus();
    final id = ++_request;
    setState(() {
      _loading = true;
      _error = null;
    });

    Roadmap? roadmap;
    String? error;
    try {
      final text = await (widget.fetcher ?? RoadmapLinkService.fetch)(uri);
      roadmap = RoadmapParser.parse(text, isTr: isTr);
      if (roadmap == null) {
        error = isTr
            ? 'Bağlantıdaki içerik yol haritası biçiminde değil. Adres doğrudan yol haritası metnine (JSON) '
                'gitmeli; GitHub\'da "Raw" bağlantısını kullan.'
            : 'The content behind the link is not a roadmap. The address must lead straight to the roadmap '
                'text (JSON); on GitHub use the "Raw" link.';
      } else if (roadmap.steps.length > RoadmapLinkService.maxSteps) {
        roadmap = null;
        error = isTr
            ? 'Bu yol haritası çok uzun (en fazla ${RoadmapLinkService.maxSteps} adım).'
            : 'This roadmap is too long (${RoadmapLinkService.maxSteps} steps at most).';
      }
    } on RoadmapLinkException catch (e) {
      error = _problemText(e, isTr);
    } catch (_) {
      error = _problemText(const RoadmapLinkException(RoadmapLinkProblem.network), isTr);
    }
    if (!mounted || id != _request) return;
    setState(() {
      _loading = false;
      _error = error;
      _preview = roadmap;
      _source = uri.host;
    });
  }

  static String _problemText(RoadmapLinkException e, bool isTr) => switch (e.problem) {
        RoadmapLinkProblem.invalidLink => isTr
            ? 'Bu bir internet adresine benzemiyor. https:// ile başlayan bir bağlantı yapıştır.'
            : 'That does not look like a web address. Paste a link that starts with https://.',
        RoadmapLinkProblem.insecure => isTr
            ? 'Güvenlik için yalnızca https:// ile başlayan bağlantılar açılır.'
            : 'For safety, only links that start with https:// are opened.',
        RoadmapLinkProblem.localAddress => isTr
            ? 'Bu adres yalnızca kendi cihazında ya da ağında geçerli; internetteki bir adres kullan.'
            : 'That address only works on your own device or network; use an address on the internet.',
        RoadmapLinkProblem.network => isTr
            ? 'Bağlantıya ulaşılamadı. İnternet bağlantını ve adresi kontrol edip yeniden dene.'
            : 'Could not reach the link. Check your internet connection and the address, then try again.',
        RoadmapLinkProblem.timeout => isTr
            ? 'Sunucu zamanında yanıt vermedi. Biraz sonra yeniden dene.'
            : 'The server did not answer in time. Try again in a moment.',
        RoadmapLinkProblem.status => isTr
            ? 'Sunucu bu bağlantıyı vermedi (hata ${e.status}). Adresi kontrol et.'
            : 'The server did not return this link (error ${e.status}). Check the address.',
        RoadmapLinkProblem.tooLarge => isTr
            ? 'Bağlantıdaki dosya bir yol haritası için fazla büyük (en fazla 256 KB).'
            : 'The file behind the link is too large for a roadmap (256 KB at most).',
        RoadmapLinkProblem.tooManyRedirects => isTr
            ? 'Bağlantı çok fazla kez başka adrese yönlendiriyor.'
            : 'The link redirects too many times.',
      };

  @override
  Widget build(BuildContext context) {
    final isTr = strings.value.isTr;
    final scheme = Theme.of(context).colorScheme;
    final preview = _preview;

    final header = Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: scheme.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(Icons.link_rounded, color: scheme.primary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isTr ? 'Bağlantıdan Yol Haritası' : 'Roadmap from a Link',
                style: const TextStyle(fontSize: AppFont.subtitle, fontWeight: FontWeight.bold),
              ),
              Text(
                isTr ? 'Paylaşılan bir yol haritasının adresini yapıştır' : 'Paste the address of a shared roadmap',
                style: TextStyle(fontSize: AppFont.caption, color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: isTr ? 'Kapat' : 'Close',
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
      ],
    );

    final input = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: const Key('roadmap-link-field'),
          controller: _controller,
          enabled: !_loading,
          keyboardType: TextInputType.url,
          textInputAction: TextInputAction.go,
          autocorrect: false,
          enableSuggestions: false,
          onSubmitted: (_) => _fetch(),
          onChanged: (_) => setState(() => _error = null),
          decoration: InputDecoration(
            labelText: isTr ? 'Bağlantı' : 'Link',
            hintText: 'https://…',
            prefixIcon: const Icon(Icons.link_rounded),
            suffixIcon: IconButton(
              tooltip: isTr ? 'Yapıştır' : 'Paste',
              icon: const Icon(Icons.content_paste_rounded),
              onPressed: _loading ? null : _paste,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          isTr
              ? 'Yalnızca https bağlantıları açılır. İndirilen metin, eklenmeden önce burada önizlenir.'
              : 'Only https links are opened. The downloaded text is previewed here before it is added.',
          style: TextStyle(fontSize: AppFont.caption, color: scheme.onSurfaceVariant),
        ),
        if (_error != null) ...[
          const SizedBox(height: 10),
          Text(
            _error!,
            key: const Key('roadmap-link-error'),
            style: TextStyle(fontSize: AppFont.caption, color: scheme.error),
          ),
        ],
      ],
    );

    final buttons = OverflowBar(
      alignment: preview != null ? MainAxisAlignment.spaceBetween : MainAxisAlignment.end,
      overflowAlignment: OverflowBarAlignment.end,
      spacing: 8,
      overflowSpacing: 4,
      children: [
        if (preview != null) ...[
          TextButton(
            onPressed: () => setState(() => _preview = null),
            child: Text(isTr ? 'Bağlantıyı Değiştir' : 'Change Link'),
          ),
          FilledButton.icon(
            onPressed: () => saveImportedRoadmap(context, preview),
            icon: const Icon(Icons.check_rounded),
            label: Text(isTr ? 'Yol Haritasını Yükle' : 'Save Roadmap'),
          ),
        ] else
          FilledButton.icon(
            onPressed: _loading || _controller.text.trim().isEmpty ? null : _fetch,
            icon: _loading
                ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.download_rounded),
            label: Text(_loading ? (isTr ? 'Getiriliyor…' : 'Fetching…') : (isTr ? 'Getir' : 'Fetch')),
          ),
      ],
    );

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 680),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              header,
              const SizedBox(height: 16),
              // Önizleme kalan yeri doldurur ve kendi içinde kayar; adres alanı ise klavye açıkken küçük
              // ekranda sığmazsa kayar.
              if (preview != null)
                Expanded(child: RoadmapPreview(roadmap: preview, source: _source))
              else
                Flexible(child: SingleChildScrollView(child: input)),
              const SizedBox(height: 16),
              buttons,
            ],
          ),
        ),
      ),
    );
  }
}
