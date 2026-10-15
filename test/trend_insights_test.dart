import 'package:flutter_test/flutter_test.dart';
import 'package:takip/data/models.dart';
import 'package:takip/data/store.dart';
import 'package:takip/logic/activity_rhythm.dart';
import 'package:takip/logic/format.dart';
import 'package:takip/logic/trend_insights.dart';

import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

import 'support/real_db.dart';

void main() {
  useRealDatabase();

  setUpAll(() async {
    await initializeDateFormatting('tr_TR');
    await initializeDateFormatting('en_US');
    Intl.defaultLocale = 'tr_TR';
  });

  group('ActivityRhythm Tests', () {
    final now = DateTime(2026, 10, 15, 14, 0);

    test('0 entries returns empty state', () {
      final r = ActivityRhythm.compute(entries: [], now: now, isTr: true);
      expect(r.cadenceText, 'Kayıt yok');
      expect(r.lastTimeText, isNull);
      expect(r.last30Days.length, 30);
      expect(r.activeDaysCount, 0);
    });

    test('1 entry returns 1 kayıt and last time', () {
      final entries = [
        Entry(id: 1, activityId: 1, ts: now.millisecondsSinceEpoch),
      ];
      final r = ActivityRhythm.compute(entries: entries, now: now, isTr: true);
      expect(r.cadenceText, '1 kayıt');
      expect(r.lastTimeText, contains('Bugün'));
      expect(r.last30Days.length, 30);
      expect(r.last30Days.last, isTrue);
      expect(r.activeDaysCount, 1);
    });

    test('cadence calculation for regular activity (e.g. every 5 days)', () {
      // 5 entries spaced 5 days apart: days 0, 5, 10, 15, 20 before now
      final entries = [
        for (var i = 4; i >= 0; i--)
          Entry(
            id: i + 1,
            activityId: 1,
            ts: subDays(now, i * 5).millisecondsSinceEpoch,
          ),
      ];
      final r = ActivityRhythm.compute(entries: entries, now: now, isTr: true);
      expect(r.cadenceText, contains('günde bir'));
      expect(r.last30Days.length, 30);
      expect(r.activeDaysCount, 5);
      expect(r.lastTimeText, contains('Bugün'));
    });

    test('daily and high frequency cadence', () {
      final entries = [
        for (var i = 9; i >= 0; i--) ...[
          Entry(id: i * 2 + 1, activityId: 1, ts: subDays(now, i).millisecondsSinceEpoch),
          Entry(id: i * 2 + 2, activityId: 1, ts: subDays(now, i).millisecondsSinceEpoch + 3600000),
        ],
      ];
      final r = ActivityRhythm.compute(entries: entries, now: now, isTr: true);
      expect(r.cadenceText, contains('günde ortalama'));
      expect(r.activeDaysCount, 10);
    });

    test('last time formats yesterday and past days accurately', () {
      final yesterday = Entry(id: 1, activityId: 1, ts: subDays(now, 1).millisecondsSinceEpoch);
      final rYesterday = ActivityRhythm.compute(entries: [yesterday], now: now, isTr: true);
      expect(rYesterday.lastTimeText, contains('Dün'));

      final threeDaysAgo = Entry(id: 2, activityId: 1, ts: subDays(now, 3).millisecondsSinceEpoch);
      final rThree = ActivityRhythm.compute(entries: [threeDaysAgo], now: now, isTr: true);
      expect(rThree.lastTimeText, contains('3 gün önce'));
    });
  });

  group('TrendInsights Weekly Changes Tests', () {
    final monday = weekStart(DateTime(2026, 10, 15)); // 2026-10-12
    final now = DateTime(2026, 10, 15, 12, 0); // Thursday noon

    test('detects increased and decreased activities compared to last week', () async {
      await store.load();
      final actRun = await store.addActivity('Koşu', emoji: '🏃');
      final actBook = await store.addActivity('Kitap', emoji: '📚');

      // This week: Koşu 4 times, Kitap 1 time
      for (var i = 0; i < 4; i++) {
        await store.addEntry(actRun.id, at: addDays(monday, i));
      }
      await store.addEntry(actBook.id, at: monday);

      // Last week: Koşu 1 time, Kitap 4 times
      final prevMonday = subDays(monday, 7);
      await store.addEntry(actRun.id, at: prevMonday);
      for (var i = 0; i < 4; i++) {
        await store.addEntry(actBook.id, at: addDays(prevMonday, i));
      }

      final insights = computeWeeklyInsights(store: store, now: now, isTr: true);

      // Koşu should be marked increased
      final runInsight = insights.where((i) => i.activityId == actRun.id && i.type == TrendType.increased);
      expect(runInsight, isNotEmpty);
      expect(runInsight.first.text, contains('Koşu'));
      expect(runInsight.first.text, contains('artışta'));

      // Kitap should be marked decreased
      final bookInsight = insights.where((i) => i.activityId == actBook.id && i.type == TrendType.decreased);
      expect(bookInsight, isNotEmpty);
      expect(bookInsight.first.text, contains('Kitap'));
      expect(bookInsight.first.text, contains('azaldı'));
    });

    test('detects dormant/breaking-cadence activity', () async {
      await store.load();
      final actMed = await store.addActivity('Meditasyon', emoji: '🧘');

      // Meditated regularly 20 days ago (3 times, interval 2 days)
      final pastDate = subDays(now, 20);
      await store.addEntry(actMed.id, at: pastDate);
      await store.addEntry(actMed.id, at: addDays(pastDate, 2));
      await store.addEntry(actMed.id, at: addDays(pastDate, 4));

      final insights = computeWeeklyInsights(store: store, now: now, isTr: true);
      final dormant = insights.where((i) => i.activityId == actMed.id && i.type == TrendType.dormant);
      expect(dormant, isNotEmpty);
      expect(dormant.first.text, contains('Meditasyon'));
      expect(dormant.first.text, contains('yapılmadı'));
    });

    test('detects reached goals', () async {
      await store.load();
      final actWater = await store.addActivity('Su', emoji: '💧');
      await store.saveGoal(
        Goal(
          id: 0,
          name: 'Haftalık Su',
          type: 'target',
          mode: 'count',
          target: 3,
          period: GoalPeriod.week,
          startDate: DateTime(2026, 1, 1).millisecondsSinceEpoch,
          createdAt: DateTime.now().millisecondsSinceEpoch,
          sort: 0,
          links: [GoalLink(activityId: actWater.id, pct: 100)],
        ),
      );

      // Log 3 waters this week
      for (var i = 0; i < 3; i++) {
        await store.addEntry(actWater.id, at: addDays(monday, i));
      }

      final insights = computeWeeklyInsights(store: store, now: now, isTr: true);
      final goalInsight = insights.where((i) => i.type == TrendType.goalMet);
      expect(goalInsight, isNotEmpty);
      expect(goalInsight.first.text, contains('Haftalık Su'));
      expect(goalInsight.first.text, contains('ulaşıldı'));
    });
  });
}
