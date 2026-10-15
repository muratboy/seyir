import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:takip/data/models.dart';
import 'package:takip/data/store.dart';
import 'package:takip/ui/components/active_timer_card.dart';
import 'package:takip/ui/components/today_timeline.dart';
import 'package:takip/ui/today_page.dart';

import 'support/fonts.dart';

void main() {
  setUpAll(() async {
    await loadRealFont();
    await initializeDateFormatting('tr_TR');
    Intl.defaultLocale = 'tr_TR';
  });

  testWidgets('the timer card fits a 360 dp wide phone in every mode', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    store.activities[1] = Activity(id: 1, name: 'Gitar', emoji: '🎸', createdAt: 0);
    addTearDown(() => store.activities.remove(1));
    final now = DateTime.now().millisecondsSinceEpoch;

    for (final mode in ['stopwatch', 'countdown', 'pomodoro']) {
      // Paused, so the card does not start its ticker.
      final timer = ActiveTimer(
        id: 1,
        activityId: 1,
        startTs: now - 60000,
        accumulatedMs: 60000,
        lastResumeTs: null,
        isRunning: false,
        mode: mode,
        targetMs: mode == 'stopwatch' ? 0 : 25 * 60000,
        isCollapsed: false,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: ActiveTimersSection(timers: [timer])),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull, reason: 'mode: $mode');
    }
  });

  testWidgets('the composer stays in place while the Today page scrolls', (tester) async {
    tester.view.physicalSize = const Size(412, 892);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // Enough entries today to make the page scroll.
    final midnight = DateTime.now();
    final dayStartMs = DateTime(midnight.year, midnight.month, midnight.day).millisecondsSinceEpoch;
    store.activities[1] = Activity(id: 1, name: 'Su', emoji: '💧', createdAt: 0);
    store.entries = [
      for (var i = 0; i < 30; i++) Entry(id: i + 1, activityId: 1, ts: dayStartMs + i * 1000, qty: 1),
    ];
    addTearDown(() {
      store.entries = [];
      store.activities.remove(1);
    });

    await tester.pumpWidget(MaterialApp(home: TodayPage(focusRequest: ValueNotifier<int>(0))));
    await tester.pump();

    final composer = find.byType(TextField);
    final timeline = find.byType(TodayTimeline);
    final composerBefore = tester.getTopLeft(composer);
    final timelineBefore = tester.getTopLeft(timeline);

    await tester.drag(find.byType(SingleChildScrollView).first, const Offset(0, -500));
    await tester.pump();

    expect(tester.getTopLeft(timeline).dy, lessThan(timelineBefore.dy), reason: 'the content scrolled');
    expect(tester.getTopLeft(composer), composerBefore, reason: 'the composer is pinned below the content');
    expect(tester.takeException(), isNull);
  });

  testWidgets('the composer preview fits a 360 dp wide phone, with and without the switch', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    store.activities[1] = Activity(id: 1, name: 'Ders çalışma', emoji: '📚', createdAt: 0);
    addTearDown(() => store.activities.remove(1));

    await tester.pumpWidget(MaterialApp(home: TodayPage(focusRequest: ValueNotifier<int>(0))));
    await tester.pump();
    final preview = find.byKey(const Key('composer-preview'));

    // The longest sentences: a new activity with a timer, and the switch next to it.
    for (final text in [
      'ders çalışma için 50 dk pomodoro başlatır mısın',
      'haftalık toplantı hazırlığı için 45 dk geri sayım',
      'ders çalışma tut',
    ]) {
      await tester.enterText(find.byType(TextField).last, text);
      await tester.pump();
      expect(preview, findsOneWidget, reason: text);
      expect(find.text('Kayıt olarak ekle'), findsOneWidget, reason: text);
      expect(tester.takeException(), isNull, reason: text);
    }

    await tester.tap(find.text('Kayıt olarak ekle'));
    await tester.pump();
    expect(find.text('Sayaç başlat'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // The whole sentence stays readable: its end says what will happen.
    expect(tester.getSize(preview).width, greaterThan(100));
  });
}
