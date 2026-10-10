import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:pedometer/pedometer.dart';
import '../data/store.dart';

class HealthTrackerService {
  static HealthTrackerService? _instance;
  static HealthTrackerService get instance => _instance ??= HealthTrackerService._();

  HealthTrackerService._();

  StreamSubscription<StepCount>? _stepSubscription;
  bool _isListening = false;
  bool _sensorAvailable = true;
  String? _lastError;

  bool get isListening => _isListening;
  bool get sensorAvailable => _sensorAvailable;
  String? get lastError => _lastError;

  /// Adım dinleyicisini başlatır.
  void startStepTracking(AppStore store) {
    if (_isListening) return;
    if (!store.stepTrackerEnabled) return;

    try {
      _stepSubscription = Pedometer.stepCountStream.listen(
        (StepCount event) {
          _sensorAvailable = true;
          _lastError = null;
          store.handlePedometerStepEvent(event.steps);
        },
        onError: (error) {
          debugPrint('HealthTrackerService: Pedometer error: $error');
          _sensorAvailable = false;
          _lastError = error.toString();
          // Sensör hatası uygulamayı çökertmez; kullanıcıya nazikçe bildirilir
          store.handlePedometerError(error.toString());
        },
        cancelOnError: false,
      );
      _isListening = true;
    } catch (e) {
      debugPrint('HealthTrackerService: Could not listen to pedometer: $e');
      _sensorAvailable = false;
      _lastError = e.toString();
    }
  }

  /// Adım dinleyicisini durdurur.
  void stopStepTracking() {
    _stepSubscription?.cancel();
    _stepSubscription = null;
    _isListening = false;
  }
}
