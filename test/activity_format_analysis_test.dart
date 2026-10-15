import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:takip/data/models.dart';
import 'package:takip/logic/activity_format_analysis.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('tr_TR');
    await initializeDateFormatting('en_US');
    Intl.defaultLocale = 'tr_TR';
  });

  Unit? mockUnitOf(String id) {
    return builtinUnits.firstWhere((u) => u.id == id, orElse: () => builtinUnits.first);
  }

  String? mockMeasureNameOf(int id) {
    if (id == 1) return 'Demlik';
    if (id == 2) return 'Kupa';
    return null;
  }

  final now = DateTime(2026, 10, 15, 12, 0);

  group('ActivityFormat Detection Tests', () {
    test('detects duration format when entries have duration or time unit', () {
      final act = Activity(id: 1, name: 'Kitap', createdAt: 0);
      final entries = [
        Entry(
          id: 1,
          activityId: 1,
          ts: now.subtract(const Duration(hours: 2)).millisecondsSinceEpoch,
          endTs: now.subtract(const Duration(hours: 1)).millisecondsSinceEpoch,
        ),
        Entry(
          id: 2,
          activityId: 1,
          ts: now.millisecondsSinceEpoch,
          value: 45,
          unitId: 'dk',
        ),
      ];

      final format = ActivityFormatAnalysis.detectFormat(
        activity: act,
        entries: entries,
        unitOf: mockUnitOf,
      );

      expect(format, equals(ActivityFormat.duration));
    });

    test('detects quantity format when entries have volume, distance or mass', () {
      final act = Activity(id: 2, name: 'Su', createdAt: 0);
      final entries = [
        Entry(
          id: 1,
          activityId: 2,
          ts: now.subtract(const Duration(hours: 5)).millisecondsSinceEpoch,
          value: 0.5,
          unitId: 'l',
        ),
        Entry(
          id: 2,
          activityId: 2,
          ts: now.millisecondsSinceEpoch,
          value: 300,
          unitId: 'ml',
        ),
      ];

      final format = ActivityFormatAnalysis.detectFormat(
        activity: act,
        entries: entries,
        unitOf: mockUnitOf,
      );

      expect(format, equals(ActivityFormat.quantity));
    });

    test('detects event format when entries have no dimension or continuous value', () {
      final act = Activity(id: 3, name: 'Baş Ağrısı', createdAt: 0);
      final entries = [
        Entry(
          id: 1,
          activityId: 3,
          ts: now.subtract(const Duration(days: 2)).millisecondsSinceEpoch,
          note: 'Hafif ağrı',
        ),
        Entry(
          id: 2,
          activityId: 3,
          ts: now.millisecondsSinceEpoch,
          note: 'Şiddet 7/10',
        ),
      ];

      final format = ActivityFormatAnalysis.detectFormat(
        activity: act,
        entries: entries,
        unitOf: mockUnitOf,
      );

      expect(format, equals(ActivityFormat.event));
    });
  });

  group('Duration Metrics Tests', () {
    test('computes total minutes, session count, avg session and longest session', () {
      final act = Activity(id: 1, name: 'Ders', createdAt: 0);
      final entries = [
        Entry(
          id: 1,
          activityId: 1,
          ts: now.subtract(const Duration(days: 2, hours: 1)).millisecondsSinceEpoch,
          endTs: now.subtract(const Duration(days: 2)).millisecondsSinceEpoch, // 60 mins
        ),
        Entry(
          id: 2,
          activityId: 1,
          ts: now.subtract(const Duration(days: 1, minutes: 90)).millisecondsSinceEpoch,
          endTs: now.subtract(const Duration(days: 1)).millisecondsSinceEpoch, // 90 mins
        ),
        Entry(
          id: 3,
          activityId: 1,
          ts: now.subtract(const Duration(minutes: 30)).millisecondsSinceEpoch,
          value: 30,
          unitId: 'dk', // 30 mins
        ),
      ];

      final analysis = ActivityFormatAnalysis.compute(
        activity: act,
        entries: entries,
        unitOf: mockUnitOf,
        measureNameOf: mockMeasureNameOf,
        now: now,
        elapsedDays: 5,
        isTr: true,
      );

      expect(analysis.format, equals(ActivityFormat.duration));
      final metrics = analysis.durationMetrics!;
      expect(metrics.totalMinutes, equals(180.0)); // 60 + 90 + 30
      expect(metrics.sessionCount, equals(3));
      expect(metrics.avgSessionMinutes, equals(60.0));
      expect(metrics.longestSessionMinutes, equals(90.0));
      expect(metrics.shortestSessionMinutes, equals(30.0));
      expect(metrics.dailyAvgMinutes, equals(36.0)); // 180 / 5
      expect(metrics.activeDayAvgMinutes, equals(60.0)); // 180 / 3 active days
    });
  });

  group('Quantity Metrics Tests', () {
    test('computes totalBase, daily avg, avg per entry and measures breakdown', () {
      final act = Activity(id: 2, name: 'Çay', createdAt: 0);
      final entries = [
        Entry(
          id: 1,
          activityId: 2,
          ts: now.subtract(const Duration(days: 1)).millisecondsSinceEpoch,
          value: 0.7,
          unitId: 'l',
          measureId: 1, // Demlik
        ),
        Entry(
          id: 2,
          activityId: 2,
          ts: now.millisecondsSinceEpoch,
          value: 0.3,
          unitId: 'l',
          measureId: 2, // Kupa
        ),
      ];

      final analysis = ActivityFormatAnalysis.compute(
        activity: act,
        entries: entries,
        unitOf: mockUnitOf,
        measureNameOf: mockMeasureNameOf,
        now: now,
        elapsedDays: 2,
        isTr: true,
      );

      expect(analysis.format, equals(ActivityFormat.quantity));
      final metrics = analysis.quantityMetrics!;
      expect(metrics.totalBase, closeTo(1.0, 1e-5)); // 0.7 + 0.3
      expect(metrics.entryCount, equals(2));
      expect(metrics.avgPerEntry, closeTo(0.5, 1e-5));
      expect(metrics.dailyAvgBase, closeTo(0.5, 1e-5));
      expect(metrics.maxEntryBase, closeTo(0.7, 1e-5));
      expect(metrics.measureBreakdown.length, equals(2));
      expect(metrics.measureBreakdown.first.$1, equals('Demlik'));
    });
  });

  group('Event Metrics & Intervals Tests', () {
    test('computes intervals between consecutive events and time since last', () {
      final act = Activity(id: 3, name: 'Migren', createdAt: 0);
      final t0 = now.subtract(const Duration(days: 6));
      final t1 = now.subtract(const Duration(days: 4)); // 2 days gap
      final t2 = now.subtract(const Duration(days: 1)); // 3 days gap

      final entries = [
        Entry(id: 1, activityId: 3, ts: t0.millisecondsSinceEpoch),
        Entry(id: 2, activityId: 3, ts: t1.millisecondsSinceEpoch),
        Entry(id: 3, activityId: 3, ts: t2.millisecondsSinceEpoch),
      ];

      final analysis = ActivityFormatAnalysis.compute(
        activity: act,
        entries: entries,
        unitOf: mockUnitOf,
        measureNameOf: mockMeasureNameOf,
        now: now,
        elapsedDays: 7,
        isTr: true,
      );

      expect(analysis.format, equals(ActivityFormat.event));
      final metrics = analysis.eventMetrics!;
      expect(metrics.totalCount, equals(3));
      expect(metrics.avgInterval?.inDays, equals(2)); // (2d + 3d) / 2 = 2.5d -> inDays = 2
      expect(metrics.minInterval?.inDays, equals(2));
      expect(metrics.maxInterval?.inDays, equals(3));
      expect(metrics.timeSinceLast?.inDays, equals(1)); // t2 is 1 day ago
    });
  });

  group('Severity Extraction & Trend Tests', () {
    test('extracts fraction, word and keyword scores accurately', () {
      final e1 = Entry(id: 1, activityId: 4, ts: 0, note: 'Baş ağrısı 8/10');
      final e2 = Entry(id: 2, activityId: 4, ts: 0, note: 'Şiddet: 6 ve bulantı');
      final e3 = Entry(id: 3, activityId: 4, ts: 0, note: 'Hafif sızı');
      final e4 = Entry(id: 4, activityId: 4, ts: 0, note: 'Çok şiddetli kriz');

      expect(ActivityFormatAnalysis.extractSeverityScore(e1), equals(8.0));
      expect(ActivityFormatAnalysis.extractSeverityScore(e2), equals(6.0));
      expect(ActivityFormatAnalysis.extractSeverityScore(e3), equals(2.5));
      expect(ActivityFormatAnalysis.extractSeverityScore(e4), equals(9.0));
    });

    test('detects decreasing severity trend over time', () {
      final entries = [
        Entry(id: 1, activityId: 4, ts: 100, note: 'Şiddetli 9/10'),
        Entry(id: 2, activityId: 4, ts: 200, note: 'Şiddet: 8'),
        Entry(id: 3, activityId: 4, ts: 300, note: 'Orta 5/10'),
        Entry(id: 4, activityId: 4, ts: 400, note: 'Hafif 3/10'),
      ];

      final severity = ActivityFormatAnalysis.extractSeverityAnalysis(entries);
      expect(severity.hasData, isTrue);
      expect(severity.count, equals(4));
      expect(severity.lastScore, equals(3.0));
      expect(severity.direction, equals(SeverityTrendDirection.decreasing));
      expect(severity.distribution['hafif'], equals(1));
      expect(severity.distribution['orta'], equals(1));
      expect(severity.distribution['şiddetli'], equals(2));
    });

    test('detects increasing severity trend', () {
      final entries = [
        Entry(id: 1, activityId: 4, ts: 100, note: 'Hafif sızı 3/10'),
        Entry(id: 2, activityId: 4, ts: 200, note: 'Şiddetli ağrı 8.5/10'),
      ];

      final severity = ActivityFormatAnalysis.extractSeverityAnalysis(entries);
      expect(severity.direction, equals(SeverityTrendDirection.increasing));
    });
  });

  group('fmtInterval Tests', () {
    test('formats day and hours cleanly', () {
      expect(fmtInterval(const Duration(days: 3, hours: 4), isTr: true), equals('3 gün 4 sa'));
      expect(fmtInterval(const Duration(days: 3, hours: 4), isTr: false), equals('3 d 4 h'));
      expect(fmtInterval(const Duration(days: 2), isTr: true), equals('2 gün'));
      expect(fmtInterval(const Duration(hours: 15, minutes: 20), isTr: true), equals('15 sa 20 dk'));
      expect(fmtInterval(const Duration(minutes: 45), isTr: true), equals('45 dk'));
    });
  });
}
