import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:takip/data/store.dart';
import 'package:takip/logic/l10n.dart';
import 'package:takip/logic/todo_parser.dart';
import 'package:takip/services/nl_parser.dart';
import 'package:takip/ui/today_page.dart';

import 'support/real_db.dart';

Future<void> settleStore(WidgetTester tester) async {
  for (var i = 0; i < 15; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> pumpToday(WidgetTester tester) async {
  await tester.runAsync(() => store.load());
  await tester.pumpWidget(MaterialApp(home: TodayPage(focusRequest: ValueNotifier<int>(0))));
  await tester.pump();
}

Future<void> finish(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.runAsync(() async {
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

  group('Kutunun Yapılacak Modu Ayrıştırma Testleri (Todo Parser Eşdeğerliği)', () {
    test('aynı metin hızlı ekleme ve parseMulti(forceTodo: true) ile aynı sonucu üretir', () async {
      final s = AppStore();
      await s.load();

      final actKosu = await s.addActivity('Koşu', emoji: '🏃');
      final actWalk = await s.addActivity('Walk', emoji: '🚶');
      final activities = s.activities.values.toList();
      final measures = s.measures;
      final now = DateTime(2026, 11, 10, 10, 0);

      // 1. Düz metin (TR ve EN)
      final plainTr = 'doktora git';
      final fastPlainTr = TodoInputParser.parse(plainTr, activities: activities, measures: measures, now: now);
      final multiPlainTr = NaturalLanguageParser.parseMulti(plainTr, activities: activities, measures: measures, now: now, forceTodo: true);
      expect(multiPlainTr.items.length, 1);
      final itemPlainTr = multiPlainTr.items.first as TodoParsedItem;
      expect(itemPlainTr.title, fastPlainTr.cleanTitle);
      expect(itemPlainTr.dueDate, fastPlainTr.date);
      expect(itemPlainTr.suggestedActivity?.id, fastPlainTr.suggestedActivity?.id);
      expect(itemPlainTr.suggestedAmount, fastPlainTr.suggestedAmount);

      final plainEn = 'call doctor';
      final fastPlainEn = TodoInputParser.parse(plainEn, activities: activities, measures: measures, now: now);
      final multiPlainEn = NaturalLanguageParser.parseMulti(plainEn, activities: activities, measures: measures, now: now, forceTodo: true);
      expect(multiPlainEn.items.length, 1);
      final itemPlainEn = multiPlainEn.items.first as TodoParsedItem;
      expect(itemPlainEn.title, fastPlainEn.cleanTitle);
      expect(itemPlainEn.dueDate, fastPlainEn.date);

      // 2. Bağlı ve miktarlı (TR ve EN)
      final linkedTr = '30 dk koşu yarın';
      final fastLinkedTr = TodoInputParser.parse(linkedTr, activities: activities, measures: measures, now: now);
      final multiLinkedTr = NaturalLanguageParser.parseMulti(linkedTr, activities: activities, measures: measures, now: now, forceTodo: true);
      expect(multiLinkedTr.items.length, 1);
      final itemLinkedTr = multiLinkedTr.items.first as TodoParsedItem;
      expect(itemLinkedTr.title, fastLinkedTr.cleanTitle);
      expect(itemLinkedTr.suggestedActivity?.id, actKosu.id);
      expect(itemLinkedTr.suggestedAmount, 30.0);
      expect(itemLinkedTr.suggestedUnit, 'dk');
      expect(itemLinkedTr.dueDate, fastLinkedTr.date);

      final linkedEn = '20 min walk tomorrow';
      final fastLinkedEn = TodoInputParser.parse(linkedEn, activities: activities, measures: measures, now: now);
      final multiLinkedEn = NaturalLanguageParser.parseMulti(linkedEn, activities: activities, measures: measures, now: now, forceTodo: true);
      expect(multiLinkedEn.items.length, 1);
      final itemLinkedEn = multiLinkedEn.items.first as TodoParsedItem;
      expect(itemLinkedEn.title, fastLinkedEn.cleanTitle);
      expect(itemLinkedEn.suggestedActivity?.id, actWalk.id);
      expect(itemLinkedEn.suggestedAmount, 20.0);

      // 3. Çoklu giriş (TR ve EN)
      final multiTr = 'doktora git ve 30 dk koşu';
      final parsedMultiTr = NaturalLanguageParser.parseMulti(multiTr, activities: activities, measures: measures, now: now, forceTodo: true);
      expect(parsedMultiTr.items.length, 2);
      final mItem1 = parsedMultiTr.items[0] as TodoParsedItem;
      final mItem2 = parsedMultiTr.items[1] as TodoParsedItem;
      expect(mItem1.title, 'doktora git');
      expect(mItem2.suggestedActivity?.id, actKosu.id);
      expect(mItem2.suggestedAmount, 30.0);

      final multiEn = 'call dentist and 20 min walk';
      final parsedMultiEn = NaturalLanguageParser.parseMulti(multiEn, activities: activities, measures: measures, now: now, forceTodo: true);
      expect(parsedMultiEn.items.length, 2);
      final mEn1 = parsedMultiEn.items[0] as TodoParsedItem;
      final mEn2 = parsedMultiEn.items[1] as TodoParsedItem;
      expect(mEn1.title, 'call dentist');
      expect(mEn2.suggestedActivity?.id, actWalk.id);
    });
  });

  group('Kutudan Yapılacak Ekleme ve Kayıt Çevirme Widget Testleri', () {
    testWidgets('yazarken seçici görünür, yapılacak modu seçilir, kaydedilince yapılacak oluşur ve geri alınabilir', (tester) async {
      await pumpToday(tester);

      // Başlangıçta kutu boşken seçici görünmez
      expect(find.byKey(const Key('mode-selector-entry')), findsNothing);
      expect(find.byKey(const Key('mode-selector-todo')), findsNothing);

      // Metin yazınca seçici görünür, varsayılan Kayıt seçilidir
      await tester.enterText(composerField, 'doktora git');
      await tester.pump();

      expect(find.byKey(const Key('mode-selector-entry')), findsOneWidget);
      expect(find.byKey(const Key('mode-selector-todo')), findsOneWidget);

      // Yapılacak seçeneğine dokun
      await tester.tap(find.byKey(const Key('mode-selector-todo')));
      await tester.pump();

      // Önizleme yapılacak başlığını göstermeli
      expect(find.text('doktora git'), findsWidgets);

      // Kaydet düğmesi yapılacak moduna uygun olmalı (checklist ikonu ve 'Yapılacak ekle' tooltip)
      final btn = tester.widget<IconButton>(submitButton);
      expect(btn.tooltip, 'Yapılacak ekle');

      // Kaydet
      await tester.tap(submitButton);
      await settleStore(tester);

      // Kayıt oluşmamalı, yapılacak oluşmalı
      expect(store.entries, isEmpty);
      expect(store.todos.length, 1);
      final createdTodo = store.todos.single;
      expect(createdTodo.title, 'doktora git');

      // Metin kutusu temizlenmiş olmalı ve seçici gizlenmiş olmalı
      expect(tester.widget<TextField>(composerField).controller?.text, '');
      expect(find.byKey(const Key('mode-selector-todo')), findsNothing);

      // Snackbar "1 yapılacak eklendi" ve "Geri al" göstermeli
      expect(find.text('1 yapılacak eklendi'), findsOneWidget);
      expect(find.text('Geri al'), findsOneWidget);

      // Geri al'a dokun
      await tester.tap(find.text('Geri al'));
      await settleStore(tester);

      // Yapılacak silinmiş olmalı
      expect(store.todos, isEmpty);

      await finish(tester);
    });

    testWidgets('zaman çizelgesindeki kayıtta "Yapılacağa çevir" kaydı siler, yapılacak oluşturur, geri al kaydı geri yükler', (tester) async {
      await tester.runAsync(() async {
        await store.load();
        final act = await store.addActivity('Koşu', emoji: '🏃');
        final m = store.measures.firstWhere((x) => x.unitId == 'km');
        await store.addEntry(act.id, measureId: m.id, qty: 5, note: 'Sabah parkuru');
      });

      await pumpToday(tester);

      expect(store.entries.length, 1);
      expect(store.todos, isEmpty);

      // Zaman çizelgesindeki kayda dokun
      await tester.tap(find.text('Koşu').first);
      await tester.pumpAndSettle();

      // Düzenleme sayfasında "Yapılacağa çevir" butonu bulunmalı
      expect(find.byKey(const Key('convert-to-todo-button')), findsOneWidget);
      expect(find.text('Yapılacağa çevir'), findsOneWidget);

      // "Yapılacağa çevir"e dokun
      await tester.tap(find.byKey(const Key('convert-to-todo-button')));
      await settleStore(tester);

      // Kayıt silinmiş, yapılacak oluşmuş olmalı
      expect(store.entries, isEmpty);
      expect(store.todos.length, 1);
      final todo = store.todos.single;
      expect(todo.title, '5 km Koşu');
      expect(todo.note, 'Sabah parkuru');

      // Snackbar "Yapılacağa çevrildi" ve "Geri al" göstermeli
      expect(find.text('Yapılacağa çevrildi'), findsOneWidget);
      expect(find.text('Geri al'), findsOneWidget);

      // Geri Al'a dokun
      await tester.tap(find.text('Geri al'));
      await settleStore(tester);

      // Kayıt geri gelmeli, yapılacak silinmeli
      expect(store.todos, isEmpty);
      expect(store.entries.length, 1);
      expect(store.entries.single.note, 'Sabah parkuru');

      await finish(tester);
    });

    testWidgets('kayıt sayfasında aktivite değiştirilip yapılacağa çevrilince eski birim taşınmaz', (tester) async {
      int actKitapId = 0;
      final now = DateTime.now();
      final todayNoon = DateTime(now.year, now.month, now.day, 12, 0);

      await tester.runAsync(() async {
        await store.load();
        final actKosu = await store.addActivity('Koşu', emoji: '🏃');
        final actKitap = await store.addActivity('Kitap okuma', emoji: '📖');
        actKitapId = actKitap.id;
        final m = store.measures.firstWhere((x) => x.unitId == 'km');
        await store.addEntry(actKosu.id, measureId: m.id, qty: 5, note: 'Sabah parkuru', at: todayNoon);
      });

      await pumpToday(tester);

      expect(store.entries.length, 1);
      expect(store.todos, isEmpty);

      // Zaman çizelgesindeki kayda dokunarak düzenleme sayfasını aç
      await tester.tap(find.text('Koşu').first);
      await tester.pumpAndSettle();

      // "Aktiviteyi Değiştir" butonuna dokun
      await tester.tap(find.byTooltip('Aktiviteyi Değiştir'));
      await tester.pumpAndSettle();

      // Seçicide "Kitap okuma" aktivitesine dokun
      await tester.tap(find.text('Kitap okuma').last);
      await tester.pumpAndSettle();

      // "Yapılacağa çevir"e dokun
      await tester.ensureVisible(find.byKey(const Key('convert-to-todo-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('convert-to-todo-button')));
      await settleStore(tester);

      // Kayıt silinmeli, yapılacak oluşmalı ve başlıkta/hedefte 'km' olmamalı
      expect(store.entries, isEmpty);
      expect(store.todos.length, 1);
      final todo = store.todos.single;
      expect(todo.title, 'Kitap okuma');
      expect(todo.targetAmount, isNull);
      expect(todo.targetUnit, isNull);
      expect(todo.linkedActivityIds, [actKitapId]);

      await finish(tester);
    });

    testWidgets('kayıt sayfasında ölçüsüz kronometre kaydı yapılacağa çevrilince dakika hedefi oluşur', (tester) async {
      int actId = 0;
      final now = DateTime.now();
      final todayStart = DateTime(now.year, now.month, now.day, 12, 0);
      final todayEnd = DateTime(now.year, now.month, now.day, 12, 25); // 25 dk

      await tester.runAsync(() async {
        await store.load();
        final act = await store.addActivity('Yürüyüş', emoji: '🚶');
        actId = act.id;
        // Ölçüsü olmayan ama bitiş zamanı olan kronometre kaydı
        await store.addEntry(act.id, at: todayStart, endAt: todayEnd, note: 'Öğle yürüyüşü');
      });

      await pumpToday(tester);

      expect(store.entries.length, 1);
      expect(store.todos, isEmpty);

      // Zaman çizelgesindeki kayda dokunarak düzenleme sayfasını aç
      await tester.tap(find.text('Yürüyüş').first);
      await tester.pumpAndSettle();

      // "Yapılacağa çevir"e dokun
      await tester.ensureVisible(find.byKey(const Key('convert-to-todo-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('convert-to-todo-button')));
      await settleStore(tester);

      // Kayıt silinmeli, 25 dk hedefli yapılacak oluşmalı
      expect(store.entries, isEmpty);
      expect(store.todos.length, 1);
      final todo = store.todos.single;
      expect(todo.title, '25 dk Yürüyüş');
      expect(todo.targetAmount, 25.0);
      expect(todo.targetUnit, 'dk');
      expect(todo.linkedActivityIds, [actId]);

      await finish(tester);
    });

    testWidgets('yapılacak önekli metinde seçici Yapılacak gösterir, Kayıt\'a basınca önek kalkar', (tester) async {
      await pumpToday(tester);

      // 1. "yapılacak: doktora git"
      await tester.enterText(composerField, 'yapılacak: doktora git');
      await tester.pump();

      expect(isSegmentSelected(tester, const Key('mode-selector-todo')), isTrue);
      expect(isSegmentSelected(tester, const Key('mode-selector-entry')), isFalse);
      expect(find.text('doktora git'), findsWidgets);
      expect(tester.widget<IconButton>(submitButton).tooltip, 'Yapılacak ekle');

      // Kayıt'a bas
      await tester.tap(find.byKey(const Key('mode-selector-entry')));
      await tester.pump();

      expect(tester.widget<TextField>(composerField).controller?.text, 'doktora git');
      expect(isSegmentSelected(tester, const Key('mode-selector-entry')), isTrue);
      expect(isSegmentSelected(tester, const Key('mode-selector-todo')), isFalse);
      expect(tester.widget<IconButton>(submitButton).tooltip, isNot('Yapılacak ekle'));

      // 2. "yarın: dişçiyi ara"
      await tester.enterText(composerField, 'yarın: dişçiyi ara');
      await tester.pump();

      expect(isSegmentSelected(tester, const Key('mode-selector-todo')), isTrue);
      expect(isSegmentSelected(tester, const Key('mode-selector-entry')), isFalse);
      expect(tester.widget<IconButton>(submitButton).tooltip, 'Yapılacak ekle');

      // Kayıt'a bas (metin geleceği gösterdiği için öğe yapılacak kalır ve açıklama satırı çıkar)
      await tester.tap(find.byKey(const Key('mode-selector-entry')));
      await tester.pump();

      expect(tester.widget<TextField>(composerField).controller?.text, 'yarın dişçiyi ara');
      expect(isSegmentSelected(tester, const Key('mode-selector-todo')), isTrue);
      expect(isSegmentSelected(tester, const Key('mode-selector-entry')), isFalse);
      expect(find.text('Gelecek zamanlı olduğu için yapılacak olarak eklenecek'), findsOneWidget);
      expect(tester.widget<IconButton>(submitButton).tooltip, 'Yapılacak ekle');

      await finish(tester);
    });

    testWidgets('yapılacak modunda tarih seçilip ardından Kayıt\'a basılınca normal kayıt eklenir', (tester) async {
      await tester.runAsync(() async {
        await store.load();
        await store.addActivity('Koşu', emoji: '🏃');
      });
      await pumpToday(tester);

      await tester.enterText(composerField, '30 dk koşu');
      await tester.pump();

      // Yapılacak seç
      await tester.tap(find.byKey(const Key('mode-selector-todo')));
      await tester.pump();
      expect(isSegmentSelected(tester, const Key('mode-selector-todo')), isTrue);

      // Tarih seç (calendar ikonuna tıkla ve dialog'u onayla)
      await tester.tap(find.byIcon(Icons.calendar_today).first);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(TextButton).last);
      await tester.pumpAndSettle();

      // Kayıt'a bas
      await tester.tap(find.byKey(const Key('mode-selector-entry')));
      await tester.pump();
      expect(isSegmentSelected(tester, const Key('mode-selector-entry')), isTrue);

      // Kaydet
      await tester.tap(submitButton);
      await settleStore(tester);

      // Kayıt oluşmalı, yapılacak oluşmamalı
      expect(store.entries.length, 1);
      expect(store.todos, isEmpty);

      await finish(tester);
    });

    testWidgets('çok öğeli listede tek öğe yapılacağa çevrildiğinde seçicide hiçbir mod seçili kalmaz', (tester) async {
      await tester.runAsync(() async {
        await store.load();
        await store.addActivity('Koşu', emoji: '🏃');
        await store.addActivity('Yüzme', emoji: '🏊');
      });
      await pumpToday(tester);

      // 'koşu ve yüzme' yaz (iki öğe de geçmiş/şimdiki zamanlı kayıt olarak başlar)
      await tester.enterText(composerField, 'koşu ve yüzme');
      await tester.pump();

      expect(isSegmentSelected(tester, const Key('mode-selector-entry')), isTrue);
      expect(isSegmentSelected(tester, const Key('mode-selector-todo')), isFalse);

      // İkinci öğeyi yapılacağa çevir
      await tester.tap(find.text('Yapılacak olarak ekle').first);
      await tester.pump();

      // Karışık: hiçbiri seçili olmamalı
      expect(isSegmentSelected(tester, const Key('mode-selector-entry')), isFalse);
      expect(isSegmentSelected(tester, const Key('mode-selector-todo')), isFalse);
      expect(tester.widget<IconButton>(submitButton).tooltip, isNot('Yapılacak ekle'));

      // Kaydet
      await tester.tap(submitButton);
      await settleStore(tester);

      // 1 kayıt ve 1 yapılacak oluşmalı
      expect(store.entries.length, 1);
      expect(store.todos.length, 1);

      await finish(tester);
    });

    testWidgets('yapılacak modunda listeden aktivite seçildiğinde mod Kayıt\'a döner ve kayıt eklenir', (tester) async {
      await tester.runAsync(() async {
        await store.load();
        await store.addActivity('Yüzme', emoji: '🏊');
      });
      await pumpToday(tester);

      await tester.enterText(composerField, 'yüzme');
      await tester.pump();

      // Yapılacak moduna al
      await tester.tap(find.byKey(const Key('mode-selector-todo')));
      await tester.pump();
      expect(isSegmentSelected(tester, const Key('mode-selector-todo')), isTrue);

      // Listeden (önerilerden) aktivite seç
      await tester.tap(find.widgetWithText(ActionChip, 'Yüzme'));
      await tester.pump();

      // Mod Kayıt olmalı
      expect(isSegmentSelected(tester, const Key('mode-selector-entry')), isTrue);
      expect(isSegmentSelected(tester, const Key('mode-selector-todo')), isFalse);
      expect(tester.widget<IconButton>(submitButton).tooltip, isNot('Yapılacak ekle'));

      // Kaydet
      await tester.tap(submitButton);
      await settleStore(tester);

      // Kayıt eklenmeli, yapılacak eklenmemeli
      expect(store.entries.length, 1);
      expect(store.entries.single.activityId, store.activities.values.firstWhere((a) => a.name == 'Yüzme').id);
      expect(store.todos, isEmpty);

      await finish(tester);
    });

    testWidgets('İngilizce arayüzde Yapılacak modunda "30 min run" yazınca önizlemede "30 min" görünür, "dk" görünmez', (tester) async {
      await tester.runAsync(() async {
        await store.load();
        await store.setLanguage(AppLanguage.en);
        await store.addActivity('Run', emoji: '🏃');
      });
      await pumpToday(tester);

      await tester.enterText(composerField, '30 min run');
      await tester.pump();

      // Yapılacak seç
      await tester.tap(find.byKey(const Key('mode-selector-todo')));
      await tester.pump();

      // Önizlemede "30 min" görünmeli, "dk" görünmemeli
      expect(find.textContaining('30 min'), findsWidgets);
      expect(find.textContaining('dk'), findsNothing);

      // Dili normale çevir
      await tester.runAsync(() => store.setLanguage(AppLanguage.tr));
      await finish(tester);
    });

    testWidgets('seçici butonları Semantics ile seçili durumunu bildirir ve dokunma yüksekliği en az 36 dp olur', (tester) async {
      await pumpToday(tester);

      await tester.enterText(composerField, 'kitap oku');
      await tester.pump();

      final entryFinder = find.byKey(const Key('mode-selector-entry'));
      final todoFinder = find.byKey(const Key('mode-selector-todo'));

      expect(tester.getSize(entryFinder).height, greaterThanOrEqualTo(36.0));
      expect(tester.getSize(todoFinder).height, greaterThanOrEqualTo(36.0));

      final entrySemantics = tester.widget<Semantics>(find.ancestor(of: entryFinder, matching: find.byType(Semantics)).first);
      expect(entrySemantics.properties.button, isTrue);
      expect(entrySemantics.properties.selected, isTrue);

      final todoSemantics = tester.widget<Semantics>(find.ancestor(of: todoFinder, matching: find.byType(Semantics)).first);
      expect(todoSemantics.properties.button, isTrue);
      expect(todoSemantics.properties.selected, isFalse);

      await finish(tester);
    });
  });
}
