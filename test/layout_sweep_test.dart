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
import 'package:takip/ui/manage_page.dart';
import 'package:takip/ui/activity_merge_page.dart';
import 'package:takip/ui/components/todo_complete_sheet.dart';
import 'package:takip/ui/components/todo_quick_add_sheet.dart';
import 'package:takip/ui/components/today_routines_panel.dart';
import 'package:takip/ui/components/today_roadmap_panel.dart';

import 'support/fonts.dart';
import 'support/real_db.dart';

/// Fills the app with a bit of everything it can show: entries, goals of every period, habits, shortcuts,
/// a roadmap, both trackers and two timers.
Future<void> seedSampleData() async {
  await store.load();
  final now = DateTime.now();
  DateTime at(int daysAgo, int hour) => DateTime(now.year, now.month, now.day - daysAgo, hour);
  Measure measure(String name) => store.measures.firstWhere((m) => m.name == name);
  final glass = measure('Su bardağı');
  final minute = measure('Dakika');
  final km = measure('Kilometre');

  final su = await store.addActivity('Su', emoji: '💧', category: 'nutrition', isHabit: true);
  final ders = await store.addActivity('Ders çalışma', emoji: '📝', category: 'study');
  final kosu = await store.addActivity('Sabah koşusu', emoji: '🏃', category: 'sport', isHabit: true);
  final gitar = await store.addActivity('Gitar', emoji: '🎸', category: 'hobby');
  // Long names are what squeezed rows: a timed activity and the activity of the next roadmap step.
  final dizi = await store.addActivity('İngilizce altyazılı dizi', emoji: '📺', category: 'study', isHabit: true);
  final yuruyus = await store.addActivity('Akşam yürüyüşü (sahil yolu)', emoji: '🚶', category: 'sport');

  Future<void> add(Activity a, DateTime t, Measure m, double qty, {int? minutes}) => store.addEntry(a.id,
      measureId: m.id, qty: qty, at: t, endAt: minutes == null ? null : t.add(Duration(minutes: minutes)));

  // Today's entries lie a fixed time before now (never before midnight), so the page shows the same rows
  // whatever the time of day. With fixed clock hours a morning run had an almost empty timeline and missed
  // the rows that are hardest to fit: an entry with a time range whose activity is being timed.
  final midnight = at(0, 0);
  DateTime earlier(int minutes) {
    final t = now.subtract(Duration(minutes: minutes));
    return t.isBefore(midnight) ? midnight : t;
  }

  for (var d = 9; d >= 1; d--) {
    for (var i = 0; i < 3; i++) {
      await add(su, at(d, 8 + i * 3), glass, 1);
    }
    await add(ders, at(d, 14), minute, 50, minutes: 50);
    if (d.isEven) await add(kosu, at(d, 7), km, 5);
  }
  await add(kosu, earlier(480), km, 5);
  await add(su, earlier(360), glass, 1);
  await add(su, earlier(240), glass, 1);
  await add(ders, earlier(110), minute, 50, minutes: 50);
  await add(su, earlier(45), glass, 1);
  await store.addEntry(su.id,
      measureId: glass.id, at: now.subtract(const Duration(minutes: 2)), note: 'öğle yemeğinden sonra');

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
  await store.saveGoal(goal('Günde 2 litre su', GoalPeriod.day, su, unit: 'l', target: 2));
  await store.saveGoal(goal('Haftada 15 km koşu', GoalPeriod.week, kosu, unit: 'km', target: 15));
  await store.saveGoal(goal('Ayda 30 saat ders', GoalPeriod.month, ders, unit: 'sa', target: 30));
  await store.saveGoal(goal('Ders limiti', GoalPeriod.day, ders, type: 'limit'));
  await store.saveGoal(goal('Sınava kadar 1500 dakika çalışma', GoalPeriod.total, ders, unit: 'dk', target: 1500));

  await store.saveQuickItem(QuickItem(id: 0, activityId: su.id, kind: 'shortcut', measureId: glass.id, createdAt: ms));
  await store.saveQuickItem(QuickItem(id: 0, activityId: kosu.id, kind: 'todo', createdAt: ms));

  final roadmap = await store.createRoadmap(RoadmapParser.parse('''{"title": "Flutter ile uygulama geliştirme",
    "description": "Sıfırdan yayınlanmış bir uygulamaya", "category": "Yazılım", "emoji": "🚀", "steps": [
    {"title": "Dart temelleri", "description": "Tipler, koleksiyonlar, async"},
    {"title": "Widget ağacı ve durum yönetimini öğren", "type": "goal", "target": 20, "unit": "saat"},
    {"title": "Play Store yayını"}]}''')!);
  await store.setRoadmapStatus(roadmap.id, 'active');
  final steps = store.roadmaps.single.steps;
  await store.toggleRoadmapStep(steps[0].id, completed: true);
  await store.setRoadmapStepActivity(steps[1].id, dizi.id);
  await store.setRoadmapStepActivity(steps[2].id, ders.id);

  await store.setSleepTrackerEnabled(true);
  // With reminders on the notification settings show their interval and time rows too.
  await store.setWaterReminder(enabled: true);
  await store.setDailySummaryReminder(enabled: true);
  store.stepTrackerEnabled = true;
  store.todaySteps = 6240;
  store.handlePedometerError('no sensor in tests');

  await store.startTimer(ders.id, mode: 'pomodoro', targetMs: 25 * 60000, note: 'Türev');
  final stopwatch = await store.startTimer(gitar.id);
  await store.pauseTimer(stopwatch.id);
  await store.startTimer(yuruyus.id, mode: 'countdown', targetMs: 45 * 60000);

  final yesterdayStr = DateFormat('yyyy-MM-dd').format(now.subtract(const Duration(days: 1)));
  final todayStr = DateFormat('yyyy-MM-dd').format(now);
  await store.createTodo(
    Todo(
      id: 0,
      title: 'Dün yapılması gereken önemli proje teslimi ve sunum hazırlığı',
      createdAt: ms - 86400000 * 2,
      dueDate: yesterdayStr,
    ),
  );
  await store.createTodo(
    Todo(
      id: 0,
      title: 'Çok uzun başlık: haftalık toplantı notlarını düzenle, sunum slaytlarını hazırla ve ekip liderine e-posta gönder',
      createdAt: ms - 3600000,
      dueDate: todayStr,
      targetAmount: 50,
    ),
    activityIds: [ders.id],
  );
  await store.createTodo(
    Todo(
      id: 0,
      title: 'Su içme görevi',
      createdAt: ms - 1800000,
      dueDate: todayStr,
    ),
    activityIds: [su.id],
  );
}

/// Texts that break inside a word, the way "Pomodor/o" or "Siste/m" did on a small phone with large text:
/// a sign of a box too narrow for its text. Each is described with its width.
List<String> wordsBrokenAcrossLines() {
  final found = <String>[];
  bool letter(String c) => RegExp(r'[\p{L}\p{N}]', unicode: true).hasMatch(c);
  void visit(RenderObject o) {
    if (o is RenderParagraph && o.hasSize) {
      final text = o.text.toPlainText(includeSemanticsLabels: false);
      final tops = <double>[];
      for (final box in o.getBoxesForSelection(TextSelection(baseOffset: 0, extentOffset: text.length))) {
        if (tops.every((t) => (t - box.top).abs() > 4)) tops.add(box.top);
      }
      tops.sort();
      for (final top in tops.skip(1)) {
        final at = o.getPositionForOffset(Offset(0.5, top + 2)).offset;
        if (at > 0 && at < text.length && letter(text[at - 1]) && letter(text[at])) {
          found.add('"$text" (${o.size.width.round()} px)');
          break;
        }
      }
    }
    o.visitChildren(visit);
  }

  for (final view in RendererBinding.instance.renderViews) {
    visit(view);
  }
  return found;
}

void main() {
  useRealDatabase();

  setUpAll(() async {
    await loadRealFont();
    await initializeDateFormatting('tr_TR');
    await initializeDateFormatting('en_US');
    Intl.defaultLocale = 'tr_TR';
    // The home screen widget plugin is asked about the launch when the app shell starts.
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final name in ['home_widget', 'home_widget/updates']) {
      messenger.setMockMethodCallHandler(MethodChannel(name), (call) async => null);
    }
  });

  for (final lang in AppLanguage.values) {
    for (final scale in [1.0, 1.3]) {
      testWidgets('nothing overflows on a 360 dp phone (${lang.name}, text x$scale)', (tester) async {
        tester.view.physicalSize = const Size(360, 640);
        tester.view.devicePixelRatio = 1.0;
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

        await tester.runAsync(() async {
          await seedSampleData();
          await store.setLanguage(lang);
        });
        final s = strings.value;
        final tr = lang == AppLanguage.tr;

        await tester.pumpWidget(const TakipApp());
        await tester.pump(const Duration(milliseconds: 500));

        Future<void> expectClean(String where) async {
          await tester.pump(const Duration(milliseconds: 300));
          expect(tester.takeException(), isNull, reason: where);
          expect(wordsBrokenAcrossLines(), isEmpty, reason: where);
        }

        Future<void> scrollThrough(String where, {int steps = 5}) async {
          for (var i = 0; i < steps; i++) {
            await tester.dragFrom(const Offset(180, 300), const Offset(0, -380));
            await expectClean('$where, scrolled ${i + 1}x');
          }
        }

        Future<void> openTab(String label) async {
          await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text(label)));
          await expectClean(label);
        }

        Future<void> scrollToTop() async {
          for (var i = 0; i < 8; i++) {
            await tester.dragFrom(const Offset(180, 200), const Offset(0, 380));
            await tester.pump(const Duration(milliseconds: 200));
          }
        }

        Future<void> back() async {
          tester.state<NavigatorState>(find.byType(Navigator).first).pop();
          await tester.pump(const Duration(milliseconds: 400));
          await tester.pump(const Duration(milliseconds: 400));
        }

        // Today: compact and expanded timers, the composer with its options, every panel (hem kapalı hem açık).
        await expectClean('today, panels collapsed');

        // Panelleri açarak yerleşim kontrolü
        final routinesHeader = find.byType(TodayRoutinesPanel);
        if (routinesHeader.evaluate().isNotEmpty) {
          await tester.ensureVisible(routinesHeader);
          await tester.tap(routinesHeader, warnIfMissed: false);
          await tester.pump(const Duration(milliseconds: 300));
        }
        final roadmapHeader = find.byType(TodayRoadmapPanel);
        if (roadmapHeader.evaluate().isNotEmpty) {
          await tester.ensureVisible(roadmapHeader);
          await tester.tap(roadmapHeader, warnIfMissed: false);
          await tester.pump(const Duration(milliseconds: 300));
        }
        await expectClean('today, panels expanded');

        // Tek satırlık boş kart kontrolü
        final savedTodos = List<Todo>.from(store.todos);
        store.todos.clear();
        await tester.pump(const Duration(milliseconds: 200));
        await expectClean('today, empty todos card');
        store.todos.addAll(savedTodos);
        await tester.pump(const Duration(milliseconds: 200));

        await tester.tap(find.text('Gitar').first);
        await expectClean('today, timer expanded');
        await tester.enterText(find.byType(TextField).last, 'su');
        await expectClean('today, composer suggestions');
        await tester.tap(find.widgetWithText(ActionChip, 'Su'));
        await expectClean('today, composer options');
        await tester.tap(find.byTooltip(tr ? 'Temizle' : 'Clear'));
        await scrollThrough('today', steps: 6);

        // Arama sayfası (TakipSearchDelegate)
        await tester.tap(find.byIcon(Icons.search));
        await tester.pump(const Duration(milliseconds: 400));
        await expectClean('search page');
        await tester.enterText(find.byType(TextField).last, 'su');
        await tester.pump(const Duration(milliseconds: 400));
        await expectClean('search results');
        await scrollThrough('search results', steps: 2);
        await tester.tap(find.byTooltip(tr ? 'Geri' : 'Back').first);
        await tester.pump(const Duration(milliseconds: 400));

        // Goals, todos, habits and roadmaps.
        await openTab(s.tabGoals);
        await tester.tap(find.textContaining(tr ? 'Isı Haritası' : 'Heatmap').first);
        await expectClean('goals, heatmap open');
        await scrollThrough('goals', steps: 6);

        // Yapılacaklar sekmesi (Tam liste)
        final todosTabFinder = find.textContaining(tr ? 'Yapılacaklar (' : 'To-dos (');
        await tester.ensureVisible(todosTabFinder);
        await tester.pumpAndSettle();
        await tester.tap(todosTabFinder);
        await expectClean('todos tab, full list');
        await scrollThrough('todos tab', steps: 3);

        // Bir yapılacağa dokunarak Düzenleme sayfasını test et
        await tester.tap(find.textContaining('Çok uzun başlık').first);
        await tester.pump(const Duration(milliseconds: 400));
        await expectClean('todo edit page');
        await scrollThrough('todo edit page', steps: 2);
        await back();

        final habitsTabFinder = find.textContaining(tr ? 'Zinciri Kırma (' : 'Habits (');
        await tester.ensureVisible(habitsTabFinder);
        await tester.pumpAndSettle();
        await tester.tap(habitsTabFinder);
        await expectClean('habits');
        await scrollThrough('habits', steps: 3);

        final roadmapsTabFinder = find.textContaining(tr ? 'Yol Haritası (' : 'Roadmaps (');
        await tester.ensureVisible(roadmapsTabFinder);
        await tester.pumpAndSettle();
        await tester.tap(roadmapsTabFinder);
        await expectClean('roadmaps');
        await tester.tap(find.text('Flutter ile uygulama geliştirme'));
        await expectClean('roadmap detail');
        await scrollThrough('roadmap detail', steps: 2);
        await back();

        // Adding a roadmap: the options, a shared link, the AI template.
        Future<void> closeDialog() async {
          tester.state<NavigatorState>(find.byType(Navigator).first).pop();
          await tester.pump(const Duration(milliseconds: 400));
          await tester.pump(const Duration(milliseconds: 400));
        }

        Future<void> settleSheet() async {
          await tester.pump(const Duration(milliseconds: 400));
          await tester.pump(const Duration(milliseconds: 400));
        }

        await tester.tap(find.byType(FloatingActionButton));
        await settleSheet();
        await expectClean('add roadmap options');
        await tester.tap(find.text(tr ? 'Bağlantıdan Ekle' : 'Add from a Link'));
        await settleSheet();
        await expectClean('roadmap from a link');
        await closeDialog();
        await tester.tap(find.byType(FloatingActionButton));
        await settleSheet();
        await tester.tap(find.textContaining(tr ? 'Yapay Zekâ Kalıbıyla' : 'Import with AI'));
        await settleSheet();
        await expectClean('roadmap from the AI template');
        await closeDialog();

        // Hızlı Todo ekleme sheet'i
        final navContext = tester.element(find.byType(Navigator).first);
        TodoQuickAddSheet.show(navContext);
        await settleSheet();
        await expectClean('todo quick add sheet');
        await closeDialog();

        // Tamamlama önizlemesi sheet'i
        final sampleLinkedTodo = store.todos.firstWhere((t) => t.isLinked);
        TodoCompleteSheet.show(navContext, sampleLinkedTodo);
        await settleSheet();
        await expectClean('todo complete sheet');
        await closeDialog();

        // Statistics in every range.
        await openTab(s.tabStats);
        await scrollThrough('stats, week');
        for (final range in [s.viewDay, s.viewMonth, s.viewYear]) {
          await scrollToTop();
          await tester.tap(find.text(range).first);
          await expectClean('stats, $range');
          await scrollThrough('stats, $range');
        }

        // One activity: its summary and chart in its own unit, the calendar, the measures.
        await scrollToTop();
        await tester.tap(find.byType(FilterChip).at(1));
        await expectClean('stats, one activity');
        await tester.ensureVisible(find.byType(ChoiceChip).first);
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(find.byType(ChoiceChip).first);
        await expectClean('stats, one activity by entries');
        await scrollThrough('stats, one activity');

        // Settings, and the activity list with the goals each activity counts for.
        await openTab(s.tabSettings);
        await tester.tap(find.text(s.activitiesManagement));
        await expectClean('activities');
        await scrollThrough('activities', steps: 2);

        // ActivityMergePage (boş)
        await tester.tap(find.byIcon(Icons.call_merge_rounded));
        await tester.pump(const Duration(milliseconds: 400));
        await expectClean('activity merge page');
        await scrollThrough('activity merge page', steps: 2);
        await back();

        // ActivityPage
        await tester.tap(find.text('Su').first);
        await tester.pump(const Duration(milliseconds: 400));
        await expectClean('activity page');
        await scrollThrough('activity page', steps: 3);
        await back();

        // ActivityMergePage (dolu - etki kartı ve uyarılar)
        final navCtx = tester.element(find.byType(Navigator).first);
        Navigator.push(
          navCtx,
          MaterialPageRoute(
            builder: (_) => ActivityMergePage(
              initialFromActivity: store.activities.values.first,
              initialIntoActivity: store.activities.values.last,
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 400));
        await expectClean('activity merge page populated');
        await scrollThrough('activity merge page populated', steps: 3);
        await back();

        await back();
        await scrollThrough('settings', steps: 3);
        final settingsList = find.descendant(of: find.byType(ManagePage), matching: find.byType(ListView));
        for (final page in [
          s.sectionNotificationsReminders,
          s.sectionHealthTracking,
          s.sectionBackupReports,
          tr ? 'Yapay Zekâ & API (BYOK)' : 'AI & API Key (BYOK)',
        ]) {
          // Coming back from a page leaves the list where it was; the next row may be out of sight.
          await tester.drag(settingsList, const Offset(0, 3000));
          await tester.pump(const Duration(milliseconds: 300));
          await tester.dragUntilVisible(find.text(page), settingsList, const Offset(0, -150));
          // To the top of the list: at its bottom edge the row lies under the navigation bar.
          await tester.ensureVisible(find.text(page));
          await tester.pump(const Duration(milliseconds: 300));
          await tester.tap(find.text(page));
          await tester.pump(const Duration(milliseconds: 400));
          await expectClean(page);
          await scrollThrough(page, steps: 4);
          await back();
        }

        // Dispose the pages (timer cards tick) and stop the store's own ticker before the test ends.
        await tester.pumpWidget(const SizedBox());
        await tester.runAsync(() async {
          for (final t in List.of(store.activeTimers)) {
            await store.cancelTimer(t.id);
          }
          await store.setLanguage(AppLanguage.tr);
        });
        await tester.pump(const Duration(seconds: 6));
      });
    }
  }
}
