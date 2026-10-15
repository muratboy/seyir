import 'dart:convert';
import 'dart:isolate';

import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:takip/data/db.dart';
import 'package:takip/data/models.dart';
import 'package:takip/data/store.dart';
import 'package:takip/logic/format.dart';
import 'package:takip/logic/l10n.dart';
import 'package:takip/logic/text_match.dart';
import 'package:takip/services/backup_service.dart';
import 'package:takip/services/health_tracker_service.dart';
import 'package:takip/services/nl_parser.dart';
import 'package:takip/services/notification_service.dart';
import 'package:takip/services/roadmap_parser.dart';
import 'package:takip/services/store_sync.dart';
import 'package:takip/widget_sync.dart';

import 'support/real_db.dart';

Future<List<Map<String, Object?>>> _entryRows(AppStore s, int activityId) async =>
    (await s.db).query('entries', where: 'activity_id = ?', whereArgs: [activityId], orderBy: 'id');

Future<Map<String, Object?>?> _timerRow(AppStore s, int timerId) async {
  final rows = await (await s.db).query('active_timers', where: 'id = ?', whereArgs: [timerId]);
  return rows.isEmpty ? null : rows.first;
}

Future<void> _wait(int ms) => Future<void>.delayed(Duration(milliseconds: ms));

/// Waits until [done] holds, for two seconds at most.
Future<void> _until(bool Function() done) async {
  for (var i = 0; i < 200 && !done(); i++) {
    await _wait(10);
  }
}

/// What tapping an action button of the timer notification delivers to the app.
Future<void> _notificationAction(String actionId, int timerId) => NotificationService.handleNotificationAction(
      NotificationResponse(
        notificationResponseType: NotificationResponseType.selectedNotificationAction,
        actionId: actionId,
        payload: '$timerId',
      ),
    );

/// Runs [work] the way the system runs a notification action or a widget tap: in another isolate, which
/// has its own `store` on the database in [dbDir].
Future<void> _inAnotherIsolate(String dbDir, Future<void> Function() work) => Isolate.run(() async {
      await joinRealDatabase(dbDir);
      await work();
    });

// The closures are built here so that they carry nothing but these values into the other isolate.
Future<void> _notificationActionInAnotherIsolate(String dbDir, String actionId, int timerId) =>
    _inAnotherIsolate(dbDir, () => _notificationAction(actionId, timerId));

Future<void> _widgetTapInAnotherIsolate(String dbDir, int quickItemId) =>
    _inAnotherIsolate(dbDir, () => widgetBackgroundCallback(Uri.parse('takip://tap?id=$quickItemId')));

void main() {
  useRealDatabase();

  group('Completed countdowns are saved exactly once', () {
    test('overlapping completion checks create a single entry', () async {
      final s = await openStore();
      final act = await s.addActivity('Ders');
      await s.startTimer(act.id, mode: 'pomodoro', targetMs: 150);
      await _wait(200);

      // The store ticker, a timer card and load() can all notice the finished countdown at the same moment.
      await Future.wait([s.checkCompletedTimers(), s.checkCompletedTimers(), s.load()]);

      expect(await _entryRows(s, act.id), hasLength(1));
      expect(s.entries.where((e) => e.activityId == act.id), hasLength(1));
      expect(s.activeTimers, isEmpty);
    });

    test('a timer finished from another isolate is not saved again by a stale copy', () async {
      final app = await openStore();
      final act = await app.addActivity('Kitap');
      final t = await app.startTimer(act.id, mode: 'pomodoro', targetMs: 150);

      // The notification's finish action runs in a background isolate with its own store.
      final background = await openStore();
      expect(await background.finishTimer(t.id), isNotNull);

      // The target passes while the app still believes the timer is running.
      await _wait(200);
      expect(app.getTimer(t.id), isNotNull);
      await app.checkCompletedTimers();

      expect(await _entryRows(app, act.id), hasLength(1));
      expect(app.activeTimers, isEmpty, reason: 'the stale copy must be dropped');
      expect(await app.finishTimer(t.id), isNull);
    });

    test('a countdown paused from another isolate is not auto-saved as completed', () async {
      final app = await openStore();
      final act = await app.addActivity('Kitap');
      final t = await app.startTimer(act.id, mode: 'countdown', targetMs: 150);

      final background = await openStore();
      await background.pauseTimer(t.id);

      await _wait(200);
      await app.checkCompletedTimers();

      expect(await _entryRows(app, act.id), isEmpty);
      expect(app.getTimer(t.id)?.isRunning, isFalse, reason: 'the app copy must adopt the paused state');
    });

    test('the app shows the session when the background isolate wins the automatic save', () async {
      final app = await openStore();
      final act = await app.addActivity('Kitap');
      await app.startTimer(act.id, mode: 'pomodoro', targetMs: 150);

      // Every notification action reloads the background store, so its ticker watches the running
      // countdown too and races the app's ticker when the countdown completes.
      final background = await openStore();
      await _wait(200);
      await background.checkCompletedTimers();
      await app.checkCompletedTimers();

      expect(await _entryRows(app, act.id), hasLength(1));
      expect(app.activeTimers, isEmpty);
      expect(app.entries.where((e) => e.activityId == act.id), hasLength(1),
          reason: 'the session saved by the other isolate must appear in the app right away');
      expect(app.todayCount(act.id), 1);
    });

    test('pausing a timer that another isolate finished drops it and shows its entry', () async {
      final app = await openStore();
      final act = await app.addActivity('Kitap');
      final t = await app.startTimer(act.id);

      final background = await openStore();
      expect(await background.finishTimer(t.id), isNotNull);

      await app.pauseTimer(t.id);

      expect(app.activeTimers, isEmpty);
      expect(await _timerRow(app, t.id), isNull);
      expect(app.entries.where((e) => e.activityId == act.id), hasLength(1));
    });
  });

  group('Notification actions', () {
    test('act on current data even when the background store was loaded earlier', () async {
      // The global store plays the background isolate; reload it last so its ticker stops too.
      addTearDown(() => store.load());
      final app = await openStore();
      final act = await app.addActivity('Koşu');
      final t = await app.startTimer(act.id);

      // The first action loads the background store.
      await _notificationAction('timer_pause', t.id);
      expect((await _timerRow(app, t.id))?['is_running'], 0);

      // The user resumes inside the app and pauses from the notification again.
      await app.load();
      await app.resumeTimer(t.id);
      await _notificationAction('timer_pause', t.id);
      expect((await _timerRow(app, t.id))?['is_running'], 0, reason: 'a second pause must not be ignored');

      // A timer the app started after the background store was loaded.
      final act2 = await app.addActivity('Yüzme');
      final t2 = await app.startTimer(act2.id);
      await _notificationAction('timer_pause', t2.id);
      expect((await _timerRow(app, t2.id))?['is_running'], 0, reason: 'timers started later must be known');

      // The app resumed the first timer five minutes ago; finishing from the notification saves that time.
      final fiveMinutesAgo = DateTime.now().millisecondsSinceEpoch - 5 * 60 * 1000;
      await (await app.db).update(
        'active_timers',
        {
          'start_ts': fiveMinutesAgo,
          'last_resume_ts': fiveMinutesAgo,
          'accumulated_ms': 0,
          'is_running': 1,
          'segments': '[]',
        },
        where: 'id = ?',
        whereArgs: [t.id],
      );
      await _notificationAction('timer_finish', t.id);

      final rows = await _entryRows(app, act.id);
      expect(rows, hasLength(1));
      expect(rows.single['unit_id'], 'dk');
      expect(rows.single['value'], closeTo(5.0, 0.11));
    });
  });

  group('Reading the data again', () {
    test('a refresh reads what another isolate wrote without redoing the start-up work', () async {
      // The step sensor of the pedometer plugin: accepts the listener and reports nothing.
      const sensor = MethodChannel('step_count');
      final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(sensor, (call) async => null);
      addTearDown(() {
        HealthTrackerService.instance.stopStepTracking();
        messenger.setMockMethodCallHandler(sensor, null);
      });

      final app = await openStore();
      expect(await app.setStepTrackerEnabled(true), isTrue);
      final act = await app.addActivity('Su');
      await app.addEntry(act.id);
      final t = await app.startTimer(act.id);
      // The listener belongs to the app; the store below stands for the one of the notification isolate.
      HealthTrackerService.instance.stopStepTracking();

      final background = newStore();
      await background.refresh();
      expect(background.loaded, isTrue);
      expect(background.entries, hasLength(1));
      expect(background.getTimer(t.id), isNotNull);
      expect(background.stepTrackerEnabled, isTrue);
      expect(HealthTrackerService.instance.isListening, isFalse, reason: 'only the app listens to the sensor');

      await background.load();
      expect(HealthTrackerService.instance.isListening, isTrue, reason: 'load() is the full start-up');
    });

    test('keeps the steps that were counted but not written yet', () async {
      final s = await openStore();
      final now = DateTime.now();
      await s.handlePedometerStepEvent(1000, at: now);
      await s.handlePedometerStepEvent(1010, at: now);
      await s.handlePedometerStepEvent(1020, at: now);
      expect(s.todaySteps, 20);

      // Not every reading is written to the database, so what is stored can be a few steps behind.
      await s.refresh();
      expect(s.todaySteps, 20);
      await s.load();
      expect(s.todaySteps, 20);
    });

    test('a day that changed in the background starts from the last sensor reading', () async {
      final s = await openStore();
      final now = DateTime.now();
      final yesterday = DateTime(now.year, now.month, now.day - 1, 22);
      await s.handlePedometerStepEvent(1000, at: yesterday);
      await s.handlePedometerStepEvent(1500, at: yesterday);
      await s.handlePedometerStepEvent(1520, at: yesterday);
      expect(s.stepsOn(yesterday), 520);

      // The app comes to the front the next morning: the data is read again before the sensor reports.
      await s.load();
      expect(s.todaySteps, 0);
      expect(s.stepsOn(yesterday), 520, reason: 'the last steps of that day had not been written yet');
      await s.handlePedometerStepEvent(1800);
      expect(s.todaySteps, 280, reason: 'the steps since the last reading are not lost');

      final restarted = newStore();
      await restarted.refresh();
      expect(restarted.stepsOn(yesterday), 520);
      expect(restarted.todaySteps, 280);
    });
  });

  group('Change signal between isolates', () {
    test('a notification action handled in another isolate reaches the open app', () async {
      final app = await openStore();
      final act = await app.addActivity('Gitar');
      final t = await app.startTimer(act.id);
      StoreSync.listen(app);
      addTearDown(StoreSync.close);

      await _notificationActionInAnotherIsolate(await databaseFactory.getDatabasesPath(), 'timer_pause', t.id);

      expect(await _timerRow(app, t.id), containsPair('is_running', 0));
      await _until(() => !app.getTimer(t.id)!.isRunning);
      expect(app.getTimer(t.id)!.isRunning, isFalse, reason: 'the app was told to read the data again');
    });

    test('a tap on the home screen widget reaches the open app', () async {
      final app = await openStore();
      final act = await app.addActivity('Su');
      final item = QuickItem(id: 0, activityId: act.id, kind: 'shortcut', createdAt: 0);
      await app.saveQuickItem(item);
      StoreSync.listen(app);
      addTearDown(StoreSync.close);

      await _widgetTapInAnotherIsolate(await databaseFactory.getDatabasesPath(), item.id);

      expect(await _entryRows(app, act.id), hasLength(1));
      await _until(() => app.entries.isNotEmpty);
      expect(app.entries, hasLength(1));
    });

    test('the app does not signal itself', () async {
      final app = await openStore();
      StoreSync.listen(app);
      addTearDown(StoreSync.close);
      var notified = 0;
      app.addListener(() => notified++);

      StoreSync.notifyChanged();
      await _wait(100);
      expect(notified, 0);
    });
  });

  group('Editing an entry that has no measure', () {
    test('keeps its value and unit', () async {
      final s = await openStore();
      final act = await s.addActivity('Adım');
      final e = (await s.addEntry(act.id, qty: 8500, value: 8500, unitId: 'adet')).entry;

      // The edit sheet only sends the measure, the quantity and the note.
      await s.updateEntry(e, activityId: act.id, time: e.time, measureId: e.measureId, qty: e.qty, note: 'akşam yürüyüşü');

      final row = (await _entryRows(s, act.id)).single;
      expect(row['value'], 8500.0);
      expect(row['unit_id'], 'adet');
      expect(row['note'], 'akşam yürüyüşü');
      expect(s.entryDetail(e), '8.500 adet');
    });

    test('scales the value when the quantity changes', () async {
      final s = await openStore();
      final act = await s.addActivity('Plank');
      final e = (await s.addEntry(act.id, qty: 40, value: 40, unitId: 'sn')).entry;

      await s.updateEntry(e, activityId: act.id, time: e.time, measureId: e.measureId, qty: 50);

      final row = (await _entryRows(s, act.id)).single;
      expect(row['value'], 50.0);
      expect(row['unit_id'], 'sn');
    });

    test('still drops the amount when the measure is removed on purpose', () async {
      final s = await openStore();
      final act = await s.addActivity('Su');
      final glass = s.measures.firstWhere((m) => m.name == 'Su bardağı');
      final e = (await s.addEntry(act.id, measureId: glass.id, qty: 2)).entry;

      await s.updateEntry(e, activityId: act.id, time: e.time, measureId: null, qty: 3);

      final row = (await _entryRows(s, act.id)).single;
      expect(row['measure_id'], isNull);
      expect(row['value'], isNull);
      expect(row['unit_id'], isNull);
      expect(row['qty'], 3.0);
    });

    test('is left as it was when a measure chip is picked and released again', () async {
      final s = await openStore();
      final act = await s.addActivity('Adım');
      final e = (await s.addEntry(act.id, qty: 8500, value: 8500, unitId: 'adet')).entry;

      // The picker reports quantity 1 when a chip is released; the edit sheet passes that through
      // entryEditSelection before saving.
      final (measureId, qty) = s.entryEditSelection(e, null, 1);
      await s.updateEntry(e, activityId: act.id, time: e.time, measureId: measureId, qty: qty);

      final row = (await _entryRows(s, act.id)).single;
      expect(row['value'], 8500.0);
      expect(row['qty'], 8500.0);
      expect(row['unit_id'], 'adet');

      // An entry that does have a measure keeps following the picker.
      final glass = s.measures.firstWhere((m) => m.name == 'Su bardağı');
      final water = (await s.addEntry(act.id, measureId: glass.id, qty: 2)).entry;
      expect(s.entryEditSelection(water, null, 1), (null, 1.0));
      expect(s.entryEditSelection(water, glass.id, 3), (glass.id, 3.0));
    });
  });

  group('Step counter', () {
    test('manual steps survive the next sensor reading and a restart', () async {
      final s = await openStore();
      await s.handlePedometerStepEvent(1000);
      await s.handlePedometerStepEvent(1200);
      expect(s.todaySteps, 200);

      await s.addManualSteps(500);
      expect(s.todaySteps, 700);
      await s.handlePedometerStepEvent(1250);
      expect(s.todaySteps, 750, reason: 'a sensor reading must not wipe the manual steps');

      final restarted = AppStore();
      await restarted.load();
      expect(restarted.todaySteps, 750);
      await restarted.handlePedometerStepEvent(1300);
      expect(restarted.todaySteps, 800);
    });

    test('a phone reboot does not reset the steps of the day', () async {
      final s = await openStore();
      await s.handlePedometerStepEvent(5000);
      await s.handlePedometerStepEvent(5600);

      // The sensor counts from zero again after a reboot.
      await s.handlePedometerStepEvent(40);
      expect(s.todaySteps, 640);
      await s.handlePedometerStepEvent(100);
      expect(s.todaySteps, 700);
    });

    test('a new day starts from the last reading while the app stays open', () async {
      final s = await openStore();
      final now = DateTime.now();
      final lateToday = DateTime(now.year, now.month, now.day, 23, 50);
      final earlyTomorrow = DateTime(now.year, now.month, now.day + 1, 0, 10);

      await s.handlePedometerStepEvent(3000, at: lateToday);
      await s.handlePedometerStepEvent(3410, at: lateToday);
      await s.addManualSteps(100, at: lateToday);
      expect(s.todaySteps, 510);

      await s.handlePedometerStepEvent(3450, at: earlyTomorrow);
      expect(s.todaySteps, 40, reason: 'steps taken since the last reading belong to the new day');

      expect(s.stepsOn(lateToday), 510, reason: 'earlier days can still be looked up');
      expect(s.stepsOn(earlyTomorrow), 40);

      // The finished day keeps its final count.
      final rows = await (await s.db).query('settings', where: 'key LIKE ?', whereArgs: ['step_today_%'], orderBy: 'key');
      expect(rows.map((r) => r['value']), ['510', '40']);
    });

    test('sensor readings do not wake the listeners of the whole store', () async {
      final s = await openStore();
      var storeNotifications = 0;
      var stepNotifications = 0;
      s.addListener(() => storeNotifications++);
      s.stepsNotifier.addListener(() => stepNotifications++);

      await s.handlePedometerStepEvent(100);
      for (var total = 101; total <= 110; total++) {
        await s.handlePedometerStepEvent(total);
      }

      expect(s.todaySteps, 10);
      expect(stepNotifications, 10);
      expect(storeNotifications, 0);
    });

    test('asks for the sensor permission and stays off when it is refused', () async {
      final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const channel = MethodChannel('dev.takip.takip/permissions');
      var granted = false;
      final calls = <String>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        return granted;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      final s = await openStore();

      expect(await s.setStepTrackerEnabled(true), isFalse);
      expect(s.stepTrackerEnabled, isFalse);
      expect(calls, ['requestActivityRecognition']);

      granted = true;
      expect(await s.setStepTrackerEnabled(true), isTrue);
      expect(s.stepTrackerEnabled, isTrue);
      await s.setStepTrackerEnabled(false);
      expect(calls, hasLength(2), reason: 'turning the counter off needs no permission');
    });

    group('permission', () {
      const permissions = MethodChannel('dev.takip.takip/permissions');
      const sensor = MethodChannel('step_count');
      var granted = false;

      setUp(() {
        granted = false;
        final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        // Both the silent check and the request answer with the current state of the permission.
        messenger.setMockMethodCallHandler(permissions, (call) async => granted);
        messenger.setMockMethodCallHandler(sensor, (call) async => null);
        addTearDown(() {
          HealthTrackerService.instance.stopStepTracking();
          messenger.setMockMethodCallHandler(permissions, null);
          messenger.setMockMethodCallHandler(sensor, null);
        });
      });

      /// A store whose step counter was switched on by a version that never asked for the permission.
      Future<AppStore> storeWithCounterOn() async {
        final before = await openStore();
        await (await before.db).insert('settings', {'key': 'step_tracker_enabled', 'value': 'true'},
            conflictAlgorithm: ConflictAlgorithm.replace);
        final s = newStore();
        await s.load();
        return s;
      }

      test('a counter without its permission says so instead of silently counting nothing', () async {
        final s = await storeWithCounterOn();
        expect(s.stepTrackerEnabled, isTrue);
        expect(s.stepPermissionMissing, isTrue);

        expect(await s.retryStepTracking(), isFalse, reason: 'refused again');
        expect(s.stepPermissionMissing, isTrue);

        granted = true;
        expect(await s.retryStepTracking(), isTrue);
        expect(s.stepPermissionMissing, isFalse);
        expect(HealthTrackerService.instance.isListening, isTrue);
      });

      test('a permission granted in the system settings is noticed when the app comes back', () async {
        final s = await storeWithCounterOn();
        expect(s.stepPermissionMissing, isTrue);

        granted = true;
        await s.load();
        expect(s.stepPermissionMissing, isFalse);
      });
    });
  });

  group('Sleep and step activities', () {
    final night = DateTime(2026, 3, 1, 23, 30);
    final morning = DateTime(2026, 3, 2, 7, 0);

    test('keep using the same activity after it is renamed, also across restarts', () async {
      final s = await openStore();
      await s.logManualSleep(start: night, end: morning);
      final sleep = s.activities.values.single;
      expect(sleep.name, 'Uyku');

      sleep.rename('Gece uykusu');
      await s.updateActivity(sleep);
      await s.logManualSleep(start: night.add(const Duration(days: 1)), end: morning.add(const Duration(days: 1)));
      expect(s.activities, hasLength(1));

      final restarted = AppStore();
      await restarted.load();
      await restarted.logManualSleep(
        start: night.add(const Duration(days: 2)),
        end: morning.add(const Duration(days: 2)),
      );
      expect(restarted.activities, hasLength(1));
      expect(restarted.entries.where((e) => e.activityId == sleep.id), hasLength(3));
    });

    test('are named in the app language and found again after switching it', () async {
      final s = await openStore();
      addTearDown(() => s.setLanguage(AppLanguage.tr));
      await s.setLanguage(AppLanguage.en);
      await s.syncTodayStepsToEntry(steps: 1200);
      expect(s.activities.values.single.name, 'Steps');

      await s.setLanguage(AppLanguage.tr);
      await s.syncTodayStepsToEntry(steps: 1500);
      expect(s.activities, hasLength(1));
      expect(s.entries.single.value, 1500.0);
    });

    test('adopt the activity an older version created by name', () async {
      final s = await openStore();
      final old = await s.addActivity('Uyku', emoji: '🛌');
      await s.logManualSleep(start: night, end: morning);

      expect(s.activities, hasLength(1));
      expect(s.entries.single.activityId, old.id);
    });
  });

  group('Today page state', () {
    test('timer cards are compact while several timers run and keep the chosen state across reloads', () async {
      final s = await openStore();
      final ders = await s.addActivity('Ders');
      final gitar = await s.addActivity('Gitar');

      final first = await s.startTimer(ders.id);
      expect(s.isTimerCollapsed(first), isFalse, reason: 'a single timer is shown in full');

      final second = await s.startTimer(gitar.id);
      expect(s.isTimerCollapsed(s.getTimer(first.id)!), isTrue);
      expect(s.isTimerCollapsed(second), isTrue);

      s.toggleTimerCollapse(first.id);
      expect(s.isTimerCollapsed(s.getTimer(first.id)!), isFalse);

      // Coming back to the app reloads the timers from the database.
      await s.load();
      expect(s.isTimerCollapsed(s.getTimer(first.id)!), isFalse, reason: 'a reload must not undo the choice');
      expect(s.isTimerCollapsed(s.getTimer(second.id)!), isTrue);
    });

    test('folded sections stay folded after a restart', () async {
      final s = await openStore();
      await s.toggleSection('health');
      expect(s.isSectionCollapsed('health'), isTrue);

      final restarted = AppStore();
      await restarted.load();
      expect(restarted.isSectionCollapsed('health'), isTrue);
      expect(restarted.isSectionCollapsed('roadmap'), isFalse);

      await restarted.toggleSection('health');
      expect(restarted.isSectionCollapsed('health'), isFalse);
    });
  });

  group('English interface', () {
    test('writes numbers, percentages, units and periods the English way', () async {
      final s = await openStore();
      addTearDown(() => s.setLanguage(AppLanguage.tr));
      final countGoal = Goal(id: 0, name: 'G', mode: 'count', target: 3, period: GoalPeriod.day, startDate: 0, createdAt: 0);

      expect(fmtPercent(62), '%62');
      expect(fmtNum(1234.5), '1.234,5');
      expect(fmtAmount(90, 'time'), '1 sa 30 dk');
      expect(s.unit('sa').symbol, 'sa');
      expect(s.goalUnitSymbol(countGoal), 'kez');

      await s.setLanguage(AppLanguage.en);
      expect(fmtPercent(62), '62%');
      expect(fmtNum(1234.5), '1,234.5');
      expect(fmtAmount(90, 'time'), '1 h 30 min');
      expect(fmtAmount(3, 'count'), '3 pcs');
      expect(s.unit('sa').symbol, 'h');
      expect(s.unit('dk').name, 'Minute');
      expect(s.dimName('mass'), 'Weight');
      expect(s.goalUnitSymbol(countGoal), 'times');
      expect(periodName(GoalPeriod.week, isTr: false), 'Weekly');
      expect(s.activity(999).name, '(deleted)');
    });
  });

  group('Goal heatmap', () {
    test('a weekly goal is judged week by week, not by holding one day against the weekly target', () async {
      final s = await openStore();
      final run = await s.addActivity('Koşu');
      final km = s.measures.firstWhere((m) => m.unitId == 'km');
      final monday = weekStart(DateTime.now());
      DateTime day(int weeksAgo, int weekday) =>
          DateTime(monday.year, monday.month, monday.day - 7 * weeksAgo + weekday, 9);

      // Two weeks with three 5 km runs each, then a week with a single run.
      for (final weeksAgo in [3, 2]) {
        for (final weekday in [0, 2, 5]) {
          await s.addEntry(run.id, measureId: km.id, qty: 5, at: day(weeksAgo, weekday));
        }
      }
      await s.addEntry(run.id, measureId: km.id, qty: 5, at: day(1, 1));
      await s.saveGoal(Goal(
        id: 0,
        name: 'Haftada 15 km',
        mode: 'amount',
        unitId: 'km',
        target: 15,
        period: GoalPeriod.week,
        startDate: day(3, 0).millisecondsSinceEpoch,
        createdAt: 0,
        links: [GoalLink(activityId: run.id, pct: 100)],
      ));

      final info = s.goalStreakInfo(s.goals.single);

      // A 5 km day counts as done when its week reached 15 km.
      expect(info.dailyLevels[dayStart(day(3, 0))], 4);
      expect(info.dailyLevels[dayStart(day(2, 5))], 4);
      expect(info.dailyTooltips[dayStart(day(3, 0))], contains('15'));
      // The single run of last week is a third of the weekly target; days without a run stay empty.
      expect(info.dailyLevels[dayStart(day(1, 1))], 2);
      expect(info.dailyLevels.containsKey(dayStart(day(1, 3))), isFalse);

      // Streaks count weeks.
      expect(info.streakPeriod, GoalPeriod.week);
      expect(info.longestStreak, 2);
      expect(info.currentStreak, 0);
      expect(info.consistencyLast30, closeTo(66.7, 0.1), reason: 'two of the three finished weeks');
    });

    test('a daily goal keeps comparing each day with its own target', () async {
      final s = await openStore();
      final water = await s.addActivity('Su');
      final litre = s.measures.firstWhere((m) => m.name == 'Litre');
      final now = DateTime.now();
      DateTime daysAgo(int n) => DateTime(now.year, now.month, now.day - n, 0, 1);
      await s.addEntry(water.id, measureId: litre.id, qty: 2, at: daysAgo(2));
      await s.addEntry(water.id, measureId: litre.id, qty: 2.5, at: daysAgo(1));
      await s.addEntry(water.id, measureId: litre.id, qty: 1, at: daysAgo(0));
      await s.saveGoal(Goal(
        id: 0,
        name: 'Günde 2 litre',
        mode: 'amount',
        unitId: 'l',
        target: 2,
        period: GoalPeriod.day,
        startDate: daysAgo(5).millisecondsSinceEpoch,
        createdAt: 0,
        links: [GoalLink(activityId: water.id, pct: 100)],
      ));

      final info = s.goalStreakInfo(s.goals.single);
      expect(info.streakPeriod, GoalPeriod.day);
      expect(info.dailyLevels[dayStart(daysAgo(1))], 4);
      expect(info.dailyLevels[dayStart(daysAgo(0))], 2);
      expect(info.currentStreak, 2, reason: 'today is not finished yet, so the streak ends yesterday');
      expect(info.longestStreak, 2);
    });
  });

  group('Roadmap import', () {
    test('accepts numbers written as text instead of rejecting the whole roadmap', () {
      final roadmap = RoadmapParser.parse('''{"title": "Plan", "steps": [
        {"order": "2", "title": "Yürüyüş", "type": "goal", "target": "30", "unit": "dk"},
        {"order": 1, "title": 42, "description": null, "target": "2,5", "type": "GOAL"},
        {"title": "", "type": "task"}]}''');

      expect(roadmap, isNotNull);
      final steps = roadmap!.steps;
      expect(steps.map((s) => s.title), ['42', 'Yürüyüş', 'Adım 3']);
      expect(steps[0].target, 2.5);
      expect(steps[0].isGoal, isTrue);
      expect(steps[1].target, 30.0);
      expect(steps[1].unit, 'dk');
    });

    test('names missing titles in the language of the app', () {
      expect(RoadmapParser.parse('{"steps": [{"type": "task"}]}', isTr: false)!.title, 'New Roadmap');
      expect(RoadmapParser.parse('{"steps": [{"type": "task"}]}', isTr: false)!.steps.single.title, 'Step 1');
      expect(RoadmapParser.promptFor(isTr: false), contains('"type": "goal"'));
    });
  });

  group('Roadmap steps', () {
    test('keep their linked activity across restarts, follow a merge and lose it with the activity', () async {
      final s = await openStore();
      final act = await s.addActivity('Kitap okuma');
      final other = await s.addActivity('Okuma');
      await s.createRoadmap(RoadmapParser.parse('{"title": "Plan", "steps": [{"title": "Oku"}, {"title": "Yaz"}]}')!);
      final stepId = s.roadmaps.single.steps.first.id;

      await s.setRoadmapStepActivity(stepId, act.id);
      var restarted = AppStore();
      await restarted.load();
      expect(restarted.roadmaps.single.steps.first.linkedActivityId, act.id);
      expect(restarted.roadmaps.single.steps.last.linkedActivityId, isNull);

      await s.mergeActivity(act.id, other.id);
      expect(s.roadmaps.single.steps.first.linkedActivityId, other.id);

      await s.deleteActivity(other.id);
      expect(s.roadmaps.single.steps.first.linkedActivityId, isNull);
      restarted = AppStore();
      await restarted.load();
      expect(restarted.roadmaps.single.steps.first.linkedActivityId, isNull);
    });
  });

  group('Roadmap steps fed by activities', () {
    /// A journey with the given steps ("title|target|unit"; no target = a plain task), already started.
    Future<Roadmap> journey(AppStore s, List<String> steps) async {
      final r = await s.createRoadmap(Roadmap(title: 'Plan', steps: [
        for (final spec in steps)
          if (spec.split('|') case [final title, final target, final unit])
            RoadmapStep(title: title, type: 'goal', target: double.parse(target), unit: unit)
          else
            RoadmapStep(title: spec),
      ]));
      await s.setRoadmapStatus(r.id, 'active');
      return r;
    }

    Future<void> log(AppStore s, Activity a, double qty, String measure) =>
        s.addEntry(a.id, measureId: s.measures.firstWhere((m) => m.name == measure).id, qty: qty);

    test('entries of the linked activity add up and tick the step when the target is reached', () async {
      final s = await openStore();
      final kelime = await s.addActivity('Kelime');
      final r = await journey(s, ['Kelime çalış|100|dk']);
      final step = r.steps.single;
      await s.setRoadmapStepActivity(step.id, kelime.id);

      for (final minutes in [10.0, 23.0, 12.0]) {
        await log(s, kelime, minutes, 'Dakika');
      }
      expect(s.stepProgress(r, step)!.done, 45);
      expect(s.stepProgress(r, step)!.target, 100);
      expect(step.isCompleted, isFalse);

      // One more hour: recorded in hours, counted in the minutes of the target.
      await log(s, kelime, 1, 'Saat');
      expect(s.stepProgress(r, step)!.done, 105);
      expect(step.isCompleted, isTrue);
      expect(step.autoCompleted, isTrue);
      expect(r.isCompleted, isTrue, reason: 'it was the only step of the journey');

      final restarted = newStore();
      await restarted.load();
      expect(restarted.roadmaps.single.steps.single.isCompleted, isTrue, reason: 'the tick is stored');
      expect(restarted.roadmaps.single.status, 'completed');
    });

    test('every linked step counts at once, not only the next one', () async {
      final s = await openStore();
      final kelime = await s.addActivity('Kelime');
      final kosu = await s.addActivity('Koşu');
      final sinav = await s.addActivity('Seviye sınavı');
      final r = await journey(s, ['Kaynak seç', 'Kelime çalış|30|dk', 'Koş|5|km', 'Sınava gir']);
      await s.setRoadmapStepActivity(r.steps[1].id, kelime.id);
      await s.setRoadmapStepActivity(r.steps[2].id, kosu.id);
      await s.setRoadmapStepActivity(r.steps[3].id, sinav.id);

      await log(s, kosu, 5, 'Kilometre');
      await log(s, kelime, 30, 'Dakika');
      // A step without a target is a task: doing the activity once completes it.
      await s.addEntry(sinav.id);

      expect([for (final step in r.steps) step.isCompleted], [false, true, true, true]);
      expect(r.currentPendingStep, r.steps.first, reason: 'the first step is still the next one on the Today page');
      expect(r.isCompleted, isFalse);
    });

    test('only entries made after the journey began count', () async {
      final s = await openStore();
      final kelime = await s.addActivity('Kelime');
      final minute = s.measures.firstWhere((m) => m.name == 'Dakika');
      await s.addEntry(kelime.id, measureId: minute.id, qty: 500, at: DateTime.now().subtract(const Duration(hours: 2)));

      final r = await journey(s, ['Kelime çalış|100|dk']);
      await s.setRoadmapStepActivity(r.steps.single.id, kelime.id);
      expect(s.stepProgress(r, r.steps.single)!.done, 0);
      expect(r.steps.single.isCompleted, isFalse);

      // A journey that has not started shows no progress at all.
      final waiting = await s.createRoadmap(Roadmap(title: 'Sonra', steps: [RoadmapStep(title: 'Bekle')]));
      await s.setRoadmapStepActivity(waiting.steps.single.id, kelime.id);
      await log(s, kelime, 10, 'Dakika');
      expect(s.stepProgress(waiting, waiting.steps.single), isNull);
      expect(waiting.steps.single.isCompleted, isFalse);
    });

    test('taking an entry back reopens the step it completed, but not a step ticked by hand', () async {
      final s = await openStore();
      final kelime = await s.addActivity('Kelime');
      final r = await journey(s, ['Kelime çalış|20|dk', 'Tekrar et|20|dk', 'Bitir']);
      final [auto, manual, _] = r.steps;
      await s.setRoadmapStepActivity(auto.id, kelime.id);
      await s.setRoadmapStepActivity(manual.id, kelime.id);
      await s.toggleRoadmapStep(manual.id, completed: true);

      final added = await s.addEntry(kelime.id,
          measureId: s.measures.firstWhere((m) => m.name == 'Dakika').id, qty: 25);
      expect(auto.isCompleted, isTrue);

      // "Undo" on the confirmation of the entry.
      await s.deleteEntry(added.entry);
      expect(auto.isCompleted, isFalse, reason: 'an entry logged by mistake must not leave the step done');
      expect(manual.isCompleted, isTrue, reason: 'the user ticked this one');

      await s.restoreEntry(added.entry);
      expect(auto.isCompleted, isTrue);
    });

    test('a step the user reopens stays open, whatever is logged, until they tick it', () async {
      final s = await openStore();
      final kelime = await s.addActivity('Kelime');
      final r = await journey(s, ['Kelime çalış|20|dk', 'Tekrar et|50|dk', 'Bitir']);
      final [step, later, _] = r.steps;
      await s.setRoadmapStepActivity(step.id, kelime.id);
      await s.setRoadmapStepActivity(later.id, kelime.id);
      await log(s, kelime, 25, 'Dakika');
      expect(step.isCompleted, isTrue);

      await s.toggleRoadmapStep(step.id, completed: false);
      await log(s, kelime, 10, 'Dakika');
      expect(step.isCompleted, isFalse, reason: 'the tick the user removed must not come back with the next entry');

      final restarted = newStore();
      await restarted.load();
      expect(restarted.roadmaps.single.steps.first.isCompleted, isFalse, reason: 'nor when the data is read again');

      await s.toggleRoadmapStep(step.id, completed: true);
      await log(s, kelime, 1, 'Dakika');
      expect(step.isCompleted, isTrue);
      expect(step.keptOpen, isFalse);

      // Below its target there is nothing to hold back: a step ticked and unticked by mistake still
      // completes when the target is reached.
      expect(s.stepProgress(r, later)!.done, 36);
      await s.toggleRoadmapStep(later.id, completed: true);
      await s.toggleRoadmapStep(later.id, completed: false);
      expect(later.keptOpen, isFalse);
      await log(s, kelime, 14, 'Dakika');
      expect(later.isCompleted, isTrue);
    });

    test('linking another activity or resetting the journey forgets that a step was held open', () async {
      final s = await openStore();
      final kelime = await s.addActivity('Kelime');
      final okuma = await s.addActivity('Okuma');
      final r = await journey(s, ['Çalış|20|dk', 'Bitir']);
      final step = r.steps.first;
      await s.setRoadmapStepActivity(step.id, kelime.id);
      await log(s, kelime, 20, 'Dakika');
      await s.toggleRoadmapStep(step.id, completed: false);
      expect(step.keptOpen, isTrue);

      await s.setRoadmapStepActivity(step.id, okuma.id);
      await log(s, okuma, 20, 'Dakika');
      expect(step.isCompleted, isTrue, reason: 'the new activity starts with a clean slate');

      await s.toggleRoadmapStep(step.id, completed: false);
      expect(step.keptOpen, isTrue);
      await s.resetRoadmapProgress(r.id);
      await _wait(5);
      await s.setRoadmapStatus(r.id, 'active');
      await log(s, okuma, 20, 'Dakika');
      expect(step.isCompleted, isTrue);
    });

    test('a paused journey keeps counting', () async {
      final s = await openStore();
      final kelime = await s.addActivity('Kelime');
      final r = await journey(s, ['Kelime çalış|20|dk', 'Sonraki']);
      await s.setRoadmapStepActivity(r.steps.first.id, kelime.id);
      await s.setRoadmapStatus(r.id, 'paused');

      await log(s, kelime, 20, 'Dakika');
      expect(s.stepProgress(r, r.steps.first)!.done, 20);
      expect(r.steps.first.isCompleted, isTrue, reason: 'the bar and the tick must agree');
      expect(r.status, 'paused');
    });

    test('a journey without a recorded start counts from the day it was made', () async {
      final s = await openStore();
      final kelime = await s.addActivity('Kelime');
      final minute = s.measures.firstWhere((m) => m.name == 'Dakika');
      await s.addEntry(kelime.id, measureId: minute.id, qty: 500, at: DateTime.now().subtract(const Duration(hours: 2)));

      // An older build could leave a running journey without its start.
      final r = await journey(s, ['Kelime çalış|20|dk', 'Sonraki']);
      await s.setRoadmapStepActivity(r.steps.first.id, kelime.id);
      await (await s.db).update('roadmaps', {'started_at': null}, where: 'id = ?', whereArgs: [r.id]);
      await s.refresh();
      final reread = s.roadmaps.single;
      expect(reread.startedAt, isNull);
      expect(s.stepProgress(reread, reread.steps.first)!.done, 0, reason: 'what was logged before it existed is history');

      await log(s, kelime, 20, 'Dakika');
      expect(reread.steps.first.isCompleted, isTrue);
    });

    test('a journey finished by hand without ever starting runs again when a step is reopened', () async {
      final s = await openStore();
      final kelime = await s.addActivity('Kelime');
      final r = await s.createRoadmap(Roadmap(title: 'Yeni', steps: [
        RoadmapStep(title: 'Kelime çalış', type: 'goal', target: 20, unit: 'dk'),
      ]));
      final step = r.steps.single;
      await s.setRoadmapStepActivity(step.id, kelime.id);
      await log(s, kelime, 5, 'Dakika');
      expect(s.stepProgress(r, step), isNull, reason: 'nothing counts before the journey runs');

      await s.toggleRoadmapStep(step.id, completed: true);
      expect(r.status, 'completed');
      await s.toggleRoadmapStep(step.id, completed: false);
      expect(r.status, 'active');
      expect(s.stepProgress(r, step)!.done, 5);

      await log(s, kelime, 15, 'Dakika');
      expect(step.isCompleted, isTrue);
      expect(step.autoCompleted, isTrue);
      expect(r.status, 'completed');
    });

    test('the last step closes the journey and taking the entry back reopens it', () async {
      final s = await openStore();
      final kosu = await s.addActivity('Koşu');
      final r = await journey(s, ['Hazırlan', 'Koş|5|km']);
      await s.setRoadmapStepActivity(r.steps.last.id, kosu.id);
      await s.toggleRoadmapStep(r.steps.first.id, completed: true);

      final run = await s.addEntry(kosu.id, measureId: s.measures.firstWhere((m) => m.name == 'Kilometre').id, qty: 5);
      expect(r.status, 'completed');

      await s.deleteEntry(run.entry);
      expect(r.status, 'active');
      expect(r.completedAt, isNull);
    });

    test('targets are read in their unit; things without a measure are counted', () async {
      final s = await openStore();
      final a = await s.addActivity('Çalışma');
      final r = await journey(s, [
        'Saat|2|saat',
        'Kilometre|5|km',
        'Bölüm|4|bölüm',
        'Adet|20|adet',
        'Litre|1|L',
      ]);
      for (final step in r.steps) {
        await s.setRoadmapStepActivity(step.id, a.id);
      }
      double done(int i) => s.stepProgress(r, r.steps[i])!.done;

      await log(s, a, 90, 'Dakika');
      expect(done(0), 1.5, reason: '90 minutes are an hour and a half');
      expect(done(1), 0, reason: 'minutes are not kilometres');
      expect(done(2), 1, reason: 'a timed session is one episode');

      await s.addEntry(a.id, value: 3000, unitId: 'm');
      await s.addEntry(a.id, value: 2, unitId: 'km');
      expect(done(1), 5);
      expect(r.steps[1].isCompleted, isTrue);

      await s.addEntry(a.id, qty: 3);
      expect(done(2), 6, reason: 'three plain entries and the three measured ones before');
      await s.addEntry(a.id, value: 12, unitId: 'adet');
      expect(done(3), 1 + 1 + 1 + 3 + 12, reason: 'pieces count as pieces, anything else once');
      expect(done(4), 0);
    });

    test('a finished timer and an entry written by another isolate count too', () async {
      final s = await openStore();
      final gitar = await s.addActivity('Gitar');
      final r = await journey(s, ['Gitar çal', 'Bir kez daha']);
      await s.setRoadmapStepActivity(r.steps.first.id, gitar.id);

      final timer = await s.startTimer(gitar.id);
      await _wait(30);
      await s.finishTimer(timer.id);
      expect(r.steps.first.isCompleted, isTrue, reason: 'the timer wrote an entry for the linked activity');

      // The notification isolate has its own store; this one learns of the entry when it reads again.
      final other = newStore();
      await other.load();
      final kelime = await other.addActivity('Kelime');
      await s.refresh();
      await s.setRoadmapStepActivity(r.steps.last.id, kelime.id);
      await other.refresh();
      await other.addEntry(kelime.id);
      expect(s.roadmaps.single.steps.last.isCompleted, isFalse, reason: 'this copy has not read the change yet');
      await s.refresh();
      expect(s.roadmaps.single.steps.last.isCompleted, isTrue);
      expect(s.roadmaps.single.status, 'completed');
    });

    test('resetting the progress makes the journey count from its next start', () async {
      final s = await openStore();
      final kelime = await s.addActivity('Kelime');
      final r = await journey(s, ['Kelime çalış|20|dk', 'Sonraki']);
      final step = r.steps.first;
      await s.setRoadmapStepActivity(step.id, kelime.id);
      await log(s, kelime, 30, 'Dakika');
      expect(step.isCompleted, isTrue);

      await s.resetRoadmapProgress(r.id);
      expect(step.isCompleted, isFalse);
      expect(r.status, 'not_started');
      expect(r.startedAt, isNull);

      await _wait(5);
      await s.setRoadmapStatus(r.id, 'active');
      expect(s.stepProgress(r, step)!.done, 0, reason: 'what was logged before the restart is history');
      expect(step.isCompleted, isFalse);
    });

    test('a database made before the flags existed gets the columns when it is opened', () async {
      final path = '${await databaseFactory.getDatabasesPath()}/takip.db';
      final old = await databaseFactory.openDatabase(path);
      await AppDb.createSchema(old);
      await AppDb.seed(old);
      await old.execute('ALTER TABLE roadmap_steps DROP COLUMN auto_completed');
      await old.execute('ALTER TABLE roadmap_steps DROP COLUMN kept_open');
      await old.execute('PRAGMA user_version = ${AppDb.currentVersion}');
      await old.insert('roadmaps', {'title': 'Eski', 'created_at': 1, 'status': 'active', 'started_at': 1});
      await old.insert('roadmap_steps', {'roadmap_id': 1, 'step_order': 1, 'title': 'Eski adım', 'is_completed': 1});
      expect(await AppDb.hasColumn(old, 'roadmap_steps', 'auto_completed'), isFalse);
      expect(await AppDb.hasColumn(old, 'roadmap_steps', 'kept_open'), isFalse);
      await old.close();

      final s = await openStore();
      expect(await AppDb.hasColumn(await s.db, 'roadmap_steps', 'auto_completed'), isTrue);
      expect(await AppDb.hasColumn(await s.db, 'roadmap_steps', 'kept_open'), isTrue);
      final step = s.roadmaps.single.steps.single;
      expect(step.isCompleted, isTrue);
      expect(step.autoCompleted, isFalse, reason: 'whatever was ticked before was ticked by hand');
      await s.toggleRoadmapStep(step.id, completed: false);
      expect(s.roadmaps.single.steps.single.isCompleted, isFalse);
    });
  });

  group('Sleep tracker', () {
    test('a night counts for the day you wake up', () async {
      final s = await openStore();
      await s.logManualSleep(start: DateTime(2026, 3, 1, 23, 30), end: DateTime(2026, 3, 2, 7, 0));
      await s.logManualSleep(start: DateTime(2026, 3, 2, 14, 0), end: DateTime(2026, 3, 2, 14, 30));

      expect(s.getTodaySleepHours(DateTime(2026, 3, 1)), 0.0);
      expect(s.getTodaySleepHours(DateTime(2026, 3, 2)), closeTo(8.0, 0.01), reason: 'the night and the nap');
      expect(s.getTodaySleepHours(DateTime(2026, 3, 3)), 0.0);
    });

    test('sleep that starts exactly at midnight is not lost', () async {
      final s = await openStore();
      await s.logManualSleep(start: DateTime(2026, 3, 3), end: DateTime(2026, 3, 3, 6, 0));
      expect(s.getTodaySleepHours(DateTime(2026, 3, 3)), closeTo(6.0, 0.01));
    });
  });

  group('Timer notes', () {
    test('can be changed and cleared again', () async {
      final s = await openStore();
      final act = await s.addActivity('Ders');
      final t = await s.startTimer(act.id, note: 'Türev');

      await s.updateTimerNote(t.id, 'İntegral');
      expect((await _timerRow(s, t.id))?['note'], 'İntegral');

      await s.updateTimerNote(t.id, '   ');
      expect((await _timerRow(s, t.id))?['note'], isNull);
      expect(s.getTimer(t.id)?.note, isNull);
    });

    test('are written without undoing a pause made by another isolate', () async {
      final app = await openStore();
      final act = await app.addActivity('Ders');
      final t = await app.startTimer(act.id);

      final background = await openStore();
      await background.pauseTimer(t.id);
      final paused = (await _timerRow(app, t.id))!;

      await app.updateTimerNote(t.id, 'not');

      final row = (await _timerRow(app, t.id))!;
      expect(row['note'], 'not');
      expect(row['is_running'], 0, reason: 'the pause must survive the note edit');
      expect(row['accumulated_ms'], paused['accumulated_ms']);
      expect(app.getTimer(t.id)?.isRunning, isFalse, reason: 'the app copy adopts the stored state');
    });
  });

  group('Merging activities', () {
    test('moves a running timer without undoing a pause made by another isolate', () async {
      final app = await openStore();
      final from = await app.addActivity('Kitap');
      final into = await app.addActivity('Kitap okuma');
      final t = await app.startTimer(from.id);

      final background = await openStore();
      await background.pauseTimer(t.id);

      await app.mergeActivity(from.id, into.id);

      final row = (await _timerRow(app, t.id))!;
      expect(row['activity_id'], into.id);
      expect(row['is_running'], 0, reason: 'the pause must survive the merge');
      expect(app.getTimer(t.id)?.activityId, into.id);
    });

    test('keeps the sleep tracker pointed at the merged activity', () async {
      final s = await openStore();
      await s.logManualSleep(start: DateTime(2026, 3, 1, 23), end: DateTime(2026, 3, 2, 7));
      final sleep = s.activities.values.single;
      final rest = await s.addActivity('Dinlenme');

      await s.mergeActivity(sleep.id, rest.id);
      await s.logManualSleep(start: DateTime(2026, 3, 2, 23), end: DateTime(2026, 3, 3, 7));

      expect(s.activities.keys, [rest.id]);
      expect(s.entries, hasLength(2));
    });
  });

  group('Natural language parser', () {
    NlParseResult parse(String input, {List<Activity> activities = const []}) =>
        NaturalLanguageParser.parse(input, activities: activities, measures: const []);

    test('keeps Turkish characters in the name of a new activity', () {
      expect(parse('Yürüyüş').activityName, 'Yürüyüş');
      expect(parse('Çay').activityName, 'Çay');
      expect(parse('öğle yemeği').activityName, 'Öğle yemeği');
      expect(parse('Iğdır gezisi').activityName, 'Iğdır gezisi');
      expect(parse('Çay!').activityName, 'Çay');

      final withQuantity = parse('3 şınav');
      expect(withQuantity.activityName, 'Şınav');
      expect(withQuantity.quantity, 3.0);
    });

    test('still matches existing activities regardless of spelling', () {
      final activities = [Activity(id: 1, name: 'Çay', createdAt: 0)];
      expect(parse('cay', activities: activities).matchedActivity?.id, 1);
      expect(parse('ÇAY', activities: activities).activityName, 'Çay');
    });

    test('does not read a command into words that merely contain a keyword', () {
      for (final input in [
        'ilaç',
        'İlaç içtim',
        'maç',
        'tütün',
        'bacak antrenmanı',
        'araç yıkama',
        'acı biber',
        'açık hava yürüyüşü',
        'tutku',
        'tutanak yazma',
        'black coffee',
        'snack',
      ]) {
        expect(parse(input).actionType, NlActionType.addEntry, reason: input);
      }
    });

    test('still recognises timer commands, including inflected forms', () {
      expect(parse('kronometreyi aç matematik').actionType, NlActionType.startStopwatch);
      expect(parse('kronometreyi aç matematik').activityName, 'Matematik');
      expect(parse('sayacı başlat').actionType, NlActionType.startStopwatch);
      expect(parse('koşu için süre tut').actionType, NlActionType.startCountdown);
      expect(parse('geri sayım 10 dakika çay demleme').actionType, NlActionType.startCountdown);
      expect(parse('geri sayım 10 dakika çay demleme').targetMinutes, 10);
      expect(parse('odaklanma kitap').actionType, NlActionType.startPomodoro);
      expect(parse('odaklan matematik').actionType, NlActionType.startPomodoro);
      expect(parse('45 dakika odaklan ders').targetMinutes, 45);
      expect(parse('koşu için süre tutar mısın').actionType, NlActionType.startCountdown);
    });

    test('does not take a word starting with "sa" for the hour unit', () {
      final res = parse('pomodoro sabah sporu');
      expect(res.actionType, NlActionType.startPomodoro);
      expect(res.targetMinutes, 25);
    });

    test('matches an existing activity by whole words, not by substring', () {
      final activities = [
        Activity(id: 1, name: 'Su', createdAt: 0),
        Activity(id: 2, name: 'Kitap okuma', createdAt: 0),
        Activity(id: 3, name: 'Kahve', createdAt: 0),
        Activity(id: 4, name: 'Ders çalışma', createdAt: 0),
      ];
      int? match(String input) => parse(input, activities: activities).matchedActivity?.id;

      // "su" inside another word is not the activity "Su": the entry would silently land in the wrong one.
      expect(match('sucuk'), isNull);
      expect(parse('sucuk', activities: activities).activityName, 'Sucuk');
      expect(match('Sudoku'), isNull);
      expect(match('kahvaltı'), isNull);

      // The name itself, also with a short case suffix, still matches.
      expect(match('2 bardak su'), 1);
      expect(match('suyu bitirdim'), 1);
      expect(match('kahvemi içtim'), 3);
      expect(match('kitap okuma yaptım'), 2);

      // The first words of a longer name are enough, and so is one of its words on its own.
      expect(match('kitap'), 2);
      expect(match('ders'), 4);
      expect(match('çalışma'), 4);

      // Extra words mean a different activity.
      expect(match('matematik çalışma'), isNull);
      expect(match('gazete okuma'), isNull);
    });

    test('finds the measure by unit words and whole measure names, not inside other words', () {
      final measures = [
        Measure(id: 1, name: 'Dakika', unitId: 'dk', amount: 1),
        Measure(id: 2, name: 'Saat', unitId: 'sa', amount: 1),
        Measure(id: 3, name: 'Gram', unitId: 'g', amount: 1),
        Measure(id: 4, name: 'Kase', unitId: 'l', amount: 0.25),
        Measure(id: 5, name: 'Kilometre', unitId: 'km', amount: 1),
        Measure(id: 6, name: 'Su bardağı', unitId: 'l', amount: 0.2),
        Measure(id: 7, name: 'Ders saati', unitId: 'dk', amount: 40),
      ];
      NlParseResult p(String input) => NaturalLanguageParser.parse(input, activities: const [], measures: measures);

      // Unit abbreviations, also glued to the number and in English.
      expect(p('45 dk koşu').matchedMeasure?.id, 1);
      expect(p('45 dk koşu').activityName, 'Koşu');
      expect(p('45dk koşu').matchedMeasure?.id, 1);
      expect(p('45dk koşu').activityName, 'Koşu');
      expect(p('2 sa ders').matchedMeasure?.id, 2);
      expect(p('5 km koşu').matchedMeasure?.id, 5);
      expect(p('30 min run').matchedMeasure?.id, 1);
      expect(p('30 min run').activityName, 'Run');

      // The name of a measure; only the words that named it are left out of the activity name.
      expect(p('3 kase çorba').matchedMeasure?.id, 4);
      expect(p('2 su bardağı su').matchedMeasure?.id, 6);
      expect(p('2 su bardağı su').activityName, 'Su');

      // A measure name inside another word is not that measure.
      expect(p('program yazma').matchedMeasure, isNull);
      expect(p('program yazma').activityName, 'Program yazma');
      expect(p('kaset dinleme').matchedMeasure, isNull);
    });

    test('understands English timer commands and units', () {
      expect(parse('stopwatch reading').actionType, NlActionType.startStopwatch);
      expect(parse('stopwatch reading').activityName, 'Reading');
      expect(parse('pomodoro 30 min study').timerCommand, (mode: 'pomodoro', targetMs: 30 * 60000));
      expect(parse('countdown 10 minutes tea').timerCommand, (mode: 'countdown', targetMs: 10 * 60000));
      expect(parse('countdown 10 minutes tea').activityName, 'Tea');
      expect(parse('focus 2 hours thesis').timerCommand, (mode: 'pomodoro', targetMs: 120 * 60000));
      expect(parse('pomodoro study').summaryIn(isTr: false), 'Start a 25 min pomodoro for Study');
    });

    test('turns timer commands into a timer configuration', () {
      expect(parse('2 bardak su').timerCommand, isNull);
      expect(parse('kronometre matematik').timerCommand, (mode: 'stopwatch', targetMs: 0));
      expect(parse('pomodoro matematik').timerCommand, (mode: 'pomodoro', targetMs: 25 * 60000));
      expect(parse('pomodoro 45 dakika matematik').timerCommand, (mode: 'pomodoro', targetMs: 45 * 60000));
      expect(parse('geri sayım 10 dakika çay demleme').timerCommand, (mode: 'countdown', targetMs: 10 * 60000));
      expect(parse('geri sayım çay').timerCommand?.targetMs, 60000);
    });

    test('suggestions tolerate typos without offering unrelated names', () {
      expect(matchScore('kitap', 'gitar'), 0);
      expect(matchScore('kit', 'gitar'), 0);
      expect(matchScore('cya', 'cay'), greaterThan(0));
      expect(matchScore('kahv', 'kahve'), greaterThan(0));
      expect(matchScore('gitra', 'gitar'), greaterThan(0));
      expect(matchScore('kahev', 'kahve'), greaterThan(0));
    });

    test('reads the duration when the unit is glued to the number or carries a suffix', () {
      expect(parse("pomodoro 45 dk'lık ders").targetMinutes, 45);
      expect(parse('pomodoro 45dakika ders').targetMinutes, 45);
      expect(parse('pomodoro 45 dakikalık ders').targetMinutes, 45);
      expect(parse('pomodoro 1saat ders').targetMinutes, 60);
      expect(parse('pomodoro 2 sa ders').targetMinutes, 120);
    });

    test('understands polite and inflected ways of asking for a timer', () {
      for (final text in [
        'gitar zamanlayıcı',
        'gitar açar mısın',
        'gitar sayacı açın',
        'gitar açsana',
        'gitar tutar mısın',
        'gitar için kronometre başlatır mısın lütfen',
      ]) {
        final r = parse(text);
        expect(r.actionType, NlActionType.startStopwatch, reason: text);
        expect(r.activityName, 'Gitar', reason: text);
      }

      // The same words in other roles are not commands, and nothing is dropped from the name.
      expect(parse('fatura tutar 500').timerCommand, isNull, reason: '"tutar" is also an amount');
      expect(parse('fatura tutar 500').quantity, 500);
      expect(parse('açınca yürüyüş').timerCommand, isNull);
      expect(parse('sınav için çalışma').activityName, 'Sınav için çalışma');
    });

    test('words inside the name of an existing activity are not commands', () {
      final activities = [
        Activity(id: 1, name: 'Sayaç okuma', createdAt: 0),
        Activity(id: 2, name: 'Not tut', createdAt: 0),
        Activity(id: 3, name: 'Pomodoro', createdAt: 0),
        Activity(id: 4, name: 'Oruç', createdAt: 0),
      ];
      NlParseResult read(String text) => parse(text, activities: activities);

      expect(read('sayaç okuma').timerCommand, isNull);
      expect(read('sayaç okuma').matchedActivity?.id, 1);
      expect(read('2 sayaç okuma').quantity, 2);
      expect(read('not tut').matchedActivity?.id, 2);

      // A real command next to the name still counts.
      final timed = read('sayaç okuma kronometre');
      expect(timed.actionType, NlActionType.startStopwatch);
      expect(timed.matchedActivity?.id, 1);

      // A name that is nothing but the command word keeps starting the timer.
      expect(read('pomodoro').actionType, NlActionType.startPomodoro);
      // "tut" is not part of the name "Oruç": this reads as a command, and the composer offers the other reading.
      expect(read('oruç tut').actionType, NlActionType.startStopwatch);
    });

    test('can read a text as an entry only', () {
      final activities = [Activity(id: 4, name: 'Oruç', createdAt: 0)];
      NlParseResult entry(String text) =>
          NaturalLanguageParser.parse(text, activities: activities, measures: const [], allowCommands: false);

      expect(entry('oruç tut').timerCommand, isNull);
      expect(entry('oruç tut').matchedActivity?.id, 4);
      expect(entry('not tut').activityName, 'Not tut', reason: 'the command word stays in the name');
      expect(entry('pomodoro 3').quantity, 3);
      expect(entry('pomodoro 3').activityName, 'Pomodoro');
    });

    test('a plain "bardak" finds the glass measures the app ships with', () {
      final measures = [
        Measure(id: 1, name: 'Çay bardağı', unitId: 'l', amount: 0.1),
        Measure(id: 2, name: 'Su bardağı', unitId: 'l', amount: 0.2),
        Measure(id: 3, name: 'Kupa', unitId: 'l', amount: 0.3),
      ];
      NlParseResult read(String text) => NaturalLanguageParser.parse(text, activities: const [], measures: measures);

      expect(read('2 bardak su').matchedMeasure?.name, 'Su bardağı');
      expect(read('2 bardak su').activityName, 'Su');
      expect(read('iki bardak çay').matchedMeasure?.name, 'Çay bardağı');
      expect(read('iki bardak çay').activityName, 'Çay');
      expect(read('1 su bardağı süt').matchedMeasure?.name, 'Su bardağı');

      // A measure the user named "Bardak" is found by its own name first.
      final own = [...measures, Measure(id: 4, name: 'Bardak', unitId: 'l', amount: 0.25)];
      expect(
        NaturalLanguageParser.parse('2 bardak su', activities: const [], measures: own).matchedMeasure?.name,
        'Bardak',
      );
    });
  });

  group('Backup import', () {
    test('rejects a backup with an unreadable row and leaves the data untouched', () async {
      final s = await openStore();
      final act = await s.addActivity('Su');
      await s.addEntry(act.id);
      final bad = (await s.exportJson()).replaceFirst(
        '"goals": []',
        '"goals": [{"id": 1, "name": "G", "type": "target", "mode": "count", "unit_id": null, "target": 1.0, '
            '"period": "yearly", "start_date": 0, "end_date": null, "created_at": 0, "sort": 0}]',
      );
      expect(bad, contains('yearly'));

      await expectLater(s.importJson(bad), throwsFormatException);

      // The next app start must still work, with nothing replaced.
      final next = AppStore();
      await next.load();
      expect(next.entries, hasLength(1));
      expect(next.goals, isEmpty);
    });

    test('rejects a backup written by a newer app version', () async {
      final s = await openStore();
      final act = await s.addActivity('Su');
      await s.addEntry(act.id);
      final newer = (await s.exportJson()).replaceFirst(
        '"version": ${AppDb.currentVersion}',
        '"version": ${AppDb.currentVersion + 1}',
      );
      expect(newer, isNot(contains('"version": ${AppDb.currentVersion},')));

      await expectLater(s.importJson(newer), throwsFormatException);
      expect(await _entryRows(s, act.id), hasLength(1));
    });

    test('restores a valid backup of every table', () async {
      final s = await openStore();
      final unit = await s.addUnit('Sayfa', 'syf');
      final measure = await s.addMeasure('Bölüm', unit.id, 20);
      final act = await s.addActivity('Kitap', emoji: '📚', category: 'study', isHabit: true);
      await s.addEntry(act.id, measureId: measure.id, qty: 2, note: 'roman');
      await s.saveGoal(Goal(
        id: 0,
        name: 'Okuma',
        mode: 'amount',
        unitId: unit.id,
        target: 40,
        period: GoalPeriod.day,
        startDate: 0,
        createdAt: 0,
        links: [GoalLink(activityId: act.id, pct: 50)],
      ));
      await s.saveQuickItem(QuickItem(id: 0, activityId: act.id, kind: 'todo', createdAt: 0));
      await s.setTimelineView('grid');
      await s.createRoadmap(RoadmapParser.parse('{"title": "Plan", "steps": [{"title": "Adım", "type": "task"}]}')!);
      final timer = await s.startTimer(act.id);
      await s.pauseTimer(timer.id);

      Map<String, Object?> snapshot(String json) => (jsonDecode(json) as Map<String, Object?>)..remove('exportedAt');
      final backup = await s.exportJson();

      await s.deleteEntry(s.entries.single);
      await s.addActivity('Sonradan eklenen');
      await s.importJson(backup);

      expect(snapshot(await s.exportJson()), snapshot(backup));
      expect(s.entries.single.note, 'roman');
      expect(s.goals.single.links.single.pct, 50);
      expect(s.roadmaps.single.steps, hasLength(1));
      expect(s.timelineView, 'grid');
    });

    test('restores running timers as paused instead of letting them run on since the backup', () async {
      final s = await openStore();
      final ders = await s.addActivity('Ders');
      final gitar = await s.addActivity('Gitar');
      final countdown = await s.startTimer(ders.id, mode: 'countdown', targetMs: 150);
      final stopwatch = await s.startTimer(gitar.id);
      await _wait(60);
      final backup = await s.exportJson();

      // By the time the backup is restored the countdown would count as complete.
      await _wait(200);
      await s.importJson(backup);

      expect(await _entryRows(s, ders.id), isEmpty, reason: 'restoring must not invent a finished session');
      final restored = s.getTimer(countdown.id)!;
      expect(restored.isRunning, isFalse);
      expect(restored.elapsedMs, inInclusiveRange(50, 149), reason: 'the time up to the backup is kept');
      expect(s.getTimer(stopwatch.id)!.isRunning, isFalse);

      // The timers can simply be continued.
      await s.resumeTimer(stopwatch.id);
      expect(s.getTimer(stopwatch.id)!.isRunning, isTrue);
    });

    test('still accepts a backup of an older version that lacks the later columns and tables', () async {
      final s = await openStore();
      final unit = await s.addUnit('Sayfa', 'syf');
      final measure = await s.addMeasure('Bölüm', unit.id, 20);
      final act = await s.addActivity('Kitap');
      await s.addEntry(act.id, measureId: measure.id, qty: 2);
      await s.saveGoal(Goal(
        id: 0,
        name: 'Okuma',
        mode: 'amount',
        unitId: unit.id,
        target: 40,
        period: GoalPeriod.day,
        startDate: 0,
        createdAt: 0,
        links: [GoalLink(activityId: act.id, pct: 100)],
      ));

      // What a version 1 export looked like: no columns of the later migrations, none of the later tables.
      final old = jsonDecode(await s.exportJson()) as Map<String, dynamic>;
      old['version'] = 1;
      void dropColumns(String table, List<String> columns) {
        for (final row in (old[table] as List).cast<Map<String, dynamic>>()) {
          columns.forEach(row.remove);
        }
      }

      dropColumns('measures', ['qty_mode', 'choices', 'grid_rows', 'grid_cols']);
      dropColumns('activities', ['category', 'color', 'is_habit', 'is_archived']);
      dropColumns('entries', ['end_ts']);
      dropColumns('goals', ['type']);
      ['settings', 'active_timers', 'roadmaps', 'roadmap_steps'].forEach(old.remove);

      await s.deleteEntry(s.entries.single);
      await s.importJson(jsonEncode(old));

      expect(s.activities.values.single.name, 'Kitap');
      expect(s.entries.single.value, 40.0);
      expect(s.goals.single.type, 'target');
      expect(s.measures.firstWhere((m) => m.name == 'Bölüm').qtyMode, 'stepper');
    });

    test('a database with an unreadable row is recovered by restoring a local backup', () async {
      final s = await openStore();
      final act = await s.addActivity('Su');
      await s.addEntry(act.id);
      final backup = await BackupService.createBackup(s, prefix: 'manual');
      // A row load() cannot read, as an import of an app version without validation could leave behind.
      await (await s.db).insert('goals', {
        'name': 'G',
        'type': 'target',
        'mode': 'count',
        'target': 1.0,
        'period': 'yearly',
        'start_date': 0,
        'created_at': 0,
        'sort': 0,
      });

      // The next app start fails ...
      final app = AppStore();
      await expectLater(app.load(), throwsArgumentError);
      expect(app.loaded, isFalse);

      // ... and the restore button of the recovery page brings the app back.
      await BackupService.restoreFromFile(app, backup);

      expect(app.loaded, isTrue);
      expect(app.entries, hasLength(1));
      expect(app.goals, isEmpty);
    });
  });
}
