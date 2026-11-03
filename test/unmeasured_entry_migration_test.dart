import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:takip/data/models.dart';
import 'package:takip/data/store.dart';
import 'package:takip/services/backup_service.dart';
import 'package:takip/services/nl_parser.dart';
import 'package:takip/ui/common.dart';
import 'package:takip/ui/today_page.dart';

import 'support/real_db.dart';

void main() {
  useRealDatabase();
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initializeDateFormatting('tr_TR', null);
  });

  group('Eski Ölçüsüz Kayıtlar ve Giriş Kuralları', () {
    test('1. Unmeasured entries migration: converts quantity activities, leaves duration/events/filled untouched', () async {
      await store.load();

      // Aktiviteleri ve ölçüleri oluştur
      final coffee = await store.addActivity('Kahve', emoji: '☕');
      final run = await store.addActivity('Yürüyüş', emoji: '🚶');
      final book = await store.addActivity('Kitap', emoji: '📖');

      final mFincan = store.measures.firstWhere((m) => m.name == 'Fincan' || m.unitId == 'l');
      await store.saveQuickItem(QuickItem(
        id: 0,
        activityId: coffee.id,
        kind: 'shortcut',
        measureId: mFincan.id,
        qty: 1.0,
        createdAt: 0,
      ));

      // 1. Ölçüsüz kahve kaydı (hacim) - Düzeltilmeli
      final e1 = Entry(id: 0, activityId: coffee.id, ts: DateTime(2026, 10, 1).millisecondsSinceEpoch, qty: 2);
      e1.id = await (await store.db).insert('entries', e1.toMap()..remove('id'));

      // 2. Ölçüsüz yürüyüş kaydı (süre) - Dokunulmamalı!
      final e2 = Entry(id: 0, activityId: run.id, ts: DateTime(2026, 10, 1).millisecondsSinceEpoch, qty: 1);
      e2.id = await (await store.db).insert('entries', e2.toMap()..remove('id'));

      // 3. Değeri dolu kahve kaydı - Dokunulmamalı!
      final e3 = Entry(id: 0, activityId: coffee.id, ts: DateTime(2026, 10, 1).millisecondsSinceEpoch, qty: 1, value: 0.25, unitId: 'l');
      e3.id = await (await store.db).insert('entries', e3.toMap()..remove('id'));

      // 4. Olay formatı (kitap) - Dokunulmamalı!
      final e4 = Entry(id: 0, activityId: book.id, ts: DateTime(2026, 10, 1).millisecondsSinceEpoch, qty: 1);
      e4.id = await (await store.db).insert('entries', e4.toMap()..remove('id'));

      await store.refresh();

      // Düzeltmeyi çalıştır
      final fixedCount = await store.fixUnmeasuredEntries();
      expect(fixedCount, 1);

      await store.refresh();
      final re1 = store.entries.firstWhere((e) => e.id == e1.id);
      final re2 = store.entries.firstWhere((e) => e.id == e2.id);
      final re3 = store.entries.firstWhere((e) => e.id == e3.id);
      final re4 = store.entries.firstWhere((e) => e.id == e4.id);

      // e1 varsayılan ölçü × adet olmalı
      final coffeeMeasure = store.defaultMeasureFor(coffee.id)!;
      expect(re1.measureId, coffeeMeasure.id);
      expect(re1.unitId, coffeeMeasure.unitId);
      expect(re1.value, closeTo(coffeeMeasure.amount * 2, 0.0001));

      // e2, e3, e4 değişmemiş olmalı
      expect(re2.measureId, isNull);
      expect(re2.value, isNull);
      expect(re3.value, 0.25);
      expect(re4.measureId, isNull);
      expect(re4.value, isNull);

      // Tekrar çalıştırınca hiçbir şey değişmemeli (idempotent)
      final secondRun = await store.fixUnmeasuredEntries();
      expect(secondRun, 0);

      // Bildirim mesajı ayarlanmış olmalı
      expect(store.unmeasuredFixMessageNotifier.value, isNotNull);
    });

    test('2. Unmeasured migration safety: aborts and rolls back if backup fails', () async {
      await store.load();

      final coffee = await store.addActivity('Kahve', emoji: '☕');
      final mFincan = store.measures.firstWhere((m) => m.name == 'Fincan' || m.unitId == 'l');
      await store.saveQuickItem(QuickItem(
        id: 0,
        activityId: coffee.id,
        kind: 'shortcut',
        measureId: mFincan.id,
        qty: 1.0,
        createdAt: 0,
      ));

      final e1 = Entry(id: 0, activityId: coffee.id, ts: DateTime(2026, 10, 1).millisecondsSinceEpoch, qty: 2);
      e1.id = await (await store.db).insert('entries', e1.toMap()..remove('id'));
      await store.refresh();

      // Simüle edilmiş yedekleme hatası
      BackupService.snapshotOverrideForTest = (s) async {
        throw const FileSystemException('Disk dolu simülasyonu');
      };

      try {
        final fixed = await store.fixUnmeasuredEntries();
        expect(fixed, 0);
      } finally {
        BackupService.snapshotOverrideForTest = null;
      }

      await store.refresh();
      final re1 = store.entries.firstWhere((e) => e.id == e1.id);
      // Hiçbir satır değişmemiş olmalı
      expect(re1.measureId, isNull);
      expect(re1.value, isNull);
    });

    test('3. Unmeasured migration after JSON restore & Goal contribution matches chip', () async {
      await store.load();

      final coffee = await store.addActivity('Kahve', emoji: '☕');
      final mFincan = store.measures.firstWhere((m) => m.name == 'Fincan');
      await store.saveQuickItem(QuickItem(
        id: 0,
        activityId: coffee.id,
        kind: 'shortcut',
        measureId: mFincan.id,
        qty: 1.0,
        createdAt: 0,
      ));

      // Hedef: Kahve için günde en fazla 0.5 L limit hedefi
      final goal = Goal(
        id: 0,
        name: 'Kahve Limiti',
        type: 'limit',
        mode: 'sum',
        target: 0.5,
        unitId: 'l',
        period: GoalPeriod.day,
        startDate: DateTime(2026, 10, 1).millisecondsSinceEpoch,
        createdAt: DateTime(2026, 10, 1).millisecondsSinceEpoch,
      );
      goal.links.add(GoalLink(activityId: coffee.id, pct: 100));
      await store.saveGoal(goal);

      // JSON yedeğe ölçüsüz bir kahve kaydı koyup içe aktaralım
      final backupData = {
        'app': 'seyir',
        'version': 3,
        'exportedAt': DateTime.now().toIso8601String(),
        'units': (await (await store.db).query('units')),
        'measures': (await (await store.db).query('measures')),
        'activities': (await (await store.db).query('activities')),
        'activity_properties': <Map<String, Object?>>[],
        'activity_reminders': <Map<String, Object?>>[],
        'routines': <Map<String, Object?>>[],
        'routine_items': <Map<String, Object?>>[],
        'goals': (await (await store.db).query('goals')),
        'goal_links': (await (await store.db).query('goal_links')),
        'goal_checkins': <Map<String, Object?>>[],
        'todos': <Map<String, Object?>>[],
        'todo_links': <Map<String, Object?>>[],
        'roadmap_steps': <Map<String, Object?>>[],
        'quick_items': (await (await store.db).query('quick_items')),
        'settings': <Map<String, Object?>>[],
        'active_timers': <Map<String, Object?>>[],
        'entries': [
          {
            'id': 101,
            'activity_id': coffee.id,
            'ts': DateTime(2026, 10, 30, 10, 0).millisecondsSinceEpoch,
            'qty': 2.0,
            'measure_id': null,
            'value': null,
            'unit_id': null,
            'note': null,
          }
        ],
      };

      // İçe aktarma (importJson) load() çağırır ve bu da fixUnmeasuredEntries()'ı çalıştırır
      await store.importJson(jsonEncode(backupData));

      // Kaydın düzeltildiğini doğrula
      final restoredEntry = store.entries.firstWhere((e) => e.activityId == coffee.id);
      expect(restoredEntry.measureId, mFincan.id);
      expect(restoredEntry.value, closeTo(mFincan.amount * 2, 0.0001));

      // Hedef katkısının çip eşdeğeri olduğunu doğrula:
      // 2 fincan = 2 * 0.08 L = 0.16 L
      final currentAmount = store.goalStatus(goal, at: DateTime(2026, 10, 30)).value;
      expect(currentAmount, closeTo(0.16, 0.0001));
    });

    test('4. Todo completion hint: duration entry does not complete distance todo, matches actual saveBatch outcome', () async {
      await store.load();

      final walk = await store.addActivity('Yürüyüş', emoji: '🚶');

      // 1. "5 km yürüyüş yap" (mesafe hedefi)
      final kmTodo = await store.createTodo(
        Todo(
          id: 0,
          title: '5 km yürüyüş yap',
          targetAmount: 5.0,
          targetUnit: 'km',
          createdAt: DateTime.now().subtract(const Duration(hours: 1)).millisecondsSinceEpoch,
        ),
        activityIds: [walk.id],
      );

      // 2. "20 dk yürü" (süre hedefi)
      final minTodo = await store.createTodo(
        Todo(
          id: 0,
          title: '20 dk yürü',
          targetAmount: 20.0,
          targetUnit: 'dk',
          createdAt: DateTime.now().subtract(const Duration(hours: 1)).millisecondsSinceEpoch,
        ),
        activityIds: [walk.id],
      );

      // Girdi: "30 dk yurudum"
      final parseRes = NaturalLanguageParser.parseMulti(
        '30 dk yurudum',
        activities: store.activities.values.toList(),
        measures: store.measures,
        openTodos: store.todos,
        defaultMeasureFor: store.defaultMeasureFor,
        predictCompletedTodos: store.predictCompletedTodos,
      );

      final entryItem = parseRes.entryItems.first;
      final completedPredictions = store.predictCompletedTodos([entryItem]);

      // "20 dk yürü" tamamlanmalı, "5 km yürüyüş yap" TAMAMLANMAMALI!
      expect(completedPredictions.any((t) => t.id == minTodo.id), isTrue);
      expect(completedPredictions.any((t) => t.id == kmTodo.id), isFalse);
      expect(entryItem.willCompleteTodos.any((t) => t.id == minTodo.id), isTrue);
      expect(entryItem.willCompleteTodos.any((t) => t.id == kmTodo.id), isFalse);

      // Kaydedince gerçek tamamlananlarla tahmin %100 aynı olmalı
      await store.saveBatch(
        entries: [
          BatchEntryInput(
            activityId: entryItem.activity!.id,
            measureId: entryItem.measure?.id,
            qty: entryItem.quantity,
            at: entryItem.at,
            endAt: entryItem.endAt,
          ),
        ],
      );

      expect(store.todoProgress(minTodo).isCompleted, isTrue);
      expect(store.todoProgress(kmTodo).isCompleted, isFalse);
    });

    test('5. Duration entry time rules: no time -> ends now; relative ago -> ends ago; clock hour -> starts at hour', () async {
      final fixedNow = DateTime(2026, 10, 30, 14, 52); // Kanıttaki saat: 14:52
      await store.load();

      await store.addActivity('Yürüyüş', emoji: '🚶');
      await store.addActivity('Koşu', emoji: '🏃');
      await store.addActivity('Kitap', emoji: '📖');

      // a) Zaman ifadesi yoksa: kayıt şimdi biter (14:52), başlangıç şimdi - süre (14:22)
      final p1 = NaturalLanguageParser.parseMulti(
        '30 dk yurudum',
        activities: store.activities.values.toList(),
        measures: store.measures,
        now: fixedNow,
        defaultMeasureFor: store.defaultMeasureFor,
      );
      final item1 = p1.entryItems.first;
      expect(item1.endAt, fixedNow);
      expect(item1.at, fixedNow.subtract(const Duration(minutes: 30)));

      // b) "2 saat once 30 dk kostum": bitiş = fixedNow - 2 saat (12:52), başlangıç = bitiş - 30 dk (12:22)
      final p2 = NaturalLanguageParser.parseMulti(
        '2 saat once 30 dk kostum',
        activities: store.activities.values.toList(),
        measures: store.measures,
        now: fixedNow,
        defaultMeasureFor: store.defaultMeasureFor,
      );
      final item2 = p2.entryItems.first;
      expect(item2.endAt, fixedNow.subtract(const Duration(hours: 2)));
      expect(item2.at, fixedNow.subtract(const Duration(hours: 2, minutes: 30)));

      // c) "aksam 1 saat kitap okudum": gün bölümü verilmiş -> o an başlangıçtır (19:00 - 20:00, 14:52'de dün 19:00)
      final p3 = NaturalLanguageParser.parseMulti(
        'aksam 1 saat kitap okudum',
        activities: store.activities.values.toList(),
        measures: store.measures,
        now: fixedNow,
        defaultMeasureFor: store.defaultMeasureFor,
      );
      final item3 = p3.entryItems.first;
      expect(item3.at.hour, 19);
      expect(item3.endAt?.hour, 20);

      // d) Gece yarısı sınırı: 00:10'da "30 dk yürüdüm" -> bitiş 00:10 (bugün), başlangıç 23:40 (dün)
      final midnightNow = DateTime(2026, 10, 31, 0, 10);
      final p4 = NaturalLanguageParser.parseMulti(
        '30 dk yurudum',
        activities: store.activities.values.toList(),
        measures: store.measures,
        now: midnightNow,
        defaultMeasureFor: store.defaultMeasureFor,
      );
      final item4 = p4.entryItems.first;
      expect(item4.endAt, midnightNow);
      expect(item4.at, DateTime(2026, 10, 30, 23, 40));
      expect(item4.at.day, 30); // Bir önceki güne düşer!
    });

    testWidgets('6. Icon verification: matched activity in multi-item preview uses its own ActivityAvatar icon, not pencil', (tester) async {
      await tester.runAsync(() async {
        await store.load();
        final coffee = await store.addActivity('Kahve', emoji: '☕');
        await store.addActivity('Yürüyüş', emoji: '🚶');
        final mFincan = store.measures.firstWhere((m) => m.name == 'Fincan');
        await store.saveQuickItem(QuickItem(
          id: 0,
          activityId: coffee.id,
          kind: 'shortcut',
          measureId: mFincan.id,
          qty: 1.0,
          createdAt: 0,
        ));
      });

      await tester.pumpWidget(MaterialApp(home: TodayPage(focusRequest: ValueNotifier<int>(0))));
      await tester.pump();
      for (var i = 0; i < 5; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump(const Duration(milliseconds: 50));
      }

      final composerField = find.byType(TextField).last;
      await tester.enterText(composerField, '2 kahve ve 30 dk yurudum');
      await tester.pump(const Duration(milliseconds: 100));

      // Çoklu önizleme satırları görünür
      // Yürüyüş ve Kahve için ActivityAvatar bileşenleri bulunmalı
      final avatars = find.byType(ActivityAvatar);
      expect(avatars, findsWidgets);

      // Önizlemede "📝" yalnızca yeni tanınmayan aktivite için kullanılmalı, eşleşenlerde görünmemeli
      expect(find.text('📝'), findsNothing);

      // Temizlik
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() async {
        for (final t in List.of(store.activeTimers)) {
          await store.cancelTimer(t.id);
        }
      });
      await tester.pump(const Duration(seconds: 6));
    });
  });
}
