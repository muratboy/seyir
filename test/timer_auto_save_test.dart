import 'package:flutter_test/flutter_test.dart';
import 'package:takip/data/models.dart';
import 'package:takip/data/store.dart';
import 'package:takip/logic/l10n.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Countdown and Pomodoro Auto-Save Settings & Logic', () {
    test('timerAutoSaveCompleted is true by default', () {
      expect(store.timerAutoSaveCompleted, isTrue);
    });

    test('timerAutoSaveCompleted setting can be toggled', () {
      store.timerAutoSaveCompleted = false;
      expect(store.timerAutoSaveCompleted, isFalse);
      store.timerAutoSaveCompleted = true;
      expect(store.timerAutoSaveCompleted, isTrue);
    });

    test('AppStrings provides localization for timer auto-save', () {
      final tr = const AppStrings(AppLanguage.tr);
      expect(tr.timerAutoSaveTitle, equals('Bitişte Otomatik Kaydet'));
      expect(tr.timerAutoSaveSubtitle, contains('Geri sayım ve Pomodoro'));

      final en = const AppStrings(AppLanguage.en);
      expect(en.timerAutoSaveTitle, equals('Auto-Save on Finish'));
      expect(en.timerAutoSaveSubtitle, contains('countdown and Pomodoro'));
    });

    test('Countdown timer isTargetReached triggers at targetMs', () {
      final now = DateTime.now().millisecondsSinceEpoch;
      final timer = ActiveTimer(
        id: 1,
        activityId: 10,
        startTs: now - (15 * 60 * 1000 + 500),
        accumulatedMs: 0,
        lastResumeTs: now - (15 * 60 * 1000 + 500),
        isRunning: true,
        mode: 'countdown',
        targetMs: 15 * 60 * 1000,
      );

      expect(timer.isCountdown, isTrue);
      expect(timer.isPomodoro, isFalse);
      expect(timer.isTargetReached, isTrue);
      expect(timer.remainingMs, equals(0));
    });

    test('Pomodoro timer isTargetReached triggers at 25 min', () {
      final now = DateTime.now().millisecondsSinceEpoch;
      final timer = ActiveTimer(
        id: 2,
        activityId: 20,
        startTs: now - (25 * 60 * 1000),
        accumulatedMs: 0,
        lastResumeTs: now - (25 * 60 * 1000),
        isRunning: true,
        mode: 'pomodoro',
        targetMs: 25 * 60 * 1000,
      );

      expect(timer.isCountdown, isTrue);
      expect(timer.isPomodoro, isTrue);
      expect(timer.isTargetReached, isTrue);
      expect(timer.remainingMs, equals(0));
    });

    test('ActiveTimer isTargetReached is false before targetMs', () {
      final now = DateTime.now().millisecondsSinceEpoch;
      final timer = ActiveTimer(
        id: 3,
        activityId: 30,
        startTs: now - (10 * 60 * 1000),
        accumulatedMs: 0,
        lastResumeTs: now - (10 * 60 * 1000),
        isRunning: true,
        mode: 'countdown',
        targetMs: 15 * 60 * 1000,
      );

      expect(timer.isTargetReached, isFalse);
      expect(timer.remainingMs, greaterThan(0));
    });
  });
}
