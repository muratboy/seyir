import 'package:flutter_test/flutter_test.dart';
import 'package:takip/data/models.dart';
import 'package:takip/data/store.dart';
import 'package:takip/logic/correlation_analysis.dart';
import 'support/real_db.dart';

void main() {
  useRealDatabase();

  group('Activity Reminders (Paket C)', () {
    test('save, toggle, and delete activity reminders with persistence', () async {
      final act = await store.addActivity('Su');

      final reminder = ActivityReminder(
        id: 0,
        activityId: act.id,
        time: '08:30',
        daysOfWeek: '1,2,3,4,5',
        isEnabled: true,
        customMessage: 'Güne bir bardak su ile başla!',
      );

      final saved = await store.saveActivityReminder(reminder);
      expect(saved.id, isNonZero);
      expect(store.remindersForActivity(act.id).length, equals(1));
      expect(store.remindersForActivity(act.id).first.time, equals('08:30'));

      // Verify persistence
      var otherStore = await openStore();
      expect(otherStore.remindersForActivity(act.id).length, equals(1));
      expect(otherStore.remindersForActivity(act.id).first.customMessage, equals('Güne bir bardak su ile başla!'));

      // Toggle
      await store.toggleActivityReminder(saved.id, false);
      expect(store.remindersForActivity(act.id).first.isEnabled, isFalse);

      otherStore = await openStore();
      expect(otherStore.remindersForActivity(act.id).first.isEnabled, isFalse);

      // Delete
      await store.deleteActivityReminder(saved.id);
      expect(store.remindersForActivity(act.id), isEmpty);

      otherStore = await openStore();
      expect(otherStore.remindersForActivity(act.id), isEmpty);
    });
  });

  group('Routines & Activity Bundles (Paket D)', () {
    test('save, reorder, execute and persist routines', () async {
      final su = await store.addActivity('Su');
      final vitamin = await store.addActivity('Vitamin');
      final meditasyon = await store.addActivity('Meditasyon');

      final routine = Routine(
        name: 'Sabah Rutini',
        emoji: '🌅',
        items: [
          RoutineItem(activityId: su.id, qty: 250),
          RoutineItem(activityId: vitamin.id, qty: 1),
          RoutineItem(activityId: meditasyon.id, qty: 15),
        ],
      );

      final saved = await store.saveRoutine(routine);
      expect(saved.id, isNonZero);
      expect(store.routines.length, equals(1));
      expect(store.routines.first.items.length, equals(3));

      // Verify persistence in another store
      var otherStore = await openStore();
      expect(otherStore.routines.length, equals(1));
      expect(otherStore.routines.first.name, equals('Sabah Rutini'));
      expect(otherStore.routines.first.items.length, equals(3));

      // Execute routine
      final now = DateTime(2026, 6, 1, 8, 0);
      final entries = await store.executeRoutine(saved.id, at: now);
      expect(entries.length, equals(3));
      expect(entries.map((e) => e.activityId).toSet(), equals({su.id, vitamin.id, meditasyon.id}));

      // Check entries are in store
      expect(store.entriesForActivity(su.id).length, equals(1));
      expect(store.entriesForActivity(vitamin.id).length, equals(1));
      expect(store.entriesForActivity(meditasyon.id).length, equals(1));

      // Delete routine
      await store.deleteRoutine(saved.id);
      expect(store.routines, isEmpty);

      otherStore = await openStore();
      expect(otherStore.routines, isEmpty);
    });
  });

  group('Correlation Analysis (Paket D)', () {
    test('detects symptom triggers and protective habits', () async {
      final kahve = await store.addActivity('Kahve');
      final uykusuzluk = await store.addActivity('Uykusuzluk');
      final basAgrisi = await store.addActivity('Baş Ağrısı'); // Symptom keyword

      final baseDate = DateTime(2026, 7, 1);

      // Day 0..2: Kahve logged, no Baş Ağrısı
      for (int i = 0; i < 3; i++) {
        final day = baseDate.add(Duration(days: i));
        await store.addEntry(kahve.id, at: day.add(const Duration(hours: 9)));
      }

      // Day 3..6: Uykusuzluk and Baş Ağrısı both logged
      for (int i = 3; i < 7; i++) {
        final day = baseDate.add(Duration(days: i));
        await store.addEntry(uykusuzluk.id, at: day.add(const Duration(hours: 8)));
        await store.addEntry(basAgrisi.id, at: day.add(const Duration(hours: 14)));
      }

      // Day 7: Just another day
      final day7 = baseDate.add(const Duration(days: 7));
      await store.addEntry(kahve.id, at: day7.add(const Duration(hours: 10)));

      final insights = CorrelationEngine.analyze(
        store,
        now: baseDate.add(const Duration(days: 8)),
        daysBack: 30,
        isTr: true,
      );

      expect(insights, isNotEmpty);

      // Uykusuzluk should be identified as a trigger for Baş Ağrısı
      final trigger = insights.where((i) => i.primaryActivityId == uykusuzluk.id && i.relatedActivityId == basAgrisi.id).firstOrNull;
      expect(trigger, isNotNull);
      expect(trigger!.type, equals(CorrelationType.warning));
      expect(trigger.title, contains('Tetikleyicisi'));

      // Kahve should be identified as a reducer / protective for Baş Ağrısı
      final reducer = insights.where((i) => i.primaryActivityId == kahve.id && i.relatedActivityId == basAgrisi.id).firstOrNull;
      expect(reducer, isNotNull);
      expect(reducer!.type, equals(CorrelationType.positive));
      expect(reducer.title, contains('Azaltıcı'));
    });
  });

  group('Sleep Routine Synchronization (Paket C)', () {
    test('startSleepSession and stopSleepSession record proper duration', () async {
      final startTime = DateTime(2026, 8, 1, 23, 0);
      final endTime = DateTime(2026, 8, 2, 7, 30); // 8.5 hours

      await store.startSleepSession(at: startTime);
      expect(store.sleepSessionStartTs, equals(startTime.millisecondsSinceEpoch));

      final entry = await store.stopSleepSession(at: endTime, note: 'Rahat bir uyku');
      expect(entry, isNotNull);
      expect(store.sleepSessionStartTs, isNull);

      expect(entry!.qty, equals(8.5));
      expect(entry.note, equals('Rahat bir uyku'));
      expect(entry.time, equals(startTime));
      expect(entry.endTime, equals(endTime));
    });
  });
}
