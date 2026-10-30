import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:takip/data/models.dart';
import 'package:takip/data/store.dart';
import 'package:takip/logic/format.dart';
import 'package:takip/ui/contribution_heatmap.dart';
import 'package:takip/ui/goals_page.dart';
import 'package:takip/ui/tabs/habits_tab.dart';
import 'package:takip/ui/tabs/roadmaps_tab.dart';

void main() {
  setUp(() async {
    await initializeDateFormatting('tr_TR');
    await initializeDateFormatting('en_US');
    Intl.defaultLocale = 'tr_TR';
  });

  testWidgets('ContributionHeatmap renders cells and legend', (tester) async {
    final today = dayStart(DateTime.now());
    final dailyCounts = <DateTime, int>{
      today: 3,
      today.subtract(const Duration(days: 1)): 2,
      today.subtract(const Duration(days: 2)): 1,
    };

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ContributionHeatmap(
            dailyCounts: dailyCounts,
            weekCount: 16,
            baseColor: const Color(0xFF22C55E),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Verify day labels (Pzt, Çar, Cum)
    expect(find.text('Pzt'), findsOneWidget);
    expect(find.text('Çar'), findsOneWidget);
    expect(find.text('Cum'), findsOneWidget);

    // Verify legend texts
    expect(find.text('Daha az'), findsOneWidget);
    expect(find.text('Daha çok'), findsOneWidget);
  });

  testWidgets('GoalsPage switches between Goals and Habits tab', (tester) async {
    // Setup in-memory activity with habit
    final testHabit = Activity(
      id: 99,
      name: 'Kitap Okuma',
      emoji: '📚',
      isHabit: true,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
    store.activities[99] = testHabit;

    await tester.pumpWidget(
      const MaterialApp(
        home: GoalsPage(),
      ),
    );

    await tester.pumpAndSettle();

    // Verify tab headers exist
    expect(find.descendant(of: find.byType(InkWell), matching: find.text('Hedefler')), findsOneWidget);
    expect(find.textContaining('Zinciri Kırma'), findsOneWidget);

    // Tap on Zinciri Kırma tab
    final habitsFinder = find.textContaining('Zinciri Kırma');
    await tester.ensureVisible(habitsFinder);
    await tester.pumpAndSettle();
    await tester.tap(habitsFinder);
    await tester.pumpAndSettle();

    // Verify HabitsTab is mounted and habit card for Kitap Okuma is shown
    expect(find.byType(HabitsTab), findsOneWidget);
    expect(find.text('Kitap Okuma'), findsOneWidget);
    expect(find.textContaining('Mevcut Seri'), findsWidgets);
    expect(find.textContaining('En Uzun Seri'), findsWidgets);
    expect(find.byType(ContributionHeatmap), findsOneWidget);

    // Tap on Yol Haritası tab
    final roadmapsFinder = find.textContaining('Yol Haritası');
    await tester.ensureVisible(roadmapsFinder);
    await tester.pumpAndSettle();
    await tester.tap(roadmapsFinder);
    await tester.pumpAndSettle();

    // Verify RoadmapsTab is mounted
    expect(find.byType(RoadmapsTab), findsOneWidget);
  });

  testWidgets('RoadmapsTab renders empty state when no roadmaps exist', (tester) async {
    store.roadmaps.clear();

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: RoadmapsTab()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Henüz Bir Yol Haritası Yok'), findsOneWidget);
    expect(find.textContaining('Yapay Zekâ Kalıbıyla İçe Aktar'), findsOneWidget);
  });

  test('habitStreakInfo timed activity calculates min 1 min, max >= 60 min levels and tooltips', () {
    store.clearHabitStreakCache();
    store.activities.clear();
    store.entries.clear();
    store.goals.clear();

    const actId = 101;
    store.activities[actId] = Activity(
      id: actId,
      name: 'Meditasyon',
      isHabit: true,
      createdAt: 1000000,
    );

    final baseDay = dayStart(DateTime(2026, 10, 10));
    final d1 = baseDay; // 10 dk -> Level 1
    final d2 = baseDay.subtract(const Duration(days: 1)); // 20 dk -> Level 2
    final d3 = baseDay.subtract(const Duration(days: 2)); // 45 dk -> Level 3
    final d4 = baseDay.subtract(const Duration(days: 3)); // 60 dk -> Level 4
    final d5 = baseDay.subtract(const Duration(days: 4)); // 90 dk -> Level 4

    store.entries = [
      Entry(
        id: 1,
        activityId: actId,
        ts: d1.millisecondsSinceEpoch,
        endTs: d1.millisecondsSinceEpoch + 10 * 60 * 1000, // 10 min
      ),
      Entry(
        id: 2,
        activityId: actId,
        ts: d2.millisecondsSinceEpoch,
        endTs: d2.millisecondsSinceEpoch + 20 * 60 * 1000, // 20 min
      ),
      Entry(
        id: 3,
        activityId: actId,
        ts: d3.millisecondsSinceEpoch,
        endTs: d3.millisecondsSinceEpoch + 45 * 60 * 1000, // 45 min
      ),
      Entry(
        id: 4,
        activityId: actId,
        ts: d4.millisecondsSinceEpoch,
        endTs: d4.millisecondsSinceEpoch + 60 * 60 * 1000, // 60 min
      ),
      Entry(
        id: 5,
        activityId: actId,
        ts: d5.millisecondsSinceEpoch,
        endTs: d5.millisecondsSinceEpoch + 90 * 60 * 1000, // 90 min
      ),
    ];

    final info = store.habitStreakInfo(actId);
    expect(info.dailyLevels[d1], equals(1));
    expect(info.dailyTooltips[d1], contains('10 dk'));

    expect(info.dailyLevels[d2], equals(2));
    expect(info.dailyTooltips[d2], contains('20 dk'));

    expect(info.dailyLevels[d3], equals(3));
    expect(info.dailyTooltips[d3], contains('45 dk'));

    expect(info.dailyLevels[d4], equals(4));
    expect(info.dailyTooltips[d4], contains('1 sa'));

    expect(info.dailyLevels[d5], equals(4));
    expect(info.dailyTooltips[d5], contains('1 sa 30 dk'));
  });

  test('habitStreakInfo target goal reaches full level 4 when target is met', () {
    store.clearHabitStreakCache();
    store.activities.clear();
    store.entries.clear();
    store.goals.clear();

    const actId = 102;
    store.activities[actId] = Activity(
      id: actId,
      name: 'Su İçme',
      isHabit: true,
      createdAt: 1000000,
    );

    // Hedef: Günde 5 adet
    final goal = Goal(
      id: 201,
      name: 'Günlük 5 Su',
      type: 'target',
      mode: 'amount',
      period: GoalPeriod.day,
      target: 5,
      unitId: 'adet',
      startDate: 1000000,
      createdAt: 1000000,
      links: [GoalLink(activityId: actId, pct: 100)],
    );
    store.goals = [goal];

    final baseDay = dayStart(DateTime(2026, 10, 10));
    final d1 = baseDay; // 1 adet -> Level 1 (20%)
    final d2 = baseDay.subtract(const Duration(days: 1)); // 2 adet -> Level 2 (40%)
    final d3 = baseDay.subtract(const Duration(days: 2)); // 4 adet -> Level 3 (80%)
    final d4 = baseDay.subtract(const Duration(days: 3)); // 5 adet -> Level 4 (Hedefe ulaşıldı ✓)

    store.entries = [
      Entry(id: 1, activityId: actId, ts: d1.millisecondsSinceEpoch, qty: 1, value: 1, unitId: 'adet'),
      Entry(id: 2, activityId: actId, ts: d2.millisecondsSinceEpoch, qty: 2, value: 2, unitId: 'adet'),
      Entry(id: 3, activityId: actId, ts: d3.millisecondsSinceEpoch, qty: 4, value: 4, unitId: 'adet'),
      Entry(id: 4, activityId: actId, ts: d4.millisecondsSinceEpoch, qty: 5, value: 5, unitId: 'adet'),
    ];

    final info = store.habitStreakInfo(actId);
    expect(info.dailyLevels[d1], equals(1));
    expect(info.dailyTooltips[d1], contains('%20'));

    expect(info.dailyLevels[d2], equals(2));
    expect(info.dailyTooltips[d2], contains('%40'));

    expect(info.dailyLevels[d3], equals(3));
    expect(info.dailyTooltips[d3], contains('%80'));

    expect(info.dailyLevels[d4], equals(4));
    expect(info.dailyTooltips[d4], contains('Hedefe ulaşıldı ✓'));
  });

  test('habitStreakInfo limit goal stays full level 4 when within limit, decreases level as excess increases', () {
    store.clearHabitStreakCache();
    store.activities.clear();
    store.entries.clear();
    store.goals.clear();

    const actId = 103;
    store.activities[actId] = Activity(
      id: actId,
      name: 'Kahve',
      isHabit: true,
      createdAt: 1000000,
    );

    // Limit: Günde en fazla 100 g
    final goal = Goal(
      id: 202,
      name: 'Maks 100 g',
      type: 'limit',
      mode: 'amount',
      period: GoalPeriod.day,
      target: 100,
      unitId: 'g',
      startDate: 1000000,
      createdAt: 1000000,
      links: [GoalLink(activityId: actId, pct: 100)],
    );
    store.goals = [goal];

    final baseDay = dayStart(DateTime(2026, 10, 10));
    final d1 = baseDay; // 80 -> Level 4 (Limit korundu ✓)
    final d2 = baseDay.subtract(const Duration(days: 1)); // 120 -> +20% -> Level 3
    final d3 = baseDay.subtract(const Duration(days: 2)); // 145 -> +45% -> Level 2
    final d4 = baseDay.subtract(const Duration(days: 3)); // 180 -> +80% -> Level 1
    final d5 = baseDay.subtract(const Duration(days: 4)); // 250 -> +150% -> Level 0

    store.entries = [
      Entry(id: 1, activityId: actId, ts: d1.millisecondsSinceEpoch, qty: 80, value: 80, unitId: 'g'),
      Entry(id: 2, activityId: actId, ts: d2.millisecondsSinceEpoch, qty: 120, value: 120, unitId: 'g'),
      Entry(id: 3, activityId: actId, ts: d3.millisecondsSinceEpoch, qty: 145, value: 145, unitId: 'g'),
      Entry(id: 4, activityId: actId, ts: d4.millisecondsSinceEpoch, qty: 180, value: 180, unitId: 'g'),
      Entry(id: 5, activityId: actId, ts: d5.millisecondsSinceEpoch, qty: 250, value: 250, unitId: 'g'),
    ];

    final info = store.habitStreakInfo(actId);
    expect(info.dailyLevels[d1], equals(4));
    expect(info.dailyTooltips[d1], contains('Limit korundu ✓'));

    expect(info.dailyLevels[d2], equals(3));
    expect(info.dailyTooltips[d2], contains('aşıldı ⚠️'));

    expect(info.dailyLevels[d3], equals(2));
    expect(info.dailyTooltips[d3], contains('aşıldı ⚠️'));

    expect(info.dailyLevels[d4], equals(1));
    expect(info.dailyTooltips[d4], contains('aşıldı ⚠️'));

    expect(info.dailyLevels[d5], equals(0));
    expect(info.dailyTooltips[d5], contains('aşıldı ⚠️'));
  });

  testWidgets('ContributionHeatmap displays custom dailyTooltips on tap', (tester) async {
    final today = dayStart(DateTime.now());
    final dailyCounts = <DateTime, int>{today: 1};
    final dailyLevels = <DateTime, int>{today: 4};
    final dailyTooltips = <DateTime, String>{today: '1 sa 15 dk (Hedefe ulaşıldı ✓)'};

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ContributionHeatmap(
            dailyCounts: dailyCounts,
            dailyLevels: dailyLevels,
            dailyTooltips: dailyTooltips,
            weekCount: 8,
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    final expectedTooltip = '${fmtDateShort(today)}: 1 sa 15 dk (Hedefe ulaşıldı ✓)';
    final cellFinder = find.byTooltip(expectedTooltip);
    expect(cellFinder, findsOneWidget);
    await tester.tap(cellFinder);
    await tester.pumpAndSettle();

    // Verify detailed tooltip message appears in bottom row
    expect(find.textContaining('1 sa 15 dk (Hedefe ulaşıldı ✓)'), findsWidgets);
  });

  testWidgets('Goal card expands Zamana Yayılmış Görünüm and shows ContributionHeatmap', (tester) async {
    store.clearHabitStreakCache();
    store.activities.clear();
    store.goals.clear();

    const actId = 301;
    final testAct = Activity(
      id: actId,
      name: 'Yürüyüş',
      emoji: '🚶',
      isHabit: false,
      createdAt: 1000000,
    );
    store.activities[actId] = testAct;

    final goal = Goal(
      id: 401,
      name: 'Haftalık Yürüyüş',
      type: 'target',
      mode: 'count',
      period: GoalPeriod.week,
      target: 3,
      unitId: 'adet',
      startDate: 1000000,
      createdAt: 1000000,
      links: [GoalLink(activityId: actId, pct: 100)],
    );
    store.goals = [goal];

    await tester.pumpWidget(
      const MaterialApp(
        home: GoalsPage(),
      ),
    );
    await tester.pumpAndSettle();

    // Verify goal card is rendered
    expect(find.text('Haftalık Yürüyüş'), findsOneWidget);

    // Verify 3-dots menu only contains Edit and Delete (no Zinciri Kırma option)
    final popupBtn = find.byIcon(Icons.more_vert);
    expect(popupBtn, findsOneWidget);
    await tester.tap(popupBtn);
    await tester.pumpAndSettle();

    expect(find.textContaining('Zinciri Kırma\'ya'), findsNothing);
    expect(find.text('Düzenle'), findsOneWidget);
    expect(find.text('Sil'), findsOneWidget);

    // Dismiss menu
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    // Verify Zamana Yayılmış Görünüm button exists
    final expandBtn = find.byIcon(Icons.calendar_month_rounded);
    expect(expandBtn, findsOneWidget);

    // Tap to expand heatmap
    await tester.tap(expandBtn);
    await tester.pumpAndSettle();

    // Verify ContributionHeatmap is displayed inside goal card
    expect(find.byType(ContributionHeatmap), findsOneWidget);
    expect(find.textContaining('Seri'), findsWidgets);
    expect(find.textContaining('Başarı'), findsOneWidget);
  });

  test('goalStreakInfo calculates daily values, tooltips and levels for target and limit goals', () {
    store.clearHabitStreakCache();
    store.activities.clear();
    store.entries.clear();
    store.goals.clear();

    const actId = 501;
    final act = Activity(
      id: actId,
      name: 'Su',
      emoji: '💧',
      createdAt: 1000000,
    );
    store.activities[actId] = act;

    final targetGoal = Goal(
      id: 601,
      name: 'Sıvı Alımı',
      type: 'target',
      mode: 'amount',
      period: GoalPeriod.day,
      target: 2.0,
      unitId: 'l',
      startDate: DateTime.now().subtract(const Duration(days: 10)).millisecondsSinceEpoch,
      createdAt: 1000000,
      links: [GoalLink(activityId: actId, pct: 100)],
    );
    store.goals = [targetGoal];

    final now = DateTime.now();
    // 2.5L entry today -> exceeds 2.0L target -> Level 4
    store.entries = [
      Entry(
        id: 701,
        activityId: actId,
        ts: now.millisecondsSinceEpoch,
        qty: 1,
        value: 2.5,
        unitId: 'l',
      ),
    ];

    final streakInfo = store.goalStreakInfo(targetGoal);
    expect(streakInfo.isDoneToday, isTrue);
    expect(streakInfo.currentStreak, 1);
    final today = dayStart(now);
    expect(streakInfo.dailyLevels[today], 4);
    expect(streakInfo.dailyTooltips[today], contains('Hedefe ulaşıldı ✓'));
  });
}
