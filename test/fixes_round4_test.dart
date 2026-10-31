import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:takip/data/models.dart';
import 'package:takip/data/store.dart';
import 'package:takip/services/nl_parser.dart';
import 'package:takip/ui/today_page.dart';

import 'support/real_db.dart';

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

Future<void> finish(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.runAsync(() async {
    for (final t in List.of(store.activeTimers)) {
      await store.cancelTimer(t.id);
    }
  });
  await tester.pump(const Duration(seconds: 6));
}

void main() {
  useRealDatabase();
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initializeDateFormatting('tr_TR', null);
  });

  group('Fixes Round 4 - Ad Temizleme ve Eşleşme Düzeltmeleri', () {
    test('1. Koşu yokken "30 dk kostum" ve "2 saat once 30 dk kostum" aktivite adını "Koşu" yapar, süreyi addan temizler', () async {
      final now = DateTime(2026, 10, 31, 12, 0);

      // 1.1 "30 dk kostum"
      final res1 = NaturalLanguageParser.parseMulti(
        '30 dk kostum',
        activities: const [],
        measures: const [],
        now: now,
      );
      expect(res1.items.length, 1);
      final item1 = res1.items.first as EntryParsedItem;
      expect(item1.activity, isNull);
      expect(item1.activityName, 'Koşu');
      expect(item1.activityName.contains(RegExp(r'\d')), isFalse, reason: 'Adda rakam olmamalı');
      expect(item1.activityName.toLowerCase().contains('dk'), isFalse, reason: 'Adda birim olmamalı');
      expect(item1.quantity, 30.0);

      // 1.2 "2 saat once 30 dk kostum"
      final res2 = NaturalLanguageParser.parseMulti(
        '2 saat once 30 dk kostum',
        activities: const [],
        measures: const [],
        now: now,
      );
      expect(res2.items.length, 1);
      final item2 = res2.items.first as EntryParsedItem;
      expect(item2.activity, isNull);
      expect(item2.activityName, 'Koşu');
      expect(item2.activityName.contains(RegExp(r'\d')), isFalse, reason: 'Adda rakam olmamalı');
      expect(item2.activityName.toLowerCase().contains('dk'), isFalse, reason: 'Adda birim olmamalı');
      expect(item2.quantity, 30.0);

      // Zaman kuralı: 2 saat önce bitiş, 30 dk önce başlangıç
      expect(item2.endAt, isNotNull);
      expect(item2.endAt, DateTime(2026, 10, 31, 10, 0));
      expect(item2.at, DateTime(2026, 10, 31, 9, 30));
    });

    testWidgets('2. Yürüyüş varken "20 dk yurudum" yazıldığında "Yeni Olarak Ekle" önerisi çıkmaz', (tester) async {
      await tester.runAsync(() async {
        await store.load();
        await store.addActivity('Yürüyüş', emoji: '🚶');
      });
      await pumpToday(tester);

      final composerField = find.byType(TextField).last;
      await tester.enterText(composerField, '20 dk yurudum');
      await tester.pump();

      // "Yeni Olarak Ekle" önerisi çıkmamalı
      expect(find.textContaining('Yeni Olarak Ekle'), findsNothing,
          reason: 'Mevcut bir aktiviteye eşleştiğinde Yeni Olarak Ekle önerisi çıkmamalıdır');
      // Önizleme Yürüyüş olmalı
      expect(find.textContaining('Yürüyüş: 20 dk eklenecek'), findsOneWidget);

      await finish(tester);
    });

    test('3. Davranış korunur: "dun gece 500 ml su", "2 kahve" ve çok öğe yolu', () async {
      final now = DateTime(2026, 10, 31, 12, 0);
      final actWater = Activity(id: 1, name: 'Su', emoji: '💧', createdAt: 0);
      final actCoffee = Activity(id: 2, name: 'Kahve', emoji: '☕', createdAt: 0);
      final actWalk = Activity(id: 3, name: 'Yürüyüş', emoji: '🚶', createdAt: 0);
      final measureMl = Measure(id: 1, name: 'ml', unitId: 'ml', amount: 1.0);

      // 3.1 "dun gece 500 ml su"
      final r1 = NaturalLanguageParser.parseMulti(
        'dun gece 500 ml su',
        activities: [actWater],
        measures: [measureMl],
        now: now,
      );
      final it1 = r1.items.first as EntryParsedItem;
      expect(it1.activity?.id, actWater.id);
      expect(it1.quantity, 500.0);
      expect(it1.at, DateTime(2026, 10, 30, 22, 0));

      // 3.2 "2 kahve"
      final r2 = NaturalLanguageParser.parseMulti(
        '2 kahve',
        activities: [actCoffee],
        measures: const [],
        now: now,
      );
      final it2 = r2.items.first as EntryParsedItem;
      expect(it2.activity?.id, actCoffee.id);
      expect(it2.quantity, 2.0);

      // 3.3 Çoklu girdi: "2 kahve ve 20 dk yurudum"
      final r3 = NaturalLanguageParser.parseMulti(
        '2 kahve ve 20 dk yurudum',
        activities: [actCoffee, actWalk],
        measures: const [],
        now: now,
      );
      expect(r3.items.length, 2);
      final it3a = r3.items[0] as EntryParsedItem;
      final it3b = r3.items[1] as EntryParsedItem;
      expect(it3a.activity?.id, actCoffee.id);
      expect(it3b.activity?.id, actWalk.id);
    });

    test('4. Ses yolu yazıyla aynı sonucu verir', () async {
      final now = DateTime(2026, 10, 31, 12, 0);
      // Sesle gelen "2 saat once 30 dk kostum"
      final voiceMulti = NaturalLanguageParser.parseMulti(
        '2 saat once 30 dk kostum',
        activities: const [],
        measures: const [],
        now: now,
      );
      final single = NaturalLanguageParser.parse(
        '2 saat once 30 dk kostum',
        activities: const [],
        measures: const [],
      );

      final it = voiceMulti.items.first as EntryParsedItem;
      expect(it.activityName, 'Koşu');
      expect(single.activityName, 'Koşu', reason: 'Tekil parse da çoklu parse da aynı temiz aktivite adını üretmeli');
    });

    test('5. Yedekleme menü yolu metni TR ve EN doğrulaması', () async {
      await store.load();

      // store.dart unmeasuredFixMessage formatı denetimi
      final msgTr = store.formatUnmeasuredFixMessage(8, isTr: true);
      final msgEn = store.formatUnmeasuredFixMessage(8, isTr: false);

      expect(msgTr, contains('(Ayarlar › Yedekleme & Raporlama › Yerel Yedekler)'));
      expect(msgEn, contains('(Settings › Backup & Reports › Local Backups)'));
      expect(msgTr.contains('(Ayarlar › Yedekler)'), isFalse);
    });
  });
}
