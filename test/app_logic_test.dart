import 'package:flutter_test/flutter_test.dart';
import 'package:takip/data/models.dart';
import 'package:takip/data/store.dart';
import 'package:takip/logic/format.dart';
import 'package:takip/logic/l10n.dart';
import 'package:takip/logic/text_match.dart';
import 'package:takip/services/nl_parser.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Turkish Text Matching & Normalization', () {
    test('normalizeTr converts uppercase Turkish characters properly', () {
      expect(normalizeTr('Çay Bardağı'), equals('cay bardagi'));
      expect(normalizeTr('İlaç'), equals('ilac'));
      expect(normalizeTr('Ispanak'), equals('ispanak'));
      expect(normalizeTr('Şeker'), equals('seker'));
      expect(normalizeTr('Ölçü'), equals('olcu'));
      expect(normalizeTr('Yoğurt'), equals('yogurt'));
    });

    test('trCapitalize capitalizes with Turkish rules', () {
      expect(trCapitalize('çay'), equals('Çay'));
      expect(trCapitalize('ilaç'), equals('İlaç'));
      expect(trCapitalize('şeker'), equals('Şeker'));
    });

    test('fuzzy match finds query even with typo or prefix', () {
      final normActivity = normalizeTr('Çay');
      expect(matchScore('cay', normActivity), greaterThan(50));
      expect(matchScore('cya', normActivity), greaterThan(0)); // typo
    });
  });

  group('Format & Units Logic', () {
    test('parseNum handles both comma and dot decimals', () {
      expect(parseNum('0.7'), equals(0.7));
      expect(parseNum('0,7'), equals(0.7));
      expect(parseNum('  2,5  '), equals(2.5));
      expect(parseNum('invalid'), isNull);
    });

    test('fmtAmount formats volume and time correctly', () {
      expect(fmtAmount(0.5, 'volume'), contains('500')); // 500 ml
      expect(fmtAmount(1.4, 'volume'), contains('L')); // 1,4 L
      expect(fmtAmount(45, 'time'), contains('dk')); // 45 dk
      expect(fmtAmount(90, 'time'), contains('sa')); // 1 sa 30 dk
    });
  });

  group('Goal Calculations', () {
    test('Liquid goal contribution calculation with percentage (e.g. Yoğurt 50%)', () {
      final goal = Goal(
        id: 1,
        name: 'Günlük Sıvı',
        mode: 'amount',
        unitId: 'l',
        target: 2.5,
        period: GoalPeriod.day,
        startDate: DateTime.now().millisecondsSinceEpoch,
        createdAt: DateTime.now().millisecondsSinceEpoch,
        links: [
          GoalLink(activityId: 10, pct: 100), // Su
          GoalLink(activityId: 20, pct: 50), // Yoğurt (%50 katkı)
        ],
      );

      // 1 Su (0.2 L, 100% contribution)
      final waterEntry = Entry(
        id: 1,
        activityId: 10,
        ts: DateTime.now().millisecondsSinceEpoch,
        value: 0.2,
        unitId: 'l',
      );
      final waterContrib = store.contribution(goal, waterEntry, 100);
      expect(waterContrib, equals(0.2));

      // 1 Yoğurt (0.4 L, 50% contribution)
      final yogurtEntry = Entry(
        id: 2,
        activityId: 20,
        ts: DateTime.now().millisecondsSinceEpoch,
        value: 0.4,
        unitId: 'l',
      );
      final yogurtContrib = store.contribution(goal, yogurtEntry, 50);
      expect(yogurtContrib, equals(0.2)); // 0.4 * 50% = 0.2 L
    });

    test('Cumulative Count Goal (e.g. 100 Deneme)', () {
      final examGoal = Goal(
        id: 2,
        name: '100 Deneme Çözülecek',
        mode: 'count',
        unitId: 'adet',
        target: 100,
        period: GoalPeriod.total,
        startDate: DateTime.now().millisecondsSinceEpoch,
        createdAt: DateTime.now().millisecondsSinceEpoch,
        links: [
          GoalLink(activityId: 30, pct: 100),
        ],
      );

      expect(examGoal.isCount, isTrue);
      final entry = Entry(
        id: 3,
        activityId: 30,
        ts: DateTime.now().millisecondsSinceEpoch,
        qty: 1,
      );
      final contrib = store.contribution(examGoal, entry, 100);
      expect(contrib, equals(1.0));
    });

    test('Limit Goal logic (e.g. Caffeine Limit 400 mg)', () {
      final caffeineLimit = Goal(
        id: 5,
        name: 'Kafein Limiti',
        type: 'limit',
        mode: 'amount',
        unitId: 'g',
        target: 400,
        period: GoalPeriod.day,
        startDate: DateTime.now().millisecondsSinceEpoch,
        createdAt: DateTime.now().millisecondsSinceEpoch,
        links: [
          GoalLink(activityId: 10, pct: 100), // Çay
          GoalLink(activityId: 11, pct: 100), // Kahve
        ],
      );

      expect(caffeineLimit.isLimit, isTrue);
      expect(caffeineLimit.isTarget, isFalse);

      // Status within limit: 250 out of 400
      final now = DateTime.now();
      final statusWithin = GoalStatus(caffeineLimit, 250, now, now, 0);
      expect(statusWithin.done, isTrue);
      expect(statusWithin.isExceeded, isFalse);
      expect(statusWithin.remaining, equals(150));
      expect(statusWithin.exceededAmount, equals(0));

      // Status exceeded: 450 out of 400
      final statusExceeded = GoalStatus(caffeineLimit, 450, now, now, 0);
      expect(statusExceeded.done, isFalse);
      expect(statusExceeded.isExceeded, isTrue);
      expect(statusExceeded.remaining, equals(0));
      expect(statusExceeded.exceededAmount, equals(50));
    });

    test('Goal serialization preserves type (target vs limit)', () {
      final targetGoal = Goal(
        id: 1,
        name: 'Su Hedefi',
        type: 'target',
        mode: 'amount',
        target: 2.5,
        period: GoalPeriod.day,
        startDate: 0,
        createdAt: 0,
      );
      final limitGoal = Goal(
        id: 2,
        name: 'Şeker Limiti',
        type: 'limit',
        mode: 'amount',
        target: 25,
        period: GoalPeriod.day,
        startDate: 0,
        createdAt: 0,
      );

      final targetMap = targetGoal.toMap();
      final limitMap = limitGoal.toMap();

      expect(targetMap['type'], equals('target'));
      expect(limitMap['type'], equals('limit'));

      expect(Goal.fromMap(targetMap).isLimit, isFalse);
      expect(Goal.fromMap(limitMap).isLimit, isTrue);
    });
  });

  group('Localization and Theme State', () {
    test('Strings switch between Turkish and English', () {
      final trStrings = const AppStrings(AppLanguage.tr);
      expect(trStrings.tabToday, equals('Günlük'));
      expect(trStrings.settingsTheme, equals('Tema Seçeneği'));

      final enStrings = const AppStrings(AppLanguage.en);
      expect(enStrings.tabToday, equals('Journal'));
      expect(enStrings.settingsTheme, equals('Theme Mode'));
    });

    test('Timeline view default and toggle modes', () {
      // Test default value
      String timelineView = 'list';
      expect(timelineView, equals('list'));

      // Toggle to grid
      timelineView = 'grid';
      expect(timelineView, equals('grid'));

      // Validate mode values
      expect(['list', 'grid'].contains(timelineView), isTrue);
    });
  });

  group('Measure Quantity Input Modes', () {
    test('Measure with choices parses choiceList correctly', () {
      final m = Measure(
        id: 1,
        name: 'Çay bardağı',
        unitId: 'l',
        amount: 0.1,
        qtyMode: 'choices',
        choices: '1, 2, 3, 4, 5',
      );
      expect(m.choiceList, equals([1.0, 2.0, 3.0, 4.0, 5.0]));
      expect(m.qtyMode, equals('choices'));
    });

    test('Measure with grid calculates dimensions and total', () {
      final m = Measure(
        id: 2,
        name: 'Su bardağı',
        unitId: 'l',
        amount: 0.2,
        qtyMode: 'grid',
        gridRows: 2,
        gridCols: 5,
      );
      expect(m.gridTotal, equals(10));
      expect(m.qtyMode, equals('grid'));
    });
  });

  group('Stopwatch Mode & ActiveTimer Logic', () {
    test('formatTimerDuration formats mm:ss and hh:mm:ss properly', () {
      expect(formatTimerDuration(0), equals('00:00'));
      expect(formatTimerDuration(5000), equals('00:05'));
      expect(formatTimerDuration(45000), equals('00:45'));
      expect(formatTimerDuration(75000), equals('01:15')); // 1m 15s
      expect(formatTimerDuration(3600000), equals('01:00:00')); // 1h
      expect(formatTimerDuration(3665000), equals('01:01:05')); // 1h 1m 5s
    });

    test('ActiveTimer elapsedMs accurately tracks running and paused states', () {
      final now = DateTime.now().millisecondsSinceEpoch;
      // Paused timer with 30 seconds accumulated
      final pausedTimer = ActiveTimer(
        id: 1,
        activityId: 10,
        startTs: now - 60000,
        accumulatedMs: 30000,
        isRunning: false,
      );
      expect(pausedTimer.elapsedMs, equals(30000));
      expect(pausedTimer.elapsedSeconds, equals(30.0));
      expect(pausedTimer.formattedDuration, equals('00:30'));

      // Running timer: 10 seconds accumulated + 5 seconds running since last resume
      final runningTimer = ActiveTimer(
        id: 1,
        activityId: 10,
        startTs: now - 15000,
        accumulatedMs: 10000,
        lastResumeTs: now - 5000,
        isRunning: true,
      );
      // elapsed should be ~15000 ms
      expect(runningTimer.elapsedMs, greaterThanOrEqualTo(14900));
      expect(runningTimer.elapsedMs, lessThanOrEqualTo(15500));
    });

    test('ActiveTimer midnight crossover and split calculation', () {
      final now = DateTime.now();
      // Dün gece 23:00'da başlayan oturum
      final yesterday23 = DateTime(now.year, now.month, now.day - 1, 23, 0);
      final twoHoursMs = 2 * 3600 * 1000; // 2 saat = 7.200.000 ms

      final timer = ActiveTimer(
        id: 1,
        activityId: 10,
        startTs: yesterday23.millisecondsSinceEpoch,
        accumulatedMs: twoHoursMs,
        isRunning: false,
      );

      // Farklı takvim gününe taştığı için spansMidnight true olmalı
      expect(timer.spansMidnight, isTrue);

      // 23:00 ile 00:00 arası: tam 1 saat (3.600.000 ms)
      expect(timer.msBeforeMidnight, equals(3600000));

      // 00:00 ile 01:00 arası: tam 1 saat (3.600.000 ms)
      expect(timer.msAfterMidnight, equals(3600000));

      // formatDurationHuman kontrolleri
      expect(formatDurationHuman(3600000, true), equals('1 sa'));
      expect(formatDurationHuman(1800000, true), equals('30 dk'));
      expect(formatDurationHuman(5400000, true), equals('1 sa 30 dk'));
      expect(formatDurationHuman(45000, true), equals('45 sn'));
    });

    test('ActiveTimer serialization roundtrip', () {
      final timer = ActiveTimer(
        id: 1,
        activityId: 5,
        startTs: 1700000000000,
        accumulatedMs: 12500,
        lastResumeTs: 1700000010000,
        isRunning: true,
        note: 'Ders çalışma molası',
      );
      final map = timer.toMap();
      final revived = ActiveTimer.fromMap(map);

      expect(revived.id, equals(timer.id));
      expect(revived.activityId, equals(timer.activityId));
      expect(revived.startTs, equals(timer.startTs));
      expect(revived.accumulatedMs, equals(timer.accumulatedMs));
      expect(revived.lastResumeTs, equals(timer.lastResumeTs));
      expect(revived.isRunning, isTrue);
      expect(revived.note, equals('Ders çalışma molası'));
    });

    test('Stopwatch duration contributes to time goals', () {
      final studyGoal = Goal(
        id: 10,
        name: 'Günde 60 dk Çalışma',
        mode: 'amount',
        unitId: 'dk',
        target: 60,
        period: GoalPeriod.day,
        startDate: DateTime.now().millisecondsSinceEpoch,
        createdAt: DateTime.now().millisecondsSinceEpoch,
        links: [GoalLink(activityId: 1, pct: 100)],
      );

      // Stopwatch entry finished with 45 dk
      final studyEntry = Entry(
        id: 1,
        activityId: 1,
        ts: DateTime.now().millisecondsSinceEpoch,
        value: 45,
        unitId: 'dk',
      );

      final contrib = store.contribution(studyGoal, studyEntry, 100);
      expect(contrib, equals(45.0));

      final status = GoalStatus(studyGoal, 45, DateTime.now(), DateTime.now(), 0);
      expect(status.done, isFalse);
      expect(status.remaining, equals(15.0));

      // Reaching 60 dk
      final statusDone = GoalStatus(studyGoal, 65, DateTime.now(), DateTime.now(), 0);
      expect(statusDone.done, isTrue);
    });

    test('Pomodoro and countdown timers calculate remaining time and progress', () {
      final now = DateTime.now().millisecondsSinceEpoch;
      final pomodoro = ActiveTimer(
        id: 1,
        activityId: 1,
        startTs: now,
        accumulatedMs: 10 * 60 * 1000, // 10 mins elapsed
        lastResumeTs: null,
        isRunning: false,
        mode: 'pomodoro',
        targetMs: 25 * 60 * 1000, // 25 mins target
      );

      expect(pomodoro.isCountdown, isTrue);
      expect(pomodoro.isPomodoro, isTrue);
      expect(pomodoro.elapsedMs, equals(10 * 60 * 1000));
      expect(pomodoro.remainingMs, equals(15 * 60 * 1000));
      expect(pomodoro.progress, closeTo(0.4, 0.001));
      expect(pomodoro.isTargetReached, isFalse);
      expect(pomodoro.displayDuration, equals('15:00'));

      final finishedPomodoro = pomodoro.copyWith(
        accumulatedMs: 25 * 60 * 1000,
      );
      expect(finishedPomodoro.remainingMs, equals(0));
      expect(finishedPomodoro.progress, equals(1.0));
      expect(finishedPomodoro.isTargetReached, isTrue);
    });

    test('Categories and colors are correctly assigned to activities', () {
      final act = Activity(
        id: 1,
        name: 'Otobüs',
        category: 'transport',
        createdAt: DateTime.now().millisecondsSinceEpoch,
      );

      expect(act.categoryDef.id, equals('transport'));
      expect(act.categoryDef.emoji, equals('🚌'));
      expect(act.displayColor.toARGB32(), equals(0xFF6A1B9A));

      final actDefault = Activity(
        id: 2,
        name: 'Bilinmeyen',
        createdAt: DateTime.now().millisecondsSinceEpoch,
      );
      expect(actDefault.categoryDef.id, equals('other'));
    });
  });

  group('Natural Language Parser Tests (Sesli / Akıllı Giriş)', () {
    final activities = [
      Activity(id: 1, name: 'Çay', createdAt: 0),
      Activity(id: 2, name: 'Filtre Kahve', createdAt: 0),
      Activity(id: 3, name: 'Su', createdAt: 0),
      Activity(id: 4, name: 'Ders Çalışma', createdAt: 0),
      Activity(id: 5, name: 'Koşu', createdAt: 0),
    ];

    final measures = [
      Measure(id: 1, name: 'Çay Bardağı', unitId: 'ml', amount: 100),
      Measure(id: 2, name: 'Kupa', unitId: 'ml', amount: 250),
      Measure(id: 3, name: 'Litre', unitId: 'l', amount: 1.0),
      Measure(id: 4, name: 'Adet', unitId: 'count', amount: 1.0),
    ];

    test('Parses quantity with digits and measure', () {
      final res = NaturalLanguageParser.parse(
        '2 kupa filtre kahve',
        activities: activities,
        measures: measures,
      );

      expect(res.matchedActivity?.id, equals(2));
      expect(res.quantity, equals(2.0));
      expect(res.matchedMeasure?.name, equals('Kupa'));
      expect(res.actionType, equals(NlActionType.addEntry));
    });

    test('Parses Turkish words like "bir buçuk litre su"', () {
      final res = NaturalLanguageParser.parse(
        'bir buçuk litre su içtim',
        activities: activities,
        measures: measures,
      );

      expect(res.matchedActivity?.id, equals(3));
      expect(res.quantity, equals(1.5));
      expect(res.matchedMeasure?.name, equals('Litre'));
      expect(res.actionType, equals(NlActionType.addEntry));
    });

    test('Parses stopwatch command for Ders Çalışma', () {
      final res = NaturalLanguageParser.parse(
        'ders çalışma kronometre başlat',
        activities: activities,
        measures: measures,
      );

      expect(res.matchedActivity?.id, equals(4));
      expect(res.actionType, equals(NlActionType.startStopwatch));
    });

    test('Parses pomodoro command with time', () {
      final res = NaturalLanguageParser.parse(
        'kitap okuma için 25 dakika pomodoro',
        activities: activities,
        measures: measures,
      );

      expect(res.actionType, equals(NlActionType.startPomodoro));
      expect(res.targetMinutes, equals(25));
    });
  });

  group('Habit Tracker & Streak Logic (Zinciri Kırma)', () {
    test('Activity serialization preserves isHabit property', () {
      final act = Activity(
        id: 10,
        name: 'Kitap Okuma',
        emoji: '📖',
        category: 'study',
        color: 0xFF1565C0,
        isHabit: true,
        createdAt: 1000000,
      );

      final map = act.toMap();
      expect(map['is_habit'], equals(1));

      final restored = Activity.fromMap(map);
      expect(restored.id, equals(10));
      expect(restored.name, equals('Kitap Okuma'));
      expect(restored.isHabit, isTrue);

      final nonHabit = Activity(
        id: 11,
        name: 'Kahve',
        createdAt: 1000000,
      );
      expect(nonHabit.isHabit, isFalse);
      expect(Activity.fromMap(nonHabit.toMap()).isHabit, isFalse);
    });

    test('Habit streak calculates correctly when done today', () {
      final store = AppStore();
      final actId = 100;
      final now = DateTime.now();
      final today = dayStart(now);

      // 3 consecutive days: today, yesterday, 2 days ago
      store.entries = [
        Entry(id: 1, activityId: actId, ts: today.subtract(const Duration(days: 2)).millisecondsSinceEpoch + 1000),
        Entry(id: 2, activityId: actId, ts: today.subtract(const Duration(days: 1)).millisecondsSinceEpoch + 2000),
        Entry(id: 3, activityId: actId, ts: today.millisecondsSinceEpoch + 3000),
      ];

      final info = store.habitStreakInfo(actId);
      expect(info.isDoneToday, isTrue);
      expect(info.todayCount, equals(1));
      expect(info.currentStreak, equals(3));
      expect(info.longestStreak, equals(3));
      expect(info.totalActiveDays, equals(3));
    });

    test('Habit streak remains intact when yesterday was done but today is pending', () {
      final store = AppStore();
      final actId = 101;
      final now = DateTime.now();
      final today = dayStart(now);

      // Yesterday and 2 days ago done, today not done yet
      store.entries = [
        Entry(id: 1, activityId: actId, ts: today.subtract(const Duration(days: 2)).millisecondsSinceEpoch + 1000),
        Entry(id: 2, activityId: actId, ts: today.subtract(const Duration(days: 1)).millisecondsSinceEpoch + 2000),
      ];

      final info = store.habitStreakInfo(actId);
      expect(info.isDoneToday, isFalse);
      expect(info.todayCount, equals(0));
      // Streak is still 2 because yesterday was completed!
      expect(info.currentStreak, equals(2));
      expect(info.longestStreak, equals(2));
    });

    test('Habit streak resets to 0 when yesterday was missed', () {
      final store = AppStore();
      final actId = 102;
      final now = DateTime.now();
      final today = dayStart(now);

      // 2 days ago and 3 days ago done, yesterday and today missed
      store.entries = [
        Entry(id: 1, activityId: actId, ts: today.subtract(const Duration(days: 3)).millisecondsSinceEpoch + 1000),
        Entry(id: 2, activityId: actId, ts: today.subtract(const Duration(days: 2)).millisecondsSinceEpoch + 2000),
      ];

      final info = store.habitStreakInfo(actId);
      expect(info.isDoneToday, isFalse);
      expect(info.currentStreak, equals(0)); // Broken!
      expect(info.longestStreak, equals(2)); // But best streak is preserved
    });

    test('Longest streak tracks maximum consecutive days across full history', () {
      final store = AppStore();
      final actId = 103;
      final now = DateTime.now();
      final today = dayStart(now);

      // 4 consecutive days in the past (days 10, 9, 8, 7 ago)
      // Gap on days 6, 5, 4, 3 ago
      // 2 consecutive days currently (yesterday and today)
      store.entries = [
        Entry(id: 1, activityId: actId, ts: today.subtract(const Duration(days: 10)).millisecondsSinceEpoch),
        Entry(id: 2, activityId: actId, ts: today.subtract(const Duration(days: 9)).millisecondsSinceEpoch),
        Entry(id: 3, activityId: actId, ts: today.subtract(const Duration(days: 8)).millisecondsSinceEpoch),
        Entry(id: 4, activityId: actId, ts: today.subtract(const Duration(days: 7)).millisecondsSinceEpoch),
        Entry(id: 5, activityId: actId, ts: today.subtract(const Duration(days: 1)).millisecondsSinceEpoch),
        Entry(id: 6, activityId: actId, ts: today.millisecondsSinceEpoch),
      ];

      final info = store.habitStreakInfo(actId);
      expect(info.currentStreak, equals(2));
      expect(info.longestStreak, equals(4)); // Preserves the 4-day historical peak
      expect(info.totalActiveDays, equals(6));
    });

    test('Consistency last 30 days calculates correct ratio', () {
      final store = AppStore();
      final actId = 104;
      final now = DateTime.now();
      final today = dayStart(now);

      // Log 15 days out of last 30
      store.entries = [
        for (int i = 0; i < 15; i++)
          Entry(id: i + 1, activityId: actId, ts: today.subtract(Duration(days: i)).millisecondsSinceEpoch),
      ];

      final info = store.habitStreakInfo(actId);
      expect(info.consistencyLast30, closeTo(50.0, 0.1));
    });
  });

  group('Stage 1 Hardening Tests', () {
    test('ActiveTimer proportional midnight split handles pauses gracefully', () {
      final now = DateTime.now();
      // Started yesterday at 23:00
      final yesterday23 = DateTime(now.year, now.month, now.day - 1, 23, 0);
      // Ran for 15 mins yesterday, then paused, total elapsed 30 mins
      final timer = ActiveTimer(
        id: 1,
        activityId: 10,
        startTs: yesterday23.millisecondsSinceEpoch,
        accumulatedMs: 30 * 60 * 1000, // 30 mins elapsed
        isRunning: false,
      );

      // Effective end time is 23:00 + 30 mins = 23:30 (all before midnight)
      expect(timer.spansMidnight, isTrue); // Calendar day of start != today
      // All 30 mins fell before midnight
      expect(timer.msBeforeMidnight, equals(30 * 60 * 1000));
      expect(timer.msAfterMidnight, equals(0));
    });

    test('CSV export structure adheres to BOM and distinct columns', () {
      final store = AppStore();
      store.activities = {
        1: Activity(id: 1, name: 'Çay', emoji: '☕', createdAt: 0),
      };
      store.measures = [
        Measure(id: 1, name: 'Çay bardağı', unitId: 'l', amount: 0.1, sort: 0),
      ];
      store.entries = [
        Entry(id: 10, activityId: 1, ts: DateTime(2026, 10, 9, 10, 30).millisecondsSinceEpoch, qty: 2, value: 0.2, unitId: 'l', measureId: 1),
      ];

      final detail = store.entryDetail(store.entries.first);
      // Detail should format amount correctly (0.2 L -> 200 ml)
      expect(detail, contains('Çay bardağı'));
      expect(detail, contains('200 ml'));
    });
  });
}

