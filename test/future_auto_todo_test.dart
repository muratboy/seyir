import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:takip/data/models.dart';
import 'package:takip/data/store.dart';
import 'package:takip/logic/l10n.dart';
import 'package:takip/services/nl_parser.dart';
import 'package:takip/ui/today_page.dart';

import 'support/real_db.dart';

Future<void> settleStore(WidgetTester tester) async {
  for (var i = 0; i < 15; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> pumpToday(WidgetTester tester, {AppLanguage lang = AppLanguage.tr}) async {
  await tester.runAsync(() async {
    await store.load();
    await store.setLanguage(lang);
  });
  await tester.pumpWidget(MaterialApp(
    locale: Locale(lang.name),
    home: TodayPage(focusRequest: ValueNotifier<int>(0)),
  ));
  await tester.pump();
}

Future<void> finish(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.runAsync(() async {
    await store.setLanguage(AppLanguage.tr);
    for (final t in List.of(store.activeTimers)) {
      await store.cancelTimer(t.id);
    }
  });
  await tester.pump(const Duration(seconds: 6));
}

Finder get composerField => find.byType(TextField).last;
Finder get submitButton => find.byKey(const Key('composer-submit'));

bool isSegmentSelected(WidgetTester tester, Key key) {
  final container = tester.widget<Container>(find.descendant(
    of: find.byKey(key),
    matching: find.byType(Container),
  ));
  final box = container.decoration as BoxDecoration?;
  return box?.color != Colors.transparent && box?.color != null;
}

void main() {
  useRealDatabase();

  setUpAll(() async {
    await initializeDateFormatting('tr_TR');
    await initializeDateFormatting('en_US');
    Intl.defaultLocale = 'tr_TR';
  });

  group('Gelecek Zamanlı Girdi Dönüşüm Kuralı (Birim Testleri)', () {
    final fixedNow = DateTime(2026, 11, 15, 10, 0); // Pazar 10:00
    final runAct = Activity(id: 1, name: 'Koşu', emoji: '🏃', color: 0xFF2196F3, createdAt: 1000);
    final coffeeAct = Activity(id: 2, name: 'Kahve', emoji: '☕', color: 0xFF795548, createdAt: 1000);
    final acts = <Activity>[runAct, coffeeAct];

    test('"yarın 30 dk koşu" kendiliğinden yapılacak öğesine çevrilir', () async {
      await store.load();
      final multi = NaturalLanguageParser.parseMulti(
        'yarın 30 dk koşu',
        activities: acts,
        measures: store.measures,
        now: fixedNow,
      );
      final items = NaturalLanguageParser.convertFutureEntriesToTodos(multi.items);

      expect(items.length, 1);
      final item = items.first;
      expect(item, isA<TodoParsedItem>());
      final todoItem = item as TodoParsedItem;
      expect(todoItem.title, '30 dk koşu');
      expect(todoItem.suggestedActivity?.name, 'Koşu');
      expect(todoItem.suggestedAmount, 30.0);
      expect(todoItem.suggestedUnit, 'dk');
      expect(todoItem.dueDate, DateTime(2026, 11, 16, 12, 0));
      expect(todoItem.autoConvertedFromFuture, isTrue);
    });

    test('"dün 30 dk koşu" ve "30 dk koşu" kayıt öğesi olarak kalır', () async {
      await store.load();
      final multiYesterday = NaturalLanguageParser.parseMulti(
        'dün 30 dk koşu',
        activities: acts,
        measures: store.measures,
        now: fixedNow,
      );
      final itemsYesterday = NaturalLanguageParser.convertFutureEntriesToTodos(multiYesterday.items);
      expect(itemsYesterday.length, 1);
      expect(itemsYesterday.first, isA<EntryParsedItem>());
      final entryYesterday = itemsYesterday.first as EntryParsedItem;
      expect(entryYesterday.activityName, 'Koşu');
      expect(entryYesterday.quantity, 30.0);

      final multiToday = NaturalLanguageParser.parseMulti(
        '30 dk koşu',
        activities: acts,
        measures: store.measures,
        now: fixedNow,
      );
      final itemsToday = NaturalLanguageParser.convertFutureEntriesToTodos(multiToday.items);
      expect(itemsToday.length, 1);
      expect(itemsToday.first, isA<EntryParsedItem>());
      final entryToday = itemsToday.first as EntryParsedItem;
      expect(entryToday.activityName, 'Koşu');
      expect(entryToday.quantity, 30.0);
    });

    test('karışık çoklu girişte yalnızca gelecekteki öğe çevrilir', () async {
      await store.load();
      final multi = NaturalLanguageParser.parseMulti(
        '1 kahve ve yarın 30 dk koşu',
        activities: acts,
        measures: store.measures,
        now: fixedNow,
      );
      final items = NaturalLanguageParser.convertFutureEntriesToTodos(multi.items);

      expect(items.length, 2);
      expect(items[0], isA<EntryParsedItem>());
      final entry = items[0] as EntryParsedItem;
      expect(entry.activityName, 'Kahve');
      expect(entry.quantity, 1.0);

      expect(items[1], isA<TodoParsedItem>());
      final todo = items[1] as TodoParsedItem;
      expect(todo.title, '30 dk koşu');
      expect(todo.suggestedAmount, 30.0);
      expect(todo.dueDate, DateTime(2026, 11, 16, 12, 0));
      expect(todo.autoConvertedFromFuture, isTrue);
    });

    test('kendiliğinden çevrilen gelecek öğe ile Yapılacak modu sonucu alan alan aynıdır', () async {
      await store.load();
      final acts = [
        Activity(id: 1, name: 'Koşu', emoji: '🏃', createdAt: 1000),
        Activity(id: 2, name: 'Ders', emoji: '📚', createdAt: 1000),
      ];
      final inputs = [
        'yarın 30 dk koşu',
        'yarın doktora git',
        'yarın 2 saat 15 dk ders',
      ];

      for (final input in inputs) {
        final entryMulti = NaturalLanguageParser.parseMulti(
          input,
          activities: acts,
          measures: store.measures,
          now: fixedNow,
          forceTodo: false,
        );
        final convertedItems = NaturalLanguageParser.convertFutureEntriesToTodos(
          entryMulti.items,
          activities: acts,
          measures: store.measures,
          now: fixedNow,
        );

        final todoMulti = NaturalLanguageParser.parseMulti(
          input,
          activities: acts,
          measures: store.measures,
          now: fixedNow,
          forceTodo: true,
        );

        expect(convertedItems.length, todoMulti.items.length, reason: 'item count for $input');
        for (var i = 0; i < convertedItems.length; i++) {
          final converted = convertedItems[i] as TodoParsedItem;
          final expected = todoMulti.items[i] as TodoParsedItem;

          expect(converted.rawText, expected.rawText, reason: 'rawText for $input');
          expect(converted.title, expected.title, reason: 'title for $input');
          expect(converted.dueDate, expected.dueDate, reason: 'dueDate for $input');
          expect(converted.dateKeyword, expected.dateKeyword, reason: 'dateKeyword for $input');
          expect(converted.suggestedActivity?.name, expected.suggestedActivity?.name, reason: 'activity for $input');
          expect(converted.suggestedAmount, expected.suggestedAmount, reason: 'amount for $input');
          expect(converted.suggestedUnit, expected.suggestedUnit, reason: 'unit for $input');
          expect(converted.autoConvertedFromFuture, isTrue, reason: 'autoConvertedFromFuture for $input');
          expect(expected.autoConvertedFromFuture, isFalse, reason: 'expected autoConvertedFromFuture for $input');
        }
      }
    });

    test('"30 dk koşu" + çipten yarın seçimi, Yapılacak modunda yarın bitişli sonuçla aynıdır', () async {
      await store.load();
      final acts = [Activity(id: 1, name: 'Koşu', emoji: '🏃', createdAt: 1000)];
      final tomorrowDate = DateTime(2026, 11, 16, 12, 0);

      final entryMulti = NaturalLanguageParser.parseMulti(
        '30 dk koşu',
        activities: acts,
        measures: store.measures,
        now: fixedNow,
        forceTodo: false,
      );
      final entryItem = entryMulti.items.first as EntryParsedItem;

      final updatedItem = entryItem.copyWith(
        at: tomorrowDate,
        hasExplicitDate: true,
        hasExplicitTime: true,
        isExplicitFuture: true,
      );

      final convertedItems = NaturalLanguageParser.convertFutureEntriesToTodos(
        [updatedItem],
        activities: acts,
        measures: store.measures,
        now: fixedNow,
      );
      final converted = convertedItems.first as TodoParsedItem;

      final todoMulti = NaturalLanguageParser.parseMulti(
        '30 dk koşu',
        activities: acts,
        measures: store.measures,
        now: fixedNow,
        forceTodo: true,
      );
      final expectedTodo = (todoMulti.items.first as TodoParsedItem).copyWith(
        dueDate: tomorrowDate,
      );

      expect(converted.rawText, expectedTodo.rawText);
      expect(converted.title, expectedTodo.title);
      expect(converted.dueDate, expectedTodo.dueDate);
      expect(converted.suggestedActivity?.name, expectedTodo.suggestedActivity?.name);
      expect(converted.suggestedAmount, expectedTodo.suggestedAmount);
      expect(converted.suggestedUnit, expectedTodo.suggestedUnit);
      expect(converted.autoConvertedFromFuture, isTrue);
    });
  });

  group('Kutudan Gelecek Zamanlı Yapılacak Dönüşümü (Arayüz Testleri)', () {
    testWidgets('(a) "30 dk koşu" yaz -> zaman çipinden yarını seç -> yapılacak önizlemesi ve açıklama satırı çıkar, gönderince yapılacak oluşur', (tester) async {
      await tester.runAsync(() async {
        await store.load();
        await store.addActivity('Koşu', emoji: '🏃');
      });
      await pumpToday(tester);

      await tester.enterText(composerField, '30 dk koşu');
      await tester.pump();

      // Başlangıçta kayıt önizlemesi ve zaman çipi görünür
      expect(find.byKey(const Key('composer-time-chip')), findsOneWidget);
      expect(isSegmentSelected(tester, const Key('mode-selector-entry')), isTrue);
      expect(isSegmentSelected(tester, const Key('mode-selector-todo')), isFalse);

      // Zaman çipine dokun (showDatePicker açılır)
      await tester.tap(find.byKey(const Key('composer-time-chip')));
      await tester.pumpAndSettle();

      final now = DateTime.now();
      final tomorrow = now.add(const Duration(days: 1));
      if (tomorrow.month != now.month) {
        await tester.tap(find.byIcon(Icons.chevron_right));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.text(tomorrow.day.toString()).last);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(TextButton).last); // Tarihi onayla
      await tester.pumpAndSettle();

      // showTimePicker açılır (mevcut saati onayla)
      await tester.tap(find.byType(TextButton).last); // Saati onayla
      await tester.pumpAndSettle();

      // Artık yapılacak önizlemesine dönüştü ve açıklama satırı çıktı
      expect(find.text('Gelecek zamanlı olduğu için yapılacak olarak eklenecek'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
      expect(isSegmentSelected(tester, const Key('mode-selector-todo')), isTrue);
      expect(isSegmentSelected(tester, const Key('mode-selector-entry')), isFalse);
      expect(tester.widget<IconButton>(submitButton).tooltip, 'Yapılacak ekle');

      // Gönder düğmesine bas
      await tester.tap(submitButton);
      await settleStore(tester);

      // Yapılacak oluştu (bitiş yarın), kayıt oluşmadı
      expect(store.entries, isEmpty);
      expect(store.todos.length, 1);
      final todo = store.todos.single;
      expect(todo.title, '30 dk koşu');
      expect(todo.targetAmount, 30.0);
      expect(todo.targetUnit, 'dk');
      expect(todo.dueDate, DateFormat('yyyy-MM-dd').format(tomorrow));

      await finish(tester);
    });

    testWidgets('(b) "yarın 30 dk koşu" yaz -> aynı önizleme; Kayıt\'a bas -> öğe yine yapılacak kalır', (tester) async {
      await tester.runAsync(() async {
        await store.load();
        await store.addActivity('Koşu', emoji: '🏃');
      });
      await pumpToday(tester);

      await tester.enterText(composerField, 'yarın 30 dk koşu');
      await tester.pump();

      expect(find.text('Gelecek zamanlı olduğu için yapılacak olarak eklenecek'), findsOneWidget);
      expect(isSegmentSelected(tester, const Key('mode-selector-todo')), isTrue);
      expect(isSegmentSelected(tester, const Key('mode-selector-entry')), isFalse);
      expect(tester.widget<IconButton>(submitButton).tooltip, 'Yapılacak ekle');

      // Kayıt'a bas (metin geleceği gösterdiği sürece öğe yapılacak kalır)
      await tester.tap(find.byKey(const Key('mode-selector-entry')));
      await tester.pump();

      expect(isSegmentSelected(tester, const Key('mode-selector-todo')), isTrue);
      expect(isSegmentSelected(tester, const Key('mode-selector-entry')), isFalse);
      expect(find.text('Gelecek zamanlı olduğu için yapılacak olarak eklenecek'), findsOneWidget);
      expect(tester.widget<IconButton>(submitButton).tooltip, 'Yapılacak ekle');

      await finish(tester);
    });

    testWidgets('(c) açıklama satırı kullanıcı elle Yapılacak seçince çıkmaz', (tester) async {
      await tester.runAsync(() async {
        await store.load();
        await store.addActivity('Koşu', emoji: '🏃');
      });
      await pumpToday(tester);

      // Kullanıcı doğrudan "yapılacak: yarın 30 dk koşu" yazarsa satır çıkmaz
      await tester.enterText(composerField, 'yapılacak: yarın 30 dk koşu');
      await tester.pump();

      expect(isSegmentSelected(tester, const Key('mode-selector-todo')), isTrue);
      expect(find.text('Gelecek zamanlı olduğu için yapılacak olarak eklenecek'), findsNothing);

      // Metni temizle, "yarın 30 dk koşu" yaz (açıklama satırı çıkar)
      await tester.tap(find.byTooltip('Temizle'));
      await tester.pump();

      await tester.enterText(composerField, 'yarın 30 dk koşu');
      await tester.pump();
      expect(find.text('Gelecek zamanlı olduğu için yapılacak olarak eklenecek'), findsOneWidget);

      // Elle Yapılacak butonuna basıldığında satır kalkar
      await tester.tap(find.byKey(const Key('mode-selector-todo')));
      await tester.pump();
      expect(find.text('Gelecek zamanlı olduğu için yapılacak olarak eklenecek'), findsNothing);

      await finish(tester);
    });

    testWidgets('(d) yapılacağın tarihi elle bugüne çekilince açıklama satırı kalkar, öğe yapılacak kalır', (tester) async {
      await tester.runAsync(() async {
        await store.load();
        await store.addActivity('Koşu', emoji: '🏃');
      });
      await pumpToday(tester);

      await tester.enterText(composerField, 'yarın 30 dk koşu');
      await tester.pump();

      expect(find.text('Gelecek zamanlı olduğu için yapılacak olarak eklenecek'), findsOneWidget);

      // Yapılacağın tarih çipine dokun (showDatePicker açılır)
      await tester.tap(find.byIcon(Icons.calendar_today).first);
      await tester.pumpAndSettle();

      final now = DateTime.now();
      // Bugünü seç
      await tester.tap(find.text(now.day.toString()).first);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(TextButton).last); // Onayla
      await tester.pumpAndSettle();

      // Açıklama satırı kalktı, öğe yapılacak olarak kaldı
      expect(find.text('Gelecek zamanlı olduğu için yapılacak olarak eklenecek'), findsNothing);
      expect(isSegmentSelected(tester, const Key('mode-selector-todo')), isTrue);
      expect(tester.widget<IconButton>(submitButton).tooltip, 'Yapılacak ekle');

      // Gönderilince yapılacak oluşur
      await tester.tap(submitButton);
      await settleStore(tester);

      expect(store.entries, isEmpty);
      expect(store.todos.length, 1);
      expect(store.todos.single.dueDate, DateFormat('yyyy-MM-dd').format(now));

      await finish(tester);
    });

    testWidgets('(e) İngilizce arayüzde açıklama satırı ve düğme metni doğru görünür', (tester) async {
      await tester.runAsync(() async {
        await store.load();
        await store.addActivity('Run', emoji: '🏃');
      });
      await pumpToday(tester, lang: AppLanguage.en);

      await tester.enterText(composerField, 'tomorrow 30 min run');
      await tester.pump();

      expect(find.text('Future time: will be added as a to-do'), findsOneWidget);
      expect(tester.widget<IconButton>(submitButton).tooltip, 'Add to-do');

      await finish(tester);
    });
  });
}
