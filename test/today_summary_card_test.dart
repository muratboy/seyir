import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:takip/data/models.dart';
import 'package:takip/data/store.dart';
import 'package:takip/ui/components/today_summary_card.dart';

void seed({
  List<Activity> activities = const [],
  List<Entry> entries = const [],
  List<Goal> goals = const [],
  List<Roadmap> roadmaps = const [],
}) {
  store.activities
    ..clear()
    ..addEntries([for (final a in activities) MapEntry(a.id, a)]);
  store.entries = [...entries]..sort((a, b) => a.ts.compareTo(b.ts));
  store.goals = [...goals];
  store.roadmaps = [...roadmaps];
  store.collapsedSections.clear();
  store.clearHabitStreakCache();
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('tr_TR');
  });

  tearDown(() {
    seed();
  });

  testWidgets('TodaySummaryCard renders empty when no goals, habits or roadmaps exist', (tester) async {
    seed();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TodaySummaryCard(currentDay: DateTime.now()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Bugünün Özeti'), findsNothing);
  });

  testWidgets('TodaySummaryCard renders remaining goal amounts and uncompleted habits', (tester) async {
    final now = DateTime.now();
    final water = Activity(id: 1, name: 'Su', emoji: '💧', createdAt: 1000);
    final run = Activity(id: 2, name: 'Koşu', emoji: '🏃', isHabit: true, createdAt: 1000);

    final goal = Goal(
      id: 1,
      name: 'Günlük Su',
      mode: 'amount',
      period: GoalPeriod.day,
      target: 2.0,
      unitId: 'l',
      startDate: 1000,
      links: [GoalLink(activityId: 1, pct: 100)],
      createdAt: 1000,
    );

    seed(
      activities: [water, run],
      entries: [
        Entry(
          id: 1,
          activityId: 1,
          ts: now.millisecondsSinceEpoch,
          value: 0.5,
          unitId: 'l',
        ),
      ],
      goals: [goal],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TodaySummaryCard(currentDay: now),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Title exists
    expect(find.text('Bugünün Özeti'), findsOneWidget);

    // Goal and remaining amount exist
    expect(find.text('Günlük Su'), findsOneWidget);
    expect(find.textContaining('Kalan:'), findsOneWidget);

    // Uncompleted habit exists
    expect(find.text('Kalan Alışkanlıklar'), findsOneWidget);
    expect(find.text('Koşu'), findsOneWidget);
  });

  testWidgets('TodaySummaryCard celebrates when everything is completed', (tester) async {
    final now = DateTime.now();
    final read = Activity(id: 1, name: 'Kitap', emoji: '📖', isHabit: true, createdAt: 1000);

    seed(
      activities: [read],
      entries: [
        Entry(
          id: 1,
          activityId: 1,
          ts: now.millisecondsSinceEpoch,
        ),
      ],
      goals: [],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TodaySummaryCard(currentDay: now),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Bugünün Özeti'), findsOneWidget);
    expect(find.textContaining('Harika!'), findsOneWidget);
  });

  testWidgets('TodaySummaryCard switches between detailed goals and compact mini rings when collapsed', (tester) async {
    final now = DateTime.now();
    final water = Activity(id: 1, name: 'Su', emoji: '💧', createdAt: 1000);
    final goal = Goal(
      id: 1,
      name: 'Günlük Su',
      mode: 'amount',
      period: GoalPeriod.day,
      target: 2.0,
      unitId: 'l',
      startDate: 1000,
      links: [GoalLink(activityId: 1, pct: 100)],
      createdAt: 1000,
    );

    seed(activities: [water], goals: [goal]);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AnimatedBuilder(
            animation: store,
            builder: (context, _) => TodaySummaryCard(currentDay: now),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // When expanded, 'Günlük Su' is rendered once with detailed progress
    expect(find.text('Günlük Su'), findsOneWidget);
    expect(find.textContaining('Kalan:'), findsOneWidget);

    // Collapse TodaySummaryCard
    store.collapsedSections.add('summary');
    store.notifyListeners();
    await tester.pumpAndSettle();

    // When collapsed, 'Günlük Su' is rendered once inside the embedded mini ring
    expect(find.text('Günlük Su'), findsOneWidget);
    expect(find.textContaining('Kalan:'), findsNothing);
  });
}
