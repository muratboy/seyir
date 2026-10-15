import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

class VoiceService {
  static final stt.SpeechToText _speech = stt.SpeechToText();
  static bool _initialized = false;
  static bool _hasSpeech = false;

  static bool get isListening => _speech.isListening;

  static Future<bool> init() async {
    if (_initialized) return _hasSpeech;
    try {
      _hasSpeech = await _speech.initialize(
        onError: (val) => debugPrint('VoiceService onError: $val'),
        onStatus: (val) => debugPrint('VoiceService onStatus: $val'),
      );
      _initialized = true;
    } catch (e) {
      debugPrint('VoiceService init failed: $e');
      _hasSpeech = false;
    }
    return _hasSpeech;
  }

  static Future<bool> startListening({
    required Function(String text) onResult,
    Function(bool isListening)? onListeningChanged,
    String localeId = 'tr_TR',
  }) async {
    final available = await init();
    if (!available) {
      onListeningChanged?.call(false);
      return false;
    }

    try {
      await _speech.listen(
        onResult: (result) {
          onResult(result.recognizedWords);
          if (result.finalResult) {
            onListeningChanged?.call(false);
          }
        },
        listenOptions: stt.SpeechListenOptions(
          localeId: localeId,
          cancelOnError: true,
          listenMode: stt.ListenMode.confirmation,
        ),
      );
      onListeningChanged?.call(true);
      return true;
    } catch (e) {
      debugPrint('VoiceService listen error: $e');
      onListeningChanged?.call(false);
      return false;
    }
  }

  static Future<void> stop() async {
    try {
      await _speech.stop();
    } catch (e) {
      debugPrint('VoiceService stop error: $e');
    }
  }
}
