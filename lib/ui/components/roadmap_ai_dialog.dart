import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../../data/store.dart';
import '../../logic/l10n.dart';
import '../../services/ai_service.dart';
import '../app_font.dart';
import '../settings_pages.dart';
import 'roadmap_import_dialog.dart';
import 'roadmap_preview.dart';

/// Yapay zekâ ile doğrudan ve tek dokunuşla yol haritası üreten diyalog (BYOK modu).
class RoadmapAiDialog extends StatefulWidget {
  final String? initialTopic;

  const RoadmapAiDialog({super.key, this.initialTopic});

  static Future<void> show(BuildContext context, {String? initialTopic}) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => RoadmapAiDialog(initialTopic: initialTopic),
    );
  }

  @override
  State<RoadmapAiDialog> createState() => _RoadmapAiDialogState();
}

class _RoadmapAiDialogState extends State<RoadmapAiDialog> {
  late final TextEditingController _topicCtrl;
  bool _isLoading = false;
  String? _errorMessage;
  Roadmap? _generatedRoadmap;

  final List<String> _trPresets = [
    '🗣️ 3 Ayda İspanyolca',
    '🏃 10K Koşu Planı',
    '💻 Flutter ile Uygulama Geliştirme',
    '🧘 30 Günlük Meditasyon & Farkındalık',
    '📚 Ayda 3 Kitap Bitirme',
    '🎸 Temel Gitar Öğrenme',
  ];

  final List<String> _enPresets = [
    '🗣️ Spanish in 3 Months',
    '🏃 10K Running Plan',
    '💻 Flutter App Development',
    '🧘 30 Days of Mindfulness',
    '📚 Read 3 Books a Month',
    '🎸 Acoustic Guitar Basics',
  ];

  @override
  void initState() {
    super.initState();
    _topicCtrl = TextEditingController(text: widget.initialTopic ?? '');
  }

  @override
  void dispose() {
    _topicCtrl.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    final topic = _topicCtrl.text.trim();
    final isTr = strings.value.isTr;

    if (topic.isEmpty) {
      setState(() {
        _errorMessage = isTr
            ? 'Lütfen neyi başarmak veya öğrenmek istediğinizi yazın.'
            : 'Please describe what you want to achieve or learn.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final roadmap = await AiService.generateRoadmap(
        topic: topic,
        provider: store.llmProvider,
        apiKey: store.llmApiKey,
        model: store.llmModel,
        customEndpoint: store.llmCustomEndpoint,
        isTr: isTr,
      );

      if (mounted) {
        setState(() {
          _isLoading = false;
          _generatedRoadmap = roadmap;
        });
      }
    } on AiException catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = e.message;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = isTr ? 'Beklenmeyen bir hata oluştu: $e' : 'An unexpected error occurred: $e';
        });
      }
    }
  }

  Widget _buildSetupRequired(BuildContext context, bool isTr, ColorScheme scheme) {
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: scheme.primaryContainer.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: scheme.primary.withValues(alpha: 0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.vpn_key_rounded, color: Colors.amber, size: 22),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        isTr ? 'Kendi Anahtarını Getir (BYOK)' : 'Bring Your Own Key (BYOK)',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: AppFont.small),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  isTr
                      ? 'Seyir tamamen çevrimdışı ve gizlilik odaklıdır. Tek tıkla uygulama içinden yol haritası üretebilmek için kendi ücretsiz Google Gemini (veya OpenAI) API anahtarınızı tanımlayabilirsiniz.'
                      : 'Seyir is offline-first and privacy focused. To generate roadmaps with one tap directly inside the app, configure your own free Google Gemini (or OpenAI) API key.',
                  style: const TextStyle(fontSize: AppFont.caption),
                ),
                const SizedBox(height: 6),
                Text(
                  isTr
                      ? '💡 Google Gemini ücretsiz katmanı kredi kartı gerektirmez ve saniyeler içinde alınabilir.'
                      : '💡 Google Gemini free tier requires no credit card and takes seconds to set up.',
                  style: TextStyle(
                    fontSize: AppFont.micro,
                    color: scheme.onSurfaceVariant,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AiSettingsPage()),
              );
            },
            icon: const Icon(Icons.settings_suggest_rounded),
            label: Text(isTr ? 'API Anahtarı Tanımla (Ayarlar)' : 'Configure API Key (Settings)'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () {
              Navigator.pop(context);
              RoadmapImportDialog.show(context);
            },
            icon: const Icon(Icons.copy_rounded),
            label: Text(isTr ? 'Kalıbı Kopyala-Yapıştır ile Kullan' : 'Use Copy-Paste Template Instead'),
          ),
        ],
      ),
    );
  }

  void _showModelSelector(BuildContext context, bool isTr, ColorScheme scheme) {
    final models = AiService.recommendedModelsFor(store.llmProvider, isTr: isTr);

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Icon(Icons.tune_rounded, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${store.llmProviderDisplayName} ${isTr ? 'Model Seçimi' : 'Model Selection'}',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: AppFont.subtitle),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ...models.map((m) {
                  final isSelected = store.activeLlmModel == m.id;
                  return ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(m.displayName, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: m.badge != null ? Text(m.badge!, style: const TextStyle(fontSize: AppFont.caption)) : null,
                    trailing: isSelected ? Icon(Icons.check_circle_rounded, color: scheme.primary) : null,
                    onTap: () async {
                      await store.setLlmConfig(
                        provider: store.llmProvider,
                        apiKey: store.llmApiKey,
                        model: m.id,
                        customEndpoint: store.llmCustomEndpoint,
                      );
                      if (ctx.mounted) Navigator.pop(ctx);
                      if (mounted) {
                        setState(() {
                          _errorMessage = null;
                        });
                      }
                    },
                  );
                }),
                const Divider(),
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.settings_suggest_rounded, size: 20),
                  title: Text(isTr ? 'Tüm Yapay Zekâ Ayarları...' : 'All AI Settings...'),
                  trailing: const Icon(Icons.chevron_right_rounded, size: 20),
                  onTap: () {
                    Navigator.pop(ctx);
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const AiSettingsPage()),
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildGenerationForm(BuildContext context, bool isTr, ColorScheme scheme) {
    final presets = isTr ? _trPresets : _enPresets;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Sağlayıcı ve model rozeti
                InkWell(
                  onTap: () => _showModelSelector(context, isTr, scheme),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.auto_awesome, size: 14, color: Colors.purpleAccent),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            '${store.llmProviderDisplayName} · ${store.activeLlmModel}',
                            style: TextStyle(
                              fontSize: AppFont.caption,
                              fontWeight: FontWeight.w600,
                              color: scheme.onSurfaceVariant,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Icon(Icons.tune_rounded, size: 14, color: scheme.onSurfaceVariant),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // Hızlı konu önerileri
                Text(
                  isTr ? 'Hızlı Öneriler:' : 'Quick Suggestions:',
                  style: TextStyle(
                    fontSize: AppFont.caption,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 6),
                SizedBox(
                  height: 32,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: presets.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 6),
                    itemBuilder: (context, i) {
                      final label = presets[i];
                      return ActionChip(
                        label: Text(label, style: const TextStyle(fontSize: AppFont.caption)),
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        visualDensity: VisualDensity.compact,
                        onPressed: () {
                          final clean = label.replaceFirst(RegExp(r'^[^\w\s]+\s*'), '');
                          _topicCtrl.text = clean;
                          setState(() => _errorMessage = null);
                        },
                      );
                    },
                  ),
                ),
                const SizedBox(height: 12),

                // Konu giriş kutusu
                TextField(
                  controller: _topicCtrl,
                  maxLines: 3,
                  textInputAction: TextInputAction.done,
                  decoration: InputDecoration(
                    labelText: isTr ? 'Hedefin veya Konun' : 'Your Goal or Topic',
                    hintText: isTr
                        ? 'Örn: 3 Ayda B2 İspanyolca, 10K Maraton Hazırlığı, KPSS Sınavı, Temel Elektronik...'
                        : 'E.g. Conversational Spanish in 3 months, 10K marathon training, Exam prep...',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                    contentPadding: const EdgeInsets.all(12),
                  ),
                  onChanged: (_) {
                    if (_errorMessage != null) {
                      setState(() => _errorMessage = null);
                    }
                  },
                ),

                if (_errorMessage != null) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: scheme.errorContainer.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.error_outline, color: scheme.error, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _errorMessage!,
                                style: TextStyle(color: scheme.onErrorContainer, fontSize: AppFont.caption),
                              ),
                            ),
                          ],
                        ),
                        if (_errorMessage!.toLowerCase().contains('model') ||
                            _errorMessage!.toLowerCase().contains('bulunamadı') ||
                            _errorMessage!.toLowerCase().contains('not found')) ...[
                          const SizedBox(height: 8),
                          FilledButton.tonalIcon(
                            style: FilledButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            ),
                            icon: const Icon(Icons.bolt_rounded, size: 16),
                            label: Text(
                              isTr
                                  ? '⚡ Önerilen Modele Geç (${AiService.defaultModelFor(store.llmProvider)}) ve Tekrar Dene'
                                  : '⚡ Switch to Recommended (${AiService.defaultModelFor(store.llmProvider)}) & Retry',
                              style: const TextStyle(fontSize: AppFont.caption, fontWeight: FontWeight.bold),
                            ),
                            onPressed: () async {
                              await store.setLlmConfig(
                                provider: store.llmProvider,
                                apiKey: store.llmApiKey,
                                model: AiService.defaultModelFor(store.llmProvider),
                                customEndpoint: store.llmCustomEndpoint,
                              );
                              setState(() {
                                _errorMessage = null;
                              });
                              _generate();
                            },
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),

        // Alt butonlar
        OverflowBar(
          alignment: MainAxisAlignment.spaceBetween,
          spacing: 8,
          overflowSpacing: 8,
          children: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                RoadmapImportDialog.show(context);
              },
              child: Text(isTr ? 'Kalıpla İçe Aktar' : 'Copy-Paste Template'),
            ),
            FilledButton.icon(
              onPressed: _generate,
              icon: const Icon(Icons.auto_awesome),
              label: Text(isTr ? 'Yol Haritası Üret' : 'Generate Roadmap'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildLoadingView(bool isTr, ColorScheme scheme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 48,
            height: 48,
            child: CircularProgressIndicator(strokeWidth: 3),
          ),
          const SizedBox(height: 20),
          Text(
            isTr ? 'Yol haritanız hazırlanıyor...' : 'Generating your roadmap...',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: AppFont.subtitle),
          ),
          const SizedBox(height: 8),
          Text(
            isTr
                ? '${store.llmProviderDisplayName} hedefleri, adımları ve süreleri planlıyor...'
                : '${store.llmProviderDisplayName} is structuring steps and targets...',
            style: TextStyle(fontSize: AppFont.caption, color: scheme.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildResultView(BuildContext context, bool isTr, ColorScheme scheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: RoadmapPreview(
            roadmap: _generatedRoadmap!,
            source: '${store.llmProviderDisplayName} (${store.activeLlmModel})',
          ),
        ),
        const SizedBox(height: 16),
        OverflowBar(
          alignment: MainAxisAlignment.spaceBetween,
          spacing: 8,
          overflowSpacing: 8,
          children: [
            TextButton.icon(
              onPressed: () {
                setState(() => _generatedRoadmap = null);
              },
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: Text(isTr ? 'Yeniden Üret' : 'Regenerate'),
            ),
            FilledButton.icon(
              onPressed: () => saveImportedRoadmap(context, _generatedRoadmap!),
              icon: const Icon(Icons.check_rounded),
              label: Text(isTr ? 'Yol Haritasını Yükle' : 'Save Roadmap'),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = strings.value;
    final isTr = s.isTr;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final hasKey = store.hasLlmKey;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 660),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Başlık satırı
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.purple.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text('✨', style: TextStyle(fontSize: AppFont.display)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isTr ? 'Yapay Zekâ ile Yol Haritası' : 'AI Roadmap Generator',
                        style: const TextStyle(fontSize: AppFont.subtitle, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        hasKey
                            ? (isTr ? 'Tek dokunuşla doğrudan üretim (BYOK)' : 'One-tap direct generation (BYOK)')
                            : (isTr ? 'Kendi API anahtarını kullan' : 'Use your own API key'),
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

            // İçerik alanı
            Expanded(
              child: AnimatedBuilder(
                animation: store,
                builder: (context, _) {
                  if (!store.hasLlmKey) {
                    return _buildSetupRequired(context, isTr, scheme);
                  }
                  if (_isLoading) {
                    return _buildLoadingView(isTr, scheme);
                  }
                  if (_generatedRoadmap != null) {
                    return _buildResultView(context, isTr, scheme);
                  }
                  return _buildGenerationForm(context, isTr, scheme);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
