import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:takip/data/models.dart';
import 'package:takip/data/store.dart';
import 'package:takip/logic/activity_format_analysis.dart';
import 'package:takip/logic/todo_parser.dart';
import 'package:takip/services/nl_parser.dart';

import 'support/real_db.dart';

void main() {
  useRealDatabase();

  setUpAll(() async {
    await initializeDateFormatting('tr_TR');
    await initializeDateFormatting('en_US');
  });

  group('TodoInputParser Tests', () {
    test('parses date words and detects weekday: if weekday is today, selects today', () {
      final now = DateTime(2026, 10, 27, 14, 0); // Salı (Tuesday = 2)

      // Salı bugünse bugün olmalı
      final rToday = TodoInputParser.parse('30 dk koşu salı', activities: [], measures: [], now: now);
      expect(rToday.date, DateTime(2026, 10, 27));
      expect(rToday.cleanTitle, '30 dk koşu');

      // Çarşamba (yarın)
      final rTomorrow = TodoInputParser.parse('kitap oku çarşamba', activities: [], measures: [], now: now);
      expect(rTomorrow.date, DateTime(2026, 10, 28));
      expect(rTomorrow.cleanTitle, 'kitap oku');

      // Pazartesi (gelecek hafta)
      final rNextMon = TodoInputParser.parse('fatura öde pazartesi', activities: [], measures: [], now: now);
      expect(rNextMon.date, DateTime(2026, 11, 2)); // 6 gün sonra
      expect(rNextMon.cleanTitle, 'fatura öde');

      // yarın, öbür gün, haftaya, hafta sonu
      final rYarin = TodoInputParser.parse('ilaç al yarın', activities: [], measures: [], now: now);
      expect(rYarin.date, DateTime(2026, 10, 28));

      final rObur = TodoInputParser.parse('öbür gün raporu bitir', activities: [], measures: [], now: now);
      expect(rObur.date, DateTime(2026, 10, 29));
      expect(rObur.cleanTitle, 'raporu bitir');

      final rHaftaya = TodoInputParser.parse('haftaya check-up', activities: [], measures: [], now: now);
      expect(rHaftaya.date, DateTime(2026, 11, 3));

      final rHaftasonu = TodoInputParser.parse('bisiklet sür hafta sonu', activities: [], measures: [], now: now);
      expect(rHaftasonu.date, DateTime(2026, 10, 31)); // Önümüzdeki Cumartesi

      // İngilizce kelimeler
      final rEng = TodoInputParser.parse('call doctor tomorrow', activities: [], measures: [], now: now);
      expect(rEng.date, DateTime(2026, 10, 28));
      expect(rEng.cleanTitle, 'call doctor');
    });

    test('extracts activity and target amount when matching natural language', () {
      final act = Activity(id: 1, name: 'Yürüyüş', emoji: '🚶', createdAt: 0);
      final m = Measure(id: 1, name: 'Dakika', unitId: 'dk', amount: 1, sort: 0);

      final r = TodoInputParser.parse('30 dk yürü yarın', activities: [act], measures: [m]);
      expect(r.date, isNotNull);
      expect(r.suggestedActivity?.id, 1);
      expect(r.suggestedAmount, 30.0);
    });
  });

  group('Todo Progress & Manual State Tests', () {
    test('linked todo progress counts entries created AFTER todo was created', () async {
      final s = AppStore();
      await s.load();

      final act = await s.addActivity('Koşu', emoji: '🏃');
      final past = DateTime(2026, 10, 25, 10, 0);
      final todoCreated = DateTime(2026, 10, 26, 12, 0);
      final future = DateTime(2026, 10, 27, 9, 0);

      // Oluşturulmadan önceki kayıt
      await s.addEntry(act.id, qty: 15, at: past);

      // Yapılacak oluşturuluyor: 30 dk koş
      final todo = await s.createTodo(
        Todo(
          id: 0,
          title: '30 dk koş',
          createdAt: todoCreated.millisecondsSinceEpoch,
          targetAmount: 30,
        ),
        activityIds: [act.id],
      );

      var p = s.todoProgress(todo);
      expect(p.isCompleted, isFalse);
      expect(p.currentAmount, 0.0); // Geçmişteki 15 dk sayılmadı

      // Oluşturulduktan sonra 20 dk kayıt
      await s.addEntry(act.id, qty: 20, at: future);
      p = s.todoProgress(todo);
      expect(p.isCompleted, isFalse);
      expect(p.currentAmount, 20.0);

      // 10 dk daha kaydedilince toplam 30 dk olur ve tamamlanır
      final e3 = (await s.addEntry(act.id, qty: 10, at: future.add(const Duration(hours: 1)))).entry;
      p = s.todoProgress(todo);
      expect(p.isCompleted, isTrue);
      expect(p.currentAmount, 30.0);

      // Kayıt silinince ilerleme geri düşer ve tamamlanma kalkar
      await s.deleteEntry(e3);
      p = s.todoProgress(todo);
      expect(p.isCompleted, isFalse);
      expect(p.currentAmount, 20.0);
    });

    test('multiple linked activities sum together properly', () async {
      final s = AppStore();
      await s.load();

      final a1 = await s.addActivity('Yürüyüş', emoji: '🚶');
      final a2 = await s.addActivity('Koşu', emoji: '🏃');
      final now = DateTime.now();

      final todo = await s.createTodo(
        Todo(
          id: 0,
          title: '45 dk kardiyo',
          createdAt: now.subtract(const Duration(hours: 2)).millisecondsSinceEpoch,
          targetAmount: 45,
        ),
        activityIds: [a1.id, a2.id],
      );

      await s.addEntry(a1.id, qty: 20, at: now.subtract(const Duration(hours: 1)));
      await s.addEntry(a2.id, qty: 25, at: now);

      final p = s.todoProgress(todo);
      expect(p.currentAmount, 45.0);
      expect(p.isCompleted, isTrue);
    });

    test('manual decision is preserved and cleared when derived matches manual state', () async {
      final s = AppStore();
      await s.load();

      final act = await s.addActivity('Kitap Okuma', emoji: '📚');
      final now = DateTime.now();

      final todo = await s.createTodo(
        Todo(
          id: 0,
          title: '50 sayfa oku',
          createdAt: now.subtract(const Duration(hours: 1)).millisecondsSinceEpoch,
          targetAmount: 50,
        ),
        activityIds: [act.id],
      );

      // İlerleme 0 iken kullanıcı elle tamamlıyor
      await s.toggleTodo(todo.id, completed: true);
      expect(todo.manualState, 'done');
      expect(s.todoProgress(todo).isCompleted, isTrue);

      // Kullanıcı hedefe ulaşan 50 sayfalık kayıt giriyor
      await s.addEntry(act.id, qty: 50, at: now);

      // Türetilen durum true olduğu için manualState null'a temizlenmeli
      expect(todo.manualState, isNull);
      expect(s.todoProgress(todo).isCompleted, isTrue);

      // Şimdi hedef doluyken kullanıcı elle "açık" (uncomplete) yapıyor
      await s.toggleTodo(todo.id, completed: false);
      expect(todo.manualState, 'open');
      expect(s.todoProgress(todo).isCompleted, isFalse);
    });

    test('unlinked todo toggles without creating entries or stats', () async {
      final s = AppStore();
      await s.load();

      final countBefore = s.entries.length;
      final todo = await s.createTodo(
        Todo(
          id: 0,
          title: 'Pasaport yenile',
          createdAt: DateTime.now().millisecondsSinceEpoch,
        ),
      );

      expect(s.todoProgress(todo).isCompleted, isFalse);
      await s.toggleTodo(todo.id, completed: true);

      expect(s.todoProgress(todo).isCompleted, isTrue);
      expect(todo.doneAt, isNotNull);
      expect(s.entries.length, countBefore); // Hiçbir kayıt oluşmadı
    });
  });

  group('Todo CRUD, Postpone & Grouping Tests', () {
    test('postpone sets next due date to max(due, today) + 1 day', () async {
      final s = AppStore();
      await s.load();

      final yesterdayStr = DateFormat('yyyy-MM-dd').format(DateTime.now().subtract(const Duration(days: 1)));
      final tomorrowStr = DateFormat('yyyy-MM-dd').format(DateTime.now().add(const Duration(days: 1)));

      // Gecikmiş olan (dün) ertelenince yarın olmalı (max(dün, bugün) + 1 = bugün + 1 = yarın)
      final t1 = await s.createTodo(
        Todo(id: 0, title: 'Gecikmiş iş', createdAt: 0, dueDate: yesterdayStr),
      );
      await s.postponeTodo(t1.id);
      expect(t1.dueDate, tomorrowStr);

      // Tarihsiz olan ertelenince yarın olmalı
      final t2 = await s.createTodo(
        Todo(id: 0, title: 'Tarihsiz iş', createdAt: 0),
      );
      await s.postponeTodo(t2.id);
      expect(t2.dueDate, tomorrowStr);
    });

    test('todos grouping and sorting correctly categorizes overdue, today, upcoming, dateless and completed', () async {
      final s = AppStore();
      await s.load();

      final now = DateTime(2026, 10, 27, 10, 0);
      final todayStr = DateFormat('yyyy-MM-dd').format(now);
      final yesterdayStr = DateFormat('yyyy-MM-dd').format(now.subtract(const Duration(days: 1)));
      final threeDaysAgo = DateFormat('yyyy-MM-dd').format(now.subtract(const Duration(days: 3)));
      final tomorrowStr = DateFormat('yyyy-MM-dd').format(now.add(const Duration(days: 1)));
      final nextWeekStr = DateFormat('yyyy-MM-dd').format(now.add(const Duration(days: 7)));

      final tOverdue1 = await s.createTodo(Todo(id: 0, title: 'Geçmiş 1', createdAt: 10, dueDate: threeDaysAgo));
      final tOverdue2 = await s.createTodo(Todo(id: 0, title: 'Geçmiş 2', createdAt: 20, dueDate: yesterdayStr));
      final tToday1 = await s.createTodo(Todo(id: 0, title: 'Bugün 1', createdAt: 30, dueDate: todayStr));
      final tTomorrow = await s.createTodo(Todo(id: 0, title: 'Yarın', createdAt: 40, dueDate: tomorrowStr));
      final tNextWeek = await s.createTodo(Todo(id: 0, title: 'Gelecek Hafta', createdAt: 50, dueDate: nextWeekStr));
      final tDateless = await s.createTodo(Todo(id: 0, title: 'Tarihsiz', createdAt: 60));
      final tCompleted = await s.createTodo(Todo(id: 0, title: 'Tamamlandı', createdAt: 70, doneAt: now.millisecondsSinceEpoch));

      // Overdue due_date artan sıralanmalı
      final overdueList = s.todos.where((t) => s.todoProgress(t).isCompleted == false && t.dueDate != null && t.dueDate!.compareTo(todayStr) < 0).toList()
        ..sort((a, b) => (a.dueDate ?? '').compareTo(b.dueDate ?? ''));
      expect(overdueList.map((t) => t.id).toList(), [tOverdue1.id, tOverdue2.id]);

      // Today
      final todayList = s.todos.where((t) => s.todoProgress(t).isCompleted == false && t.dueDate == todayStr).toList();
      expect(todayList.map((t) => t.id).toList(), [tToday1.id]);

      // Upcoming due_date artan sıralanmalı
      final upcomingList = s.todos.where((t) => s.todoProgress(t).isCompleted == false && t.dueDate != null && t.dueDate!.compareTo(todayStr) > 0).toList()
        ..sort((a, b) => (a.dueDate ?? '').compareTo(b.dueDate ?? ''));
      expect(upcomingList.map((t) => t.id).toList(), [tTomorrow.id, tNextWeek.id]);

      // Dateless
      final datelessList = s.todos.where((t) => s.todoProgress(t).isCompleted == false && (t.dueDate == null || t.dueDate!.isEmpty)).toList();
      expect(datelessList.map((t) => t.id).toList(), [tDateless.id]);

      // Completed listesi doneAt azalan sıralanmalı
      final completedList = s.todos.where((t) => s.todoProgress(t).isCompleted).toList();
      expect(completedList.map((t) => t.id).toList(), [tCompleted.id]);
    });

    test('delete and restore restores links properly', () async {
      final s = AppStore();
      await s.load();

      final act = await s.addActivity('Su', emoji: '💧');
      final todo = await s.createTodo(
        Todo(id: 0, title: '2L su iç', createdAt: 0, targetAmount: 2),
        activityIds: [act.id],
      );

      final deleted = await s.deleteTodo(todo.id);
      expect(deleted, isNotNull);
      expect(s.todos.any((t) => t.id == todo.id), isFalse);

      await s.restoreTodo(deleted!.$1, deleted.$2);
      expect(s.todos.any((t) => t.id == todo.id), isTrue);
      final restored = s.todos.firstWhere((t) => t.id == todo.id);
      expect(restored.linkedActivityIds, [act.id]);
    });
  });

  group('Todo Data Integrity Tests', () {
    test('activity deletion removes links and preserves completed state for orphaned todo', () async {
      final s = AppStore();
      await s.load();

      final act = await s.addActivity('Meditasyon', emoji: '🧘');
      final now = DateTime.now();

      final todo = await s.createTodo(
        Todo(
          id: 0,
          title: 'Meditasyon yap',
          createdAt: now.subtract(const Duration(minutes: 30)).millisecondsSinceEpoch,
        ),
        activityIds: [act.id],
      );

      // Kayıt ekleyip tamamlanmasını sağlayalım
      await s.addEntry(act.id, qty: 1, at: now);
      expect(s.todoProgress(todo).isCompleted, isTrue);

      // Aktiviteyi sil
      await s.deleteActivity(act.id);

      // Yapılacağın bağlantısı kalkmalı ama o anki tamamlanmış durumu korunmalı (doneAt dolmalı)
      expect(todo.linkedActivityIds, isEmpty);
      expect(todo.doneAt, isNotNull);
      expect(s.todoProgress(todo).isCompleted, isTrue);
    });

    test('activity merge carries links and deduplicates', () async {
      final s = AppStore();
      await s.load();

      final a1 = await s.addActivity('Yuruyus');
      final a2 = await s.addActivity('Yürüyüş');

      final todo = await s.createTodo(
        Todo(id: 0, title: 'Yürü', createdAt: 0),
        activityIds: [a1.id, a2.id],
      );

      // a1'i a2 ile birleştir
      await s.mergeActivity(a1.id, a2.id);

      final t = s.todos.firstWhere((x) => x.id == todo.id);
      // Çiftler tekilleşmeli ve yalnızca a2 kalmalı
      expect(t.linkedActivityIds, [a2.id]);
    });

    test('backup import without todo tables restores seamlessly', () async {
      final s = AppStore();
      await s.load();

      // Eski sürüm bir yedek (todos veya todo_links anahtarı içermiyor)
      final oldBackup = {
        'app': 'seyir',
        'version': 3,
        'exportedAt': DateTime.now().toIso8601String(),
        'units': [],
        'measures': [],
        'activities': [
          {'id': 1, 'name': 'Eski Aktivite', 'created_at': 100}
        ],
        'entries': [],
        'goals': [],
        'goal_links': [],
        'quick_items': [],
        'settings': [],
        'active_timers': [],
        'roadmaps': [],
        'roadmap_steps': [],
        'activity_properties': [],
      };

      await s.importJson(jsonEncode(oldBackup));
      expect(s.activities.containsKey(1), isTrue);
      expect(s.todos, isEmpty);
    });

    test('todoWidgetPayload formats items in order: overdue -> today -> upcoming -> dateless', () async {
      final s = AppStore();
      await s.load();

      final now = DateTime(2026, 10, 27, 10, 0);
      final yesterday = '2026-10-26';
      final today = '2026-10-27';
      final tomorrow = '2026-10-28';

      await s.createTodo(Todo(id: 1, title: 'Tarihsiz', createdAt: 100));
      await s.createTodo(Todo(id: 2, title: 'Yarınki', createdAt: 200, dueDate: tomorrow));
      await s.createTodo(Todo(id: 3, title: 'Gecikmiş', createdAt: 300, dueDate: yesterday));
      await s.createTodo(Todo(id: 4, title: 'Bugünkü', createdAt: 400, dueDate: today));

      final payload = s.todoWidgetPayload(at: now);
      expect(payload['count'], 4);
      final items = payload['items'] as List;
      expect(items[0]['t'], 'Gecikmiş');
      expect(items[1]['t'], 'Bugünkü');
      expect(items[2]['t'], 'Yarınki');
      expect(items[3]['t'], 'Tarihsiz');
    });

    test('süre bağlı yapılacakta kalan 12 dk ile "kaydet ve tamamla" tam 12 dakikalık kayıt açar (720 değil)', () async {
      final s = AppStore();
      await s.load();

      final actWalk = await s.addActivity('Yürüyüş', emoji: '🚶');
      final todoCreated = DateTime(2026, 10, 27, 8, 0);

      final todo = await s.createTodo(
        Todo(
          id: 0,
          title: '30 dk tempolu yürüyüş yap',
          createdAt: todoCreated.millisecondsSinceEpoch,
          targetAmount: 30, // 30 dk
        ),
        activityIds: [actWalk.id],
      );

      // Daha önce 18 dakikalık yürüyüş yapılmış
      final e1 = await s.addEntry(actWalk.id, value: 18, unitId: 'dk', at: DateTime(2026, 10, 27, 9, 0));
      expect(e1.entry.duration?.inMinutes, 18);

      var p = s.todoProgress(todo);
      expect(p.currentAmount, 18.0);
      expect(p.unitSymbol, 'dk');
      expect(p.isCompleted, isFalse);

      final remaining = (todo.targetAmount! - p.currentAmount).clamp(0.0, 9999.0);
      expect(remaining, 12.0);

      // Tamamlama sheet'indeki gibi kalan miktar kaydediliyor:
      final format = s.activityFormat(actWalk.id);
      expect(format, ActivityFormat.duration);

      final e2 = await s.addEntry(actWalk.id, value: remaining, unitId: 'dk', at: DateTime(2026, 10, 27, 10, 0));
      // Kayıt 720 dakika (12 saat) DEĞİL, tam 12 dakika olmalı!
      expect(e2.entry.duration?.inMinutes, 12);
      expect(e2.entry.value, 12.0);
      expect(e2.entry.unitId, 'dk');

      p = s.todoProgress(todo);
      expect(p.currentAmount, 30.0);
      expect(p.isCompleted, isTrue);
    });

    test('Su (L) bağlı yapılacakta doğru miktar kaydedilir ve etiketler "L" gösterir', () async {
      final s = AppStore();
      await s.load();

      final actWater = await s.addActivity('Su', emoji: '💧');
      final mGlass = await s.addMeasure('Su bardağı', 'l', 0.2);

      final todoCreated = DateTime(2026, 10, 27, 8, 0);
      final todo = await s.createTodo(
        Todo(
          id: 0,
          title: '2 litre su iç',
          createdAt: todoCreated.millisecondsSinceEpoch,
          targetAmount: 2.0, // 2 L
        ),
        activityIds: [actWater.id],
      );

      // 4 su bardağı içilmiş (0.8 L)
      await s.addEntry(actWater.id, measureId: mGlass.id, qty: 4, at: DateTime(2026, 10, 27, 9, 0));

      var p = s.todoProgress(todo);
      expect(p.currentAmount, 0.8);
      // Etiket "Su bardağı" değil, "L" olmalı!
      expect(p.unitSymbol, 'L');
      expect(p.isCompleted, isFalse);

      final remaining = (todo.targetAmount! - p.currentAmount).clamp(0.0, 9999.0);
      expect(remaining, 1.2);

      // Kalan 1.2 L kaydediliyor
      await s.addEntry(actWater.id, value: remaining, unitId: 'l', at: DateTime(2026, 10, 27, 10, 0));

      p = s.todoProgress(todo);
      expect(p.currentAmount, 2.0);
      expect(p.unitSymbol, 'L');
      expect(p.isCompleted, isTrue);
    });

    test('etiketler "dk" ve "L" gösterir', () async {
      final s = AppStore();
      await s.load();

      final actWalk = await s.addActivity('Yürüyüş', emoji: '🚶');
      final actWater = await s.addActivity('Su', emoji: '💧');
      await s.addMeasure('Su bardağı', 'l', 0.2);
      await s.addMeasure('Dakika', 'dk', 1.0);

      final todoWalk = await s.createTodo(
        Todo(id: 0, title: 'Yürüyüş', createdAt: 0, targetAmount: 30),
        activityIds: [actWalk.id],
      );
      final todoWater = await s.createTodo(
        Todo(id: 0, title: 'Su', createdAt: 0, targetAmount: 2.0),
        activityIds: [actWater.id],
      );

      expect(s.todoProgress(todoWalk).unitSymbol, 'dk');
      expect(s.todoProgress(todoWater).unitSymbol, 'L');
    });

    test('hızlı ekleme hedefi dakika olarak saklanır ve "30 dk" gösterilir', () {
      final act = Activity(id: 1, name: 'Yürüyüş', emoji: '🚶', createdAt: 0);
      final mMin = Measure(id: 1, name: 'Dakika', unitId: 'dk', amount: 1, sort: 0);
      final mHour = Measure(id: 2, name: 'Saat', unitId: 'sa', amount: 1, sort: 1);

      // "30 dk yürü" -> 30 dakika ve 'dk'
      final r1 = TodoInputParser.parse('30 dk yürü yarın', activities: [act], measures: [mMin, mHour]);
      expect(r1.suggestedActivity?.name, 'Yürüyüş');
      expect(r1.suggestedAmount, 30.0);
      expect(r1.suggestedUnit, 'dk');

      // "1 saat yürü" -> 60 dakika olarak saklanır
      final r2 = TodoInputParser.parse('1 saat yürü yarın', activities: [act], measures: [mMin, mHour]);
      expect(r2.suggestedActivity?.name, 'Yürüyüş');
      expect(r2.suggestedAmount, 60.0);
      expect(r2.suggestedUnit, 'dk');
    });

    test('Birim Genelliği: Mesafe (km) bağlı yapılacak, dönüşüm ve açılan kayıt', () async {
      final s = AppStore();
      await s.load();

      final actRun = await s.addActivity('Koşu Parkuru', emoji: '🏃');
      await s.addMeasure('1 Kilometre', 'km', 1.0);

      final todo = await s.createTodo(
        Todo(id: 0, title: '5 km koş', createdAt: DateTime(2026, 10, 27, 8, 0).millisecondsSinceEpoch, targetAmount: 5.0),
        activityIds: [actRun.id],
      );

      // 3000 metre koşulmuş (3 km)
      await s.addEntry(actRun.id, value: 3000, unitId: 'm', at: DateTime(2026, 10, 27, 9, 0));

      var p = s.todoProgress(todo);
      expect(p.currentAmount, 3.0);
      expect(p.unitSymbol, 'km');
      expect(p.remainingAmount, 2.0);
      expect(p.isCompleted, isFalse);

      // Kalan 2 km ile tamamlama kaydı açılır
      final res = await s.completeTodoWithEntry(todo);
      expect(res.entry.value, 2.0);
      expect(res.entry.unitId, 'km');

      p = s.todoProgress(todo);
      expect(p.currentAmount, 5.0);
      expect(p.isCompleted, isTrue);
    });

    test('Birim Genelliği: Ağırlık/Kütle (kg) bağlı yapılacak, dönüşüm ve açılan kayıt', () async {
      final s = AppStore();
      await s.load();

      final actWeight = await s.addActivity('Halter', emoji: '🏋️');
      await s.addMeasure('1 Kilogram', 'kg', 1.0);

      final todo = await s.createTodo(
        Todo(id: 0, title: '2 kg kaldır', createdAt: DateTime(2026, 10, 27, 8, 0).millisecondsSinceEpoch, targetAmount: 2.0),
        activityIds: [actWeight.id],
      );

      // 500 gram kaldırılmış (0.5 kg)
      await s.addEntry(actWeight.id, value: 500, unitId: 'g', at: DateTime(2026, 10, 27, 9, 0));

      var p = s.todoProgress(todo);
      expect(p.currentAmount, 0.5);
      expect(p.unitSymbol, 'kg');
      expect(p.remainingAmount, 1.5);
      expect(p.isCompleted, isFalse);

      // Kalan 1.5 kg ile tamamlama kaydı açılır
      final res = await s.completeTodoWithEntry(todo);
      expect(res.entry.value, 1.5);
      expect(res.entry.unitId, 'kg');

      p = s.todoProgress(todo);
      expect(p.currentAmount, 2.0);
      expect(p.isCompleted, isTrue);
    });

    test('Birim Genelliği: Sayı/Adet bağlı yapılacak ve açılan kayıt', () async {
      final s = AppStore();
      await s.load();

      final actPushups = await s.addActivity('Şınav', emoji: '💪');
      final todo = await s.createTodo(
        Todo(id: 0, title: '50 şınav çek', createdAt: DateTime(2026, 10, 27, 8, 0).millisecondsSinceEpoch, targetAmount: 50.0),
        activityIds: [actPushups.id],
      );

      // 20 şınav çekilmiş
      await s.addEntry(actPushups.id, qty: 20, value: 20, unitId: 'adet', at: DateTime(2026, 10, 27, 9, 0));

      var p = s.todoProgress(todo);
      expect(p.currentAmount, 20.0);
      expect(p.unitSymbol, 'adet');
      expect(p.remainingAmount, 30.0);
      expect(p.isCompleted, isFalse);

      // Kalan 30 adet ile tamamlama kaydı açılır
      final res = await s.completeTodoWithEntry(todo);
      expect(res.entry.qty, 30.0);
      expect(res.entry.value, 30.0);
      expect(res.entry.unitId, 'adet');

      p = s.todoProgress(todo);
      expect(p.currentAmount, 50.0);
      expect(p.isCompleted, isTrue);
    });

    test('Birim Genelliği: Olay bağlı yapılacak ve açılan kayıt', () async {
      final s = AppStore();
      await s.load();

      final actDoc = await s.addActivity('Doktora Git', emoji: '🏥');
      final todo = await s.createTodo(
        Todo(id: 0, title: 'Doktora git', createdAt: DateTime(2026, 10, 27, 8, 0).millisecondsSinceEpoch),
        activityIds: [actDoc.id],
      );

      var p = s.todoProgress(todo);
      expect(p.targetAmount, isNull);
      expect(p.unitSymbol, isNull);
      expect(p.isCompleted, isFalse);

      // Olay tamamlama kaydı açılır (qty: 1.0)
      final res = await s.completeTodoWithEntry(todo);
      expect(res.entry.qty, 1.0);

      p = s.todoProgress(todo);
      expect(p.isCompleted, isTrue);
    });

    test('Birim Genelliği: Özel birimli miktar (sayfa) bağlı yapılacak ve açılan kayıt', () async {
      final s = AppStore();
      await s.load();

      final pageUnit = await s.addUnit('Sayfa', 'sayfa');
      final actRead = await s.addActivity('Kitap Okuma', emoji: '📖');
      await s.addMeasure('10 Sayfa', pageUnit.id, 10.0);

      final todo = await s.createTodo(
        Todo(id: 0, title: '30 sayfa oku', createdAt: DateTime(2026, 10, 27, 8, 0).millisecondsSinceEpoch, targetAmount: 30.0),
        activityIds: [actRead.id],
      );

      // 10 sayfa okunmuş
      await s.addEntry(actRead.id, value: 10, unitId: pageUnit.id, at: DateTime(2026, 10, 27, 9, 0));

      var p = s.todoProgress(todo);
      expect(p.currentAmount, 10.0);
      expect(p.unitSymbol, 'sayfa');
      expect(p.remainingAmount, 20.0);
      expect(p.isCompleted, isFalse);

      // Kalan 20 sayfa ile tamamlama kaydı açılır
      final res = await s.completeTodoWithEntry(todo);
      expect(res.entry.value, 20.0);
      expect(res.entry.unitId, pageUnit.id);
      expect(s.unit(res.entry.unitId!).symbol, 'sayfa');

      p = s.todoProgress(todo);
      expect(p.currentAmount, 30.0);
      expect(p.isCompleted, isTrue);
    });

    test('Widget Payload: isTr dil bayrağını içerir ve etiketleri doğru biçimlendirir', () async {
      final s = AppStore();
      await s.load();

      final act = await s.addActivity('Yürüyüş', emoji: '🚶');
      await s.createTodo(
        Todo(id: 0, title: 'Yürüyüş yap', createdAt: 0, targetAmount: 30),
        activityIds: [act.id],
      );

      final payload = s.todoWidgetPayload();
      expect(payload['isTr'], isTrue);
      final items = payload['items'] as List<Map<String, Object?>>;
      expect(items.isNotEmpty, isTrue);
      expect(items.first['sub'], '0/30 dk');
    });

    test('H5: Hedefe ulaşma karşılaştırması aynı toleransla tek bir yardımcıda toplanır ve _syncTodos ile todoProgress uyumludur', () async {
      final s = AppStore();
      await s.load();
      final act = await s.addActivity('Su');
      final todo = await s.createTodo(
        Todo(id: 0, title: '0.1 L su', createdAt: 0, targetAmount: 0.1),
        activityIds: [act.id],
      );
      // 1.0 - 0.9 = 0.09999999999999998 (< 0.1)
      final val = 1.0 - 0.9;
      await s.addEntry(act.id, value: val, unitId: 'l');

      final prog = s.todoProgress(todo);
      expect(prog.isCompleted, isTrue);
      final dbTodo = s.todos.firstWhere((t) => t.id == todo.id);
      expect(dbTodo.doneAt, isNotNull, reason: '_syncTodos must agree with todoProgress via isTargetReached');
    });

    test('H1: ml/L alt birim ölçeklemesi, hedef, ilerleme ve açılan kayıt', () async {
      final s = AppStore();
      await s.load();
      final act = await s.addActivity('Su');
      final todo = await s.createTodo(
        Todo(id: 0, title: '500 ml su iç', createdAt: 0, targetAmount: 500.0, targetUnit: 'ml'),
        activityIds: [act.id],
      );

      // Başlangıç durumu
      var p = s.todoProgress(todo);
      expect(p.targetAmount, 500.0);
      expect(p.unitSymbol, 'ml');
      expect(p.currentAmount, 0.0);
      expect(p.remainingAmount, 500.0);
      expect(p.isCompleted, isFalse);

      // 0.2 L su içildiğinde (200 ml katkı yapmalı)
      await s.addEntry(act.id, value: 0.2, unitId: 'l');
      p = s.todoProgress(todo);
      expect(p.currentAmount, closeTo(200.0, 1e-9));
      expect(p.remainingAmount, closeTo(300.0, 1e-9));
      expect(p.isCompleted, isFalse);

      // Tamamlama kaydı açıldığında 300 ml kayıt açılmalı (500 L veya 300 L DEĞİL!)
      final res = await s.completeTodoWithEntry(todo);
      expect(res.entry.unitId, 'ml');
      expect(res.entry.value, closeTo(300.0, 1e-9));

      p = s.todoProgress(todo);
      expect(p.currentAmount, closeTo(500.0, 1e-9));
      expect(p.isCompleted, isTrue);
    });

    test('H1: mg/g alt birim ölçeklemesi, hedef, ilerleme ve açılan kayıt', () async {
      final s = AppStore();
      await s.load();
      final act = await s.addActivity('Aspirin');
      final todo = await s.createTodo(
        Todo(id: 0, title: '500 mg aspirin al', createdAt: 0, targetAmount: 500.0, targetUnit: 'mg'),
        activityIds: [act.id],
      );

      var p = s.todoProgress(todo);
      expect(p.unitSymbol, 'mg');
      expect(p.targetAmount, 500.0);

      // 0.2 g alındığında (200 mg katkı yapmalı)
      await s.addEntry(act.id, value: 0.2, unitId: 'g');
      p = s.todoProgress(todo);
      expect(p.currentAmount, closeTo(200.0, 1e-9));

      final res = await s.completeTodoWithEntry(todo);
      expect(res.entry.unitId, 'mg');
      expect(res.entry.value, closeTo(300.0, 1e-9));

      p = s.todoProgress(todo);
      expect(p.isCompleted, isTrue);
    });

    test('H1: sn/dk/sa alt birim ölçeklemesi, hedef, ilerleme ve açılan kayıt', () async {
      final s = AppStore();
      await s.load();
      final actPlank = await s.addActivity('Plank');
      final todoPlank = await s.createTodo(
        Todo(id: 0, title: '90 sn plank', createdAt: 0, targetAmount: 90.0, targetUnit: 'sn'),
        activityIds: [actPlank.id],
      );

      var p = s.todoProgress(todoPlank);
      expect(p.unitSymbol, 'sn');
      expect(p.targetAmount, 90.0);

      // 30 sn yapıldı
      await s.addEntry(actPlank.id, value: 30, unitId: 'sn');
      p = s.todoProgress(todoPlank);
      expect(p.currentAmount, closeTo(30.0, 1e-9));

      // 0.5 dk (30 sn) daha yapıldı
      await s.addEntry(actPlank.id, value: 0.5, unitId: 'dk');
      p = s.todoProgress(todoPlank);
      expect(p.currentAmount, closeTo(60.0, 1e-9));

      final res = await s.completeTodoWithEntry(todoPlank);
      expect(res.entry.unitId, 'sn');
      expect(res.entry.value, closeTo(30.0, 1e-9));

      p = s.todoProgress(todoPlank);
      expect(p.isCompleted, isTrue);

      // 2 sa ders testi
      final actDers = await s.addActivity('Ders');
      final todoDers = await s.createTodo(
        Todo(id: 0, title: '2 sa ders çalış', createdAt: 0, targetAmount: 2.0, targetUnit: 'sa'),
        activityIds: [actDers.id],
      );
      var pDers = s.todoProgress(todoDers);
      expect(pDers.unitSymbol, 'sa');
      expect(pDers.targetAmount, 2.0);

      // 60 dk ders girildiğinde 1 sa saymalı
      await s.addEntry(actDers.id, value: 60, unitId: 'dk');
      pDers = s.todoProgress(todoDers);
      expect(pDers.currentAmount, closeTo(1.0, 1e-9));
    });

    test('H1: m/km ve g/kg alt birim ölçeklemesi, hedef, ilerleme ve açılan kayıt', () async {
      final s = AppStore();
      await s.load();
      final actKos = await s.addActivity('Koşu');
      final todoKos = await s.createTodo(
        Todo(id: 0, title: '500 m koşu', createdAt: 0, targetAmount: 500.0, targetUnit: 'm'),
        activityIds: [actKos.id],
      );
      var pKos = s.todoProgress(todoKos);
      expect(pKos.unitSymbol, 'm');

      // 0.2 km koşulduğunda (200 m saymalı)
      await s.addEntry(actKos.id, value: 0.2, unitId: 'km');
      pKos = s.todoProgress(todoKos);
      expect(pKos.currentAmount, closeTo(200.0, 1e-9));

      final resKos = await s.completeTodoWithEntry(todoKos);
      expect(resKos.entry.unitId, 'm');
      expect(resKos.entry.value, closeTo(300.0, 1e-9));

      // 500 g dambıl
      final actAgirlik = await s.addActivity('Ağırlık');
      final todoAgirlik = await s.createTodo(
        Todo(id: 0, title: '500 g kaldır', createdAt: 0, targetAmount: 500.0, targetUnit: 'g'),
        activityIds: [actAgirlik.id],
      );
      var pAg = s.todoProgress(todoAgirlik);
      expect(pAg.unitSymbol, 'g');

      // 0.5 kg girildiğinde (500 g tamamlamalı)
      await s.addEntry(actAgirlik.id, value: 0.5, unitId: 'kg');
      pAg = s.todoProgress(todoAgirlik);
      expect(pAg.currentAmount, closeTo(500.0, 1e-9));
      expect(pAg.isCompleted, isTrue);
    });

    test('H1: Başlık düzenlenince hedefin birimi ve anlamı değişmez', () async {
      final s = AppStore();
      await s.load();
      final act = await s.addActivity('Su');
      final todo = await s.createTodo(
        Todo(id: 0, title: '500 ml su iç', createdAt: 0, targetAmount: 500.0, targetUnit: 'ml'),
        activityIds: [act.id],
      );

      expect(s.todoProgress(todo).unitSymbol, 'ml');

      // Başlıkta birim geçmeyen bir metinle güncelle
      final updated = todo.copyWith(title: 'Günlük hidrasyon hedefini tamamla');
      await s.updateTodo(updated);

      final reloaded = s.todos.firstWhere((t) => t.id == todo.id);
      expect(reloaded.targetUnit, 'ml');
      expect(s.todoProgress(reloaded).unitSymbol, 'ml');
      expect(s.todoProgress(reloaded).targetAmount, 500.0);
    });

    test('H1: target_unit NULL olan eski satırların geçişi (migration) doğru çalışır', () async {
      final s = AppStore();
      await s.load();
      final act = await s.addActivity('Su');

      // Veritabanına doğrudan target_unit NULL olan eski satırlar ekle
      final d = await s.db;
      final id1 = await d.insert('todos', {
        'title': '500 ml su iç',
        'created_at': 0,
        'target_amount': 500.0,
        'target_unit': null,
        'sort_order': 0,
      });
      await d.insert('todo_links', {'todo_id': id1, 'activity_id': act.id});

      final id2 = await d.insert('todos', {
        'title': 'Günde su iç',
        'created_at': 0,
        'target_amount': 2.0,
        'target_unit': null,
        'sort_order': 0,
      });
      await d.insert('todo_links', {'todo_id': id2, 'activity_id': act.id});

      // Mağaza veritabanından yeniden okur
      await s.load();

      final todo1 = s.todos.firstWhere((t) => t.id == id1);
      expect(todo1.targetUnit, 'ml'); // Başlıktan türetilmiş olmalı
      expect(s.todoProgress(todo1).unitSymbol, 'ml');

      final todo2 = s.todos.firstWhere((t) => t.id == id2);
      expect(todo2.targetUnit, 'l'); // Aktivitenin temel biriminden türetilmiş olmalı
      expect(s.todoProgress(todo2).unitSymbol, 'L');
    });

    test('H1: "Ne yaptın?" kutusu ile "Kaydet ve tamamla" eşdeğerliği', () async {
      final s = AppStore();
      await s.load();
      final act = await s.addActivity('Su');

      // 1. "500 ml su iç" yapılacak öğesini tamamlayarak kayıt aç
      final todo = await s.createTodo(
        Todo(id: 0, title: '500 ml su iç', createdAt: 0, targetAmount: 500.0, targetUnit: 'ml'),
        activityIds: [act.id],
      );
      final resTodo = await s.completeTodoWithEntry(todo);

      // 2. "Ne yaptın?" kutusundan "500 ml su" yazıldığında açılan kayıt
      final parsed = NaturalLanguageParser.parse('500 ml su', activities: [act], measures: s.measures);
      final resDirect = await s.addEntry(
        act.id,
        measureId: parsed.matchedMeasure?.id,
        qty: parsed.quantity,
      );

      // Değer ve birim birebir aynı olmalı
      expect(resTodo.entry.value, resDirect.entry.value);
      expect(resTodo.entry.unitId, resDirect.entry.unitId);
      expect(resTodo.entry.value, 500.0);
      expect(resTodo.entry.unitId, 'ml');
    });
  });
}
