import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:takip/data/models.dart';
import 'package:takip/data/store.dart';
import 'package:takip/logic/time_suggestions.dart';

import 'support/real_db.dart';

void main() {
  useRealDatabase();

  setUpAll(() async {
    await initializeDateFormatting('tr_TR');
    await initializeDateFormatting('en_US');
    Intl.defaultLocale = 'tr_TR';
  });

  group('TimeSuggestions Pattern-Based Ranking Tests', () {
    test('prioritizes morning activity in morning hours and evening activity in evening hours', () async {
      await store.load();
      final actCoffee = await store.addActivity('Kahve', emoji: '☕');
      final actRun = await store.addActivity('Koşu', emoji: '🏃');

      // Seed coffee in mornings (08:00) for the last 5 days
      final now = DateTime(2026, 10, 15);
      for (var i = 1; i <= 5; i++) {
        final morningTime = DateTime(now.year, now.month, now.day - i, 8, 15);
        await store.addEntry(actCoffee.id, at: morningTime);
      }

      // Seed running in evenings (19:30) for the last 5 days
      for (var i = 1; i <= 5; i++) {
        final eveningTime = DateTime(now.year, now.month, now.day - i, 19, 30);
        await store.addEntry(actRun.id, at: eveningTime);
      }

      // 1. Morning query at 08:30
      final morningQueryTime = DateTime(2026, 10, 15, 8, 30);
      final morningSuggestions = store.timeBasedSuggestions(now: morningQueryTime, limit: 2);
      expect(morningSuggestions.first.id, equals(actCoffee.id));

      // 2. Evening query at 20:00
      final eveningQueryTime = DateTime(2026, 10, 15, 20, 0);
      final eveningSuggestions = store.timeBasedSuggestions(now: eveningQueryTime, limit: 2);
      expect(eveningSuggestions.first.id, equals(actRun.id));
    });

    test('weekday affinity boosts activities done on the same day of week', () async {
      await store.load();
      final actYoga = await store.addActivity('Yoga', emoji: '🧘');
      final actRead = await store.addActivity('Okuma', emoji: '📚');

      // Yoga done specifically on Thursdays (weekday 4) at 12:00
      // 2026-10-15 is Thursday
      for (var i = 1; i <= 4; i++) {
        final thurs = DateTime(2026, 10, 15 - (i * 7), 12, 0);
        await store.addEntry(actYoga.id, at: thurs);
      }

      // Reading done on Mondays at 12:00
      for (var i = 1; i <= 4; i++) {
        final mon = DateTime(2026, 10, 12 - (i * 7), 12, 0);
        await store.addEntry(actRead.id, at: mon);
      }

      final queryThursNoon = DateTime(2026, 10, 15, 12, 0);
      final suggestions = store.timeBasedSuggestions(now: queryThursNoon, limit: 2);
      expect(suggestions.first.id, equals(actYoga.id));
    });

    test('store.suggest falls back to time-based suggestions when query text is empty', () async {
      await store.load();
      final actA = await store.addActivity('Su', emoji: '💧');
      await store.addEntry(actA.id);

      final emptyQuerySuggestions = store.suggest('', limit: 5);
      expect(emptyQuerySuggestions, isNotEmpty);
      expect(emptyQuerySuggestions.any((a) => a.id == actA.id), isTrue);
    });
  });

  group('repeatLastEntry (Basılı Tutunca Son Kaydı Tekrarla) Tests', () {
    test('repeats previous entry with identical measure, value, unit, and note', () async {
      await store.load();
      final actWater = await store.addActivity('Su', emoji: '💧');

      // Log an entry with specific measure: 500 ml with note
      await store.addEntry(
        actWater.id,
        value: 500,
        unitId: 'ml',
        note: 'Şişeden içildi',
      );

      final todayEntriesBefore = store.entries.where((e) => e.activityId == actWater.id).length;
      expect(todayEntriesBefore, equals(1));

      // Call repeatLastEntry
      final msg = await store.repeatLastEntry(actWater.id);
      expect(msg, isNotNull);
      expect(msg, contains('Su'));
      expect(msg, contains('tekrarlandı'));

      // Verify a second entry was added with same parameters
      final entriesAfter = store.entries.where((e) => e.activityId == actWater.id).toList();
      expect(entriesAfter.length, equals(2));

      final repeated = entriesAfter.last;
      expect(repeated.value, equals(500));
      expect(repeated.unitId, equals('ml'));
      expect(repeated.note, equals('Şişeden içildi'));
    });

    test('repeatLastEntry on activity with no prior logs gracefully adds default 1 unit', () async {
      await store.load();
      final actWalk = await store.addActivity('Yürüyüş', emoji: '🚶');

      final msg = await store.repeatLastEntry(actWalk.id);
      expect(msg, isNotNull);
      expect(msg, contains('Yürüyüş'));

      final entries = store.entries.where((e) => e.activityId == actWalk.id).toList();
      expect(entries.length, equals(1));
    });
  });
}
