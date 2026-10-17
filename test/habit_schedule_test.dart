import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:takip/data/models.dart';
import 'package:takip/data/store.dart';
import 'package:takip/logic/format.dart';
import 'package:takip/ui/tabs/habits_tab.dart';

import 'support/real_db.dart';

void seedHabit(Activity habit, List<Entry> entries) {
  store.activities
    ..clear()
    ..[habit.id] = habit;
  store.entries = [...entries]..sort((a, b) => a.ts.compareTo(b.ts));
  store.clearHabitStreakCache();
}

void main() {
  useRealDatabase();

  setUpAll(() async {
    await initializeDateFormatting('tr_TR');
    await initializeDateFormatting('en_US');
    Intl.defaultLocale = 'tr_TR';
  });

  tearDown(() {
    store.activities.clear();
    store.entries = [];
    store.clearHabitStreakCache();
  });

  test('habit schedule text formats correctly in Turkish and English', () {
    final habit = Activity(id: 10, name: 'Spor', isHabit: true, createdAt: 0);

    // Default (empty/all)
    expect(store.habitScheduleText(habit.id, isTr: true), 'Her gün');
    expect(store.habitScheduleText(habit.id, isTr: false), 'Every day');

    // Weekdays
    store.setHabitTargetDays(habit.id, {1, 2, 3, 4, 5});
    expect(store.habitScheduleText(habit.id, isTr: true), 'Hafta içi');
    expect(store.habitScheduleText(habit.id, isTr: false), 'Weekdays');

    // Weekends
    store.setHabitTargetDays(habit.id, {6, 7});
    expect(store.habitScheduleText(habit.id, isTr: true), 'Hafta sonu');
    expect(store.habitScheduleText(habit.id, isTr: false), 'Weekends');

    // Custom: Mon, Wed, Fri
    store.setHabitTargetDays(habit.id, {1, 3, 5});
    expect(store.habitScheduleText(habit.id, isTr: true), 'Pzt, Çar, Cum');
    expect(store.habitScheduleText(habit.id, isTr: false), 'Mon, Wed, Fri');
  });

  test('isHabitScheduledFor returns true for every day when not configured', () {
    final habit = Activity(id: 20, name: 'Su', isHabit: true, createdAt: 0);
    store.setHabitTargetDays(habit.id, null);

    final monday = DateTime(2026, 10, 12); // Mon
    final sunday = DateTime(2026, 10, 18); // Sun

    expect(store.isHabitScheduledFor(habit.id, monday), isTrue);
    expect(store.isHabitScheduledFor(habit.id, sunday), isTrue);
  });

  test('flexible habit streak skips off-days and does not break', () {
    final habit = Activity(id: 30, name: 'Kodlama', isHabit: true, createdAt: 0);
    // Hafta içi (Pzt-Cum: 1..5)
    store.setHabitTargetDays(habit.id, {1, 2, 3, 4, 5});

    final now = DateTime.now();
    final today = dayStart(now);

    // Find previous Monday through Friday dates
    // If today is Monday (1), Friday was 3 days ago.
    // Let's create entries for today and the last 3 scheduled days:
    var entries = <Entry>[];
    int idCounter = 1;
    var cur = today;
    int scheduledCount = 0;

    // Add an entry for today so isDoneToday is always true
    entries.add(Entry(
      id: idCounter++,
      activityId: habit.id,
      ts: today.add(const Duration(hours: 10)).millisecondsSinceEpoch,
      qty: 1,
    ));
    if (store.isHabitScheduledFor(habit.id, today)) {
      scheduledCount++;
    }
    cur = today.subtract(const Duration(days: 1));

    while (scheduledCount < 4) {
      if (store.isHabitScheduledFor(habit.id, cur)) {
        entries.add(Entry(
          id: idCounter++,
          activityId: habit.id,
          ts: cur.add(const Duration(hours: 10)).millisecondsSinceEpoch,
          qty: 1,
        ));
        scheduledCount++;
      }
      cur = cur.subtract(const Duration(days: 1));
    }

    seedHabit(habit, entries);

    final streakInfo = store.habitStreakInfo(habit.id);
    expect(streakInfo.isDoneToday, isTrue);
    expect(streakInfo.currentStreak, greaterThanOrEqualTo(4));
    expect(streakInfo.longestStreak, greaterThanOrEqualTo(4));
  });

  testWidgets('HabitsTab renders schedule chip and opens schedule dialog', (tester) async {
    final habit = Activity(id: 40, name: 'Meditasyon', isHabit: true, createdAt: 0);
    await tester.runAsync(() async {
      await store.load();
      seedHabit(habit, []);
      await store.setHabitTargetDays(habit.id, {1, 3, 5});
    });

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: HabitsTab(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Pzt, Çar, Cum'), findsOneWidget);

    await tester.tap(find.text('Pzt, Çar, Cum'));
    await tester.pumpAndSettle();

    expect(find.text('Alışkanlık Sıklığı'), findsOneWidget);
    expect(find.text('Her gün'), findsOneWidget);
    expect(find.text('Hafta içi'), findsOneWidget);
    expect(find.text('Hafta sonu'), findsOneWidget);

    await tester.tap(find.text('Hafta içi'));
    await tester.pumpAndSettle();

    await tester.runAsync(() async {
      await tester.tap(find.text('Kaydet'));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();

    expect(store.habitScheduleText(habit.id, isTr: true), 'Hafta içi');
  });
}
