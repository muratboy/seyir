import 'package:flutter/material.dart';
import '../data/store.dart';
import '../logic/l10n.dart';
import '../services/nl_parser.dart';
import '../services/voice_service.dart';
import '../logic/format.dart';
import 'app_font.dart';

Future<void> showVoiceInputDialog(
  BuildContext context, {
  required void Function(NlParseResult result) onConfirmed,
  void Function(String complexText)? onComplexInput,
}) async {
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _VoiceInputModal(onConfirmed: onConfirmed, onComplexInput: onComplexInput),
  );
}

class _VoiceInputModal extends StatefulWidget {
  final void Function(NlParseResult result) onConfirmed;
  final void Function(String complexText)? onComplexInput;

  const _VoiceInputModal({required this.onConfirmed, this.onComplexInput});

  @override
  State<_VoiceInputModal> createState() => _VoiceInputModalState();
}

class _VoiceInputModalState extends State<_VoiceInputModal> with SingleTickerProviderStateMixin {
  bool _isListening = false;
  String _spokenText = '';
  final TextEditingController _textController = TextEditingController();
  NlParseResult? _parsedResult;
  late AnimationController _animController;

  // Dile göre örnek cümleler.
  List<String> get _quickSamples => strings.value.isTr
      ? const [
          '2 kupa filtre kahve',
          '1.5 litre su içtim',
          'ders çalışma kronometre başlat',
          'kitap okuma 25 dakika pomodoro',
          '1 porsiyon meyve',
        ]
      : const [
          '2 cups of coffee',
          'reading 30 min',
          'study stopwatch',
          'pomodoro 25 min reading',
          'countdown 10 min tea',
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
    _textController.dispose();
    super.dispose();
  }

  Future<void> _startListening() async {
    setState(() {
      _isListening = true;
      _spokenText = '';
      _textController.clear();
      _parsedResult = null;
    });

    final success = await VoiceService.startListening(
      onResult: (text) {
        if (!mounted) return;
        setState(() {
          _spokenText = text;
          _textController.text = text;
          _textController.selection = TextSelection.fromPosition(
            TextPosition(offset: text.length),
          );
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
    if (text.trim().isEmpty) {
      setState(() => _parsedResult = null);
      return;
    }
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
      _textController.text = sample;
      _textController.selection = TextSelection.fromPosition(
        TextPosition(offset: sample.length),
      );
      _parseText(sample);
      _isListening = false;
    });
    VoiceService.stop();
  }

  void _confirmAndApply() {
    if (_parsedResult == null) return;
    Navigator.of(context).pop();

    final multi = NaturalLanguageParser.parseMulti(
      _spokenText,
      activities: store.activities.values.toList(),
      measures: store.measures,
    );
    final isComplex = multi.items.length > 1 ||
        multi.isTodoMode ||
        (multi.entryItems.isNotEmpty &&
            (multi.entryItems[0].hasExplicitDate ||
                multi.entryItems[0].hasExplicitTime ||
                multi.entryItems[0].isExplicitFuture));

    if (isComplex && widget.onComplexInput != null) {
      widget.onComplexInput!(_spokenText);
    } else {
      widget.onConfirmed(_parsedResult!);
    }
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
                style: const TextStyle(fontSize: AppFont.title, fontWeight: FontWeight.bold),
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
                fontSize: AppFont.body,
                color: _isListening ? scheme.primary : scheme.outline,
                fontWeight: _isListening ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Spoken / edited text input
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: _spokenText.isNotEmpty ? scheme.primary.withValues(alpha: 0.6) : scheme.outlineVariant,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(
                  Icons.edit_note_rounded,
                  size: 22,
                  color: _spokenText.isNotEmpty ? scheme.primary : scheme.outline,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _textController,
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      hintText: s.isTr ? 'Konuşun ya da komutu buraya yazın/düzeltin...' : 'Speak or type/edit command here...',
                      hintStyle: TextStyle(fontSize: AppFont.body, color: scheme.outline),
                    ),
                    style: const TextStyle(fontSize: AppFont.body, fontWeight: FontWeight.w600),
                    onChanged: (text) {
                      _spokenText = text;
                      _parseText(text);
                    },
                  ),
                ),
                if (_spokenText.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.clear, size: 18),
                    visualDensity: VisualDensity.compact,
                    onPressed: () {
                      _textController.clear();
                      setState(() {
                        _spokenText = '';
                        _parsedResult = null;
                      });
                    },
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
                          fontSize: AppFont.small,
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
                          '${fmtPercent((_parsedResult!.confidence * 100).round())} ${strings.value.isTr ? "Eşleşme" : "match"}',
                          style: TextStyle(fontSize: AppFont.micro, color: scheme.primary, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _parsedResult!.summaryIn(isTr: strings.value.isTr),
                    style: const TextStyle(fontSize: AppFont.subtitle, fontWeight: FontWeight.bold),
                  ),
                  if (_parsedResult!.matchedMeasure != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        '${strings.value.isTr ? "Ölçü" : "Measure"}: ${store.measureLabel(_parsedResult!.matchedMeasure!)}',
                        style: TextStyle(fontSize: AppFont.caption, color: scheme.outline),
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
                style: const TextStyle(fontSize: AppFont.subtitle, fontWeight: FontWeight.bold),
              ),
            ),
          ],

          // Quick samples for easy testing (especially on emulator or noisy environments)
          const SizedBox(height: 16),
          Text(
            s.isTr ? 'Hızlı Komut Örnekleri (Dokun ve Dene):' : 'Quick Samples (Tap to Try):',
            style: TextStyle(fontSize: AppFont.caption, fontWeight: FontWeight.w600, color: scheme.outline),
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
                      label: Text(sample, style: const TextStyle(fontSize: AppFont.caption)),
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
