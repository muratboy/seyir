import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:takip/data/models.dart';
import 'package:takip/data/store.dart';
import 'package:takip/logic/l10n.dart';

import 'support/real_db.dart';

void main() {
  useRealDatabase();

  setUpAll(() async {
    await initializeDateFormatting('tr_TR');
    await initializeDateFormatting('en_US');
  });

  group('Kayıttan Yapılacağa Çevirme (convertEntryToTodo) Store Testleri', () {
    test('miktarlı kaydı yapılacağa çevirir, hedef ilerlemesini düşürür ve geri al eski hâle getirir', () async {
      final s = AppStore();
      await s.load();

      final act = await s.addActivity('Koşu', emoji: '🏃');
      final m = s.measures.firstWhere((x) => x.unitId == 'km');

      // 10 km koşu hedefi
      final goal = Goal(
        id: 0,
        name: 'Haftalık Koşu',
        type: 'target',
        mode: 'amount',
        unitId: 'km',
        target: 10,
        period: GoalPeriod.week,
        startDate: DateTime.now().subtract(const Duration(days: 1)).millisecondsSinceEpoch,
        createdAt: DateTime.now().millisecondsSinceEpoch,
        links: [GoalLink(activityId: act.id, pct: 100)],
      );
      await s.saveGoal(goal);

      // 5 km koşu kaydı ekle
      final now = DateTime.now();
      final addRes = await s.addEntry(
        act.id,
        measureId: m.id,
        qty: 5,
        note: 'Sabah parkurunda',
        at: now,
      );
      final entry = addRes.entry;

      // Hedef durumu kontrolü: 5 km ilerleme olmalı
      final statusBefore = s.goalStatus(goal);
      expect(statusBefore.value, 5.0);
      expect(s.entries.any((e) => e.id == entry.id), isTrue);

      // Kaydı yapılacağa çevir
      final res = await s.convertEntryToTodo(entry);
      final todo = res.todo;

      // Yapılacak alanları
      expect(todo.title, '5 km Koşu');
      expect(todo.note, 'Sabah parkurunda');
      expect(todo.targetAmount, 5.0);
      expect(todo.targetUnit, 'km');
      expect(todo.linkedActivityIds, [act.id]);
      expect(s.todos.any((t) => t.id == todo.id), isTrue);

      // Kayıt silinmiş olmalı
      expect(s.entries.any((e) => e.id == entry.id), isFalse);

      // Hedef ilerlemesi düşmüş olmalı (0 km)
      final statusAfter = s.goalStatus(goal);
      expect(statusAfter.value, 0.0);

      // Geri al işlemi
      await res.undo();

      // Yapılacak silinmiş, kayıt aynı id ve alanlarla geri dönmüş olmalı
      expect(s.todos.any((t) => t.id == todo.id), isFalse);
      expect(s.entries.any((e) => e.id == entry.id), isTrue);
      final restored = s.entries.firstWhere((e) => e.id == entry.id);
      expect(restored.id, entry.id);
      expect(restored.qty, entry.qty);
      expect(restored.note, 'Sabah parkurunda');
      expect(restored.ts, entry.ts);

      // Hedef ilerlemesi tekrar 5 km olmalı
      final statusRestored = s.goalStatus(goal);
      expect(statusRestored.value, 5.0);
    });

    test('miktarsız kaydı aktivite adıyla yapılacağa çevirir', () async {
      final s = AppStore();
      await s.load();

      final act = await s.addActivity('Kitap okuma', emoji: '📖');
      final addRes = await s.addEntry(act.id, qty: 1);
      final entry = addRes.entry;

      final res = await s.convertEntryToTodo(entry);
      expect(res.todo.title, 'Kitap okuma');
      expect(res.todo.targetAmount, isNull);
      expect(res.todo.linkedActivityIds, [act.id]);
      expect(s.entries.any((e) => e.id == entry.id), isFalse);
      expect(s.todos.any((t) => t.id == res.todo.id), isTrue);

      await res.undo();
      expect(s.todos.any((t) => t.id == res.todo.id), isFalse);
      expect(s.entries.any((e) => e.id == entry.id), isTrue);
    });

    test('otomatik adım ve uyku aktiviteleri için canConvertEntryToTodo false döner', () async {
      final s = AppStore();
      await s.load();

      await s.setLanguage(AppLanguage.tr);
      await s.syncTodayStepsToEntry(steps: 5000);
      final stepEntry = s.entries.firstWhere((e) => e.activityId == s.stepsActivity!.id);

      expect(s.canConvertEntryToTodo(stepEntry), isFalse);

      final normalAct = await s.addActivity('Yüzme', emoji: '🏊');
      final normalEntry = (await s.addEntry(normalAct.id, qty: 1)).entry;
      expect(s.canConvertEntryToTodo(normalEntry), isTrue);
    });

    test('İngilizce dilde başlıkta min sembolü kullanılır', () async {
      final s = AppStore();
      await s.load();
      await s.setLanguage(AppLanguage.en);

      final act = await s.addActivity('Running', emoji: '🏃');
      final startTime = DateTime.now().subtract(const Duration(minutes: 30));
      final addRes = await s.addEntry(
        act.id,
        qty: 1,
        at: startTime,
        endAt: DateTime.now(),
      );
      final entry = addRes.entry;

      final res = await s.convertEntryToTodo(entry);
      expect(res.todo.title, '30 min Running');
      expect(res.todo.targetAmount, 30.0);
      expect(res.todo.targetUnit, 'dk');
    });

    test('ölçü ve süre birlikteyse hedef süreden değil ölçüden belirlenir', () async {
      final s = AppStore();
      await s.load();
      await s.setLanguage(AppLanguage.tr);

      final act = await s.addActivity('Koşu', emoji: '🏃');
      final mKm = s.measures.firstWhere((x) => x.unitId == 'km');
      final startTime = DateTime.now().subtract(const Duration(minutes: 45));

      // 45 dk süresi olan ama 5 km ölçüsü verilmiş kayıt
      final addRes = await s.addEntry(
        act.id,
        measureId: mKm.id,
        qty: 5,
        at: startTime,
        endAt: DateTime.now(),
      );
      final entry = addRes.entry;
      expect(entry.duration?.inMinutes, 45);

      final res = await s.convertEntryToTodo(entry);
      // Hedef 45 dk değil, 5 km olmalı!
      expect(res.todo.title, '5 km Koşu');
      expect(res.todo.targetAmount, 5.0);
      expect(res.todo.targetUnit, 'km');
    });

    test('sayfadaki güncel değerlerle çevrilir ve geri al kaydı değiştirmeden getirir', () async {
      final s = AppStore();
      await s.load();
      await s.setLanguage(AppLanguage.tr);

      final act = await s.addActivity('Koşu', emoji: '🏃');
      final mKm = s.measures.firstWhere((x) => x.unitId == 'km');

      final addRes = await s.addEntry(
        act.id,
        measureId: mKm.id,
        qty: 3,
        note: 'Eski orijinal not',
        at: DateTime.now(),
      );
      final entry = addRes.entry;

      // Sayfada kaydedilmemiş değişiklikler var: miktar 8 km ve not değiştirilmiş
      final res = await s.convertEntryToTodo(
        entry,
        qty: 8,
        note: 'Sayfadaki kaydedilmemiş güncel not',
      );

      // Yapılacak güncel değerlerle oluşmalı
      expect(res.todo.title, '8 km Koşu');
      expect(res.todo.targetAmount, 8.0);
      expect(res.todo.note, 'Sayfadaki kaydedilmemiş güncel not');

      // Ancak orijinal entry nesnesi mutate edilmemiş olmalı
      expect(entry.note, 'Eski orijinal not');
      expect(entry.qty, 3.0);

      // Geri al işlemi kaydı orijinal hâliyle geri yüklemeli
      await res.undo();
      expect(s.entries.any((e) => e.id == entry.id), isTrue);
      final restored = s.entries.firstWhere((e) => e.id == entry.id);
      expect(restored.note, 'Eski orijinal not');
      expect(restored.qty, 3.0);
    });

    test('aktivite değişti ve ölçü seçilmediğinde hedefsiz ve yeni aktivite adıyla yapılacak oluşur', () async {
      final s = AppStore();
      await s.load();
      await s.setLanguage(AppLanguage.tr);

      final actKosu = await s.addActivity('Koşu', emoji: '🏃');
      final actKitap = await s.addActivity('Kitap okuma', emoji: '📖');
      final mKm = s.measures.firstWhere((x) => x.unitId == 'km');

      final baseTime = DateTime(2026, 5, 10, 10, 0);
      final addRes = await s.addEntry(
        actKosu.id,
        measureId: mKm.id,
        qty: 5,
        note: 'Sabah koşusu',
        at: baseTime,
      );
      final entry = addRes.entry;

      // Sayfada aktivite Kitap okuma seçilmiş, ölçü null
      final res = await s.convertEntryToTodo(
        entry,
        activityId: actKitap.id,
        measureId: null,
      );

      expect(res.todo.title, 'Kitap okuma');
      expect(res.todo.targetAmount, isNull);
      expect(res.todo.targetUnit, isNull);
      expect(res.todo.linkedActivityIds, [actKitap.id]);
      expect(res.todo.note, 'Sabah koşusu');
    });

    test('aktivite değişti ve süre var ise hedef yeni aktivite ve süre olur', () async {
      final s = AppStore();
      await s.load();
      await s.setLanguage(AppLanguage.tr);

      final actKosu = await s.addActivity('Koşu', emoji: '🏃');
      final actDers = await s.addActivity('Ders Çalışma', emoji: '📚');

      final startTime = DateTime(2026, 5, 10, 10, 0);
      final endTime = DateTime(2026, 5, 10, 10, 30);
      final addRes = await s.addEntry(
        actKosu.id,
        qty: 1,
        at: startTime,
        endAt: endTime,
      );
      final entry = addRes.entry;

      // Sayfada aktivite Ders Çalışma yapıldı, ölçü seçilmedi
      final res = await s.convertEntryToTodo(
        entry,
        activityId: actDers.id,
        measureId: null,
      );

      expect(res.todo.title, '30 dk Ders Çalışma');
      expect(res.todo.targetAmount, 30.0);
      expect(res.todo.targetUnit, 'dk');
      expect(res.todo.linkedActivityIds, [actDers.id]);
    });

    test('ölçü bilerek kaldırıldığında miktar hedefi oluşmaz, süre varsa süre hedef olur', () async {
      final s = AppStore();
      await s.load();
      await s.setLanguage(AppLanguage.tr);

      final act = await s.addActivity('Koşu', emoji: '🏃');
      final mKm = s.measures.firstWhere((x) => x.unitId == 'km');

      final baseTime = DateTime(2026, 5, 10, 10, 0);
      final addRes = await s.addEntry(
        act.id,
        measureId: mKm.id,
        qty: 5,
        at: baseTime,
      );
      final entry = addRes.entry;

      // Ölçü kaldırıldı (measureId: null)
      final resNoDuration = await s.convertEntryToTodo(
        entry,
        measureId: null,
      );
      expect(resNoDuration.todo.title, 'Koşu');
      expect(resNoDuration.todo.targetAmount, isNull);
      expect(resNoDuration.todo.targetUnit, isNull);

      // Süresi de olan kayıtta ölçü kaldırılırsa süre hedefe dönüşür
      final addRes2 = await s.addEntry(
        act.id,
        measureId: mKm.id,
        qty: 5,
        at: baseTime,
        endAt: DateTime(2026, 5, 10, 10, 45),
      );
      final entry2 = addRes2.entry;

      final resWithDuration = await s.convertEntryToTodo(
        entry2,
        measureId: null,
      );
      expect(resWithDuration.todo.title, '45 dk Koşu');
      expect(resWithDuration.todo.targetAmount, 45.0);
      expect(resWithDuration.todo.targetUnit, 'dk');
    });

    test('ölçüsüz ve bitiş zamanı olan kronometre kaydı çevrilince dakika hedefi oluşur', () async {
      final s = AppStore();
      await s.load();
      await s.setLanguage(AppLanguage.tr);

      final act = await s.addActivity('Yürüyüş', emoji: '🚶');
      final startTime = DateTime(2026, 5, 10, 9, 0);
      final endTime = DateTime(2026, 5, 10, 9, 25); // 25 dk
      final addRes = await s.addEntry(
        act.id,
        at: startTime,
        endAt: endTime,
      );
      final entry = addRes.entry;

      // Sayfa süre ölçüsü seçili değilken endTs: null gönderse bile bitiş zamanı korunmalı
      final res = await s.convertEntryToTodo(
        entry,
        endTs: null,
      );

      expect(res.todo.title, '25 dk Yürüyüş');
      expect(res.todo.targetAmount, 25.0);
      expect(res.todo.targetUnit, 'dk');
      expect(res.todo.linkedActivityIds, [act.id]);
    });

    test('sayfadaki adet değişikliği yapılacak hedefine yansır', () async {
      final s = AppStore();
      await s.load();
      await s.setLanguage(AppLanguage.tr);

      // Ölçülü kayıt: 1 km * 3 = 3 km
      final actKosu = await s.addActivity('Koşu', emoji: '🏃');
      final mKm = s.measures.firstWhere((x) => x.unitId == 'km');
      final entryKosu = (await s.addEntry(actKosu.id, measureId: mKm.id, qty: 1)).entry;

      final resKosu = await s.convertEntryToTodo(entryKosu, qty: 3);
      expect(resKosu.todo.title, '3 km Koşu');
      expect(resKosu.todo.targetAmount, 3.0);
      expect(resKosu.todo.targetUnit, 'km');

      // Ölçüsüz kayıt: 4 adet
      final actKitap = await s.addActivity('Kitap okuma', emoji: '📖');
      final entryKitap = (await s.addEntry(actKitap.id, qty: 1)).entry;

      final resKitap = await s.convertEntryToTodo(entryKitap, qty: 4);
      expect(resKitap.todo.title, '4 adet Kitap okuma');
      expect(resKitap.todo.targetAmount, 4.0);
      expect(resKitap.todo.targetUnit, 'adet');
    });

    test('aktivite veya ölçü değiştirilerek çevrilen kayıtta geri al orijinal alanları aynen getirir', () async {
      final s = AppStore();
      await s.load();
      await s.setLanguage(AppLanguage.tr);

      final actKosu = await s.addActivity('Koşu', emoji: '🏃');
      final actKitap = await s.addActivity('Kitap okuma', emoji: '📖');
      final mKm = s.measures.firstWhere((x) => x.unitId == 'km');

      final originalTime = DateTime(2026, 5, 10, 8, 30);
      final originalEnd = DateTime(2026, 5, 10, 9, 15);
      final addRes = await s.addEntry(
        actKosu.id,
        measureId: mKm.id,
        qty: 5,
        note: 'Sabah parkur koşusu',
        at: originalTime,
        endAt: originalEnd,
      );
      final entry = addRes.entry;

      // Sayfada aktivite değiştirildi, adet 2 yapıldı
      final res = await s.convertEntryToTodo(
        entry,
        activityId: actKitap.id,
        measureId: null,
        qty: 2,
        note: 'Yeni not',
      );

      // Orijinal entry nesnesi bellekte mutate edilmemiş olmalı
      expect(entry.activityId, actKosu.id);
      expect(entry.measureId, mKm.id);
      expect(entry.qty, 5.0);
      expect(entry.value, 5.0);
      expect(entry.unitId, 'km');
      expect(entry.note, 'Sabah parkur koşusu');
      expect(entry.ts, originalTime.millisecondsSinceEpoch);
      expect(entry.endTs, originalEnd.millisecondsSinceEpoch);

      // Geri al çağrıldığında DB'deki kayıt orijinal değerleriyle geri dönmeli
      await res.undo();
      expect(s.todos.any((t) => t.id == res.todo.id), isFalse);
      expect(s.entries.any((e) => e.id == entry.id), isTrue);

      final restored = s.entries.firstWhere((e) => e.id == entry.id);
      expect(restored.activityId, actKosu.id);
      expect(restored.measureId, mKm.id);
      expect(restored.qty, 5.0);
      expect(restored.value, 5.0);
      expect(restored.unitId, 'km');
      expect(restored.note, 'Sabah parkur koşusu');
      expect(restored.ts, originalTime.millisecondsSinceEpoch);
      expect(restored.endTs, originalEnd.millisecondsSinceEpoch);
    });
  });
}
