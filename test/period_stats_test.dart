import 'package:flutter_test/flutter_test.dart';
import 'package:takip/data/models.dart';
import 'package:takip/logic/period_stats.dart';

Unit? _unitOf(String id) => builtinUnits.where((u) => u.id == id).firstOrNull;

Entry _entry(DateTime at, {int activity = 1, double? value, String? unit}) =>
    Entry(id: 0, activityId: activity, ts: at.millisecondsSinceEpoch, qty: 1, value: value, unitId: unit);

/// Statistics of the period that contains [anchor], seen at the moment [now].
PeriodStats _stats(StatRange range, DateTime anchor, List<Entry> all, {required DateTime now}) {
  final sorted = [...all]..sort((a, b) => a.ts.compareTo(b.ts));
  return PeriodStats.compute(
    period: StatPeriod.containing(range, anchor),
    entriesIn: (from, to) => sorted.where((e) => !e.time.isBefore(from) && e.time.isBefore(to)),
    unitOf: _unitOf,
    now: now,
    trackingSince: sorted.isEmpty ? null : sorted.first.time,
  );
}

void main() {
  // 12 October 2026 is a Monday.
  final monday = DateTime(2026, 10, 12);

  group('Periods', () {
    test('are split into the slices their chart shows', () {
      final day = StatPeriod.containing(StatRange.day, DateTime(2026, 10, 13, 16));
      expect(day.buckets, hasLength(24));
      expect(day.buckets[9], (DateTime(2026, 10, 13, 9), DateTime(2026, 10, 13, 10)));

      final week = StatPeriod.containing(StatRange.week, DateTime(2026, 10, 15));
      expect(week.from, monday);
      expect(week.buckets, hasLength(7));
      expect(week.buckets.last.$1, DateTime(2026, 10, 18));

      expect(StatPeriod.containing(StatRange.month, DateTime(2026, 10, 13)).buckets, hasLength(31));
      expect(StatPeriod.containing(StatRange.month, DateTime(2028, 2, 10)).buckets, hasLength(29));

      final year = StatPeriod.containing(StatRange.year, DateTime(2026, 10, 13));
      expect(year.buckets, hasLength(12));
      expect(year.buckets[9], (DateTime(2026, 10), DateTime(2026, 11)));
    });

    test('step by whole calendar periods', () {
      final week = StatPeriod.containing(StatRange.week, DateTime(2026, 10, 1, 23, 30));
      expect(week.from, DateTime(2026, 9, 28));
      expect(week.shifted(1).from, DateTime(2026, 10, 5));
      expect(week.previous.from, DateTime(2026, 9, 21));

      // From the 31st of a month: the next month, not the one after.
      final january = StatPeriod.containing(StatRange.month, DateTime(2027, 1, 31));
      expect(january.shifted(1).from, DateTime(2027, 2));
      expect(january.shifted(1).to, DateTime(2027, 3));
      expect(january.previous.from, DateTime(2026, 12));

      final day = StatPeriod.containing(StatRange.day, DateTime(2026, 12, 31, 23, 59));
      expect(day.shifted(1).from, DateTime(2027, 1, 1));
      expect(StatPeriod.containing(StatRange.year, DateTime(2026, 6)).previous.from, DateTime(2025));
    });
  });

  group('Period statistics', () {
    test('a day is counted by the hour, not by "weeks"', () {
      final s = _stats(
        StatRange.day,
        DateTime(2026, 10, 13),
        [
          _entry(DateTime(2026, 10, 13, 9, 10)),
          _entry(DateTime(2026, 10, 13, 9, 50)),
          _entry(DateTime(2026, 10, 13, 14)),
          _entry(DateTime(2026, 10, 12, 9)),
        ],
        now: DateTime(2026, 10, 13, 16),
      );

      expect(s.total.count, 3);
      expect(s.buckets[9].count, 2);
      expect(s.buckets[14].count, 1);
      expect(s.busiestBucket(null), 9);
      expect(s.firstEntry, DateTime(2026, 10, 13, 9, 10));
      expect(s.lastEntry, DateTime(2026, 10, 13, 14));
    });

    test('a month is counted day by day and a year month by month', () {
      final entries = [
        _entry(DateTime(2026, 10, 1, 8)),
        _entry(DateTime(2026, 10, 13, 8)),
        _entry(DateTime(2026, 10, 13, 20)),
        _entry(DateTime(2026, 3, 5)),
      ];
      final month = _stats(StatRange.month, DateTime(2026, 10, 13), entries, now: DateTime(2026, 10, 20));
      expect(month.buckets[0].count, 1);
      expect(month.buckets[12].count, 2);
      expect(month.busiestBucket(null), 12);

      final year = _stats(StatRange.year, DateTime(2026, 10, 13), entries, now: DateTime(2026, 10, 20));
      expect(year.buckets[2].count, 1);
      expect(year.buckets[9].count, 3);
    });

    test('amounts are summed per dimension, in its base unit', () {
      final s = _stats(
        StatRange.week,
        monday,
        [
          _entry(DateTime(2026, 10, 12, 9), value: 30, unit: 'dk'),
          _entry(DateTime(2026, 10, 13, 9), value: 2, unit: 'sa'),
          _entry(DateTime(2026, 10, 13, 10), value: 0.2, unit: 'l'),
          _entry(DateTime(2026, 10, 13, 11), value: 200, unit: 'ml'),
          _entry(DateTime(2026, 10, 13, 12)),
        ],
        now: DateTime(2026, 10, 14, 10),
      );

      expect(s.total.count, 5);
      expect(s.total.value('time'), 150);
      expect(s.total.value('volume'), closeTo(0.4, 1e-9));
      expect(s.total.value('distance'), 0);
      // The busiest day depends on what is measured: Tuesday by time and by entries.
      expect(s.busiestBucket('time'), 1);
      expect(s.busiestBucket('distance'), isNull);
    });

    test('averages count the days that have passed, not the whole period', () {
      final s = _stats(
        StatRange.week,
        monday,
        [_entry(DateTime(2026, 10, 5, 9)), _entry(DateTime(2026, 10, 12, 9)), _entry(DateTime(2026, 10, 13, 9))],
        now: DateTime(2026, 10, 14, 10),
      );
      expect(s.activeDays, 2);
      expect(s.elapsedDays, 3, reason: 'Monday to Wednesday');

      final finished = _stats(StatRange.month, DateTime(2026, 9, 10), [_entry(DateTime(2026, 8, 1))],
          now: DateTime(2026, 10, 14));
      expect(finished.elapsedDays, 30);

      // A single day, and a period that has not begun: never less than one day to divide by.
      final earlier = [_entry(DateTime(2026, 8, 1))];
      expect(_stats(StatRange.day, DateTime(2026, 10, 14), earlier, now: DateTime(2026, 10, 14, 8)).elapsedDays, 1);
      expect(_stats(StatRange.week, DateTime(2026, 11, 3), earlier, now: DateTime(2026, 10, 14)).elapsedDays, 1);
    });

    test('days before the first entry ever do not dilute the average', () {
      final entries = [for (var d = 9; d <= 13; d++) _entry(DateTime(2026, 10, d, 9))];
      final year = _stats(StatRange.year, DateTime(2026, 10, 13), entries, now: DateTime(2026, 10, 13, 16));

      expect(year.total.count, 5);
      expect(year.elapsedDays, 5, reason: 'tracking began on 9 October, not on 1 January');
    });

    test('a period still running is compared with the same part of the previous one', () {
      final entries = [
        // Last week: Monday, Tuesday, Thursday, Saturday.
        _entry(DateTime(2026, 10, 5, 9)),
        _entry(DateTime(2026, 10, 6, 9)),
        _entry(DateTime(2026, 10, 8, 9)),
        _entry(DateTime(2026, 10, 10, 9)),
        // This week so far.
        _entry(DateTime(2026, 10, 12, 9)),
        _entry(DateTime(2026, 10, 13, 9)),
        _entry(DateTime(2026, 10, 14, 9)),
      ];
      final wednesdayNoon = DateTime(2026, 10, 14, 12);

      final running = _stats(StatRange.week, monday, entries, now: wednesdayNoon);
      expect(running.total.count, 3);
      expect(running.comparesPartial, isTrue);
      expect(running.previous.count, 2, reason: 'last week up to Wednesday noon');
      expect(running.hasComparison, isTrue);

      // Looking back at last week: it is over, so the whole week before it counts.
      final finished = _stats(StatRange.week, DateTime(2026, 10, 5), entries, now: wednesdayNoon);
      expect(finished.comparesPartial, isFalse);
      expect(finished.total.count, 4);
      expect(finished.previous.count, 0);
      expect(finished.hasComparison, isFalse, reason: 'nothing was tracked before 5 October');
    });

    test('today is compared with yesterday up to the same time', () {
      final s = _stats(
        StatRange.day,
        DateTime(2026, 10, 13),
        [
          _entry(DateTime(2026, 10, 12, 8)),
          _entry(DateTime(2026, 10, 12, 21)),
          _entry(DateTime(2026, 10, 13, 8)),
          _entry(DateTime(2026, 10, 13, 9)),
        ],
        now: DateTime(2026, 10, 13, 12),
      );
      expect(s.total.count, 2);
      expect(s.previous.count, 1, reason: "yesterday's evening entry came after this time of day");
    });
  });

  group('Chart axis', () {
    test('uses round numbers', () {
      expect(niceAxis(37, integers: true), (40, 10));
      expect(niceAxis(9, integers: true), (10, 2));
      expect(niceAxis(4, integers: true), (4, 1));
      expect(niceAxis(1, integers: true), (1, 1));
      expect(niceAxis(0, integers: true), (4, 1));
      expect(niceAxis(1500), (1500, 500));

      final (top, step) = niceAxis(0.7);
      expect(top, closeTo(0.8, 1e-9));
      expect(step, closeTo(0.2, 1e-9));
    });

    test('always reaches the largest value', () {
      for (final value in [0.03, 0.9, 1.0, 2.6, 7.0, 13.0, 99.0, 100.0, 365.5, 12000.0]) {
        final (top, step) = niceAxis(value);
        expect(top, greaterThanOrEqualTo(value - 1e-9), reason: '$value');
        expect(top / step, lessThanOrEqualTo(5.000001), reason: 'at most five steps for $value');
      }
    });
  });
}
