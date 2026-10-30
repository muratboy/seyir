import 'package:flutter_test/flutter_test.dart';
import 'package:takip/data/models.dart';
import 'package:takip/logic/time_parser.dart';
import 'package:takip/services/nl_parser.dart';

void main() {
  // Sabit bir referans tarihi: 2026-10-30 Cuma saat 14:00 (Friday)
  final fixedNow = DateTime(2026, 10, 30, 14, 0);

  final su = Activity(id: 1, name: 'Su', emoji: '💧', createdAt: 0);
  final kahve = Activity(id: 2, name: 'Kahve', emoji: '☕', createdAt: 0);
  final kosu = Activity(id: 3, name: 'Koşu', emoji: '🏃', createdAt: 0);
  final yuruyus = Activity(id: 4, name: 'Yürüyüş', emoji: '🚶', createdAt: 0);
  final yogaVeMed = Activity(id: 5, name: 'Yoga ve meditasyon', emoji: '🧘', createdAt: 0);
  final ilac = Activity(id: 6, name: 'İlaç', emoji: '💊', createdAt: 0);

  final glass = Measure(id: 1, name: 'Su bardağı', unitId: 'l', amount: 0.2, sort: 0);
  final mlMeasure = Measure(id: 2, name: 'Mililitre', unitId: 'ml', amount: 1.0, sort: 1);
  final dkMeasure = Measure(id: 3, name: 'Dakika', unitId: 'dk', amount: 1.0, sort: 2);
  final kmMeasure = Measure(id: 4, name: 'Kilometre', unitId: 'km', amount: 1.0, sort: 3);

  final activities = [su, kahve, kosu, yuruyus, yogaVeMed, ilac];
  final measures = [glass, mlMeasure, dkMeasure, kmMeasure];

  group('TimeParser Unit Tests', () {
    test('parses relative times ("2 saat önce", "30 dk önce", "yarım saat önce", "az önce")', () {
      final r1 = TimeParser.parse('2 saat önce kahve', direction: TemporalDirection.past, now: fixedNow);
      expect(r1.dateTime, DateTime(2026, 10, 30, 12, 0));
      expect(r1.isRelative, true);
      expect(r1.cleanedText, 'kahve');

      final r2 = TimeParser.parse('30 dk önce', direction: TemporalDirection.past, now: fixedNow);
      expect(r2.dateTime, DateTime(2026, 10, 30, 13, 30));

      final r3 = TimeParser.parse('yarım saat önce', direction: TemporalDirection.past, now: fixedNow);
      expect(r3.dateTime, DateTime(2026, 10, 30, 13, 30));

      final r4 = TimeParser.parse('az önce', direction: TemporalDirection.past, now: fixedNow);
      expect(r4.dateTime, fixedNow);

      final rEng = TimeParser.parse('2 hours ago', direction: TemporalDirection.past, now: fixedNow);
      expect(rEng.dateTime, DateTime(2026, 10, 30, 12, 0));
    });

    test('distinguishes between duration ("30 dk koştum") and timestamp ("30 dk önce koştum")', () {
      final rTime = TimeParser.parse('30 dk önce koştum', direction: TemporalDirection.past, now: fixedNow);
      expect(rTime.hasExplicitTime, true);
      expect(rTime.dateTime, DateTime(2026, 10, 30, 13, 30));

      // Without "önce", it is duration, not a relative timestamp
      final rDuration = TimeParser.parse('30 dk koştum', direction: TemporalDirection.past, now: fixedNow);
      expect(rDuration.isRelative, false);
      expect(rDuration.hasExplicitTime, false);
    });

    test('parses days ("dün", "önceki gün", "evvelsi gün", "dünden önceki gün")', () {
      final rDun = TimeParser.parse('dün 2 kahve', direction: TemporalDirection.past, now: fixedNow);
      expect(rDun.hasExplicitDate, true);
      expect(rDun.dateTime, DateTime(2026, 10, 29, 12, 0)); // Saatsiz gün: 12:00

      final rOnceki = TimeParser.parse('önceki gün', direction: TemporalDirection.past, now: fixedNow);
      expect(rOnceki.dateTime, DateTime(2026, 10, 28, 12, 0));

      final rEvvelsi = TimeParser.parse('evvelsi gün', direction: TemporalDirection.past, now: fixedNow);
      expect(rEvvelsi.dateTime, DateTime(2026, 10, 28, 12, 0));

      final rDundenOnceki = TimeParser.parse('dünden önceki gün', direction: TemporalDirection.past, now: fixedNow);
      expect(rDundenOnceki.dateTime, DateTime(2026, 10, 28, 12, 0));

      // ASCII
      final rAsciiDun = TimeParser.parse('dun', direction: TemporalDirection.past, now: fixedNow);
      expect(rAsciiDun.dateTime, DateTime(2026, 10, 29, 12, 0));
    });

    test('weekday resolution in past direction (en yakın geçmiş gün, bugünün adıysa bugün, geçen cuma -7 gün)', () {
      // fixedNow is Friday 2026-10-30
      final rCuma = TimeParser.parse('cuma', direction: TemporalDirection.past, now: fixedNow);
      expect(rCuma.dateTime.day, 30); // Bugünün adıysa bugün

      final rPersembe = TimeParser.parse('perşembe', direction: TemporalDirection.past, now: fixedNow);
      expect(rPersembe.dateTime.day, 29); // Dün

      final rCarsamba = TimeParser.parse('çarşamba', direction: TemporalDirection.past, now: fixedNow);
      expect(rCarsamba.dateTime.day, 28);

      final rCumartesi = TimeParser.parse('cumartesi', direction: TemporalDirection.past, now: fixedNow);
      expect(rCumartesi.dateTime.day, 24); // Geçen Cumartesi (en yakın geçmiş cumartesi)

      final rGecenCuma = TimeParser.parse('geçen cuma', direction: TemporalDirection.past, now: fixedNow);
      expect(rGecenCuma.dateTime.day, 23); // Bir önceki haftanın cuması (-7 gün)
    });

    test('time of day (sabah 08:00, öğle 12:30, öğleden sonra 15:00, akşam 19:00, gece 22:00)', () {
      final rSabah = TimeParser.parse('dün sabah', direction: TemporalDirection.past, now: fixedNow);
      expect(rSabah.dateTime, DateTime(2026, 10, 29, 8, 0));

      final rOgle = TimeParser.parse('dün öğle', direction: TemporalDirection.past, now: fixedNow);
      expect(rOgle.dateTime, DateTime(2026, 10, 29, 12, 30));

      final rOgledenSonra = TimeParser.parse('dün öğleden sonra', direction: TemporalDirection.past, now: fixedNow);
      expect(rOgledenSonra.dateTime, DateTime(2026, 10, 29, 15, 0));

      final rAksam = TimeParser.parse('dün akşam', direction: TemporalDirection.past, now: fixedNow);
      expect(rAksam.dateTime, DateTime(2026, 10, 29, 19, 0));

      final rGece = TimeParser.parse('dün gece', direction: TemporalDirection.past, now: fixedNow);
      expect(rGece.dateTime, DateTime(2026, 10, 29, 22, 0));

      // Special night rule: "gece" with hour 1-5 -> 01:00 - 05:00
      final rGece2 = TimeParser.parse('dün gece 2', direction: TemporalDirection.past, now: fixedNow);
      expect(rGece2.dateTime, DateTime(2026, 10, 29, 2, 0));
    });

    test('12-hour ambiguity resolution (en yakın geçmiş saat)', () {
      // fixedNow is 14:00 (2 PM)
      // "saat 8":
      // 08:00 is 6 hours ago.
      // 20:00 (8 PM) is 6 hours in the future.
      // Closest past is 08:00!
      final r8 = TimeParser.parse('saat 8', direction: TemporalDirection.past, now: fixedNow);
      expect(r8.dateTime.hour, 8);

      // Now set time to 21:00 (9 PM)
      final eveningNow = DateTime(2026, 10, 30, 21, 0);
      // 08:00 is 13 hours ago.
      // 20:00 (8 PM) is 1 hour ago.
      // Closest past is 20:00!
      final r8Eve = TimeParser.parse('saat 8', direction: TemporalDirection.past, now: eveningNow);
      expect(r8Eve.dateTime.hour, 20);

      // Now set time to 10:00 AM
      final morningNow = DateTime(2026, 10, 30, 10, 0);
      final r8Morn = TimeParser.parse('saat 8', direction: TemporalDirection.past, now: morningNow);
      expect(r8Morn.dateTime.hour, 8);
    });

    test('implicit vs explicit future in past direction', () {
      // fixedNow is 14:00 (2 PM)
      // "akşam" (19:00): implicit future shifts to yesterday 19:00
      final rImplicit = TimeParser.parse('akşam', direction: TemporalDirection.past, now: fixedNow);
      expect(rImplicit.dateTime.day, 29); // dün
      expect(rImplicit.dateTime.hour, 19);
      expect(rImplicit.isExplicitFuture, false);

      // "yarın": explicit future
      final rExplicitYarin = TimeParser.parse('yarın', direction: TemporalDirection.past, now: fixedNow);
      expect(rExplicitYarin.isExplicitFuture, true);

      // Morning 09:00, "bugün akşam" -> explicit future
      final morningNow = DateTime(2026, 10, 30, 9, 0);
      final rExplicitBugunAksam = TimeParser.parse('bugün akşam', direction: TemporalDirection.past, now: morningNow);
      expect(rExplicitBugunAksam.isExplicitFuture, true);
    });
  });

  group('NaturalLanguageParser Splitting & Multi-entry Tests', () {
    test('strong separators: ve, comma, semicolon, ayrica, +, and', () {
      final s1 = NaturalLanguageParser.splitSentence(
        '2 kahve içtim ve 30 dk koştum',
        activities: activities,
        measures: measures,
      );
      expect(s1, ['2 kahve içtim', '30 dk koştum']);

      final s2 = NaturalLanguageParser.splitSentence(
        '500 ml su, 1 elma; 2 kahve ayrıca 15 dk yürüyüş + 10 sayfa kitap and 1 çay',
        activities: activities,
        measures: measures,
      );
      expect(s2.length, 6);
    });

    test('protected places: number with comma and activity names', () {
      // 1,5 l su should NOT split on comma
      final sCommaNum = NaturalLanguageParser.splitSentence(
        '1,5 l su ve 30 dk yürüyüş',
        activities: activities,
        measures: measures,
      );
      expect(sCommaNum, ['1,5 l su', '30 dk yürüyüş']);

      // "Yoga ve meditasyon" should NOT split on "ve"
      final sActivityName = NaturalLanguageParser.splitSentence(
        '1 saat Yoga ve meditasyon yaptım ve 2 kahve içtim',
        activities: activities,
        measures: measures,
      );
      expect(sActivityName.length, 2);
      expect(sActivityName[0].contains('Yoga ve meditasyon'), true);
      expect(sActivityName[1].contains('2 kahve'), true);
    });

    test('weak separators (sonra, daha sonra, then): splits only if both sides match activity', () {
      // "yemekten sonra ilaç aldım" -> "yemekten" is not an activity, should NOT split
      final sPreposition = NaturalLanguageParser.splitSentence(
        'yemekten sonra ilaç aldım',
        activities: activities,
        measures: measures,
      );
      expect(sPreposition, ['yemekten sonra ilaç aldım']);

      // "2 kahve içtim sonra 1 bardak su içtim" -> both match activity (Kahve, Su), SHOULD split
      final sBothActivities = NaturalLanguageParser.splitSentence(
        '2 kahve içtim sonra 1 bardak su içtim',
        activities: activities,
        measures: measures,
      );
      expect(sBothActivities, ['2 kahve içtim', '1 bardak su içtim']);
    });

    test('number words parsing (iki, yarım, buçuk, çeyrek, yirmi iki)', () {
      final p1 = NaturalLanguageParser.parse('iki kahve', activities: activities, measures: measures);
      expect(p1.quantity, 2.0);

      final p2 = NaturalLanguageParser.parse('yarım saat yürüyüş', activities: activities, measures: measures);
      expect(p2.quantity, 0.5);

      final p3 = NaturalLanguageParser.parse('bir buçuk litre su', activities: activities, measures: measures);
      expect(p3.quantity, 1.5);

      final p4 = NaturalLanguageParser.parse('yirmi iki kahve', activities: activities, measures: measures);
      expect(p4.quantity, 22.0);
    });

    test('shared time applies to parts without their own time expression', () {
      final res = NaturalLanguageParser.parseMulti(
        'dün 2 kahve ve 30 dk yürüyüş',
        activities: activities,
        measures: measures,
        now: fixedNow,
      );

      expect(res.items.length, 2);
      final e1 = res.entryItems[0];
      final e2 = res.entryItems[1];

      expect(e1.activity?.name, 'Kahve');
      expect(e1.quantity, 2.0);
      expect(e1.at.day, 29); // dün

      expect(e2.activity?.name, 'Yürüyüş');
      expect(e2.quantity, 30.0);
      expect(e2.at.day, 29); // dün (paylaşılan zaman!)
    });

    test('todo mode detection (yapılacak, todo, date keyword with colon)', () {
      // "yarin: disciyi ara"
      final r1 = NaturalLanguageParser.parseMulti(
        'yarin: disciyi ara',
        activities: activities,
        measures: measures,
        now: fixedNow,
      );
      expect(r1.isTodoMode, true);
      expect(r1.items.length, 1);
      final t1 = r1.todoItems[0];
      expect(t1.title, 'disciyi ara');
      expect(t1.dueDate?.day, 31); // tomorrow

      // "todo 2 kahve ve 30 dk koşu"
      final r2 = NaturalLanguageParser.parseMulti(
        'todo 2 kahve ve 30 dk koşu',
        activities: activities,
        measures: measures,
        now: fixedNow,
      );
      expect(r2.isTodoMode, true);
      expect(r2.todoItems.length, 2);
      expect(r2.todoItems[0].title.contains('kahve'), true);
      expect(r2.todoItems[1].title.contains('koşu'), true);
    });

    test('ASCII Turkish support ("dun gece 500 ml su", "yarin 2 kahve")', () {
      final res = NaturalLanguageParser.parseMulti(
        'dun gece 500 ml su',
        activities: activities,
        measures: measures,
        now: fixedNow,
      );
      expect(res.entryItems.length, 1);
      final e = res.entryItems[0];
      expect(e.activity?.name, 'Su');
      expect(e.quantity, 500.0);
      expect(e.at, DateTime(2026, 10, 29, 22, 0)); // Dün 22:00

      // "yarin 2 kahve" -> explicit future flag
      final resFut = NaturalLanguageParser.parseMulti(
        'yarin 2 kahve',
        activities: activities,
        measures: measures,
        now: fixedNow,
      );
      expect(resFut.entryItems.length, 1);
      expect(resFut.entryItems[0].isExplicitFuture, true);
    });
  });
}
