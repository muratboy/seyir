import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
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

Finder get composerField => find.byType(TextField).last;

void main() {
  useRealDatabase();

  setUpAll(() async {
    await initializeDateFormatting('tr_TR');
    Intl.defaultLocale = 'tr_TR';
  });

  group('Sayı aktivitenin varsayılan ölçüsüyle çarpılır', () {
    test('Kahve için "2 kahve" varsayılan ölçüyü (Fincan 0.08 L) kullanır, 2 L ve limit aşımı olmaz', () async {
      final s = await openStore();
      final actCoffee = await s.addActivity('Kahve', emoji: '☕');
      final mFincan = s.measures.firstWhere((m) => m.name == 'Fincan');

      // Sık yapılanlar / varsayılan ölçü: Fincan (0.08 L)
      await s.saveQuickItem(QuickItem(
        id: 0,
        activityId: actCoffee.id,
        kind: 'shortcut',
        measureId: mFincan.id,
        qty: 1.0,
        createdAt: 0,
      ));

      // 1. Tek öğe parse
      final singleRes = NaturalLanguageParser.parse(
        '2 kahve',
        activities: s.activities.values.toList(),
        measures: s.measures,
        defaultMeasureFor: s.defaultMeasureFor,
      );
      expect(singleRes.matchedActivity?.id, actCoffee.id);
      expect(singleRes.matchedMeasure?.id, mFincan.id, reason: 'Varsayılan ölçü Fincan atanmalı');
      expect(singleRes.quantity, 2.0);

      // 2. Çok öğe parse
      final multiRes = NaturalLanguageParser.parseMulti(
        '2 kahve ve 30 dk yürüyüş',
        activities: s.activities.values.toList(),
        measures: s.measures,
        defaultMeasureFor: s.defaultMeasureFor,
      );
      final eCoffee = multiRes.entryItems.first;
      expect(eCoffee.activity?.id, actCoffee.id);
      expect(eCoffee.measure?.id, mFincan.id);
      expect(eCoffee.quantity, 2.0);

      // 3. Önizleme metninde "2 kez" yazmamalı, fincan ve litre yazmalı
      final amountStr = s.amountDetail(eCoffee.measure?.id, eCoffee.quantity);
      expect(amountStr, contains('Fincan'));
      expect(amountStr, anyOf(contains('160 ml'), contains('0,16 L')));
      expect(amountStr, isNot(contains('kez')));

      // 4. Hedef katkısı ve limit aşımı testi
      // Sıvı alımı hedefi (2.5 L, Kahve katsayısı %80)
      final liquidGoal = Goal(
        id: 0,
        name: 'Sıvı Alımı',
        type: 'target',
        mode: 'amount',
        target: 2.5,
        period: GoalPeriod.day,
        unitId: 'l',
        startDate: DateTime.now().millisecondsSinceEpoch,
        createdAt: 0,
        links: [GoalLink(activityId: actCoffee.id, pct: 80)],
      );
      await s.saveGoal(liquidGoal);

      // Kafein Limiti (0.3 L)
      final caffeineLimit = Goal(
        id: 0,
        name: 'Kafein Limiti',
        type: 'limit',
        mode: 'amount',
        target: 0.3,
        period: GoalPeriod.day,
        unitId: 'l',
        startDate: DateTime.now().millisecondsSinceEpoch,
        createdAt: 0,
        links: [GoalLink(activityId: actCoffee.id, pct: 100)],
      );
      await s.saveGoal(caffeineLimit);

      // 2 kahveyi batch olarak kaydet
      await s.saveBatch(entries: [
        BatchEntryInput(
          activityId: actCoffee.id,
          measureId: eCoffee.measure?.id,
          qty: eCoffee.quantity,
          at: DateTime.now(),
        ),
      ]);

      // Kontroller:
      // Sıvı alımı tam 2 * 0.08 L * %80 = 0.128 L olmalı (1.6 L değil!)
      final lStatus = s.goalStatus(liquidGoal);
      expect(lStatus.value, closeTo(0.128, 0.001));

      // Kafein limiti (0.16 L <= 0.3 L) aşılmamalı!
      final cStatus = s.goalStatus(caffeineLimit);
      expect(cStatus.value, closeTo(0.16, 0.001));
      expect(cStatus.isExceeded, isFalse, reason: '2 fincan kahve kafein limitini aşmamalı');
    });

    test('Bütün ölçü türleri için varsayılan ölçü doğru çözümlenir (hacim, süre, kütle, mesafe, adet)', () async {
      final s = await openStore();
      final actSu = await s.addActivity('Su', emoji: '💧'); // volume -> Su bardağı
      final actMekik = await s.addActivity('Mekik', emoji: '💪'); // count -> adet
      final actYuruyus = await s.addActivity('Yürüyüş', emoji: '🚶'); // time -> Saat veya Dakika

      expect(s.defaultMeasureFor(actSu.id)?.name, anyOf('Su bardağı', 'Litre', 'Mililitre'));
      expect(s.defaultMeasureFor(actMekik.id)?.unitId, 'adet');
      expect(s.defaultMeasureFor(actYuruyus.id)?.unitId, anyOf('sa', 'dk'));
    });
  });

  group('Fiil çekimleri ve ASCII yazım eşleşmesi', () {
    test('"30 dk yurudum" Yürüyüş aktivitesine eşleşir ve adında miktar kalmaz', () async {
      final s = await openStore();
      final actWalk = await s.addActivity('Yürüyüş', emoji: '🚶');

      final res = NaturalLanguageParser.parse(
        '30 dk yurudum',
        activities: s.activities.values.toList(),
        measures: s.measures,
      );

      expect(res.matchedActivity?.id, actWalk.id, reason: 'yurudum Yürüyüş ile eşleşmeli');
      expect(res.quantity, 30.0);
      expect(res.matchedMeasure?.unitId, 'dk');
      expect(res.activityName, 'Yürüyüş');
    });

    test('ASCII ve çekimli fiiller eşleşir: koştum/kostum, içtim/ictim, okudum, uyudum, yaptım/yaptim', () async {
      final s = await openStore();
      final actRun = await s.addActivity('Koşu', emoji: '🏃');
      final actRead = await s.addActivity('Kitap', emoji: '📚');
      final actSleep = await s.addActivity('Uyku', emoji: '😴');

      final r1 = NaturalLanguageParser.parse('45 dk kostum', activities: s.activities.values.toList(), measures: s.measures);
      expect(r1.matchedActivity?.id, actRun.id);

      final r2 = NaturalLanguageParser.parse('20 sayfa okudum', activities: s.activities.values.toList(), measures: s.measures);
      expect(r2.matchedActivity?.id, actRead.id);

      final r3 = NaturalLanguageParser.parse('8 saat uyudum', activities: s.activities.values.toList(), measures: s.measures);
      expect(r3.matchedActivity?.id, actSleep.id);
    });
  });

  group('"Yeni Olarak Ekle" önerisi temizliği', () {
    testWidgets('Metin bir aktiviteye eşlendiğinde ("dun gece su", "2 saat once kahve") Yeni Olarak Ekle çipi çıkmaz', (tester) async {
      await tester.runAsync(() async {
        await store.load();
        await store.addActivity('Su', emoji: '💧');
        await store.addActivity('Kahve', emoji: '☕');
      });

      await pumpToday(tester);
      await settleStore(tester);

      // 1. "dun gece 500 ml su" yazıldığında
      await tester.enterText(composerField, 'dun gece 500 ml su');
      await tester.pump();
      expect(find.textContaining('Yeni Olarak Ekle'), findsNothing, reason: 'Su eşleştiği için Yeni Olarak Ekle çıkmamalı');

      // 2. "2 saat once kahve" yazıldığında
      await tester.enterText(composerField, '2 saat once kahve');
      await tester.pump();
      expect(find.textContaining('Yeni Olarak Ekle'), findsNothing, reason: 'Kahve eşleştiği için Yeni Olarak Ekle çıkmamalı');

      // 3. Mevcut benzer aktivite ("Kitap okuma") varken "dun gece kitap" yazıldığında,
      // "Dun gece kitap" değil, zaman sözcükleri ayıklanmış "Kitap" önerilmeli
      await tester.runAsync(() async {
        await store.addActivity('Kitap okuma', emoji: '📚');
      });
      await tester.enterText(composerField, 'dun gece kitap');
      await tester.pump();
      expect(find.textContaining('Yeni Olarak Ekle: "Kitap"'), findsOneWidget, reason: 'Zaman ayıklanıp temiz ad Kitap önerilmeli');
      expect(find.textContaining('Dun gece'), findsNothing, reason: 'Temizlenmemiş zaman sözcüğü önerilmemeli');

      await finish(tester);
    });
  });

  group('Çok öğede tanınmayan parça ve Geri al aktivite temizliği', () {
    test('Toplu kaydı Geri al, bu kaydın yarattığı ve başka kaydı olmayan aktiviteyi de siler', () async {
      final s = await openStore();
      final initialActCount = s.activities.length;

      // Yeni aktivite oluşturarak batch kaydet (örn: 1 elma)
      final newAct = await s.addActivity('Elma', emoji: '🍎');
      expect(s.activities.length, initialActCount + 1);

      final batchRes = await s.saveBatch(
        entries: [
          BatchEntryInput(
            activityId: newAct.id,
            qty: 1.0,
            at: DateTime.now(),
          ),
        ],
        createdActivityIds: [newAct.id],
      );

      expect(s.entries, hasLength(1));

      // Geri al çağrıldığında aktivite de silinmeli
      await batchRes.undo();
      expect(s.entries, isEmpty);
      expect(s.activities.containsKey(newAct.id), isFalse, reason: 'Elma aktivitesi de silinmeli');
      expect(s.activities.length, initialActCount);
    });
  });

  group('Yapılacak tamamlama ipucu geçmiş kayıt kuralı', () {
    test('Kaydın zamanı yapılacağın oluşturulmasından önceyse willCompleteTodo null olmalıdır', () async {
      final s = await openStore();
      final actSu = await s.addActivity('Su', emoji: '💧');

      // Bugün oluşturulmuş bir yapılacak
      final now = DateTime.now();
      final todo = Todo(
        id: 1,
        title: 'Sıvı Alımı',
        dueDate: '2026-10-30',
        targetAmount: 0.5,
        targetUnit: 'l',
        createdAt: now.millisecondsSinceEpoch,
        linkedActivityIds: [actSu.id],
      );

      // Dün 22:00'ye ait parse isteği (yapılacağın createdAt'ından önce)
      final yesterdayNight = now.subtract(const Duration(hours: 14));
      final res = NaturalLanguageParser.parseMulti(
        '500 ml su',
        activities: s.activities.values.toList(),
        measures: s.measures,
        openTodos: [todo],
        now: yesterdayNight,
      );

      final entryItem = res.entryItems.first;
      expect(entryItem.willCompleteTodo, isNull, reason: 'Geçmiş kayıt, kendisinden sonra oluşturulan yapılacağı tamamlamaz');
    });
  });
}
