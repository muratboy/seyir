import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:takip/data/models.dart';
import 'package:takip/data/store.dart';
import 'package:takip/logic/l10n.dart';
import 'package:takip/main.dart';
import 'package:takip/services/roadmap_parser.dart';
import 'package:takip/ui/activity_page.dart';
import 'package:takip/ui/components/goal_edit_dialog.dart';
import 'package:takip/ui/components/todo_quick_add_sheet.dart';
import 'package:takip/ui/components/today_timeline.dart';
import 'package:takip/ui/manage_page.dart';

import 'support/fonts.dart';
import 'support/real_db.dart';

Future<void> seedEnglishData() async {
  await store.load();
  final now = DateTime.now();
  DateTime at(int daysAgo, int hour) => DateTime(now.year, now.month, now.day - daysAgo, hour);

  final water = await store.addActivity('Water', emoji: '💧', category: 'nutrition', isHabit: true);
  final study = await store.addActivity('Study', emoji: '📝', category: 'study');
  final run = await store.addActivity('Morning Run', emoji: '🏃', category: 'sport', isHabit: true);
  final guitar = await store.addActivity('Guitar', emoji: '🎸', category: 'hobby');
  final walk = await store.addActivity('Evening Walk', emoji: '🚶', category: 'sport');

  // Besin değeri/özelliği olan aktivite
  final proteinBar = await store.addActivity('Protein Bar', emoji: '🍫', category: 'nutrition');
  await store.saveActivityProperty(
    ActivityProperty(
      id: 0,
      activityId: proteinBar.id,
      name: 'Protein',
      value: 20,
      unitId: 'g',
      perQty: 1,
      perUnitId: 'adet',
    ),
  );

  // Ölçü adlarını İngilizce örnek veri olarak güncelle
  for (final m in List.of(store.measures)) {
    final enName = switch (m.name) {
      'Su bardağı' => 'Glass',
      'Çay bardağı' => 'Tea glass',
      'Fincan' => 'Cup',
      'Kupa' => 'Mug',
      'Şişe' => 'Bottle',
      'Kase' => 'Bowl',
      'Litre' => 'Liter',
      'Mililitre' => 'Milliliter',
      'Dakika' => 'Minute',
      'Saat' => 'Hour',
      'Saniye' => 'Second',
      'Adet' => 'Piece',
      'Gram' => 'Gram',
      'Kilogram' => 'Kilogram',
      'Metre' => 'Meter',
      'Kilometre' => 'Kilometer',
      'Kalori' => 'Calorie',
      _ => m.name,
    };
    m.name = enName;
    await store.updateMeasure(m);
  }

  // Ölçüler
  Measure measure(String name) => store.measures.firstWhere((m) => m.name == name);
  final glass = measure('Glass');
  final minute = measure('Minute');
  final km = measure('Kilometer');

  Future<void> add(Activity a, DateTime t, Measure m, double qty, {int? minutes, String? note}) =>
      store.addEntry(a.id,
          measureId: m.id,
          qty: qty,
          at: t,
          endAt: minutes == null ? null : t.add(Duration(minutes: minutes)),
          note: note);

  for (var d = 5; d >= 1; d--) {
    await add(water, at(d, 8), glass, 1);
    await add(study, at(d, 14), minute, 50, minutes: 50);
    if (d.isEven) await add(run, at(d, 7), km, 5);
  }

  await add(run, at(0, 7), km, 5);
  await add(water, at(0, 9), glass, 1);
  await add(study, at(0, 13), minute, 50, minutes: 50);
  await add(proteinBar, at(0, 15), glass, 1, note: 'after lunch');

  final from = at(9, 0).millisecondsSinceEpoch;
  final ms = now.millisecondsSinceEpoch;

  Goal goal(String name, GoalPeriod period, Activity a, {String type = 'target', String? unit, double target = 3}) =>
      Goal(
        id: 0,
        name: name,
        type: type,
        mode: unit == null ? 'count' : 'amount',
        unitId: unit,
        target: target,
        period: period,
        startDate: from,
        endDate: period == GoalPeriod.total ? at(-20, 0).millisecondsSinceEpoch : null,
        createdAt: ms,
        links: [GoalLink(activityId: a.id, pct: 100)],
      );

  await store.saveGoal(goal('Daily 2 liters water', GoalPeriod.day, water, unit: 'l', target: 2));
  await store.saveGoal(goal('Weekly 15 km run', GoalPeriod.week, run, unit: 'km', target: 15));
  await store.saveGoal(goal('Monthly 30 hours study', GoalPeriod.month, study, unit: 'sa', target: 30));
  await store.saveGoal(goal('Study limit', GoalPeriod.day, study, type: 'limit'));

  // Özellikli hedef
  final proteinGoal = Goal(
    id: 0,
    name: 'Daily 50g protein',
    type: 'target',
    mode: 'amount',
    unitId: 'g',
    target: 50,
    period: GoalPeriod.day,
    startDate: from,
    createdAt: ms,
    links: [
      GoalLink(
        activityId: proteinBar.id,
        pct: 100,
        propertyId: store.activityProperties(proteinBar.id).firstOrNull?.id,
      ),
    ],
  );
  await store.saveGoal(proteinGoal);

  await store.saveQuickItem(QuickItem(id: 0, activityId: water.id, kind: 'shortcut', measureId: glass.id, createdAt: ms));
  await store.saveQuickItem(QuickItem(id: 0, activityId: run.id, kind: 'todo', createdAt: ms));

  final roadmap = await store.createRoadmap(RoadmapParser.parse('''{
    "title": "Flutter Development Roadmap",
    "description": "From beginner to publishing an app",
    "category": "Development",
    "emoji": "🚀",
    "steps": [
      {"title": "Dart Fundamentals", "description": "Types, collections, async"},
      {"title": "Learn Widget Tree", "type": "goal", "target": 20, "unit": "hours"},
      {"title": "Publish to App Store"}
    ]
  }''')!);
  await store.setRoadmapStatus(roadmap.id, 'active');
  final steps = store.roadmaps.single.steps;
  await store.toggleRoadmapStep(steps[0].id, completed: true);
  await store.setRoadmapStepActivity(steps[1].id, study.id);

  await store.setSleepTrackerEnabled(true);
  await store.setWaterReminder(enabled: true);
  await store.setDailySummaryReminder(enabled: true);
  store.stepTrackerEnabled = true;
  store.todaySteps = 6240;
  store.handlePedometerError('no sensor in tests');

  await store.startTimer(study.id, mode: 'pomodoro', targetMs: 25 * 60000, note: 'Calculus');
  final stopwatch = await store.startTimer(guitar.id);
  await store.pauseTimer(stopwatch.id);
  await store.startTimer(walk.id, mode: 'countdown', targetMs: 45 * 60000);

  final yesterdayStr = DateFormat('yyyy-MM-dd').format(now.subtract(const Duration(days: 1)));
  final todayStr = DateFormat('yyyy-MM-dd').format(now);
  await store.createTodo(
    Todo(
      id: 0,
      title: 'Project submission due yesterday',
      createdAt: at(2, 10).millisecondsSinceEpoch,
      dueDate: yesterdayStr,
    ),
  );
  await store.createTodo(
    Todo(
      id: 0,
      title: 'Prepare presentation slides for weekly team sync',
      createdAt: at(0, 14).millisecondsSinceEpoch,
      dueDate: todayStr,
      targetAmount: 50,
    ),
    activityIds: [study.id],
  );
}

final _trLettersPattern = RegExp(r'[çğıöşüÇĞİÖŞÜ]');
final _trKeywordsPattern = RegExp(
  r'\b(adet|kaydet|sil|ekle|tamam|yok|hedef|toplam|yeni|evet|bitti|geri|kapat|tekrar|bugun|bugün|hafta|ay|gun|gün)\b',
  caseSensitive: false,
);

List<String> findTurkishTextsOnScreen() {
  final issues = <String>{};
  void visit(RenderObject obj) {
    if (obj is RenderParagraph && obj.hasSize) {
      final text = obj.text.toPlainText(includeSemanticsLabels: false);
      if (text.isNotEmpty) {
        // Dil seçicide dil adları kullanıcının dili tanıyabilmesi için kendi dilinde tutulur (Türkçe / English).
        if (text.trim() == 'Türkçe') return;
        if (_trLettersPattern.hasMatch(text) || _trKeywordsPattern.hasMatch(text)) {
          issues.add(text);
        }
      }
    }
    obj.visitChildren(visit);
  }

  for (final view in RendererBinding.instance.renderViews) {
    visit(view);
  }
  return issues.toList()..sort();
}

void main() {
  useRealDatabase();

  setUpAll(() async {
    await loadRealFont();
    await initializeDateFormatting('tr_TR');
    await initializeDateFormatting('en_US');
    Intl.defaultLocale = 'en_US';
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final name in ['home_widget', 'home_widget/updates']) {
      messenger.setMockMethodCallHandler(MethodChannel(name), (call) async => null);
    }
  });

  testWidgets('verify English locale contains no Turkish text in UI', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.runAsync(() async {
      await seedEnglishData();
      await store.setLanguage(AppLanguage.en);
    });

    final screenIssues = <String, List<String>>{};

    void checkScreen(String screenName) {
      final found = findTurkishTextsOnScreen();
      if (found.isNotEmpty) {
        screenIssues[screenName] = found;
      }
    }

    await tester.pumpWidget(const TakipApp());
    await tester.pump(const Duration(milliseconds: 500));

    // 1. Journal (TodayPage)
    // Kutu boş
    checkScreen('Journal - Empty Composer');

    // Kutu dolu / önizlemeli
    await tester.enterText(
      find.byType(TextField).last,
      'yesterday 500 ml water and 2 hours study and tomorrow dentist',
    );
    await tester.pump(const Duration(milliseconds: 300));
    checkScreen('Journal - Multi Item Preview');
    await tester.tap(find.byTooltip('Clear'));
    await tester.pump(const Duration(milliseconds: 300));

    // Zaman çizelgesi dolu (scroll)
    for (var i = 0; i < 4; i++) {
      await tester.dragFrom(const Offset(180, 300), const Offset(0, -300));
      await tester.pump(const Duration(milliseconds: 200));
      checkScreen('Journal - Timeline scroll $i');
    }

    // 2. Goals (GoalsPage)
    final s = strings.value;
    await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text(s.tabGoals)));
    await tester.pump(const Duration(milliseconds: 400));
    checkScreen('Goals - Main');

    // Heatmap aç
    final heatmapFinder = find.textContaining('Heatmap');
    if (heatmapFinder.evaluate().isNotEmpty) {
      await tester.tap(heatmapFinder.first);
      await tester.pump(const Duration(milliseconds: 300));
      checkScreen('Goals - Heatmap Open');
    }

    // 3. To-dos (TodosTab)
    final todosTabFinder = find.textContaining('To-dos (');
    if (todosTabFinder.evaluate().isNotEmpty) {
      await tester.tap(todosTabFinder);
      await tester.pump(const Duration(milliseconds: 400));
      checkScreen('To-dos - List');
    }

    // 4. Yol haritası sekmesi (RoadmapsTab)
    final roadmapsTabFinder = find.textContaining('Roadmaps (');
    if (roadmapsTabFinder.evaluate().isNotEmpty) {
      await tester.tap(roadmapsTabFinder);
      await tester.pump(const Duration(milliseconds: 400));
      checkScreen('Roadmaps - List');
    }

    // 5. Stats (StatsPage)
    await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text(s.tabStats)));
    await tester.pump(const Duration(milliseconds: 400));
    checkScreen('Stats - Week');

    for (final range in [s.viewDay, s.viewMonth, s.viewYear]) {
      await tester.tap(find.text(range).first);
      await tester.pump(const Duration(milliseconds: 300));
      checkScreen('Stats - $range');
    }

    // Stats - Tek aktivite
    final filterChip = find.byType(FilterChip);
    if (filterChip.evaluate().length > 1) {
      await tester.tap(filterChip.at(1));
      await tester.pump(const Duration(milliseconds: 300));
      checkScreen('Stats - One Activity');
    }

    // 6. Settings (ManagePage) ve alt sayfalar
    await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text(s.tabSettings)));
    await tester.pump(const Duration(milliseconds: 400));
    checkScreen('Settings - Main');

    final settingsList = find.descendant(of: find.byType(ManagePage), matching: find.byType(ListView));

    Future<void> back() async {
      tester.state<NavigatorState>(find.byType(Navigator).first).pop();
      await tester.pump(const Duration(milliseconds: 400));
    }

    for (final page in [
      s.activitiesManagement,
      s.sectionNotificationsReminders,
      s.sectionHealthTracking,
      s.sectionBackupReports,
      'AI & API Key (BYOK)',
    ]) {
      await tester.drag(settingsList, const Offset(0, 3000));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.dragUntilVisible(find.text(page), settingsList, const Offset(0, -150));
      await tester.ensureVisible(find.text(page));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(find.text(page));
      await tester.pump(const Duration(milliseconds: 400));
      checkScreen('Settings - $page');
      await back();
    }

    // 7. ActivityPage (özellikli aktiviteyle)
    final proteinBarAct = store.activities.values.firstWhere((a) => a.name == 'Protein Bar');
    final navContext = tester.element(find.byType(Navigator).first);
    Navigator.push(navContext, MaterialPageRoute(builder: (_) => ActivityPage(activity: proteinBarAct)));
    await tester.pump(const Duration(milliseconds: 400));
    checkScreen('ActivityPage - Protein Bar');
    await back();

    // 8. GoalEditDialog (özellikli aktiviteyle)
    final proteinGoal = store.goals.firstWhere((g) => g.name.contains('protein'));
    GoalEditDialog.show(navContext, existing: proteinGoal);
    await tester.pump(const Duration(milliseconds: 400));
    checkScreen('GoalEditDialog');
    await back();

    // 9. Kayıt düzenleme sayfası (Entry edit sheet)
    final sampleEntry = store.entries.first;
    TodayTimeline.showEntryEditSheet(navContext, sampleEntry);
    await tester.pump(const Duration(milliseconds: 400));
    checkScreen('EntryEditSheet');
    await back();

    // 10. Hızlı yapılacak ekleme (TodoQuickAddSheet)
    TodoQuickAddSheet.show(navContext);
    await tester.pump(const Duration(milliseconds: 400));
    checkScreen('TodoQuickAddSheet');
    await back();

    // Clean up
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() async {
      for (final t in List.of(store.activeTimers)) {
        await store.cancelTimer(t.id);
      }
      await store.setLanguage(AppLanguage.tr);
    });
    await tester.pump(const Duration(seconds: 6));

    if (screenIssues.isNotEmpty) {
      final msg = StringBuffer('Turkish text found on screens in English locale:\n');
      for (final entry in screenIssues.entries) {
        msg.writeln('  [${entry.key}]:');
        for (final text in entry.value) {
          msg.writeln('    - "$text"');
        }
      }
      fail(msg.toString());
    }
  });
}
