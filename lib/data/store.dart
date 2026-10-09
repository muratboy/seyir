import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';

import '../logic/format.dart';
import '../logic/l10n.dart';
import '../logic/text_match.dart';
import '../services/backup_service.dart';
import '../services/notification_service.dart';
import 'db.dart';
import 'models.dart';

/// Uygulama genelinde tek veri deposu.
final store = AppStore();

class ActivityStats {
  int count = 0;
  int lastTs = 0;
  int recent = 0; // son 30 gün
  int? lastMeasureId;
  final Map<int, int> measureUses = {};
  final Map<String, int> dimUses = {};

  String? get mainDim => dimUses.isEmpty
      ? null
      : dimUses.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
}

class GoalStatus {
  final Goal goal;
  final double value;
  final DateTime from;
  final DateTime? to;
  final int ignored; // birimi uyumsuz olduğu için sayılamayan kayıt sayısı
  int? daysLeft;
  double? timeRatio;
  double? perDayNeeded;

  GoalStatus(this.goal, this.value, this.from, this.to, this.ignored);

  double get ratio => goal.target <= 0 ? 0 : value / goal.target;
  bool get done => goal.isLimit
      ? value <= goal.target + 1e-9
      : value >= goal.target - 1e-9;
  bool get isExceeded => goal.isLimit && value > goal.target + 1e-9;
  double get remaining => (goal.target - value).clamp(0.0, double.infinity);
  double get exceededAmount => (value - goal.target).clamp(0.0, double.infinity);
  bool get expired => daysLeft != null && daysLeft! < 0;
}

class PeriodTotal {
  int count = 0;
  final Map<String, double> byDim = {};
  final Map<String, int> dimCount = {};

  String? get mainDim => dimCount.isEmpty
      ? null
      : dimCount.entries.reduce((a, b) => a.value >= b.value ? a : b).key;

  void add(Entry e, Unit? u) {
    count++;
    if (u != null && e.value != null) {
      byDim[u.dim] = (byDim[u.dim] ?? 0) + e.value! * u.factor;
      dimCount[u.dim] = (dimCount[u.dim] ?? 0) + 1;
    }
  }
}

class AddResult {
  final Entry entry;
  final List<Goal> achieved;
  final List<Goal> exceeded;
  AddResult(this.entry, this.achieved, {this.exceeded = const []});
}

class QuickTapResult {
  final Entry? added;
  final Entry? removed;
  final List<Goal> achieved;
  final List<Goal> exceeded;
  QuickTapResult({this.added, this.removed, this.achieved = const [], this.exceeded = const []});
}

class HabitStreakInfo {
  final int currentStreak;
  final int longestStreak;
  final int totalActiveDays;
  final bool isDoneToday;
  final int todayCount;
  final double consistencyLast30;
  final Map<DateTime, int> dailyCounts; // Normalized to dayStart

  const HabitStreakInfo({
    required this.currentStreak,
    required this.longestStreak,
    required this.totalActiveDays,
    required this.isDoneToday,
    required this.todayCount,
    required this.consistencyLast30,
    required this.dailyCounts,
  });
}

int daysBetween(DateTime a, DateTime b) =>
    (dayStart(b).difference(dayStart(a)).inHours / 24).round();

class AppStore extends ChangeNotifier {
  Database? _db;
  List<Unit> customUnits = [];
  List<Measure> measures = [];
  Map<int, Activity> activities = {};
  List<Entry> entries = []; // ts'ye göre artan sıralı
  List<Goal> goals = [];
  List<QuickItem> quickItems = [];
  Map<int, ActivityStats> stats = {};
  ThemeMode themeMode = ThemeMode.system;
  AppLanguage language = AppLanguage.tr;
  final appThemeNotifier = ValueNotifier<ThemeMode>(ThemeMode.system);
  final appLanguageNotifier = ValueNotifier<AppLanguage>(AppLanguage.tr);
  String timelineView = 'list'; // 'list' | 'grid'
  List<ActiveTimer> activeTimers = [];
  ActiveTimer? get activeTimer => activeTimers.firstOrNull;
  bool loaded = false;

  bool waterReminderEnabled = false;
  int waterReminderIntervalHours = 2;
  bool dailySummaryReminderEnabled = false;
  String dailySummaryReminderTime = '21:30';
  bool timerSoundEnabled = true;

  Future<Database> get db async => _db ??= await AppDb.open();

  // ---------------------------------------------------------------- yükleme

  Future<void> load() async {
    final d = await db;
    final settingsRows = await d.query('settings');
    final settingsMap = {for (final r in settingsRows) r['key'] as String: r['value'] as String};
    final themeStr = settingsMap['theme'];
    if (themeStr == 'dark') {
      themeMode = ThemeMode.dark;
    } else if (themeStr == 'light') {
      themeMode = ThemeMode.light;
    } else {
      themeMode = ThemeMode.system;
    }
    appThemeNotifier.value = themeMode;

    final langStr = settingsMap['lang'];
    if (langStr == 'en') {
      language = AppLanguage.en;
      strings.value = const AppStrings(AppLanguage.en);
    } else {
      language = AppLanguage.tr;
      strings.value = const AppStrings(AppLanguage.tr);
    }
    appLanguageNotifier.value = language;

    final tView = settingsMap['timeline_view'];
    if (tView == 'grid') {
      timelineView = 'grid';
    } else {
      timelineView = 'list';
    }

    waterReminderEnabled = settingsMap['reminder_water_enabled'] == 'true';
    waterReminderIntervalHours = int.tryParse(settingsMap['reminder_water_interval'] ?? '2') ?? 2;
    dailySummaryReminderEnabled = settingsMap['reminder_daily_summary_enabled'] == 'true';
    dailySummaryReminderTime = settingsMap['reminder_daily_summary_time'] ?? '21:30';
    timerSoundEnabled = settingsMap['reminder_timer_sound'] != 'false';

    customUnits = (await d.query('units')).map(Unit.fromMap).toList();
    measures = (await d.query('measures', orderBy: 'sort, id')).map(Measure.fromMap).toList();
    activities = {
      for (final m in await d.query('activities')) m['id'] as int: Activity.fromMap(m),
    };
    entries = (await d.query('entries', orderBy: 'ts, id')).map(Entry.fromMap).toList();
    final links = await d.query('goal_links');
    goals = (await d.query('goals', orderBy: 'sort, id')).map((m) {
      final g = Goal.fromMap(m);
      g.links = links.where((l) => l['goal_id'] == g.id).map(GoalLink.fromMap).toList();
      return g;
    }).toList();
    quickItems =
        (await d.query('quick_items', orderBy: 'sort, id')).map(QuickItem.fromMap).toList();
    await _cleanupQuickItems();

    final timerRows = await d.query('active_timers', orderBy: 'id ASC');
    activeTimers = timerRows.map(ActiveTimer.fromMap).toList();
    await NotificationService.updateTimerNotification(activeTimers, activities);

    for (final t in activeTimers) {
      if (t.isCountdown && t.isRunning && t.remainingMs > 0) {
        final actName = activities[t.activityId]?.name ?? 'Aktivite';
        await NotificationService.scheduleTimerAlarm(
          timerId: t.id,
          activityName: actName,
          remainingMs: t.remainingMs,
          isPomodoro: t.isPomodoro,
          soundEnabled: timerSoundEnabled,
        );
      }
    }
    unawaited(NotificationService.scheduleReminders(this));

    loaded = true;
    _changed();
    unawaited(BackupService.checkAndPerformDailyAutoBackup(this));
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    themeMode = mode;
    appThemeNotifier.value = mode;
    final d = await db;
    final val = mode == ThemeMode.dark ? 'dark' : (mode == ThemeMode.light ? 'light' : 'system');
    await d.insert('settings', {'key': 'theme', 'value': val}, conflictAlgorithm: ConflictAlgorithm.replace);
    notifyListeners();
  }

  Future<void> setLanguage(AppLanguage lang) async {
    language = lang;
    appLanguageNotifier.value = lang;
    strings.value = AppStrings(lang);
    final d = await db;
    final val = lang == AppLanguage.en ? 'en' : 'tr';
    await d.insert('settings', {'key': 'lang', 'value': val}, conflictAlgorithm: ConflictAlgorithm.replace);
    notifyListeners();
  }

  Future<void> setTimelineView(String mode) async {
    timelineView = mode == 'grid' ? 'grid' : 'list';
    final d = await db;
    await d.insert('settings', {'key': 'timeline_view', 'value': timelineView},
        conflictAlgorithm: ConflictAlgorithm.replace);
    notifyListeners();
  }

  Future<void> setWaterReminder({required bool enabled, int? intervalHours}) async {
    waterReminderEnabled = enabled;
    if (intervalHours != null) waterReminderIntervalHours = intervalHours;
    final d = await db;
    await d.insert('settings', {'key': 'reminder_water_enabled', 'value': enabled.toString()},
        conflictAlgorithm: ConflictAlgorithm.replace);
    await d.insert('settings', {'key': 'reminder_water_interval', 'value': waterReminderIntervalHours.toString()},
        conflictAlgorithm: ConflictAlgorithm.replace);
    notifyListeners();
    await NotificationService.scheduleReminders(this);
  }

  Future<void> setDailySummaryReminder({required bool enabled, String? time}) async {
    dailySummaryReminderEnabled = enabled;
    if (time != null) dailySummaryReminderTime = time;
    final d = await db;
    await d.insert('settings', {'key': 'reminder_daily_summary_enabled', 'value': enabled.toString()},
        conflictAlgorithm: ConflictAlgorithm.replace);
    await d.insert('settings', {'key': 'reminder_daily_summary_time', 'value': dailySummaryReminderTime},
        conflictAlgorithm: ConflictAlgorithm.replace);
    notifyListeners();
    await NotificationService.scheduleReminders(this);
  }

  Future<void> setTimerSoundEnabled(bool enabled) async {
    timerSoundEnabled = enabled;
    final d = await db;
    await d.insert('settings', {'key': 'reminder_timer_sound', 'value': enabled.toString()},
        conflictAlgorithm: ConflictAlgorithm.replace);
    notifyListeners();
  }

  final Map<String, DaySummary> _daySummaryCache = {};

  void _changed() {
    _daySummaryCache.clear();
    _rebuildStats();
    notifyListeners();
  }

  void _rebuildStats() {
    final s = <int, ActivityStats>{};
    final recentFrom = DateTime.now().subtract(const Duration(days: 30)).millisecondsSinceEpoch;
    for (final e in entries) {
      final st = s.putIfAbsent(e.activityId, ActivityStats.new);
      st.count++;
      if (e.ts >= recentFrom) st.recent++;
      if (e.ts >= st.lastTs) {
        st.lastTs = e.ts;
        st.lastMeasureId = e.measureId;
      }
      if (e.measureId != null) {
        st.measureUses[e.measureId!] = (st.measureUses[e.measureId!] ?? 0) + 1;
      }
      final u = e.unitId == null ? null : unit(e.unitId!);
      final dim = u?.dim ?? 'times';
      st.dimUses[dim] = (st.dimUses[dim] ?? 0) + 1;
    }
    stats = s;
  }

  // ---------------------------------------------------------------- birimler

  List<Unit> get allUnits => [...builtinUnits, ...customUnits];

  Unit unit(String id) => builtinUnits.firstWhere(
        (u) => u.id == id,
        orElse: () => customUnits.firstWhere(
          (u) => u.id == id,
          orElse: () => Unit(id: id, name: id, symbol: id, dim: id, factor: 1),
        ),
      );

  String dimName(String dim) => dimNames[dim] ?? unit(dim).name;

  String fmtBase(double base, String dim) => fmtAmount(base, dim, customUnit: unit(dim));

  Future<Unit> addUnit(String name, String symbol) async {
    final id = 'u${DateTime.now().millisecondsSinceEpoch}';
    final u = Unit(id: id, name: name, symbol: symbol, dim: id, factor: 1);
    await (await db).insert('units', u.toMap());
    customUnits.add(u);
    _changed();
    return u;
  }

  bool unitInUse(String id) =>
      measures.any((m) => m.unitId == id) ||
      goals.any((g) => g.unitId == id) ||
      entries.any((e) => e.unitId == id);

  Future<void> deleteUnit(String id) async {
    await (await db).delete('units', where: 'id=?', whereArgs: [id]);
    customUnits.removeWhere((u) => u.id == id);
    _changed();
  }

  // ---------------------------------------------------------------- ölçüler

  Measure? measureById(int? id) {
    if (id == null) return null;
    for (final m in measures) {
      if (m.id == id) return m;
    }
    return null;
  }

  String measureLabel(Measure m) {
    final u = unit(m.unitId);
    return '${m.name} (${fmtNum(m.amount)} ${u.symbol})';
  }

  /// Bu kayıtla daha önce kullanılan ölçüler (sık kullanılan önce) ve diğerleri.
  (List<Measure>, List<Measure>) measuresFor(int? activityId) {
    final st = activityId == null ? null : stats[activityId];
    if (st == null || st.measureUses.isEmpty) return (<Measure>[], List.of(measures));
    final used = measures.where((m) => st.measureUses.containsKey(m.id)).toList()
      ..sort((a, b) => st.measureUses[b.id]!.compareTo(st.measureUses[a.id]!));
    final others = measures.where((m) => !st.measureUses.containsKey(m.id)).toList();
    return (used, others);
  }

  Future<Measure> addMeasure(
    String name,
    String unitId,
    double amount, {
    String qtyMode = 'stepper',
    String choices = '1,2,3,4,5',
    int gridRows = 2,
    int gridCols = 5,
  }) async {
    final m = Measure(
      id: 0,
      name: name,
      unitId: unitId,
      amount: amount,
      sort: measures.length,
      qtyMode: qtyMode,
      choices: choices,
      gridRows: gridRows,
      gridCols: gridCols,
    );
    m.id = await (await db).insert('measures', m.toMap()..remove('id'));
    measures.add(m);
    _changed();
    return m;
  }

  Future<void> updateMeasure(Measure m) async {
    await (await db).update('measures', m.toMap(), where: 'id=?', whereArgs: [m.id]);
    _changed();
  }

  Future<void> deleteMeasure(Measure m) async {
    final d = await db;
    await d.delete('measures', where: 'id=?', whereArgs: [m.id]);
    await d.update('quick_items', {'measure_id': null}, where: 'measure_id=?', whereArgs: [m.id]);
    measures.removeWhere((x) => x.id == m.id);
    for (final q in quickItems) {
      if (q.measureId == m.id) q.measureId = null;
    }
    _changed();
  }

  // ---------------------------------------------------------------- kayıt türleri

  Activity activity(int id) =>
      activities[id] ?? Activity(id: id, name: '(silinmiş)', createdAt: 0);

  String activityLabel(int id) {
    final a = activity(id);
    return a.emoji == null || a.emoji!.isEmpty ? a.name : '${a.emoji} ${a.name}';
  }

  Activity? exactMatch(String text) {
    final n = normalizeTr(text);
    if (n.isEmpty) return null;
    for (final a in activities.values) {
      if (a.norm == n) return a;
    }
    return null;
  }

  /// Yazarken öneriler: benzerlik + kullanım sıklığı (arşivlenenler hariç).
  List<Activity> suggest(String text, {int limit = 6}) {
    final q = normalizeTr(text);
    if (q.isEmpty) return frequent(limit: limit);
    final scored = <(Activity, double)>[];
    for (final a in activities.values.where((a) => !a.isArchived)) {
      var s = matchScore(q, a.norm);
      if (s <= 0) continue;
      final st = stats[a.id];
      if (st != null) s += min(10, log(1 + st.count) * 2 + st.recent * 0.3);
      scored.add((a, s));
    }
    scored.sort((a, b) => b.$2.compareTo(a.$2));
    return scored.take(limit).map((e) => e.$1).toList();
  }

  /// Son 30 günde en sık yapılanlar (arşivlenenler hariç).
  List<Activity> frequent({int limit = 8}) {
    final list = activities.values.where((a) => !a.isArchived && (stats[a.id]?.count ?? 0) > 0).toList();
    list.sort((a, b) {
      final sa = stats[a.id]!, sb = stats[b.id]!;
      final c = sb.recent.compareTo(sa.recent);
      return c != 0 ? c : sb.lastTs.compareTo(sa.lastTs);
    });
    return list.take(limit).toList();
  }

  Future<Activity> addActivity(
    String name, {
    String? emoji,
    String? category,
    int? color,
    bool isHabit = false,
  }) async {
    final a = Activity(
      id: 0,
      name: trCapitalize(name),
      emoji: emoji,
      category: category,
      color: color,
      isHabit: isHabit,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
    a.id = await (await db).insert('activities', a.toMap()..remove('id'));
    activities[a.id] = a;
    _changed();
    return a;
  }

  Future<Activity> findOrCreateActivity(String name) async =>
      exactMatch(name) ?? await addActivity(name);

  Future<void> updateActivity(Activity a) async {
    await (await db).update('activities', a.toMap(), where: 'id=?', whereArgs: [a.id]);
    _changed();
  }

  /// Aktiviteyi arşivler veya arşivden çıkarır.
  /// Geçmiş kayıtlar korunur, ancak yeni kayıt oluştururken önerilmez.
  Future<void> archiveActivity(int id, {bool archived = true}) async {
    final act = activities[id];
    if (act == null) return;
    act.isArchived = archived;
    final d = await db;
    await d.update('activities', {'is_archived': archived ? 1 : 0}, where: 'id=?', whereArgs: [id]);
    if (archived) {
      await d.delete('quick_items', where: 'activity_id=?', whereArgs: [id]);
      quickItems.removeWhere((q) => q.activityId == id);
    }
    _changed();
  }

  /// Kayıt türünü ve ona ait TÜM kayıtları siler.
  Future<void> deleteActivity(int id) async {
    final d = await db;
    final matchingTimers = activeTimers.where((t) => t.activityId == id).toList();
    for (final t in matchingTimers) {
      await d.delete('active_timers', where: 'id=?', whereArgs: [t.id]);
    }
    activeTimers.removeWhere((t) => t.activityId == id);
    await NotificationService.updateTimerNotification(activeTimers, activities);
    await d.transaction((tx) async {
      await tx.delete('entries', where: 'activity_id=?', whereArgs: [id]);
      await tx.delete('goal_links', where: 'activity_id=?', whereArgs: [id]);
      await tx.delete('quick_items', where: 'activity_id=?', whereArgs: [id]);
      await tx.delete('activities', where: 'id=?', whereArgs: [id]);
    });
    entries.removeWhere((e) => e.activityId == id);
    for (final g in goals) {
      g.links.removeWhere((l) => l.activityId == id);
    }
    quickItems.removeWhere((q) => q.activityId == id);
    activities.remove(id);
    _changed();
  }

  /// [fromId] kayıtlarını [intoId] altına taşır ve [fromId]'yi siler (yazım hatalı tekrarları birleştirmek için).
  Future<void> mergeActivity(int fromId, int intoId) async {
    if (fromId == intoId) return;
    final d = await db;
    final matchingTimers = activeTimers.where((t) => t.activityId == fromId).toList();
    for (final t in matchingTimers) {
      final updated = t.copyWith(activityId: intoId);
      final idx = activeTimers.indexWhere((x) => x.id == updated.id);
      if (idx != -1) activeTimers[idx] = updated;
      await d.update('active_timers', updated.toMap(), where: 'id=?', whereArgs: [updated.id]);
    }
    await d.transaction((tx) async {
      await tx.update('entries', {'activity_id': intoId}, where: 'activity_id=?', whereArgs: [fromId]);
      await tx.update('quick_items', {'activity_id': intoId},
          where: 'activity_id=?', whereArgs: [fromId]);
      for (final g in goals) {
        final hasFrom = g.links.any((l) => l.activityId == fromId);
        final hasInto = g.links.any((l) => l.activityId == intoId);
        if (hasFrom && !hasInto) {
          await tx.update('goal_links', {'activity_id': intoId},
              where: 'goal_id=? AND activity_id=?', whereArgs: [g.id, fromId]);
        } else if (hasFrom) {
          await tx.delete('goal_links',
              where: 'goal_id=? AND activity_id=?', whereArgs: [g.id, fromId]);
        }
      }
      await tx.delete('activities', where: 'id=?', whereArgs: [fromId]);
    });
    await load();
  }

  // ---------------------------------------------------------------- kayıtlar

  int _lowerBound(int ts) {
    var lo = 0, hi = entries.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (entries[mid].ts < ts) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  void _insertSorted(Entry e) {
    var i = _lowerBound(e.ts + 1);
    entries.insert(i, e);
  }

  /// [from] dahil, [to] hariç aralıktaki kayıtlar (eskiden yeniye).
  Iterable<Entry> entriesIn(DateTime from, DateTime? to) sync* {
    final toTs = to?.millisecondsSinceEpoch;
    for (var i = _lowerBound(from.millisecondsSinceEpoch); i < entries.length; i++) {
      final e = entries[i];
      if (toTs != null && e.ts >= toTs) break;
      yield e;
    }
  }

  List<Entry> entriesOfDay(DateTime day) {
    final s = dayStart(day);
    return entriesIn(s, DateTime(s.year, s.month, s.day + 1)).toList();
  }

  /// Belirli bir günün özetini (toplam süre, hacim, kayıt adetleri) önbellekten veya hesaplayarak döner.
  DaySummary getDaySummary(DateTime day) {
    final key = dayKey(day);
    final cached = _daySummaryCache[key];
    if (cached != null) return cached;

    final list = entriesOfDay(day);
    if (list.isEmpty) {
      final empty = DaySummary.empty(dayStart(day));
      _daySummaryCache[key] = empty;
      return empty;
    }

    double totalTimeMinutes = 0;
    double totalVolumeLiters = 0;
    final actCounts = <int, int>{};
    final actTimes = <int, double>{};
    final actVolumes = <int, double>{};

    for (final e in list) {
      actCounts[e.activityId] = (actCounts[e.activityId] ?? 0) + 1;
      final u = e.unitId != null ? unit(e.unitId!) : null;
      if (u != null && e.value != null) {
        if (u.dim == 'time') {
          final mins = e.value! * u.factor;
          totalTimeMinutes += mins;
          actTimes[e.activityId] = (actTimes[e.activityId] ?? 0) + mins;
        } else if (u.dim == 'volume') {
          final liters = e.value! * u.factor;
          totalVolumeLiters += liters;
          actVolumes[e.activityId] = (actVolumes[e.activityId] ?? 0) + liters;
        }
      }
    }

    final summary = DaySummary(
      date: dayStart(day),
      count: list.length,
      totalTimeMinutes: totalTimeMinutes,
      totalVolumeLiters: totalVolumeLiters,
      activityCounts: actCounts,
      activityTimeMinutes: actTimes,
      activityVolumeLiters: actVolumes,
    );
    _daySummaryCache[key] = summary;
    return summary;
  }

  void invalidateDaySummary(DateTime day) {
    _daySummaryCache.remove(dayKey(day));
  }

  void clearSummaryCache() {
    _daySummaryCache.clear();
  }

  /// Kayıt detayı: "2 Demlik · 1,4 L", "45 dk"
  String entryDetail(Entry e) {
    if (e.value == null || e.unitId == null) {
      return e.qty != 1 ? '${fmtNum(e.qty)} ${strings.value.timesSuffix}' : '';
    }
    final u = unit(e.unitId!);
    final amount = fmtAmount(e.value! * u.factor, u.dim, customUnit: u);
    final m = measureById(e.measureId);
    if (m == null || (m.amount == 1 && m.unitId == e.unitId)) return amount;
    return '${fmtNum(e.qty)} ${m.name} · $amount';
  }

  Set<int> _doneTargetGoalIds(int activityId, DateTime at) => {
        for (final g in goals)
          if (g.isTarget && g.links.any((l) => l.activityId == activityId) && goalStatus(g, at: at).done) g.id,
      };

  Set<int> _exceededLimitGoalIds(int activityId, DateTime at) => {
        for (final g in goals)
          if (g.isLimit && g.links.any((l) => l.activityId == activityId) && goalStatus(g, at: at).isExceeded) g.id,
      };

  Future<AddResult> addEntry(
    int activityId, {
    int? measureId,
    double qty = 1,
    DateTime? at,
    DateTime? endAt,
    int? endTs,
    String? note,
    double? value,
    String? unitId,
  }) async {
    final time = at ?? DateTime.now();
    final beforeDone = _doneTargetGoalIds(activityId, time);
    final beforeExceeded = _exceededLimitGoalIds(activityId, time);
    final m = measureById(measureId);
    final finalUnitId = m?.unitId ?? unitId;
    final finalValue = m != null ? m.amount * qty : value;

    int? calculatedEndTs = endTs ?? endAt?.millisecondsSinceEpoch;
    if (calculatedEndTs == null && (finalUnitId == 'dk' || finalUnitId == 'sa') && finalValue != null && finalValue > 0) {
      final durationMins = (finalValue * (finalUnitId == 'sa' ? 60 : 1)).round();
      calculatedEndTs = time.add(Duration(minutes: durationMins)).millisecondsSinceEpoch;
    }

    final e = Entry(
      id: 0,
      activityId: activityId,
      ts: time.millisecondsSinceEpoch,
      endTs: calculatedEndTs,
      measureId: m?.id,
      qty: qty,
      value: finalValue,
      unitId: finalUnitId,
      note: (note?.trim().isEmpty ?? true) ? null : note!.trim(),
    );
    e.id = await (await db).insert('entries', e.toMap()..remove('id'));
    _insertSorted(e);
    _changed();
    final afterDone = _doneTargetGoalIds(activityId, time);
    final afterExceeded = _exceededLimitGoalIds(activityId, time);
    final achieved = goals.where((g) => afterDone.contains(g.id) && !beforeDone.contains(g.id)).toList();
    final exceeded = goals.where((g) => afterExceeded.contains(g.id) && !beforeExceeded.contains(g.id)).toList();
    for (final g in exceeded) {
      NotificationService.showLimitAlert(
        '⚠️ Limit Aşıldı!',
        '${g.name} limitinizi aştınız.',
      );
    }
    for (final g in achieved) {
      NotificationService.showLimitAlert(
        '🎯 Hedefe Ulaşıldı!',
        'Tebrikler! ${g.name} hedefini tamamladınız.',
      );
    }
    return AddResult(e, achieved, exceeded: exceeded);
  }

  Future<void> updateEntry(
    Entry e, {
    required int activityId,
    required DateTime time,
    int? measureId,
    double qty = 1,
    String? note,
  }) async {
    final m = measureById(measureId);
    if (m != null) {
      e.value = m.amount * qty;
      e.unitId = m.unitId;
      e.measureId = m.id;
      e.qty = qty;
    } else if (measureId != null && measureId == e.measureId && e.value != null) {
      // ölçü silinmiş: anlık görüntüyü orantılı ölçekle
      if (e.qty != 0) e.value = e.value! / e.qty * qty;
      e.qty = qty;
    } else {
      e.measureId = null;
      e.value = null;
      e.unitId = null;
      e.qty = 1;
    }
    e.activityId = activityId;
    e.note = (note?.trim().isEmpty ?? true) ? null : note!.trim();
    final newTs = time.millisecondsSinceEpoch;
    if (newTs != e.ts) {
      entries.remove(e);
      e.ts = newTs;
      _insertSorted(e);
    }
    await (await db).update('entries', e.toMap(), where: 'id=?', whereArgs: [e.id]);
    _changed();
  }

  Future<void> deleteEntry(Entry e) async {
    await (await db).delete('entries', where: 'id=?', whereArgs: [e.id]);
    entries.removeWhere((x) => x.id == e.id);
    _changed();
  }

  Future<void> restoreEntry(Entry e) async {
    if (!activities.containsKey(e.activityId)) return;
    await (await db).insert('entries', e.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
    entries.removeWhere((x) => x.id == e.id);
    _insertSorted(e);
    _changed();
  }

  // ---------------------------------------------------------------- kronometre

  ActiveTimer? getTimer(int id) =>
      activeTimers.where((t) => t.id == id).firstOrNull;

  ActiveTimer? getTimerForActivity(int activityId) =>
      activeTimers.where((t) => t.activityId == activityId).firstOrNull;

  void toggleTimerCollapse(int id) {
    final idx = activeTimers.indexWhere((t) => t.id == id);
    if (idx != -1) {
      activeTimers[idx] = activeTimers[idx].copyWith(
        isCollapsed: !activeTimers[idx].isCollapsed,
      );
      notifyListeners();
    }
  }

  Future<ActiveTimer> startTimer(
    int activityId, {
    String? note,
    String mode = 'stopwatch',
    int targetMs = 0,
  }) async {
    // Aynı aktivite için zaten sayaç çalışıyorsa onu döndür
    final existing = getTimerForActivity(activityId);
    if (existing != null) {
      return existing;
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    final d = await db;
    final rowId = await d.insert('active_timers', {
      'activity_id': activityId,
      'start_ts': now,
      'accumulated_ms': 0,
      'last_resume_ts': now,
      'is_running': 1,
      'note': (note?.trim().isEmpty ?? true) ? null : note!.trim(),
      'mode': mode,
      'target_ms': targetMs,
    });

    final timer = ActiveTimer(
      id: rowId,
      activityId: activityId,
      startTs: now,
      accumulatedMs: 0,
      lastResumeTs: now,
      isRunning: true,
      note: (note?.trim().isEmpty ?? true) ? null : note!.trim(),
      mode: mode,
      targetMs: targetMs,
      isCollapsed: false,
    );
    activeTimers.add(timer);
    unawaited(NotificationService.requestPermission());
    await NotificationService.updateTimerNotification(activeTimers, activities);
    if (timer.isCountdown && timer.remainingMs > 0) {
      final actName = activities[timer.activityId]?.name ?? 'Aktivite';
      await NotificationService.scheduleTimerAlarm(
        timerId: timer.id,
        activityName: actName,
        remainingMs: timer.remainingMs,
        isPomodoro: timer.isPomodoro,
        soundEnabled: timerSoundEnabled,
      );
    }
    notifyListeners();
    return timer;
  }

  Future<void> pauseTimer([int? id]) async {
    final timer = id != null ? getTimer(id) : activeTimers.where((t) => t.isRunning).firstOrNull;
    if (timer == null || !timer.isRunning) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    final last = timer.lastResumeTs;
    final diff = last != null ? (now - last).clamp(0, 1000000000) : 0;
    final segs = List<TimerSegment>.from(timer.segments);
    if (last != null && now > last) {
      segs.add(TimerSegment(startTs: last, endTs: now));
    }
    final updated = timer.copyWith(
      accumulatedMs: timer.accumulatedMs + diff,
      isRunning: false,
      clearLastResumeTs: true,
      segments: segs,
    );

    final d = await db;
    await d.update('active_timers', updated.toMap(), where: 'id=?', whereArgs: [updated.id]);
    final idx = activeTimers.indexWhere((t) => t.id == updated.id);
    if (idx != -1) activeTimers[idx] = updated;

    await NotificationService.cancelTimerAlarm(timer.id);
    await NotificationService.updateTimerNotification(activeTimers, activities);
    notifyListeners();
  }

  Future<void> resumeTimer([int? id]) async {
    final timer = id != null ? getTimer(id) : activeTimers.where((t) => !t.isRunning).firstOrNull;
    if (timer == null || timer.isRunning) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    final updated = timer.copyWith(
      lastResumeTs: now,
      isRunning: true,
    );

    final d = await db;
    await d.update('active_timers', updated.toMap(), where: 'id=?', whereArgs: [updated.id]);
    final idx = activeTimers.indexWhere((t) => t.id == updated.id);
    if (idx != -1) activeTimers[idx] = updated;

    await NotificationService.updateTimerNotification(activeTimers, activities);
    if (updated.isCountdown && updated.remainingMs > 0) {
      final actName = activities[updated.activityId]?.name ?? 'Aktivite';
      await NotificationService.scheduleTimerAlarm(
        timerId: updated.id,
        activityName: actName,
        remainingMs: updated.remainingMs,
        isPomodoro: updated.isPomodoro,
        soundEnabled: timerSoundEnabled,
      );
    }
    notifyListeners();
  }

  Future<void> updateTimerNote(dynamic idOrNote, [String? note]) async {
    ActiveTimer? timer;
    String? noteText;
    if (idOrNote is int) {
      timer = getTimer(idOrNote);
      noteText = note;
    } else {
      timer = activeTimer;
      noteText = idOrNote as String?;
    }
    if (timer == null) return;

    final updated = timer.copyWith(
      note: (noteText?.trim().isEmpty ?? true) ? null : noteText!.trim(),
    );
    final d = await db;
    await d.update('active_timers', updated.toMap(), where: 'id=?', whereArgs: [updated.id]);
    final idx = activeTimers.indexWhere((t) => t.id == updated.id);
    if (idx != -1) activeTimers[idx] = updated;
    notifyListeners();
  }

  (String unitId, double qty, int? measureId) _calculateTimerUnitAndQty(int totalMs) {
    final totalSeconds = (totalMs / 1000.0).round();
    String finalUnitId;
    double finalQty;
    int? measureId;

    if (totalSeconds < 60) {
      finalUnitId = 'sn';
      finalQty = totalSeconds < 1 ? 1.0 : totalSeconds.toDouble();
      final secM = measures.cast<Measure?>().firstWhere(
            (m) => m?.unitId == 'sn',
            orElse: () => null,
          );
      measureId = secM?.id;
    } else {
      finalUnitId = 'dk';
      final rawMins = totalMs / 60000.0;
      finalQty = (rawMins * 10).round() / 10.0;
      if (finalQty < 1.0) finalQty = 1.0;
      final minM = measures.cast<Measure?>().firstWhere(
            (m) => m?.unitId == 'dk' && m?.amount == 1.0,
            orElse: () => measures.cast<Measure?>().firstWhere(
              (m) => m?.unitId == 'dk',
              orElse: () => null,
            ),
          );
      measureId = minM?.id;
    }
    return (finalUnitId, finalQty, measureId);
  }

  Future<AddResult?> finishTimer([
    int? id,
    MidnightSplitChoice splitChoice = MidnightSplitChoice.startDay,
  ]) async {
    final timer = id != null ? getTimer(id) : activeTimer;
    if (timer == null) return null;

    final actId = timer.activityId;
    final note = timer.note;
    final startTime = timer.startTime;
    final endTime = DateTime.now();

    final beforeDone = _doneTargetGoalIds(actId, startTime);
    final beforeExceeded = _exceededLimitGoalIds(actId, startTime);

    final entriesToSave = <Entry>[];

    // Gece yarısı bölme seçeneği ve oturum gerçekten gece yarısını aşıyorsa
    if (splitChoice == MidnightSplitChoice.split && timer.spansMidnight) {
      final msBefore = timer.msBeforeMidnight;
      final msAfter = timer.msAfterMidnight;

      final nextMidnight = DateTime(startTime.year, startTime.month, startTime.day + 1);

      if (msBefore > 0) {
        final (unitId1, qty1, measureId1) = _calculateTimerUnitAndQty(msBefore);
        final m1 = measureById(measureId1);
        entriesToSave.add(Entry(
          id: 0,
          activityId: actId,
          ts: startTime.millisecondsSinceEpoch,
          endTs: nextMidnight.millisecondsSinceEpoch,
          measureId: measureId1,
          qty: qty1,
          value: m1 != null ? m1.amount * qty1 : qty1,
          unitId: m1?.unitId ?? unitId1,
          note: note,
        ));
      }

      if (msAfter > 0) {
        final (unitId2, qty2, measureId2) = _calculateTimerUnitAndQty(msAfter);
        final m2 = measureById(measureId2);
        entriesToSave.add(Entry(
          id: 0,
          activityId: actId,
          ts: nextMidnight.millisecondsSinceEpoch,
          endTs: endTime.millisecondsSinceEpoch,
          measureId: measureId2,
          qty: qty2,
          value: m2 != null ? m2.amount * qty2 : qty2,
          unitId: m2?.unitId ?? unitId2,
          note: note,
        ));
      }
    } else {
      // Tek parça kayıt: startDay (başlangıç saati) veya endDay (bitiş saati)
      final totalMs = timer.elapsedMs;
      final (finalUnitId, finalQty, measureId) = _calculateTimerUnitAndQty(totalMs);
      final recordTime = splitChoice == MidnightSplitChoice.endDay ? endTime : startTime;
      final m = measureById(measureId);

      entriesToSave.add(Entry(
        id: 0,
        activityId: actId,
        ts: recordTime.millisecondsSinceEpoch,
        endTs: endTime.millisecondsSinceEpoch,
        measureId: measureId,
        qty: finalQty,
        value: m != null ? m.amount * finalQty : finalQty,
        unitId: m?.unitId ?? finalUnitId,
        note: note,
      ));
    }

    if (entriesToSave.isEmpty) return null;

    final d = await db;
    final createdEntries = <Entry>[];

    // Atomik SQLite işlemi: tüm kayıtlar yazılır ve sayaç tek transaction'da silinir
    await d.transaction((tx) async {
      for (final raw in entriesToSave) {
        final rowId = await tx.insert('entries', raw.toMap()..remove('id'));
        raw.id = rowId;
        createdEntries.add(raw);
      }
      await tx.delete('active_timers', where: 'id=?', whereArgs: [timer.id]);
    });

    // Veritabanı başarılı oldu -> bellek durumunu ve bildirimleri güvenle güncelle
    await NotificationService.cancelTimerAlarm(timer.id);
    activeTimers.removeWhere((t) => t.id == timer.id);
    for (final e in createdEntries) {
      _insertSorted(e);
    }
    _changed();
    await NotificationService.updateTimerNotification(activeTimers, activities);

    // Hedef ve limit durumlarını kontrol et
    final achieved = <Goal>[];
    final exceeded = <Goal>[];
    for (final e in createdEntries) {
      final afterDone = _doneTargetGoalIds(actId, e.time);
      final afterExceeded = _exceededLimitGoalIds(actId, e.time);
      for (final g in goals) {
        if (afterDone.contains(g.id) && !beforeDone.contains(g.id) && !achieved.contains(g)) {
          achieved.add(g);
        }
        if (afterExceeded.contains(g.id) && !beforeExceeded.contains(g.id) && !exceeded.contains(g)) {
          exceeded.add(g);
        }
      }
    }

    for (final g in exceeded) {
      NotificationService.showLimitAlert(
        '⚠️ Limit Aşıldı!',
        '${g.name} limitinizi aştınız.',
      );
    }
    for (final g in achieved) {
      NotificationService.showLimitAlert(
        '🎯 Hedefe Ulaşıldı!',
        'Tebrikler! ${g.name} hedefini tamamladınız.',
      );
    }

    return AddResult(createdEntries.last, achieved, exceeded: exceeded);
  }

  Future<void> cancelTimer([int? id]) async {
    final timer = id != null ? getTimer(id) : activeTimer;
    if (timer == null) return;
    final d = await db;
    await d.delete('active_timers', where: 'id=?', whereArgs: [timer.id]);
    await NotificationService.cancelTimerAlarm(timer.id);
    activeTimers.removeWhere((t) => t.id == timer.id);
    await NotificationService.updateTimerNotification(activeTimers, activities);
    notifyListeners();
  }

  Future<void> discardTimer([int? id]) => cancelTimer(id);

  // ---------------------------------------------------------------- istatistik

  PeriodTotal totals(int activityId, DateTime from, DateTime to) {
    final t = PeriodTotal();
    for (final e in entriesIn(from, to)) {
      if (e.activityId == activityId) t.add(e, e.unitId == null ? null : unit(e.unitId!));
    }
    return t;
  }

  Map<int, PeriodTotal> totalsByActivity(DateTime from, DateTime to) {
    final res = <int, PeriodTotal>{};
    for (final e in entriesIn(from, to)) {
      res.putIfAbsent(e.activityId, PeriodTotal.new).add(e, e.unitId == null ? null : unit(e.unitId!));
    }
    return res;
  }

  /// "1,4 L · 5 kez"
  String totalText(PeriodTotal t) {
    final dim = t.mainDim;
    final kez = '${t.count} kez';
    if (dim == null) return kez;
    return '${fmtBase(t.byDim[dim]!, dim)} · $kez';
  }

  // ---------------------------------------------------------------- hedefler

  (DateTime, DateTime?) goalRange(Goal g, DateTime at) {
    final start = dayStart(DateTime.fromMillisecondsSinceEpoch(g.startDate));
    DateTime from;
    DateTime? to;
    switch (g.period) {
      case GoalPeriod.day:
        from = dayStart(at);
        to = DateTime(from.year, from.month, from.day + 1);
      case GoalPeriod.week:
        from = weekStart(at);
        to = DateTime(from.year, from.month, from.day + 7);
      case GoalPeriod.month:
        from = monthStart(at);
        to = DateTime(from.year, from.month + 1);
      case GoalPeriod.total:
        from = start;
        if (g.endDate != null) {
          final e = dayStart(DateTime.fromMillisecondsSinceEpoch(g.endDate!));
          to = DateTime(e.year, e.month, e.day + 1);
        }
    }
    if (from.isBefore(start)) from = start;
    return (from, to);
  }

  /// Bir kaydın hedefe katkısı (hedef biriminde). null = birim uyumsuz.
  double? contribution(Goal g, Entry e, double pct) {
    final f = pct / 100;
    if (g.isCount) return f;
    final gu = unit(g.unitId ?? 'adet');
    if (e.unitId == null || e.value == null) {
      if (gu.dim == 'count') return e.qty * f / gu.factor;
      return null;
    }
    final eu = unit(e.unitId!);
    if (eu.dim != gu.dim) return null;
    return e.value! * eu.factor / gu.factor * f;
  }

  (double, int) goalValue(Goal g, DateTime from, DateTime? to, {Map<int, double>? byActivity}) {
    final pcts = {for (final l in g.links) l.activityId: l.pct};
    var v = 0.0;
    var ignored = 0;
    if (to != null && !to.isAfter(from)) return (0, 0);
    for (final e in entriesIn(from, to)) {
      final pct = pcts[e.activityId];
      if (pct == null) continue;
      final c = contribution(g, e, pct);
      if (c == null) {
        ignored++;
      } else {
        v += c;
        if (byActivity != null) byActivity[e.activityId] = (byActivity[e.activityId] ?? 0) + c;
      }
    }
    return (v, ignored);
  }

  GoalStatus goalStatus(Goal g, {DateTime? at, Map<int, double>? byActivity}) {
    final now = DateTime.now();
    final (from, to) = goalRange(g, at ?? now);
    final (v, ign) = goalValue(g, from, to, byActivity: byActivity);
    final st = GoalStatus(g, v, from, to, ign);
    if (g.endDate != null) {
      final end = dayStart(DateTime.fromMillisecondsSinceEpoch(g.endDate!));
      final start = dayStart(DateTime.fromMillisecondsSinceEpoch(g.startDate));
      st.daysLeft = daysBetween(now, end);
      final total = end.add(const Duration(days: 1)).difference(start).inMinutes;
      final passed = now.difference(start).inMinutes;
      st.timeRatio = total <= 0 ? 1 : (passed / total).clamp(0.0, 1.0);
      if (g.period == GoalPeriod.total && !st.done && st.daysLeft! >= 0) {
        st.perDayNeeded = (g.target - v) / (st.daysLeft! + 1);
      }
    }
    return st;
  }

  String goalUnitSymbol(Goal g) => g.isCount ? 'kez' : unit(g.unitId ?? 'adet').symbol;

  String goalValueText(Goal g, double v) => '${fmtNum(v)} ${goalUnitSymbol(g)}';

  /// Periyodik hedeflerin geçmişi (en yeni önce), hedef başlangıcına kadar.
  List<GoalStatus> goalHistory(Goal g, int n) {
    final res = <GoalStatus>[];
    if (g.period == GoalPeriod.total) return res;
    final start = dayStart(DateTime.fromMillisecondsSinceEpoch(g.startDate));
    var at = DateTime.now();
    for (var i = 0; i < n; i++) {
      final st = goalStatus(g, at: at);
      if (st.to != null && !st.to!.isAfter(start)) break;
      res.add(st);
      final (f, _) = goalRange(g, at);
      if (!f.isAfter(start)) break;
      at = DateTime(f.year, f.month, f.day - 1, 12);
    }
    return res;
  }

  /// Arka arkaya tamamlanan periyot sayısı (bugünkü henüz bitmediyse dünden başlar).
  int goalStreak(Goal g) {
    if (g.period == GoalPeriod.total) return 0;
    final start = dayStart(DateTime.fromMillisecondsSinceEpoch(g.startDate));
    var at = DateTime.now();
    final firstSt = goalStatus(g, at: at);
    if (firstSt.to != null && !firstSt.to!.isAfter(start)) return 0;

    int s = 0;
    if (firstSt.done) {
      s = 1;
    }

    final (f0, _) = goalRange(g, at);
    if (!f0.isAfter(start)) return s;
    at = DateTime(f0.year, f0.month, f0.day - 1, 12);

    // Seri bozulana kadar geriye doğru kontrol et (maksimum 365 periyot)
    for (var i = 0; i < 365; i++) {
      if (!at.isAfter(start)) break;
      final st = goalStatus(g, at: at);
      if (st.to != null && !st.to!.isAfter(start)) break;
      if (!st.done) break;
      s++;
      final (f, _) = goalRange(g, at);
      if (!f.isAfter(start)) break;
      at = DateTime(f.year, f.month, f.day - 1, 12);
    }
    return s;
  }

  Future<void> saveGoal(Goal g) async {
    final d = await db;
    await d.transaction((tx) async {
      if (g.id == 0) {
        g.sort = goals.length;
        g.id = await tx.insert('goals', g.toMap()..remove('id'));
      } else {
        await tx.update('goals', g.toMap(), where: 'id=?', whereArgs: [g.id]);
        await tx.delete('goal_links', where: 'goal_id=?', whereArgs: [g.id]);
      }
      for (final l in g.links) {
        await tx.insert('goal_links', l.toMap(g.id));
      }
    });
    final i = goals.indexWhere((x) => x.id == g.id);
    if (i < 0) {
      goals.add(g);
    } else {
      goals[i] = g;
    }
    _changed();
  }

  Future<void> deleteGoal(Goal g) async {
    final d = await db;
    await d.delete('goal_links', where: 'goal_id=?', whereArgs: [g.id]);
    await d.delete('goals', where: 'id=?', whereArgs: [g.id]);
    goals.removeWhere((x) => x.id == g.id);
    _changed();
  }

  /// Belirli bir aktivitenin bağlı olduğu hedefleri döner.
  List<(Goal, GoalLink)> goalsForActivity(int activityId) {
    final res = <(Goal, GoalLink)>[];
    for (final g in goals) {
      for (final l in g.links) {
        if (l.activityId == activityId) {
          res.add((g, l));
          break;
        }
      }
    }
    return res;
  }

  /// Bir aktivitenin hedeflerle olan bağlantılarını günceller (ekler, siler veya % değiştirir).
  Future<void> setActivityGoals(int activityId, Map<int, double?> goalPcts) async {
    for (final entry in goalPcts.entries) {
      final goalId = entry.key;
      final pct = entry.value;
      final g = goals.where((x) => x.id == goalId).firstOrNull;
      if (g == null) continue;
      g.links.removeWhere((l) => l.activityId == activityId);
      if (pct != null && pct > 0) {
        g.links.add(GoalLink(activityId: activityId, pct: pct));
      }
      await saveGoal(g);
    }
    _changed();
  }

  // ---------------------------------------------------------------- zinciri kırma (habit tracker)

  List<Activity> get habitActivities => activities.values.where((a) => a.isHabit).toList();

  Future<void> setActivityHabit(int activityId, bool isHabit) async {
    final act = activities[activityId];
    if (act == null) return;
    act.isHabit = isHabit;
    await updateActivity(act);
  }

  HabitStreakInfo habitStreakInfo(int activityId) {
    final now = DateTime.now();
    final today = dayStart(now);

    final dailyCounts = <DateTime, int>{};
    for (final e in entries) {
      if (e.activityId == activityId) {
        final d = dayStart(DateTime.fromMillisecondsSinceEpoch(e.ts));
        dailyCounts[d] = (dailyCounts[d] ?? 0) + 1;
      }
    }

    final todayCount = dailyCounts[today] ?? 0;
    final isDoneToday = todayCount > 0;
    final totalActiveDays = dailyCounts.length;

    // Current streak (bugün yapıldıysa bugünden geriye, yapılmadıysa dünden geriye)
    int currentStreak = 0;
    DateTime checkDate = isDoneToday ? today : DateTime(today.year, today.month, today.day - 1);
    while (dailyCounts.containsKey(checkDate)) {
      currentStreak++;
      checkDate = DateTime(checkDate.year, checkDate.month, checkDate.day - 1);
    }

    // Longest streak
    int longestStreak = 0;
    if (dailyCounts.isNotEmpty) {
      final sortedDays = dailyCounts.keys.toList()..sort();
      int tempStreak = 0;
      DateTime? prevDay;
      for (final day in sortedDays) {
        if (prevDay == null) {
          tempStreak = 1;
        } else {
          final diff = daysBetween(prevDay, day);
          if (diff == 1) {
            tempStreak++;
          } else {
            tempStreak = 1;
          }
        }
        if (tempStreak > longestStreak) {
          longestStreak = tempStreak;
        }
        prevDay = day;
      }
    }
    if (currentStreak > longestStreak) {
      longestStreak = currentStreak;
    }

    // Consistency in last 30 days
    int activeIn30 = 0;
    for (int i = 0; i < 30; i++) {
      final d = DateTime(today.year, today.month, today.day - i);
      if (dailyCounts.containsKey(d)) activeIn30++;
    }
    final consistencyLast30 = (activeIn30 / 30.0) * 100.0;

    return HabitStreakInfo(
      currentStreak: currentStreak,
      longestStreak: longestStreak,
      totalActiveDays: totalActiveDays,
      isDoneToday: isDoneToday,
      todayCount: todayCount,
      consistencyLast30: consistencyLast30,
      dailyCounts: dailyCounts,
    );
  }

  Future<AddResult> quickLogHabit(int activityId, {DateTime? date}) async {
    final lastMeasureId = stats[activityId]?.lastMeasureId;
    return addEntry(
      activityId,
      measureId: lastMeasureId,
      qty: 1,
      at: date ?? DateTime.now(),
    );
  }

  // ---------------------------------------------------------------- hızlı liste

  int todayCount(int activityId) =>
      entriesOfDay(DateTime.now()).where((e) => e.activityId == activityId).length;

  Entry? quickDoneEntry(QuickItem q) {
    if (!q.isTodo) return null;
    final from = q.daily
        ? dayStart(DateTime.now())
        : DateTime.fromMillisecondsSinceEpoch(q.createdAt);
    Entry? last;
    for (final e in entriesIn(from, null)) {
      if (e.activityId == q.activityId) last = e;
    }
    return last;
  }

  bool quickDone(QuickItem q) => quickDoneEntry(q) != null;

  Future<QuickTapResult> tapQuickItem(int id) async {
    final q = quickItems.where((x) => x.id == id).firstOrNull;
    if (q == null) return QuickTapResult();
    final done = quickDoneEntry(q);
    if (done != null) {
      await deleteEntry(done);
      return QuickTapResult(removed: done);
    }
    final r = await addEntry(q.activityId, measureId: q.measureId, qty: q.qty);
    return QuickTapResult(added: r.entry, achieved: r.achieved, exceeded: r.exceeded);
  }

  Future<void> saveQuickItem(QuickItem q) async {
    final d = await db;
    if (q.id == 0) {
      q.sort = quickItems.isEmpty ? 0 : quickItems.map((e) => e.sort).reduce(max) + 1;
      q.id = await d.insert('quick_items', q.toMap()..remove('id'));
      quickItems.add(q);
    } else {
      await d.update('quick_items', q.toMap(), where: 'id=?', whereArgs: [q.id]);
    }
    _changed();
  }

  Future<void> deleteQuickItem(QuickItem q) async {
    await (await db).delete('quick_items', where: 'id=?', whereArgs: [q.id]);
    quickItems.removeWhere((x) => x.id == q.id);
    _changed();
  }

  Future<void> reorderQuick(int oldIndex, int newIndex) async {
    final item = quickItems.removeAt(oldIndex);
    quickItems.insert(newIndex, item);
    final d = await db;
    await d.transaction((tx) async {
      for (var i = 0; i < quickItems.length; i++) {
        quickItems[i].sort = i;
        await tx.update('quick_items', {'sort': i}, where: 'id=?', whereArgs: [quickItems[i].id]);
      }
    });
    _changed();
  }

  /// Bir kerelik yapılacaklar, tamamlandıkları günden sonra listeden kalkar.
  Future<void> _cleanupQuickItems() async {
    final today = dayStart(DateTime.now());
    final remove = <QuickItem>[];
    for (final q in quickItems) {
      if (q.isTodo && !q.daily) {
        final e = quickDoneEntry(q);
        if (e != null && e.time.isBefore(today)) remove.add(q);
      }
      if (!activities.containsKey(q.activityId)) remove.add(q);
    }
    if (remove.isEmpty) return;
    final d = await db;
    for (final q in remove) {
      await d.delete('quick_items', where: 'id=?', whereArgs: [q.id]);
      quickItems.remove(q);
    }
  }

  // ---------------------------------------------------------------- widget verisi

  Map<String, Object?> widgetPayload() {
    final now = DateTime.now();
    final items = quickItems.take(8).map((q) {
      final n = todayCount(q.activityId);
      final done = quickDone(q);
      String sub;
      if (!q.isTodo) {
        sub = n > 0 ? 'Bugün $n' : '';
      } else {
        sub = q.daily ? '' : 'bir kez';
      }
      return {
        'id': q.id,
        't': activityLabel(q.activityId),
        'k': q.kind,
        'd': done,
        's': sub,
        'o': q.isTodo && !q.daily,
      };
    }).toList();
    final goalParts = <String>[];
    for (final g in goals.where((g) => g.period == GoalPeriod.day)) {
      final st = goalStatus(g);
      if (st.expired) continue;
      if (g.isLimit) {
        goalParts.add(st.isExceeded ? '⚠️ ${g.name}!' : '✓ ${g.name}');
      } else {
        goalParts.add(st.done ? '✓ ${g.name}' : '${g.name} %${(st.ratio * 100).floor()}');
      }
    }
    return {
      'date': dayKey(now),
      'items': items,
      'goals': goalParts.isEmpty ? '' : '🎯 ${goalParts.join('  ·  ')}',
    };
  }

  // ---------------------------------------------------------------- yedekleme

  Future<String> exportJson() async {
    final d = await db;
    final out = <String, Object?>{
      'app': 'takip',
      'version': AppDb.currentVersion,
      'exportedAt': DateTime.now().toIso8601String(),
    };
    for (final t in AppDb.tables) {
      out[t] = await d.query(t);
    }
    return const JsonEncoder.withIndent(' ').convert(out);
  }

  Future<void> importJson(String json) async {
    final m = jsonDecode(json);
    if (m is! Map || m['app'] != 'takip') {
      throw const FormatException('Bu dosya bir Takip yedeği değil.');
    }
    // Geri yükleme öncesinde mevcut verileri korumak için güvenlik yedeği al
    try {
      await BackupService.createPreRestoreSnapshot(this);
    } catch (_) {}

    final d = await db;
    await d.transaction((tx) async {
      for (final t in AppDb.tables) {
        await tx.delete(t);
      }
      for (final t in AppDb.tables) {
        final rows = (m[t] as List?) ?? const [];
        for (final r in rows) {
          await tx.insert(t, Map<String, Object?>.from(r as Map));
        }
      }
    });
    await load();
  }
}
