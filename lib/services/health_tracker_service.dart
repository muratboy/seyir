import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:pedometer/pedometer.dart';
import '../data/store.dart';

class HealthTrackerService {
  static HealthTrackerService? _instance;
  static HealthTrackerService get instance => _instance ??= HealthTrackerService._();

  HealthTrackerService._();

  StreamSubscription<StepCount>? _stepSubscription;
  bool _isListening = false;

  bool get isListening => _isListening;

  static const _permissions = MethodChannel('dev.takip.takip/permissions');

  /// Adım sensörü için Android 10+ "fiziksel aktivite" iznini ister. İzin verildiyse ya da gerekmiyorsa
  /// true döner. pedometer eklentisi bu izni kendisi istemez; izin yoksa sensör hiç veri göndermez.
  Future<bool> requestStepPermission() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return true;
    try {
      return await _permissions.invokeMethod<bool>('requestActivityRecognition') ?? false;
    } on MissingPluginException {
      // Ekranı olmayan bir isolate'tayız (bildirim ya da widget): izin penceresi açılamaz.
      return true;
    } catch (e) {
      debugPrint('HealthTrackerService: permission request failed: $e');
      return false;
    }
  }

  /// Fiziksel aktivite izni verilmiş mi; pencere açmadan bakar. İzin yokken sensör hata vermez, yalnızca
  /// hiç okuma göndermez, bu yüzden eksik izin ancak böyle anlaşılır.
  Future<bool> hasStepPermission() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return true;
    try {
      return await _permissions.invokeMethod<bool>('hasActivityRecognition') ?? true;
    } catch (_) {
      return true;
    }
  }

  /// Adım dinleyicisini başlatır.
  void startStepTracking(AppStore store) {
    if (_isListening) return;
    if (!store.stepTrackerEnabled) return;

    try {
      _stepSubscription = Pedometer.stepCountStream.listen(
        (StepCount event) {
          store.handlePedometerStepEvent(event.steps);
        },
        onError: (error) {
          debugPrint('HealthTrackerService: Pedometer error: $error');
          // Sensör hatası uygulamayı çökertmez; kullanıcıya nazikçe bildirilir
          store.handlePedometerError(error.toString());
        },
        cancelOnError: false,
      );
      _isListening = true;
    } catch (e) {
      debugPrint('HealthTrackerService: Could not listen to pedometer: $e');
    }
  }

  /// Adım dinleyicisini durdurur.
  void stopStepTracking() {
    _stepSubscription?.cancel();
    _stepSubscription = null;
    _isListening = false;
  }
}
