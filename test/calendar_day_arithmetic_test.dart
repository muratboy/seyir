import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:takip/data/models.dart';
import 'package:takip/data/store.dart';
import 'package:takip/logic/format.dart';
import 'package:takip/logic/period_stats.dart';
import 'package:takip/logic/time_parser.dart';
import 'package:takip/logic/todo_parser.dart';
import 'package:takip/logic/trend_insights.dart';
import 'package:takip/services/nl_parser.dart';
import 'package:takip/ui/activity_page.dart';
import 'package:takip/ui/components/todo_quick_add_sheet.dart';
import 'package:takip/ui/components/todo_tile.dart';
import 'package:takip/ui/tabs/todos_tab.dart';

import 'support/real_db.dart';

void main() {
  useRealDatabase();

  setUpAll(() async {
    await initializeDateFormatting('tr_TR', null);
    await initializeDateFormatting('en_US', null);
  });

  group('Gün başlığı (fmtDayTitle)', () {
    test('Avrupa ilkbahar yaz saati geçişi (2026-03-29, 23 saat): ertesi gün Yarın görünür', () {
      // 29 Mart 23 saattir. 29 Mart günündeyken 30 Mart "Yarın" olmalıdır ("Bugün" değil).
      final now = DateTime(2026, 3, 29, 10, 0);
      final tomorrow = DateTime(2026, 3, 30, 10, 0);
      expect(fmtDayTitle(tomorrow, isTr: true, now: now), 'Yarın');

      // 30 Mart günündeyken 29 Mart "Dün" olmalıdır ("Bugün" değil).
      final dayAfter = DateTime(2026, 3, 30, 10, 0);
      final yesterday = DateTime(2026, 3, 29, 10, 0);
      expect(fmtDayTitle(yesterday, isTr: true, now: dayAfter), 'Dün');
    });

    test('ABD ilkbahar geçişi (2026-03-08, 23 saat): ertesi gün Yarın, önceki gün Dün', () {
      final now = DateTime(2026, 3, 8, 10, 0);
      final tomorrow = DateTime(2026, 3, 9, 10, 0);
      expect(fmtDayTitle(tomorrow, isTr: true, now: now), 'Yarın');

      final dayAfter = DateTime(2026, 3, 9, 10, 0);
      final yesterday = DateTime(2026, 3, 8, 10, 0);
      expect(fmtDayTitle(yesterday, isTr: true, now: dayAfter), 'Dün');
    });

    test('Avrupa sonbahar geçişi (2026-10-25, 25 saat): ertesi gün Yarın, önceki gün Dün', () {
      final now = DateTime(2026, 10, 24, 10, 0);
      final transitionDay = DateTime(2026, 10, 25, 10, 0);
      expect(fmtDayTitle(transitionDay, isTr: true, now: now), 'Yarın');

      final dayAfter = DateTime(2026, 10, 26, 10, 0);
      expect(fmtDayTitle(transitionDay, isTr: true, now: dayAfter), 'Dün');
    });
  });

  group('Yapılacak kartındaki kalan gün rozeti (TodoTile)', () {
    test('Avrupa ilkbahar geçişinde ertesi gün teslim edilecek görev "yarın" rozeti alır', () {
      final now = DateTime(2026, 3, 29, 10, 0);
      expect(TodoTile.dueDiffDays('2026-03-30', now: now), 1);
      expect(TodoTile.formatDueLabel('2026-03-30', true, now: now), 'yarın');

      final dayAfter = DateTime(2026, 3, 30, 10, 0);
      expect(TodoTile.dueDiffDays('2026-03-29', now: dayAfter), -1);
      expect(TodoTile.formatDueLabel('2026-03-29', true, now: dayAfter), 'dün');
    });

    test('ABD ilkbahar geçişinde ertesi gün teslim edilecek görev "yarın" rozeti alır', () {
      final now = DateTime(2026, 3, 8, 10, 0);
      expect(TodoTile.dueDiffDays('2026-03-09', now: now), 1);
      expect(TodoTile.formatDueLabel('2026-03-09', true, now: now), 'yarın');
    });

    test('Avrupa sonbahar geçişinde gün farkı doğru hesaplanır', () {
      final now = DateTime(2026, 10, 24, 10, 0);
      expect(TodoTile.dueDiffDays('2026-10-25', now: now), 1);
      expect(TodoTile.formatDueLabel('2026-10-25', true, now: now), 'yarın');
    });
  });

  group('Günlük sayfasındaki gün farkı (calendarDaysBetween)', () {
    test('23 ve 25 saatlik geçiş günlerinde takvim günü farkı 1 çıkar', () {
      expect(calendarDaysBetween(DateTime(2026, 3, 28), DateTime(2026, 3, 29)), 1);
      expect(calendarDaysBetween(DateTime(2026, 3, 29), DateTime(2026, 3, 30)), 1);
      expect(calendarDaysBetween(DateTime(2026, 10, 24), DateTime(2026, 10, 25)), 1);
      expect(calendarDaysBetween(DateTime(2026, 10, 25), DateTime(2026, 10, 26)), 1);
      expect(calendarDaysBetween(DateTime(2026, 3, 7), DateTime(2026, 3, 8)), 1);
      expect(calendarDaysBetween(DateTime(2026, 3, 8), DateTime(2026, 3, 9)), 1);
      expect(calendarDaysBetween(DateTime(2026, 10, 31), DateTime(2026, 11, 1)), 1);
      expect(calendarDaysBetween(DateTime(2026, 11, 1), DateTime(2026, 11, 2)), 1);
    });
  });

  group('Metinden tarih okuma (TimeParser & TodoInputParser & NLParser)', () {
    test('ABD sonbahar geçişinde haftanın günü 6 gün sonraya kaymaz: fatura öde pazartesi', () {
      final now = DateTime(2026, 10, 27, 14, 0); // Salı
      final res = TodoInputParser.parse('fatura öde pazartesi', activities: [], measures: [], now: now);
      expect(res.date, DateTime(2026, 11, 2));
    });

    test('Avrupa sonbahar geçişinde "haftaya" tam 7 gün sonrasını verir', () {
      final now = DateTime(2026, 10, 24, 10, 0); // Cumartesi
      final res = TimeParser.parse('haftaya', direction: TemporalDirection.future, now: now);
      expect(res.dateTime, DateTime(2026, 10, 31, 12, 0));
    });

    test('Avrupa sonbahar geçişinde "öbür gün" tam 2 gün sonrasını verir', () {
      final now = DateTime(2026, 10, 24, 10, 0); // Cumartesi
      final res = TimeParser.parse('öbür gün', direction: TemporalDirection.future, now: now);
      expect(res.dateTime, DateTime(2026, 10, 26, 12, 0));
    });

    test('Avrupa sonbahar geçişinde "evvelsi gün" tam 2 gün öncesini verir', () {
      final now = DateTime(2026, 10, 26, 10, 0); // Pazartesi
      final res = TimeParser.parse('evvelsi gün', direction: TemporalDirection.past, now: now);
      expect(res.dateTime, DateTime(2026, 10, 24, 12, 0));
    });

    test('Avrupa sonbahar geçişinde "geçen hafta" tam 7 gün öncesini verir', () {
      final now = DateTime(2026, 10, 26, 10, 0); // Pazartesi
      final res = TimeParser.parse('geçen hafta', direction: TemporalDirection.past, now: now);
      expect(res.dateTime, DateTime(2026, 10, 19, 12, 0));
    });

    test('Avrupa sonbahar geçişinde "hafta sonu" doğru cumartesiyi verir', () {
      final now = DateTime(2026, 10, 21, 10, 0); // Çarşamba
      final res = TimeParser.parse('hafta sonu', direction: TemporalDirection.future, now: now);
      expect(res.dateTime, DateTime(2026, 10, 24, 12, 0));
    });

    test('Kayıt ayrıştırıcısında "dün" ve "yarın" geçiş günlerinde doğru takvim gününü verir', () {
      final now1 = DateTime(2026, 10, 25, 14, 0); // Geçiş günü Pazar
      final resDun = TimeParser.parse('dün 2 kahve', direction: TemporalDirection.past, now: now1);
      expect(resDun.dateTime, DateTime(2026, 10, 24, 12, 0));

      final now2 = DateTime(2026, 10, 24, 14, 0); // Geçişten önceki gün
      final resYarin = TimeParser.parse('yarın', direction: TemporalDirection.future, now: now2);
      expect(resYarin.dateTime, DateTime(2026, 10, 25, 12, 0));
    });

    test('NaturalLanguageParser.parseMulti geçiş haftasında haftanın gününü doğru tarihler', () {
      final now = DateTime(2026, 10, 27, 14, 0); // Salı
      final multi = NaturalLanguageParser.parseMulti('fatura öde pazartesi', activities: [], measures: [], forceTodo: true, now: now);
      expect(multi.items.isNotEmpty, isTrue);
      final item = multi.items.first;
      final d = item is TodoParsedItem ? item.dueDate : (item as EntryParsedItem).at;
      expect(d, DateTime(2026, 11, 2));
    });

    test('İlkbahar geçişinde "dün" ifadesi geçiş gününün takvim tarihini verir', () {
      final nowEurope = DateTime(2026, 3, 30, 10, 0);
      final resEurope = TimeParser.parse('dün', direction: TemporalDirection.past, now: nowEurope);
      expect(resEurope.dateTime, DateTime(2026, 3, 29, 12, 0));

      final nowUs = DateTime(2026, 3, 9, 10, 0);
      final resUs = TimeParser.parse('dün', direction: TemporalDirection.past, now: nowUs);
      expect(resUs.dateTime, DateTime(2026, 3, 8, 12, 0));
    });

    test('İlkbahar geçişinde "evvelsi gün" ifadesi iki takvim günü öncesini verir', () {
      final nowEurope = DateTime(2026, 3, 30, 10, 0);
      final resEurope = TimeParser.parse('evvelsi gün', direction: TemporalDirection.past, now: nowEurope);
      expect(resEurope.dateTime, DateTime(2026, 3, 28, 12, 0));

      final nowUs = DateTime(2026, 3, 9, 10, 0);
      final resUs = TimeParser.parse('evvelsi gün', direction: TemporalDirection.past, now: nowUs);
      expect(resUs.dateTime, DateTime(2026, 3, 7, 12, 0));
    });

    test('İlkbahar geçişinde "geçen hafta" ifadesi yedi takvim günü öncesini verir', () {
      final nowEurope = DateTime(2026, 4, 1, 10, 0);
      final resEurope = TimeParser.parse('geçen hafta', direction: TemporalDirection.past, now: nowEurope);
      expect(resEurope.dateTime, DateTime(2026, 3, 25, 12, 0));

      final nowUs = DateTime(2026, 3, 11, 10, 0);
      final resUs = TimeParser.parse('geçen hafta', direction: TemporalDirection.past, now: nowUs);
      expect(resUs.dateTime, DateTime(2026, 3, 4, 12, 0));
    });

    test('İlkbahar geçişinde geçmiş yönde haftanın günü önceki cuma gününü verir', () {
      final nowEurope = DateTime(2026, 3, 31, 10, 0); // Salı
      final resEurope = TimeParser.parse('cuma kahve', direction: TemporalDirection.past, now: nowEurope);
      expect(resEurope.dateTime, DateTime(2026, 3, 27, 12, 0));

      final nowUs = DateTime(2026, 3, 10, 10, 0); // Salı
      final resUs = TimeParser.parse('cuma kahve', direction: TemporalDirection.past, now: nowUs);
      expect(resUs.dateTime, DateTime(2026, 3, 6, 12, 0));
    });

    test('İlkbahar geçişinde geçmiş yönde "hafta sonu" önceki cumartesiyi verir', () {
      final nowEurope = DateTime(2026, 3, 30, 10, 0); // Pazartesi
      final resEurope = TimeParser.parse('hafta sonu', direction: TemporalDirection.past, now: nowEurope);
      expect(resEurope.dateTime, DateTime(2026, 3, 28, 12, 0));

      final nowUs = DateTime(2026, 3, 9, 10, 0); // Pazartesi
      final resUs = TimeParser.parse('hafta sonu', direction: TemporalDirection.past, now: nowUs);
      expect(resUs.dateTime, DateTime(2026, 3, 7, 12, 0));
    });

    test('İlkbahar geçişinde gece yarısından hemen sonra örtük dünkü saat geçiş gününü verir', () {
      final nowEurope = DateTime(2026, 3, 30, 0, 30);
      final resEurope = TimeParser.parse('23:30 kahve', direction: TemporalDirection.past, now: nowEurope);
      expect(resEurope.dateTime, DateTime(2026, 3, 29, 23, 30));

      final nowUs = DateTime(2026, 3, 9, 0, 30);
      final resUs = TimeParser.parse('23:30 kahve', direction: TemporalDirection.past, now: nowUs);
      expect(resUs.dateTime, DateTime(2026, 3, 8, 23, 30));
    });
  });

  group('Hızlı yapılacak eklemedeki Yarın ve Hafta sonu çipleri', () {
    test('Avrupa sonbahar geçişinde Yarın çipi ertesi günün tarihini verir (aynı güne düşmez)', () {
      final now = DateTime(2026, 10, 25, 0, 0); // 25 saatlik pazarın başlangıcı
      expect(TodoQuickAddSheet.tomorrowDate(now: now), DateTime(2026, 10, 26));
    });

    test('ABD sonbahar geçişinde Yarın çipi ertesi günün tarihini verir', () {
      final now = DateTime(2026, 11, 1, 0, 0); // 25 saatlik pazarın başlangıcı
      expect(TodoQuickAddSheet.tomorrowDate(now: now), DateTime(2026, 11, 2));
    });

    test('Avrupa sonbahar geçişinde Hafta sonu çipi doğru cumartesiyi verir', () {
      final now = DateTime(2026, 10, 21, 10, 0); // Çarşamba
      expect(TodoQuickAddSheet.weekendDate(now: now), DateTime(2026, 10, 24));
    });
  });

  group('Yapılacaklar sekmesindeki yarın ve hafta sonu süzgeçleri', () {
    test('Avrupa sonbahar geçişinde tomorrowDateStr ertesi günün tarihini üretir', () {
      final now = DateTime(2026, 10, 25, 0, 0);
      expect(TodosView.tomorrowDateStr(now: now), '2026-10-26');
    });

    test('ABD sonbahar geçişinde tomorrowDateStr ertesi günün tarihini üretir', () {
      final now = DateTime(2026, 11, 1, 0, 0);
      expect(TodosView.tomorrowDateStr(now: now), '2026-11-02');
    });

    test('Avrupa sonbahar geçişinde endOfWeekDateStr pazar gününün tarihini üretir', () {
      final now = DateTime(2026, 10, 21, 10, 0); // Çarşamba
      expect(TodosView.endOfWeekDateStr(now: now), '2026-10-25');
    });
  });

  group('Yapılacağı bir gün erteleme (postponeTodo)', () {
    test('Avrupa sonbahar geçişinde yapılacak bir gün ertelenince tarihi ertesi güne geçer', () async {
      await store.load();
      final created = await store.createTodo(
        Todo(
          id: 0,
          title: 'Erteleme testi görevi',
          createdAt: DateTime(2026, 10, 25, 0, 0).millisecondsSinceEpoch,
          dueDate: '2026-10-25',
        ),
      );
      expect(created, isNotNull);

      // 25 Ekim 25 saat olduğu için +24 saat eklenirse aynı günün 23:00'ünde kalır!
      await store.postponeTodo(created.id, now: DateTime(2026, 10, 25, 0, 0));
      final updated = store.todos.firstWhere((t) => t.id == created.id);
      expect(updated.dueDate, '2026-10-26');
    });

    test('ABD sonbahar geçişinde yapılacak ertelenince tarihi ertesi güne geçer', () async {
      await store.load();
      final created = await store.createTodo(
        Todo(
          id: 0,
          title: 'ABD Erteleme testi görevi',
          createdAt: DateTime(2026, 11, 1, 0, 0).millisecondsSinceEpoch,
          dueDate: '2026-11-01',
        ),
      );
      expect(created, isNotNull);

      await store.postponeTodo(created.id, now: DateTime(2026, 11, 1, 0, 0));
      final updated = store.todos.firstWhere((t) => t.id == created.id);
      expect(updated.dueDate, '2026-11-02');
    });
  });

  group('Yol haritası adımlarının gün döngüsü ve geçen gün sayısı', () {
    test('Avrupa ilkbahar geçişinde gün sayısı 23 saat için 0 kalmaz, her gün sayılır', () async {
      await store.load();
      final act = await store.addActivity('Adım Koşu', emoji: '🏃');
      final goal = Goal(
        id: 0,
        name: 'Günlük Koşu',
        type: 'target',
        mode: 'count',
        target: 1,
        period: GoalPeriod.day,
        startDate: DateTime(2026, 3, 29, 0, 0).millisecondsSinceEpoch,
        createdAt: DateTime(2026, 3, 29, 0, 0).millisecondsSinceEpoch,
        links: [GoalLink(activityId: act.id, pct: 100)],
      );
      await store.saveGoal(goal);
      final g = store.goals.last;

      final r = Roadmap(
        id: 100,
        title: 'Koşu Yol Haritası',
        createdAt: DateTime(2026, 3, 29, 0, 0).millisecondsSinceEpoch,
        startedAt: DateTime(2026, 3, 29, 0, 0).millisecondsSinceEpoch,
        status: 'active',
        steps: [
          RoadmapStep(
            id: 101,
            roadmapId: 100,
            title: '2 Gün Koş',
            target: 2,
            unit: 'gün',
            linkedGoalId: g.id,
            startedAt: DateTime(2026, 3, 29, 0, 0).millisecondsSinceEpoch,
          ),
        ],
      );

      // 29 Mart ve 30 Mart'a kayıt ekle
      await store.addEntry(act.id, at: DateTime(2026, 3, 29, 10, 0));
      await store.addEntry(act.id, at: DateTime(2026, 3, 30, 10, 0));

      final prog = store.stepProgress(r, r.steps.first, now: DateTime(2026, 3, 30, 15, 0));
      expect(prog, isNotNull);
      expect(prog!.done, 2.0); // 29 ve 30 Mart'ın ikisi de sayılmalı
    });

    test('Süreli adımda geçen gün sayısı ilkbahar geçişinde eksik kalmaz', () async {
      await store.load();
      final r = Roadmap(
        id: 200,
        title: 'Meydan Okuma',
        createdAt: DateTime(2026, 3, 29, 0, 0).millisecondsSinceEpoch,
        startedAt: DateTime(2026, 3, 29, 0, 0).millisecondsSinceEpoch,
        status: 'active',
        steps: [
          RoadmapStep(
            id: 201,
            roadmapId: 200,
            title: '2 Günlük Meydan Okuma',
            target: 2,
            unit: 'gün',
            startedAt: DateTime(2026, 3, 29, 0, 0).millisecondsSinceEpoch,
          ),
        ],
      );

      final prog = store.stepProgress(r, r.steps.first, now: DateTime(2026, 3, 30, 15, 0));
      expect(prog, isNotNull);
      expect(prog!.done, 2.0); // 29 ve 30 Mart = 2 gün
    });

    test('Avrupa sonbahar geçişinde gün sayısı aynı günü iki kez saymaz', () async {
      await store.load();
      final act = await store.addActivity('Sonbahar Koşu', emoji: '🏃');
      final goal = Goal(
        id: 0,
        name: 'Günlük Koşu Hedefi',
        type: 'target',
        mode: 'count',
        target: 1,
        period: GoalPeriod.day,
        startDate: DateTime(2026, 10, 25, 0, 0).millisecondsSinceEpoch,
        createdAt: DateTime(2026, 10, 25, 0, 0).millisecondsSinceEpoch,
        links: [GoalLink(activityId: act.id, pct: 100)],
      );
      await store.saveGoal(goal);
      final g = store.goals.last;

      final r = Roadmap(
        id: 300,
        title: 'Sonbahar Yol Haritası',
        createdAt: DateTime(2026, 10, 25, 0, 0).millisecondsSinceEpoch,
        startedAt: DateTime(2026, 10, 25, 0, 0).millisecondsSinceEpoch,
        status: 'active',
        steps: [
          RoadmapStep(
            id: 301,
            roadmapId: 300,
            title: '2 Gün Koş',
            target: 2,
            unit: 'gün',
            linkedGoalId: g.id,
            startedAt: DateTime(2026, 10, 25, 0, 0).millisecondsSinceEpoch,
          ),
        ],
      );

      // Yalnızca 25 Ekim'e kayıt ekle
      await store.addEntry(act.id, at: DateTime(2026, 10, 25, 10, 0));

      // Şimdi = 2026-10-26 15:00. Henüz 26 Ekim'e kayıt eklenmediğinden tamamlanan gün 1 olmalıdır.
      final now = DateTime(2026, 10, 26, 15, 0);
      final prog1 = store.stepProgress(r, r.steps.first, now: now);
      expect(prog1, isNotNull);
      expect(prog1!.done, 1.0);

      // 26 Ekim'e de kayıt eklenince tamamlanan gün 2 olur
      await store.addEntry(act.id, at: DateTime(2026, 10, 26, 10, 0));
      final prog2 = store.stepProgress(r, r.steps.first, now: now);
      expect(prog2, isNotNull);
      expect(prog2!.done, 2.0);
    });
  });

  group('Hedefin toplam süresi', () {
    test('İlkbahar geçiş gününde biten hedefin toplam dakikası tam hesaplanır', () async {
      await store.load();
      final act = await store.addActivity('Hedef Test', emoji: '🎯');
      final goal = Goal(
        id: 0,
        name: 'Geçiş Hedefi',
        type: 'target',
        mode: 'count',
        target: 10,
        period: GoalPeriod.total,
        startDate: DateTime(2026, 3, 28, 0, 0).millisecondsSinceEpoch,
        endDate: DateTime(2026, 3, 29, 0, 0).millisecondsSinceEpoch,
        createdAt: DateTime(2026, 3, 28, 0, 0).millisecondsSinceEpoch,
        links: [GoalLink(activityId: act.id, pct: 100)],
      );
      await store.saveGoal(goal);
      final g = store.goals.last;

      final expectedMinutes = DateTime(2026, 3, 30, 0, 0).difference(DateTime(2026, 3, 28, 0, 0)).inMinutes;
      final st = store.goalStatus(g, now: DateTime(2026, 3, 28, 12, 0));

      final start = DateTime(2026, 3, 28, 0, 0);
      final nowMoment = DateTime(2026, 3, 28, 12, 0);
      final passed = nowMoment.difference(start).inMinutes;
      final expectedRatio = (passed / expectedMinutes).clamp(0.0, 1.0);

      expect(st.timeRatio, closeTo(expectedRatio, 0.0001));
    });

    test('at ile now farklı verildiğinde daysLeft ve timeRatio now parametresine göre hesaplanır', () async {
      await store.load();
      final act = await store.addActivity('Hedef Referans Test', emoji: '🎯');
      final goal = Goal(
        id: 0,
        name: 'Kalan Gün Testi',
        type: 'target',
        mode: 'count',
        target: 10,
        period: GoalPeriod.total,
        startDate: DateTime(2026, 3, 20, 0, 0).millisecondsSinceEpoch,
        endDate: DateTime(2026, 3, 29, 0, 0).millisecondsSinceEpoch,
        createdAt: DateTime(2026, 3, 20, 0, 0).millisecondsSinceEpoch,
        links: [GoalLink(activityId: act.id, pct: 100)],
      );
      await store.saveGoal(goal);
      final g = store.goals.last;

      final atDate = DateTime(2026, 3, 20, 0, 0);
      final nowDate = DateTime(2026, 3, 25, 12, 0);
      final st = store.goalStatus(g, at: atDate, now: nowDate);

      final end = DateTime(2026, 3, 29, 0, 0);
      final start = DateTime(2026, 3, 20, 0, 0);
      expect(st.daysLeft, daysBetween(nowDate, end));
      expect(st.daysLeft, isNot(daysBetween(atDate, end)));

      final totalMinutes = addDays(end, 1).difference(start).inMinutes;
      final passedMinutes = nowDate.difference(start).inMinutes;
      expect(st.timeRatio, closeTo(passedMinutes / totalMinutes, 0.0001));
    });
  });

  group('Aktivite sayfasındaki günlük ortalamanın gün sayısı', () {
    test('İlkbahar geçiş haftasında elapsedDays 6 değil 7 çıkar', () {
      final period = StatPeriod.containing(StatRange.week, DateTime(2026, 3, 29));
      expect(ActivityPage.elapsedDaysForPeriod(period), 7);
    });
  });

  group('Önceki dönem karşılaştırma anı (hafta ve ay)', () {
    test('TrendInsights haftalık içgörülerde önceki haftanın anı 1 saat kaymaz', () async {
      await store.load();
      final now = DateTime(2026, 3, 29, 14, 0);

      final act = await store.addActivity('Haftalık Test', emoji: '⚡');
      // Önceki haftanın Pazar 10:00, 12:00 ve 13:30'una kayıt ekle (hepsi 14:00'ten önce)
      await store.addEntry(act.id, at: DateTime(2026, 3, 22, 10, 0));
      await store.addEntry(act.id, at: DateTime(2026, 3, 22, 12, 0));
      await store.addEntry(act.id, at: DateTime(2026, 3, 22, 13, 30));

      // Bu haftada da aynı ana kadar 3 kayıt (önceki haftayla aynı tempo)
      await store.addEntry(act.id, at: DateTime(2026, 3, 25, 10, 0));
      await store.addEntry(act.id, at: DateTime(2026, 3, 26, 12, 0));
      await store.addEntry(act.id, at: DateTime(2026, 3, 28, 10, 0));

      // Önceki haftanın karşılaştırma anı tam 2026-03-22 14:00 olduğunda 3 vs 3 çıkar,
      // artış veya azalış içgörüsü oluşmaz. Eski 24 saat ekleme hesabında an 13:00'e kayarak
      // 13:30 kaydını dışarıda bırakır ve hatalı bir "artışta" içgörüsü üretir.
      final insights = computeWeeklyInsights(store: store, now: now, isTr: true);
      expect(insights.any((i) => i.activityId == act.id && (i.type == TrendType.increased || i.type == TrendType.decreased)), isFalse);
    });

    test('PeriodStats karşılaştırma anı DST geçişinde 1 saat kaymaz', () {
      final now = DateTime(2026, 3, 29, 14, 0); // Pazar 14:00
      final period = StatPeriod.containing(StatRange.week, now);
      final stats = PeriodStats.compute(
        period: period,
        entriesIn: (from, to) => [
          Entry(id: 1, activityId: 1, ts: DateTime(2026, 3, 22, 13, 30).millisecondsSinceEpoch),
        ].where((e) => e.time.isAfter(from.subtract(const Duration(milliseconds: 1))) && e.time.isBefore(to)),
        unitOf: (id) => null,
        now: now,
      );
      // 13:30 kaydı önceki haftanın 14:00'üne kadar olan karşılaştırmasında bulunmalı
      expect(stats.previous.count, 1);
    });

    test('PeriodStats ay karşılaştırma anı ABD sonbahar geçişinde 1 saat kaymaz', () {
      final now = DateTime(2026, 11, 5, 14, 0); // Kasım 14:00 (1 Kasım DST geçişi sonrası)
      final period = StatPeriod.containing(StatRange.month, now);
      final stats = PeriodStats.compute(
        period: period,
        entriesIn: (from, to) => [
          Entry(id: 1, activityId: 1, ts: DateTime(2026, 10, 5, 13, 30).millisecondsSinceEpoch),
          Entry(id: 2, activityId: 1, ts: DateTime(2026, 10, 5, 14, 30).millisecondsSinceEpoch),
        ].where((e) => e.time.isAfter(from.subtract(const Duration(milliseconds: 1))) && e.time.isBefore(to)),
        unitOf: (id) => null,
        now: now,
      );
      // Karşılaştırma anı tam 5 Ekim 14:00'tür: 13:30 sayılır, 14:30 sayılmaz
      expect(stats.previous.count, 1);
    });
  });
}
