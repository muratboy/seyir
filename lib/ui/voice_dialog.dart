import 'package:flutter/material.dart';
import '../data/store.dart';
import '../logic/l10n.dart';
import '../services/nl_parser.dart';
import '../services/voice_service.dart';

Future<void> showVoiceInputDialog(
  BuildContext context, {
  required void Function(NlParseResult result) onConfirmed,
}) async {
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _VoiceInputModal(onConfirmed: onConfirmed),
  );
}

class _VoiceInputModal extends StatefulWidget {
  final void Function(NlParseResult result) onConfirmed;

  const _VoiceInputModal({required this.onConfirmed});

  @override
  State<_VoiceInputModal> createState() => _VoiceInputModalState();
}

class _VoiceInputModalState extends State<_VoiceInputModal> with SingleTickerProviderStateMixin {
  bool _isListening = false;
  String _spokenText = '';
  NlParseResult? _parsedResult;
  late AnimationController _animController;

  final List<String> _quickSamples = [
    '2 kupa filtre kahve',
    '1.5 litre su içtim',
    'ders çalışma kronometre başlat',
    'kitap okuma 25 dakika pomodoro',
    '1 porsiyon meyve',
  ];

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);

    _startListening();
  }

  @override
  void dispose() {
    VoiceService.stop();
    _animController.dispose();
    super.dispose();
  }

  Future<void> _startListening() async {
    setState(() {
      _isListening = true;
      _spokenText = '';
      _parsedResult = null;
    });

    final success = await VoiceService.startListening(
      onResult: (text) {
        if (!mounted) return;
        setState(() {
          _spokenText = text;
          _parseText(text);
        });
      },
      onListeningChanged: (listening) {
        if (!mounted) return;
        setState(() => _isListening = listening);
      },
    );

    if (!success && mounted) {
      setState(() => _isListening = false);
    }
  }

  void _parseText(String text) {
    final res = NaturalLanguageParser.parse(
      text,
      activities: store.activities.values.toList(),
      measures: store.measures,
    );
    setState(() {
      _parsedResult = res;
    });
  }

  void _selectSample(String sample) {
    setState(() {
      _spokenText = sample;
      _parseText(sample);
      _isListening = false;
    });
    VoiceService.stop();
  }

  void _confirmAndApply() {
    if (_parsedResult == null) return;
    Navigator.of(context).pop();
    widget.onConfirmed(_parsedResult!);
  }

  @override
  Widget build(BuildContext context) {
    final s = strings.value;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: scheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Header
          Row(
            children: [
              Icon(Icons.mic, color: scheme.primary, size: 24),
              const SizedBox(width: 8),
              Text(
                s.isTr ? 'Sesli / Akıllı Komut' : 'Voice / Smart Command',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Microphone animation circle
          Center(
            child: AnimatedBuilder(
              animation: _animController,
              builder: (context, child) {
                final scale = _isListening ? 1.0 + (_animController.value * 0.15) : 1.0;
                return Transform.scale(
                  scale: scale,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(44),
                    onTap: () {
                      if (_isListening) {
                        VoiceService.stop();
                        setState(() => _isListening = false);
                      } else {
                        _startListening();
                      }
                    },
                    child: Container(
                      width: 88,
                      height: 88,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _isListening
                            ? scheme.primaryContainer
                            : scheme.surfaceContainerHighest,
                        border: Border.all(
                          color: _isListening ? scheme.primary : Colors.transparent,
                          width: 3,
                        ),
                        boxShadow: _isListening
                            ? [
                                BoxShadow(
                                  color: scheme.primary.withValues(alpha: 0.3),
                                  blurRadius: 18,
                                  spreadRadius: 2,
                                )
                              ]
                            : null,
                      ),
                      child: Icon(
                        _isListening ? Icons.mic : Icons.mic_none,
                        size: 40,
                        color: _isListening ? scheme.primary : scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 12),

          // Status subtitle
          Center(
            child: Text(
              _isListening
                  ? (s.isTr ? 'Dinleniyor... Şimdi konuşun' : 'Listening... Speak now')
                  : (s.isTr ? 'Mikrofona dokunup konuşun' : 'Tap mic to speak'),
              style: TextStyle(
                fontSize: 14,
                color: _isListening ? scheme.primary : scheme.outline,
                fontWeight: _isListening ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Spoken text display
          if (_spokenText.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: scheme.outlineVariant),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.isTr ? 'Algılanan Ses:' : 'Recognized Voice:',
                    style: TextStyle(fontSize: 12, color: scheme.outline),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '"$_spokenText"',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),

          // Parsed result preview card
          if (_parsedResult != null) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: scheme.primaryContainer.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: scheme.primary.withValues(alpha: 0.5)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.auto_awesome, color: scheme.primary, size: 18),
                      const SizedBox(width: 6),
                      Text(
                        s.isTr ? 'Akıllı Ayrıştırma Sonucu' : 'Smart Parse Result',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: scheme.primary,
                        ),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: scheme.primary.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '%${(_parsedResult!.confidence * 100).round()} Eşleşme',
                          style: TextStyle(fontSize: 11, color: scheme.primary, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _parsedResult!.summary,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  if (_parsedResult!.matchedMeasure != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        'Ölçü: ${_parsedResult!.matchedMeasure!.name} (${_parsedResult!.matchedMeasure!.amount} ${_parsedResult!.matchedMeasure!.unitId})',
                        style: TextStyle(fontSize: 12, color: scheme.outline),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: _confirmAndApply,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              icon: Icon(
                _parsedResult!.actionType == NlActionType.startStopwatch ||
                        _parsedResult!.actionType == NlActionType.startPomodoro
                    ? Icons.play_arrow
                    : Icons.check,
              ),
              label: Text(
                _parsedResult!.actionType == NlActionType.startStopwatch
                    ? (s.isTr ? 'Kronometreyi Başlat' : 'Start Stopwatch')
                    : _parsedResult!.actionType == NlActionType.startPomodoro
                        ? (s.isTr ? 'Pomodoro Başlat' : 'Start Pomodoro')
                        : (s.isTr ? 'Onayla ve Kaydet' : 'Confirm and Log'),
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
            ),
          ],

          // Quick samples for easy testing (especially on emulator or noisy environments)
          const SizedBox(height: 16),
          Text(
            s.isTr ? 'Hızlı Komut Örnekleri (Dokun ve Dene):' : 'Quick Samples (Tap to Try):',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: scheme.outline),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final sample in _quickSamples)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ActionChip(
                      label: Text(sample, style: const TextStyle(fontSize: 12)),
                      onPressed: () => _selectSample(sample),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
