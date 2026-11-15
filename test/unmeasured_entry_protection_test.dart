import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:takip/data/models.dart';
import 'package:takip/data/store.dart';
import 'package:takip/services/backup_service.dart';
import 'package:takip/services/nl_parser.dart';

import 'support/real_db.dart';

void main() {
  useRealDatabase();
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initializeDateFormatting('tr_TR', null);
  });

  group('Ölçüsüz Kayıt Koruma ve Tek Dokunuş Davranışı', () {
    test('Kutuda veya sayfada ölçüsü kaldırılan kayıt yeniden yüklemeden sonra ölçüsüz kalır ve yedek oluşmaz', () async {
      await store.load();

      final water = await store.addActivity('Su', emoji: '💧');

      // Kullanıcı bilerek ölçüsüz kayıt ekliyor (veya ölçüyü siliyor)
      final res = await store.addEntry(
        water.id,
        qty: 1,
        at: DateTime(2026, 11, 1, 10, 0),
      );
      final entryId = res.entry.id;

      // Kaydın ölçüsüz olduğunu teyit et
      final saved = store.entries.firstWhere((e) => e.id == entryId);
      expect(saved.measureId, isNull);
      expect(saved.value, isNull);

      // Yeniden yükleme yap (uygulama açılışı / öne gelme)
      final backupsBefore = await BackupService.listBackups();
      await store.load();
      final backupsAfter = await BackupService.listBackups();

      // Yeniden yüklemeden sonra kayıt hala ölçüsüz kalmalı
      final reloaded = store.entries.firstWhere((e) => e.id == entryId);
      expect(reloaded.measureId, isNull);
      expect(reloaded.value, isNull);

      // Yeni pre_fix_unmeasured yedeği oluşturulmamış olmalı
      final newPreFixBackups = backupsAfter
          .where((b) => b.name.contains('pre_fix_unmeasured'))
          .where((b) => !backupsBefore.any((prev) => prev.name == b.name));
      expect(newPreFixBackups, isEmpty);
    });

    test('tapQuickItem ve executeRoutine sonrası bellekteki kayıt ile yeniden yüklenen kayıt aynıdır', () async {
      await store.load();

      final water = await store.addActivity('Su', emoji: '💧');
      final mBardak = store.measures.firstWhere((m) => m.name == 'Bardak' || (m.unitId == 'l' && m.amount == 0.2));

      // Ölçüsü belirtilmemiş QuickItem (tek dokunuşluk kısayol)
      final quickItem = QuickItem(
        id: 0,
        activityId: water.id,
        kind: 'shortcut',
        measureId: null,
        qty: 1.0,
        createdAt: 0,
      );
      await store.saveQuickItem(quickItem);
      final savedQ = store.quickItems.firstWhere((q) => q.activityId == water.id);

      // QuickItem'a dokun
      final tapRes = await store.tapQuickItem(savedQ.id);
      final tappedEntry = tapRes.added!;
      expect(tappedEntry.measureId, mBardak.id);
      expect(tappedEntry.value, closeTo(mBardak.amount, 0.0001));

      // Rutin oluştur (içinde ölçüsü belirtilmemiş su adımı var)
      final routine = Routine(
        id: 0,
        name: 'Sabah',
        items: [
          RoutineItem(id: 0, routineId: 0, activityId: water.id, qty: 1.0, measureId: null, sort: 0),
        ],
      );
      await store.saveRoutine(routine);
      final savedRoutine = store.routines.firstWhere((r) => r.name == 'Sabah');
      final routineEntries = await store.executeRoutine(savedRoutine.id);
      expect(routineEntries, isNotEmpty);
      final rEntry = routineEntries.first;
      expect(rEntry.measureId, mBardak.id);
      expect(rEntry.value, closeTo(mBardak.amount, 0.0001));

      // Yeniden yükleme yap
      await store.load();

      // Bellek ve yeniden yüklenen kayıtlar birebir aynı olmalı
      final reloadedTap = store.entries.firstWhere((e) => e.id == tappedEntry.id);
      expect(reloadedTap.measureId, tappedEntry.measureId);
      expect(reloadedTap.value, tappedEntry.value);
      expect(reloadedTap.unitId, tappedEntry.unitId);

      final reloadedRoutine = store.entries.firstWhere((e) => e.id == rEntry.id);
      expect(reloadedRoutine.measureId, rEntry.measureId);
      expect(reloadedRoutine.value, rEntry.value);
      expect(reloadedRoutine.unitId, rEntry.unitId);
    });

    test('Süre ve adet boyutlu aktivitelerde tek dokunuş davranışı değişmez', () async {
      await store.load();

      final run = await store.addActivity('Koşu', emoji: '🏃');
      final book = await store.addActivity('Kitap', emoji: '📖');

      final qRun = QuickItem(id: 0, activityId: run.id, kind: 'shortcut', measureId: null, qty: 1.0, createdAt: 0);
      await store.saveQuickItem(qRun);
      final savedQRun = store.quickItems.firstWhere((q) => q.activityId == run.id);

      final tapRun = await store.tapQuickItem(savedQRun.id);
      expect(tapRun.added!.measureId, isNull);

      final qBook = QuickItem(id: 0, activityId: book.id, kind: 'shortcut', measureId: null, qty: 1.0, createdAt: 0);
      await store.saveQuickItem(qBook);
      final savedQBook = store.quickItems.firstWhere((q) => q.activityId == book.id);

      final tapBook = await store.tapQuickItem(savedQBook.id);
      expect(tapBook.added!.measureId, isNull);
    });

    test('Bayraksız eski veride düzeltme yalnızca bir kez çalışır', () async {
      await store.load();

      final coffee = await store.addActivity('Kahve', emoji: '☕');

      // Eski veritabanı simülasyonu: ölçüsüz kahve kaydı var ve bayrak ayarlar tablosunda yok
      final e = Entry(id: 0, activityId: coffee.id, ts: DateTime(2026, 10, 1).millisecondsSinceEpoch, qty: 1);
      e.id = await (await store.db).insert('entries', e.toMap()..remove('id'));
      await (await store.db).delete('settings', where: 'key = ?', whereArgs: ['unmeasured_entries_fixed']);

      // İlk çalıştırma (load): düzeltme çalışmalı ve bayrağı yazmalı
      final defCoffee = store.defaultMeasureFor(coffee.id)!;
      await store.load();

      final fixedEntry = store.entries.firstWhere((entry) => entry.id == e.id);
      expect(fixedEntry.measureId, defCoffee.id);
      expect(fixedEntry.value, closeTo(defCoffee.amount, 0.0001));

      // Bayrak yazılmış olmalı
      final d = await store.db;
      final flagRows = await d.query('settings', where: 'key = ?', whereArgs: ['unmeasured_entries_fixed']);
      expect(flagRows, isNotEmpty);
      expect(flagRows.first['value'], 'true');

      // Şimdi yeni bir ölçüsüz kayıt ekleyelim (örneğin kullanıcı ölçüyü sildi)
      final unmeasuredEntry = await store.addEntry(coffee.id, qty: 1);

      // İkinci kez load() çalıştırıldığında düzeltme tekrar ÇALIŞMAMALI
      await store.load();
      final checkEntry = store.entries.firstWhere((entry) => entry.id == unmeasuredEntry.entry.id);
      expect(checkEntry.measureId, isNull);
      expect(checkEntry.value, isNull);
    });

    test('saveParsedItems ile ölçü bilerek boş bırakıldığında kayıt ölçüsüz kaydedilir', () async {
      await store.load();
      final water = await store.addActivity('Su', emoji: '💧');
      final defM = store.defaultMeasureFor(water.id);
      expect(defM, isNotNull);

      final item = EntryParsedItem(
        rawText: 'Su',
        parseResult: NaturalLanguageParser.parse('Su', activities: [water], measures: store.measures),
        activity: water,
        activityName: water.name,
        quantity: 1,
        at: DateTime(2026, 11, 1, 10, 0),
      );

      final res = await store.saveParsedItems(
        [item],
        hasMeasureOverride: true,
        overrideMeasureId: null,
      );
      expect(res.entries, isNotEmpty);
      final saved = res.entries.first;
      expect(saved.measureId, isNull);
      expect(saved.value, isNull);
    });

    test('Var olan aktivite tam eşleşmeyle kullanıldığında geri al var olan aktiviteyi silmez', () async {
      await store.load();
      final existingAct = await store.addActivity('Meditasyon');
      expect(store.entries.where((e) => e.activityId == existingAct.id), isEmpty);

      // item.activity = null verilerek tam eşleşme yolu test edilir
      final item = EntryParsedItem(
        rawText: 'Meditasyon',
        parseResult: NaturalLanguageParser.parse('Meditasyon', activities: [existingAct], measures: store.measures),
        activity: null,
        activityName: 'Meditasyon',
        quantity: 1,
        at: DateTime(2026, 11, 1, 11, 0),
      );

      final res = await store.saveParsedItems([item]);
      expect(res.entries, isNotEmpty);

      // Geri al işlemi çalıştırılır
      await res.undo();

      // Aktivitenin hala var olduğunu doğrula
      expect(store.activities.containsKey(existingAct.id), isTrue);
    });

    test('repeatLastEntry aktivitede kayıt yoksa varsayılan ölçüyü uygular, son kayıt ölçüsüzse aynen ölçüsüz tekrarlar', () async {
      await store.load();
      final tea = await store.addActivity('Çay');
      final defTea = store.defaultPhysicalMeasureFor(tea.id);
      expect(defTea, isNotNull);

      // 1. Aktivitede hiç kayıt yokken repeatLastEntry varsayılan ölçüyü uygular
      await store.repeatLastEntry(tea.id);
      final firstEntry = store.entries.firstWhere((e) => e.activityId == tea.id);
      expect(firstEntry.measureId, defTea!.id);
      expect(firstEntry.value, closeTo(defTea.amount, 0.0001));

      // 2. Bilerek ölçüsüz bir kayıt eklenir
      final unmeasuredRes = await store.addEntry(tea.id, qty: 1);
      final unmeasuredId = unmeasuredRes.entry.id;
      final unmeasured = store.entries.firstWhere((e) => e.id == unmeasuredId);
      expect(unmeasured.measureId, isNull);
      expect(unmeasured.value, isNull);

      // 3. Tekrarlandığında son kayıt ölçüsüz olduğu için yeni kayıt da ölçüsüz olmalı
      await store.repeatLastEntry(tea.id);
      final repeatedEntry = store.lastEntryForActivity(tea.id)!;
      expect(repeatedEntry.id, isNot(unmeasuredId));
      expect(repeatedEntry.measureId, isNull);
      expect(repeatedEntry.value, isNull);
    });

    test('logFromQuickText gelecek zamanlı girdiyi yapılacak olarak ekler', () async {
      await store.load();
      await store.addActivity('Koşu');

      final entriesBefore = store.entries.length;
      final todosBefore = store.todos.length;

      final msg = await store.logFromQuickText('yarın 30 dk koşu');
      expect(msg, 'Yapılacaklara eklendi');

      expect(store.entries.length, entriesBefore);
      expect(store.todos.length, todosBefore + 1);

      final addedTodo = store.todos.last;
      expect(addedTodo.title, '30 dk koşu');
      expect(addedTodo.targetAmount, 30.0);
      expect(addedTodo.targetUnit, 'dk');
      expect(addedTodo.dueDate, isNotNull);
    });
  });
}
