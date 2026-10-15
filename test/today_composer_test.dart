import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:takip/data/store.dart';
import 'package:takip/ui/today_page.dart';

import 'support/real_db.dart';

/// Store calls started by a tap await real database I/O, which the fake clock of a widget test never
/// advances: alternate between real time and frames until they have finished.
Future<void> settleStore(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> pumpToday(WidgetTester tester) async {
  await tester.runAsync(() => store.load());
  await tester.pumpWidget(MaterialApp(home: TodayPage(focusRequest: ValueNotifier<int>(0))));
  await tester.pump();
}

/// Ends a test: disposes the page (its timer cards tick), stops the store's ticker and lets snack bars
/// expire. The binding checks for pending timers before tear-downs run, so this is called by the test.
Future<void> finish(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.runAsync(() async {
    for (final t in List.of(store.activeTimers)) {
      await store.cancelTimer(t.id);
    }
  });
  await tester.pump(const Duration(seconds: 6));
}

// The badge of a running stopwatch card carries the same text; the sheet is the last one in the tree.
Finder get stopwatchOption => find.text('⏱️ Kronometre').last;
// The note field of the options panel sits above the input row, so the composer is the last text field.
Finder get composerField => find.byType(TextField).last;
// The button shows a check mark for an entry and a play arrow for a timer.
Finder get submitButton => find.byKey(const Key('composer-submit'));
String? previewOf(WidgetTester tester) => tester.widget<Text>(find.byKey(const Key('composer-preview'))).data;
// The header of the active timers card uses the same icon, so the button is found by its tooltip.
Finder get timerButton => find.byTooltip('Kronometre Başlat').first;

void main() {
  useRealDatabase();

  setUpAll(() async {
    await initializeDateFormatting('tr_TR');
    Intl.defaultLocale = 'tr_TR';
  });

  testWidgets('a countdown typed into the composer starts a countdown instead of adding an entry', (tester) async {
    await pumpToday(tester);

    await tester.enterText(composerField, 'geri sayım 10 dakika çay demleme');
    await tester.pump();
    expect(previewOf(tester), 'Çay demleme (yeni aktivite): 10 dk geri sayım başlayacak');
    expect(tester.widget<IconButton>(submitButton).tooltip, 'Sayacı Başlat');

    // A timer has no measure or amount to choose: one tap starts it.
    await tester.tap(submitButton);
    await settleStore(tester);

    expect(store.entries, isEmpty);
    final timer = store.activeTimers.single;
    expect(timer.mode, 'countdown');
    expect(timer.targetMs, 10 * 60000);
    expect(store.activity(timer.activityId).name, 'Çay demleme');
    await finish(tester);
  });

  testWidgets('the preview says what will be saved, and the options show the same amount', (tester) async {
    await tester.runAsync(() async {
      await store.load();
      await store.addActivity('Su', emoji: '💧');
    });
    await pumpToday(tester);

    await tester.enterText(composerField, '2 bardak su');
    await tester.pump();
    expect(previewOf(tester), '💧 Su: 2 Su bardağı · 400 ml eklenecek');
    expect(tester.widget<IconButton>(submitButton).tooltip, 'Kaydet');
    expect(find.textContaining('Yeni Olarak Ekle'), findsNothing, reason: 'the text names the activity "Su"');

    await tester.tap(submitButton); // opens the options
    await tester.pump();
    final selectedMeasure = find.byWidgetPredicate((w) => w is ChoiceChip && w.selected);
    expect(
      find.descendant(of: selectedMeasure, matching: find.textContaining('Su bardağı', findRichText: true)),
      findsOneWidget,
    );
    await tester.tap(submitButton);
    await settleStore(tester);

    final entry = store.entries.single;
    expect(store.measureById(entry.measureId)?.name, 'Su bardağı');
    expect(entry.qty, 2);

    // A name nothing matches is announced as a new activity before it is created.
    await tester.enterText(composerField, 'yüzme');
    await tester.pump();
    expect(previewOf(tester), 'Yüzme (yeni aktivite) eklenecek');
    expect(find.textContaining('Yeni Olarak Ekle'), findsNothing, reason: 'the preview already says so');
    expect(store.activities, hasLength(1));
    await finish(tester);
  });

  testWidgets('an amount changed in the options wins over the one in the text', (tester) async {
    await tester.runAsync(() async {
      await store.load();
      await store.addActivity('Su', emoji: '💧');
    });
    await pumpToday(tester);

    await tester.enterText(composerField, '2 bardak su');
    await tester.pump();
    await tester.tap(submitButton);
    await tester.pump();
    await tester.tap(find.byIcon(Icons.remove));
    await tester.pump();
    expect(previewOf(tester), '💧 Su: 1 Su bardağı · 200 ml eklenecek');

    await tester.tap(submitButton);
    await settleStore(tester);
    expect(store.entries.single.qty, 1, reason: 'the stepper said one, whatever the text says');
    await finish(tester);
  });

  testWidgets('a text read as a timer command can be logged as an entry instead', (tester) async {
    await tester.runAsync(() async {
      await store.load();
      await store.addActivity('Oruç', emoji: '🌙');
    });
    await pumpToday(tester);

    await tester.enterText(composerField, 'oruç tut');
    await tester.pump();
    expect(previewOf(tester), '🌙 Oruç: kronometre başlayacak');
    expect(tester.widget<IconButton>(submitButton).tooltip, 'Sayacı Başlat');
    expect(find.textContaining('Yeni Olarak Ekle'), findsNothing, reason: 'one choice at a time');

    await tester.tap(find.text('Kayıt olarak ekle'));
    await tester.pump();
    expect(previewOf(tester), '🌙 Oruç eklenecek');
    expect(find.text('Yeni Olarak Ekle: "Oruç tut"'), findsOneWidget);
    expect(tester.widget<IconButton>(submitButton).tooltip, 'Kaydet');
    expect(find.text('Sayaç başlat'), findsOneWidget, reason: 'the other reading stays one tap away');

    await tester.tap(submitButton); // opens the options
    await tester.pump();
    await tester.tap(submitButton);
    await settleStore(tester);

    expect(store.activeTimers, isEmpty);
    expect(store.entries.map((e) => store.activity(e.activityId).name), ['Oruç']);
    expect(store.activities, hasLength(1));
    await finish(tester);
  });

  testWidgets('typing the name of an activity that contains a command word logs that activity', (tester) async {
    await tester.runAsync(() async {
      await store.load();
      await store.addActivity('Sayaç okuma', emoji: '🔌');
    });
    await pumpToday(tester);

    await tester.enterText(composerField, 'sayaç okuma');
    await tester.pump();
    expect(previewOf(tester), '🔌 Sayaç okuma eklenecek');
    expect(find.text('Sayaç başlat'), findsNothing);

    await tester.tap(submitButton);
    await tester.pump();
    await tester.tap(submitButton);
    await settleStore(tester);

    expect(store.activeTimers, isEmpty);
    expect(store.entries, hasLength(1));
    await finish(tester);
  });

  testWidgets('closing the timer sheet leaves no empty activity behind', (tester) async {
    await pumpToday(tester);

    await tester.enterText(composerField, 'yüzme');
    await tester.pump();
    await tester.tap(timerButton);
    await settleStore(tester);
    expect(find.text('Yüzme'), findsOneWidget, reason: 'the sheet names the activity that would be created');

    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await settleStore(tester);

    expect(store.activities, isEmpty);
    expect(store.activeTimers, isEmpty);
    await finish(tester);
  });

  testWidgets('the timer button times the activity the text refers to and creates it only when needed',
      (tester) async {
    await tester.runAsync(() async {
      await store.load();
      await store.addActivity('Kitap okuma', emoji: '📚');
    });
    await pumpToday(tester);

    await tester.enterText(composerField, 'kitap');
    await tester.pump();
    await tester.tap(timerButton);
    await settleStore(tester);
    await tester.tap(stopwatchOption);
    await settleStore(tester);

    expect(store.activities.values.map((a) => a.name), ['Kitap okuma']);
    expect(store.activity(store.activeTimers.single.activityId).name, 'Kitap okuma');

    // A name nothing matches is created once the mode is chosen.
    await tester.enterText(composerField, 'yüzme');
    await tester.pump();
    await tester.tap(timerButton);
    await settleStore(tester);
    await tester.tap(stopwatchOption);
    await settleStore(tester);

    expect(store.activities.values.map((a) => a.name), ['Kitap okuma', 'Yüzme']);
    expect(store.activeTimers, hasLength(2));
    await finish(tester);
  });

  testWidgets('"add as new" creates the typed activity even when a similar one exists', (tester) async {
    await tester.runAsync(() async {
      await store.load();
      await store.addActivity('Kitap okuma', emoji: '📚');
    });
    await pumpToday(tester);

    // Plain submit goes to the activity whose name starts with the text.
    await tester.enterText(composerField, 'kitap');
    await tester.pump();
    await tester.tap(submitButton);
    await tester.pump();
    await tester.tap(submitButton);
    await settleStore(tester);
    expect(store.activities, hasLength(1));
    expect(store.entries, hasLength(1));

    await tester.enterText(composerField, 'kitap');
    await tester.pump();
    expect(previewOf(tester), '📚 Kitap okuma eklenecek');
    await tester.tap(find.text('Yeni Olarak Ekle: "Kitap"'));
    await tester.pump();
    expect(previewOf(tester), 'Kitap (yeni aktivite) eklenecek');
    await tester.tap(submitButton);
    await settleStore(tester);

    expect(store.activities.values.map((a) => a.name), ['Kitap okuma', 'Kitap']);
    expect(store.entries.map((e) => store.activity(e.activityId).name), ['Kitap okuma', 'Kitap']);
    await finish(tester);
  });

  testWidgets('the confirmation of a new entry appears above the composer, not over it', (tester) async {
    await pumpToday(tester);

    await tester.enterText(composerField, 'çay');
    await tester.pump();
    await tester.tap(submitButton);
    await tester.pump();
    await tester.tap(submitButton);
    await settleStore(tester);

    expect(store.entries, hasLength(1));
    final snackBar = tester.getRect(find.byType(SnackBar));
    final composer = tester.getRect(composerField);
    expect(snackBar.bottom, lessThanOrEqualTo(composer.top));
    await finish(tester);
  });
}
