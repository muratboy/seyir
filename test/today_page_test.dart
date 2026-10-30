import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:takip/data/models.dart';
import 'package:takip/data/store.dart';
import 'package:takip/ui/components/today_quick_shortcuts.dart';
import 'package:takip/ui/components/today_roadmap_panel.dart';
import 'package:takip/ui/components/today_timeline.dart';
import 'package:takip/ui/today_page.dart';

void main() {
  setUp(() async {
    await initializeDateFormatting('tr_TR');
    await initializeDateFormatting('en_US');
    Intl.defaultLocale = 'tr_TR';
    store.clearHabitStreakCache();
  });

  testWidgets('TodayPage renders without overflow when navigating dates and prevents future navigation', (tester) async {
    // Set a compact screen size (e.g., standard 360x640) to strictly verify overflow safety
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final focusNotifier = ValueNotifier<int>(0);

    await tester.pumpWidget(
      MaterialApp(
        home: TodayPage(focusRequest: focusNotifier),
      ),
    );
    await tester.pumpAndSettle();

    // Verify initial "Bugün" is rendered
    expect(find.text('Bugün'), findsOneWidget);

    // Verify next day button is disabled on today
    final nextBtnFinder = find.widgetWithIcon(IconButton, Icons.chevron_right);
    expect(nextBtnFinder, findsOneWidget);
    final nextBtnWidget = tester.widget<IconButton>(nextBtnFinder);
    expect(nextBtnWidget.onPressed, isNull);

    // Tap previous day button twice to reach 2 days in the past
    final prevBtn = find.widgetWithIcon(IconButton, Icons.chevron_left);
    expect(prevBtn, findsOneWidget);

    await tester.tap(prevBtn);
    await tester.pumpAndSettle();

    await tester.tap(prevBtn);
    await tester.pumpAndSettle();

    // No RenderFlex overflow exception should be thrown
    expect(tester.takeException(), isNull);

    // Verify "Bugüne dön" button appears
    final todayBtn = find.byTooltip('Bugüne dön');
    expect(todayBtn, findsOneWidget);

    // Now next day button should be enabled
    final enabledNextBtnWidget = tester.widget<IconButton>(nextBtnFinder);
    expect(enabledNextBtnWidget.onPressed, isNotNull);

    // Tap "Bugüne dön"
    await tester.tap(todayBtn);
    await tester.pumpAndSettle();

    expect(find.text('Bugün'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('TodayPage renders multiple active roadmaps with only next pending step between shortcuts and timeline', (tester) async {
    final r1 = Roadmap(
      id: 101,
      title: 'Fitness Yolculuğu',
      emoji: '🏃',
      status: 'active',
      steps: [
        RoadmapStep(id: 1, roadmapId: 101, order: 1, title: 'Hafif Isınma', isCompleted: true),
        RoadmapStep(id: 2, roadmapId: 101, order: 2, title: '3 km Tempolu Koşu', isCompleted: false),
        RoadmapStep(id: 3, roadmapId: 101, order: 3, title: 'Bitiş Esnemesi', isCompleted: false),
      ],
    );

    final r2 = Roadmap(
      id: 102,
      title: 'Radyo Tamiri',
      emoji: '📻',
      status: 'active',
      steps: [
        RoadmapStep(id: 4, roadmapId: 102, order: 1, title: 'Kapağı Aç', isCompleted: true),
        RoadmapStep(id: 5, roadmapId: 102, order: 2, title: 'Kondansatörü Değiştir', isCompleted: false),
        RoadmapStep(id: 6, roadmapId: 102, order: 3, title: 'Anteni Test Et', isCompleted: false),
      ],
    );

    store.roadmaps = [r1, r2];

    final focusNotifier = ValueNotifier<int>(0);
    await tester.pumpWidget(
      MaterialApp(
        home: TodayPage(focusRequest: focusNotifier),
      ),
    );
    await tester.pumpAndSettle();

    // Verify TodayRoadmapPanel is present and initially collapsed by default
    expect(find.byType(TodayRoadmapPanel), findsOneWidget);
    expect(find.text('Kondansatörü Değiştir'), findsNothing);

    // Expand the panel by tapping its header
    await tester.tap(find.byType(TodayRoadmapPanel));
    await tester.pumpAndSettle();

    // Verify only the NEXT pending steps are shown for each active roadmap
    expect(find.text('3 km Tempolu Koşu'), findsOneWidget);
    expect(find.text('Kondansatörü Değiştir'), findsOneWidget);

    // Verify future steps (not yet pending) are NOT rendered
    expect(find.text('Bitiş Esnemesi'), findsNothing);
    expect(find.text('Anteni Test Et'), findsNothing);

    // Verify spatial ordering: TodayQuickShortcuts < TodayRoadmapPanel < TodayTimeline
    final shortcutsTop = tester.getTopLeft(find.byType(TodayQuickShortcuts)).dy;
    final roadmapTop = tester.getTopLeft(find.byType(TodayRoadmapPanel)).dy;
    final timelineTop = tester.getTopLeft(find.byType(TodayTimeline)).dy;

    expect(shortcutsTop < roadmapTop, isTrue, reason: 'Shortcuts must be above RoadmapPanel');
    expect(roadmapTop < timelineTop, isTrue, reason: 'RoadmapPanel must be above Timeline');
  });
}
