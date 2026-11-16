import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:takip/data/store.dart';
import 'package:takip/logic/l10n.dart';
import 'package:takip/logic/text_match.dart';
import 'package:takip/logic/time_parser.dart';
import 'package:takip/services/nl_parser.dart';

import 'support/real_db.dart';

void main() {
  useRealDatabase();
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initializeDateFormatting('tr_TR', null);
    await initializeDateFormatting('en_US', null);
  });

  group('İngilizce girdi okuma', () {
    final fixedNow = DateTime(2026, 11, 11, 15, 0); // 15:00 Çarşamba

    setUp(() async {
      await store.load();
      final actNames = [
        'At', 'Kas', 'Yas', 'Tenis', 'Coffee', 'Kahve',
        'Running', 'Walking', 'Hiking', 'Dancing', 'Biking', 'Meditating', 'Eating', 'Wine',
        'Baking', 'Writing', 'Riding', 'Swimming', 'Study', 'Squat', 'Squats', 'Walk',
      ];
      for (final name in actNames) {
        if (store.exactMatch(name) == null) {
          await store.addActivity(name);
        }
      }
    });

    tearDown(() async {
      await store.setLanguage(AppLanguage.tr);
    });

    test('Türkçe arayüzde "at" kelimesi saatin önünde yutulmaz', () async {
      await store.setLanguage(AppLanguage.tr);
      final acts = store.activities.values.toList();
      final measures = store.measures;

      // çöp at 19:30 -> kayıt modunda aktivite "At", saat 19:30
      final resRecord1 = NaturalLanguageParser.parseMulti(
        'çöp at 19:30',
        activities: acts,
        measures: measures,
        openTodos: store.todos,
        now: fixedNow,
        fallbackDay: fixedNow,
      );
      expect(resRecord1.items, isNotEmpty);
      final item1 = resRecord1.items.first as EntryParsedItem;
      expect(item1.activity?.name, 'At');
      expect(item1.at.hour, 19);
      expect(item1.at.minute, 30);

      // çöp at 19:30 -> yapılacak modunda başlık "çöp at"
      final resTodo1 = NaturalLanguageParser.parseMulti(
        'todo: çöp at 19:30',
        activities: acts,
        measures: measures,
        openTodos: store.todos,
        now: fixedNow,
        fallbackDay: fixedNow,
      );
      expect(resTodo1.items, isNotEmpty);
      final todoItem1 = resTodo1.items.first as TodoParsedItem;
      expect(todoItem1.title, 'çöp at');

      // at 19:30 -> kayıt modunda aktivite "At", saat 19:30
      final resRecord2 = NaturalLanguageParser.parseMulti(
        'at 19:30',
        activities: acts,
        measures: measures,
        openTodos: store.todos,
        now: fixedNow,
        fallbackDay: fixedNow,
      );
      expect(resRecord2.items, isNotEmpty);
      final item2 = resRecord2.items.first as EntryParsedItem;
      expect(item2.activity?.name, 'At');
      expect(item2.at.hour, 19);
      expect(item2.at.minute, 30);

      // at 19:30 -> yapılacak modunda başlık "at"
      final resTodo2 = NaturalLanguageParser.parseMulti(
        'todo: at 19:30',
        activities: acts,
        measures: measures,
        openTodos: store.todos,
        now: fixedNow,
        fallbackDay: fixedNow,
      );
      expect(resTodo2.items, isNotEmpty);
      final todoItem2 = resTodo2.items.first as TodoParsedItem;
      expect(todoItem2.title, 'at');

      // at bindim 19:30 -> "At", 19:30
      final resRecord3 = NaturalLanguageParser.parseMulti(
        'at bindim 19:30',
        activities: acts,
        measures: measures,
        openTodos: store.todos,
        now: fixedNow,
        fallbackDay: fixedNow,
      );
      expect(resRecord3.items, isNotEmpty);
      final item3 = resRecord3.items.first as EntryParsedItem;
      expect(item3.activity?.name, 'At');
      expect(item3.at.hour, 19);
      expect(item3.at.minute, 30);
    });

    test('İngilizce arayüzde saat çiftleri 06:00, 15:00 ve 23:30 için birebir aynı sonucu verir', () async {
      await store.setLanguage(AppLanguage.en);
      final acts = store.activities.values.toList();
      final measures = store.measures;

      final testHours = [
        DateTime(2026, 11, 11, 6, 0),
        DateTime(2026, 11, 11, 15, 0),
        DateTime(2026, 11, 11, 23, 30),
      ];

      final pairs = [
        ('coffee at 19:30', 'coffee 19:30'),
        ('coffee at 7:30', 'coffee 7:30'),
        ('coffee at 7pm', 'coffee 19:00'),
        ('coffee at 7am', 'coffee 07:00'),
        ('yesterday at 7pm coffee', 'yesterday 19:00 coffee'),
        ('tomorrow at 7am coffee', 'tomorrow 07:00 coffee'),
      ];

      for (final refNow in testHours) {
        for (final (inputA, inputB) in pairs) {
          // Kayıt modu
          final resA = NaturalLanguageParser.parseMulti(
            inputA,
            activities: acts,
            measures: measures,
            openTodos: store.todos,
            now: refNow,
            fallbackDay: refNow,
          );
          final resB = NaturalLanguageParser.parseMulti(
            inputB,
            activities: acts,
            measures: measures,
            openTodos: store.todos,
            now: refNow,
            fallbackDay: refNow,
          );

          expect(resA.items.length, resB.items.length, reason: 'Kayıt öğe sayısı eşit olmalı: "$inputA" vs "$inputB" at $refNow');
          for (var i = 0; i < resA.items.length; i++) {
            final itemA = resA.items[i];
            final itemB = resB.items[i];
            expect(itemA.runtimeType, itemB.runtimeType, reason: 'Öğe türü eşit olmalı: "$inputA" vs "$inputB" at $refNow');
            if (itemA is EntryParsedItem && itemB is EntryParsedItem) {
              expect(itemA.activity?.name, itemB.activity?.name, reason: 'Aktivite eşit olmalı: "$inputA" vs "$inputB" at $refNow');
              expect(itemA.quantity, itemB.quantity, reason: 'Miktar eşit olmalı: "$inputA" vs "$inputB" at $refNow');
              expect(itemA.at, itemB.at, reason: 'Zaman eşit olmalı: "$inputA" vs "$inputB" at $refNow');
            } else if (itemA is TodoParsedItem && itemB is TodoParsedItem) {
              expect(itemA.title, itemB.title, reason: 'Yapılacak başlığı eşit olmalı: "$inputA" vs "$inputB" at $refNow');
              expect(itemA.suggestedAmount, itemB.suggestedAmount, reason: 'Miktar eşit olmalı: "$inputA" vs "$inputB" at $refNow');
              expect(itemA.dueDate, itemB.dueDate, reason: 'Bitiş tarihi eşit olmalı: "$inputA" vs "$inputB" at $refNow');
            }
          }

          // Yapılacak modu
          final todoA = NaturalLanguageParser.parseMulti(
            'todo: $inputA',
            activities: acts,
            measures: measures,
            openTodos: store.todos,
            now: refNow,
            fallbackDay: refNow,
          );
          final todoB = NaturalLanguageParser.parseMulti(
            'todo: $inputB',
            activities: acts,
            measures: measures,
            openTodos: store.todos,
            now: refNow,
            fallbackDay: refNow,
          );

          expect(todoA.items.length, todoB.items.length, reason: 'Yapılacak öğe sayısı eşit olmalı: "$inputA" vs "$inputB" at $refNow');
          for (var i = 0; i < todoA.items.length; i++) {
            final tItemA = todoA.items[i] as TodoParsedItem;
            final tItemB = todoB.items[i] as TodoParsedItem;
            expect(tItemA.title.toLowerCase(), tItemB.title.toLowerCase(), reason: 'Todo başlığı eşit olmalı: "$inputA" vs "$inputB" at $refNow');
            expect(tItemA.suggestedAmount, tItemB.suggestedAmount, reason: 'Todo miktarı eşit olmalı: "$inputA" vs "$inputB" at $refNow');
            expect(tItemA.dueDate, tItemB.dueDate, reason: 'Todo zamanı eşit olmalı: "$inputA" vs "$inputB" at $refNow');
          }
        }
      }
    });

    test('Noktalı am / pm cümle ortasında ve sonunda okunur', () async {
      await store.setLanguage(AppLanguage.en);
      final acts = store.activities.values.toList();
      final measures = store.measures;

      // 7 a.m. coffee -> 07:00
      final res1 = NaturalLanguageParser.parseMulti(
        '7 a.m. coffee',
        activities: acts,
        measures: measures,
        openTodos: store.todos,
        now: fixedNow,
        fallbackDay: fixedNow,
      );
      expect(res1.items, isNotEmpty);
      final item1 = res1.items.first as EntryParsedItem;
      expect(item1.activity?.name, 'Coffee');
      expect(item1.at.hour, 7);
      expect(item1.at.minute, 0);

      // 7:30 a.m. coffee yapılacak modunda -> başlıkta a.m. kalmaz ("coffee")
      final res1Todo = NaturalLanguageParser.parseMulti(
        'todo: 7:30 a.m. coffee',
        activities: acts,
        measures: measures,
        openTodos: store.todos,
        now: fixedNow,
        fallbackDay: fixedNow,
      );
      expect(res1Todo.items, isNotEmpty);
      final item1Todo = res1Todo.items.first as TodoParsedItem;
      expect(item1Todo.title, 'coffee');

      // coffee 7:30 p.m. today -> bugün 19:30
      final res2 = NaturalLanguageParser.parseMulti(
        'coffee 7:30 p.m. today',
        activities: acts,
        measures: measures,
        openTodos: store.todos,
        now: fixedNow,
        fallbackDay: fixedNow,
      );
      expect(res2.items, isNotEmpty);
      final item2 = res2.items.first as EntryParsedItem;
      expect(item2.activity?.name, 'Coffee');
      expect(item2.at.day, fixedNow.day);
      expect(item2.at.hour, 19);
      expect(item2.at.minute, 30);

      // kahve 7 a.m. içtim -> Kahve, 07:00, miktar yazılmamış (1.0)
      final res3 = NaturalLanguageParser.parseMulti(
        'kahve 7 a.m. içtim',
        activities: acts,
        measures: measures,
        openTodos: store.todos,
        now: fixedNow,
        fallbackDay: fixedNow,
      );
      expect(res3.items, isNotEmpty);
      final item3 = res3.items.first as EntryParsedItem;
      expect(item3.activity?.name, 'Kahve');
      expect(item3.at.hour, 7);
      expect(item3.at.minute, 0);
      expect(item3.parseResult.hasExplicitQuantity, isFalse);

      // 7:30 p.m. coffee -> 19:30, başlıkta/aktivitede p.m. yok
      final res4 = NaturalLanguageParser.parseMulti(
        '7:30 p.m. coffee',
        activities: acts,
        measures: measures,
        openTodos: store.todos,
        now: fixedNow,
        fallbackDay: fixedNow,
      );
      expect(res4.items, isNotEmpty);
      final item4 = res4.items.first as EntryParsedItem;
      expect(item4.activity?.name, 'Coffee');
      expect(item4.at.hour, 19);
      expect(item4.at.minute, 30);

      // Geçersiz veya saat olmayanlar (saat okunmaz)
      for (final nonClock in ['2 ampul', '5 pmt', '13pm coffee', 'coffee at 7']) {
        final tp = TimeParser.parse(nonClock, direction: TemporalDirection.past, now: fixedNow);
        expect(tp.hasExplicitTime, isFalse, reason: 'Saat okunmamalı: "$nonClock"');
      }
    });

    test('Kök eşleştirme: e düşen fiiller, aday kümeleri ve iki harfli koruma', () async {
      final acts = store.activities.values.toList();
      final measures = store.measures;
      // Eşleşmeli
      final shouldMatch = [
        ('hiked', 'Hiking'),
        ('hike', 'Hiking'),
        ('hikes', 'Hiking'),
        ('biked', 'Biking'),
        ('danced', 'Dancing'),
        ('dance', 'Dancing'),
        ('meditated', 'Meditating'),
        ('baked', 'Baking'),
        ('ate', 'Eating'),
        ('eat', 'Eating'),
        ('wrote', 'Writing'),
        ('rode', 'Riding'),
        ('swam', 'Swimming'),
        ('ran', 'Running'),
        ('run', 'Running'),
        ('runs', 'Running'),
        ('studied', 'Study'),
        ('studies', 'Study'),
        ('studying', 'Study'),
        ('squats', 'Squat'),
        ('squat', 'Squats'),
        ('walked', 'Walk'),
      ];

      for (final (input, target) in shouldMatch) {
        expect(
          matchesEnglishCandidates(input, target),
          isTrue,
          reason: '$input -> $target eşleşmeli (adaylar: ${englishWordCandidates(input)} vs ${englishWordCandidates(target)})',
        );
      }

      // Eşleşmemeli
      final shouldNotMatch = [
        ('ka', 'Kas'),
        ('ya', 'Yas'),
        ('win', 'Wine'),
        ('wins', 'Wine'),
        ('red', 'Reading'),
        ('bed', 'Bid'),
        ('ran', 'Ranch'),
        ('runner', 'Run'),
        ('car', 'Care'),
        ('need', 'Reading'),
      ];

      for (final (input, target) in shouldNotMatch) {
        expect(
          matchesEnglishCandidates(input, target),
          isFalse,
          reason: '$input -> $target eşleşmemeli',
        );
      }

      // NaturalLanguageParser üzerinden yanlış eşleşmeme doğrulaması
      final kaRes = NaturalLanguageParser.parseMulti(
        'ka',
        activities: acts,
        measures: measures,
        openTodos: store.todos,
        now: fixedNow,
        fallbackDay: fixedNow,
      );
      final kaItem = kaRes.items.first as EntryParsedItem;
      expect(kaItem.activity?.name, isNot('Kas'), reason: '"ka" girdisi "Kas" aktivitesiyle eşleşmemeli');

      final yaRes = NaturalLanguageParser.parseMulti(
        'ya',
        activities: acts,
        measures: measures,
        openTodos: store.todos,
        now: fixedNow,
        fallbackDay: fixedNow,
      );
      final yaItem = yaRes.items.first as EntryParsedItem;
      expect(yaItem.activity?.name, isNot('Yas'), reason: '"ya" girdisi "Yas" aktivitesiyle eşleşmemeli');

      final winRes = NaturalLanguageParser.parseMulti(
        'win',
        activities: acts,
        measures: measures,
        openTodos: store.todos,
        now: fixedNow,
        fallbackDay: fixedNow,
      );
      final winItem = winRes.items.first as EntryParsedItem;
      expect(winItem.activity?.name, isNot('Wine'), reason: '"win" girdisi "Wine" ile eşleşmemeli');

      final winsRes = NaturalLanguageParser.parseMulti(
        'wins',
        activities: acts,
        measures: measures,
        openTodos: store.todos,
        now: fixedNow,
        fallbackDay: fixedNow,
      );
      final winsItem = winsRes.items.first as EntryParsedItem;
      expect(winsItem.activity?.name, isNot('Wine'), reason: '"wins" girdisi "Wine" ile eşleşmemeli');
    });

    test('Serbest metinde fiil çekimiyle aktivite çözümlenmesi', () async {
      await store.setLanguage(AppLanguage.en);
      final acts = store.activities.values.toList();
      final measures = store.measures;

      final testCases = [
        ('hiked 5 km', 'Hiking', 5.0),
        ('biked 10 km', 'Biking', 10.0),
        ('meditated 10 min', 'Meditating', 10.0),
        ('dance 30 min', 'Dancing', 30.0),
      ];

      for (final (input, expectedAct, expectedQty) in testCases) {
        final res = NaturalLanguageParser.parseMulti(
          input,
          activities: acts,
          measures: measures,
          openTodos: store.todos,
          now: fixedNow,
          fallbackDay: fixedNow,
        );
        expect(res.items, isNotEmpty, reason: 'Girdi ayrıştırılamadı: $input');
        final item = res.items.first as EntryParsedItem;
        expect(item.activity?.name, expectedAct, reason: 'Aktivite uyuşmadı: $input');
        expect(item.quantity, expectedQty, reason: 'Miktar uyuşmadı: $input');
      }
    });
  });
}
