import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:sqflite/sqflite.dart';

import '../logic/activity_format_analysis.dart';
import '../logic/format.dart';
import '../logic/l10n.dart';
import '../logic/text_match.dart';
import '../logic/time_suggestions.dart';
import '../services/ai_service.dart';
import '../services/backup_service.dart';
import '../services/health_tracker_service.dart';
import '../services/nl_parser.dart';
import '../services/notification_service.dart';
import '../widget_sync.dart';
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
  final bool isManual; // Kullanıcı tarafından doğrudan ulaşıldı olarak işaretlendi mi?
  int? daysLeft;
  double? timeRatio;
  double? perDayNeeded;

  GoalStatus(this.goal, this.value, this.from, this.to, this.ignored, {this.isManual = false});

  double get ratio => goal.target <= 0 ? (isManual ? 1.0 : 0.0) : value / goal.target;
  bool get done => isManual || (goal.isLimit
      ? value <= goal.target + 1e-9
      : value >= goal.target - 1e-9);
  bool get isExceeded => !isManual && goal.isLimit && value > goal.target + 1e-9;
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

  /// [dim] null ise kayıt sayısı, değilse o boyuttaki miktar (temel birimde: L, dk, m, g...).
  double value(String? dim) => dim == null ? count.toDouble() : (byDim[dim] ?? 0);
}

/// Bir yol haritası adımının, bağlı aktivitesinin kayıtlarından gelen ilerlemesi.
class StepProgress {
  final double done;
  final double target;

  /// Hedefin birimi, adımda yazıldığı gibi ("dk", "bölüm"); hedefi yazılmamış adımda boştur.
  final String unit;

  const StepProgress(this.done, this.target, this.unit);

  bool get reached => done >= target - 1e-9;
  double get ratio => target <= 0 ? 1.0 : (done / target).clamp(0.0, 1.0);
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
  final Map<DateTime, int> dailyLevels; // 0..4 visual contribution level
  final Map<DateTime, String> dailyTooltips; // Formatted daily tooltip text

  /// Seri sayılarının birimi: günlük hedeflerde ve alışkanlıklarda gün, haftalık hedeflerde hafta,
  /// aylık hedeflerde ay sayılır.
  final GoalPeriod streakPeriod;

  const HabitStreakInfo({
    required this.currentStreak,
    required this.longestStreak,
    required this.totalActiveDays,
    required this.isDoneToday,
    required this.todayCount,
    required this.consistencyLast30,
    required this.dailyCounts,
    this.dailyLevels = const {},
    this.dailyTooltips = const {},
    this.streakPeriod = GoalPeriod.day,
  });
}

int daysBetween(DateTime a, DateTime b) =>
    (dayStart(b).difference(dayStart(a)).inHours / 24).round();

class AppStore extends ChangeNotifier {
  Database? _db;
  List<Unit> customUnits = [];
  List<Measure> measures = [];
  Map<int, Activity> activities = {};
  List<Entry> _entries = []; // ts'ye göre artan sıralı
  List<Entry> get entries => _entries;
  set entries(List<Entry> val) {
    _entries = val;
    _rebuildStats();
  }
  Map<int, List<Entry>> _entriesByActivity = {};

  /// Aktiviteye ait kayıtlar (ts artan sıralı). O(1) erişim sağlar.
  List<Entry> entriesForActivity(int activityId) {
    if (_entriesByActivity.isEmpty && _entries.isNotEmpty) {
      _rebuildStats();
    }
    return _entriesByActivity[activityId] ?? const [];
  }

  /// Aktivitenin en son kaydı.
  Entry? lastEntryForActivity(int activityId) {
    if (_entriesByActivity.isEmpty && _entries.isNotEmpty) {
      _rebuildStats();
    }
    return _entriesByActivity[activityId]?.lastOrNull;
  }

  List<Goal> goals = [];
  final Map<int, List<ActivityProperty>> _activityProperties = {};
  List<ActivityProperty> activityProperties(int activityId) =>
      List.unmodifiable(_activityProperties[activityId] ?? const []);
  ActivityProperty? findActivityProperty(int? id) {
    if (id == null) return null;
    for (final list in _activityProperties.values) {
      for (final p in list) {
        if (p.id == id) return p;
      }
    }
    return null;
  }
  List<QuickItem> quickItems = [];
  Map<int, ActivityStats> stats = {};
  ThemeMode themeMode = ThemeMode.system;
  String get themeModeString => themeMode == ThemeMode.dark ? 'dark' : (themeMode == ThemeMode.light ? 'light' : 'system');
  AppLanguage language = AppLanguage.tr;
  final appThemeNotifier = ValueNotifier<ThemeMode>(ThemeMode.system);
  final appLanguageNotifier = ValueNotifier<AppLanguage>(AppLanguage.tr);
  String timelineView = 'list'; // 'list' | 'grid'
  List<ActiveTimer> activeTimers = [];
  ActiveTimer? get activeTimer => activeTimers.firstOrNull;
  List<Roadmap> roadmaps = [];
  List<Roadmap> get activeRoadmaps => roadmaps.where((r) => r.isActive).toList();
  List<ActivityReminder> activityReminders = [];
  List<Routine> routines = [];
  List<Todo> todos = [];
  final ValueNotifier<String?> todoCompletedNotifier = ValueNotifier<String?>(null);
  final ValueNotifier<String?> unmeasuredFixMessageNotifier = ValueNotifier<String?>(null);
  final Set<String> _goalCheckins = {};
  bool loaded = false;

  bool waterReminderEnabled = false;
  int waterReminderIntervalHours = 2;
  bool dailySummaryReminderEnabled = false;
  String dailySummaryReminderTime = '21:30';
  bool timerSoundEnabled = true;
  bool timerAutoSaveCompleted = true;
  bool persistentQuickLogEnabled = false;

  bool stepTrackerEnabled = false;
  int stepDailyGoal = 10000;

  // BYOK (Kendi Anahtarını Getir) Yapay Zekâ Ayarları
  String llmProvider = 'gemini'; // 'gemini' | 'openai' | 'openrouter' | 'custom'
  String llmApiKey = '';
  String llmModel = '';
  String llmCustomEndpoint = '';

  bool get hasLlmKey => llmApiKey.trim().isNotEmpty;

  String get activeLlmModel => AiService.normalizeModelName(llmProvider, llmModel);

  String get llmProviderDisplayName {
    return switch (llmProvider) {
      'openai' => 'OpenAI',
      'openrouter' => 'OpenRouter',
      'custom' => 'Özel Uç Nokta',
      _ => 'Google Gemini',
    };
  }

  /// Bugünün adım sayısı. Sensör her adımda bildirim yollar; bu yüzden store'un tüm dinleyicilerini
  /// uyandırmak yerine yalnızca adım gösteren bileşenlerin dinlediği ayrı bir bildirici kullanılır.
  final stepsNotifier = ValueNotifier<int>(0);
  int get todaySteps => stepsNotifier.value;
  set todaySteps(int v) => stepsNotifier.value = v;
  String? stepSensorError;

  /// Adım sayar açık ama fiziksel aktivite izni yok: sensör hata vermeden susar, sayı hiç artmaz.
  bool stepPermissionMissing = false;

  // Sensör, telefon açıldığından beri atılan toplam adımı verir: günün ilk okuması taban alınır.
  // Elle eklenen adımlar ayrı tutulur, yoksa bir sonraki sensör okuması onları silerdi.
  String? _stepDay;
  int? _stepBaseline;
  int _stepManual = 0;
  int _stepPersisted = -1;
  DateTime? _stepPersistedAt;
  // Bu kopya adımları kendisi sayıyorsa (sensör okuması ya da elle ekleme aldıysa) true.
  bool _stepLive = false;

  /// Günlük ekranında kullanıcının kapattığı bölümler ('health', 'roadmap', 'routines').
  /// Rutinler ve Yol Haritası panelleri varsayılan olarak kapalıdır.
  Set<String> collapsedSections = {'routines', 'roadmap'};

  bool isSectionCollapsed(String id) => collapsedSections.contains(id);

  Future<void> toggleSection(String id) async {
    if (!collapsedSections.remove(id)) collapsedSections.add(id);
    notifyListeners();
    await _putSetting('today_collapsed', collapsedSections.join(','));
  }

  // Geçmiş günlerin adım sayıları (gün anahtarı -> adım).
  Map<String, int> _stepHistory = {};

  /// [day] gününün adım sayısı.
  int stepsOn(DateTime day) {
    final key = _stepDayKey(day);
    return key == _stepDay ? todaySteps : (_stepHistory[key] ?? 0);
  }

  // Adım ve uyku kayıtlarının yazıldığı aktiviteler (ayarlarda kimlikleriyle tutulur).
  int? _stepsActivityId;
  int? _sleepActivityId;
  int? _singleWidgetActivityId;
  int? get singleWidgetActivityId => _singleWidgetActivityId;

  bool sleepTrackerEnabled = false;
  double sleepDailyGoalHours = 8.0;
  int? sleepSessionStartTs;

  Future<Database> get db async => _db ??= await AppDb.open();

  /// Testler içindir: veritabanı bağlantısını bırakır; sonraki erişim geçerli veritabanı yolunu açar.
  @visibleForTesting
  Future<void> resetForTest() async {
    _timerTicker?.cancel();
    _timerTicker = null;
    await _db?.close();
    _db = null;
    loaded = false;
    _stepLive = false;
    _entries.clear();
    _entriesByActivity.clear();
    activities.clear();
    goals.clear();
    quickItems.clear();
    roadmaps.clear();
    measures.clear();
    customUnits.clear();
    stats.clear();
    _activityProperties.clear();
    activeTimers.clear();
    activityReminders.clear();
    routines.clear();
    llmProvider = 'gemini';
    llmApiKey = '';
    llmModel = '';
    llmCustomEndpoint = '';
  }

  // ---------------------------------------------------------------- yükleme

  /// Açılışta ve uygulama öne geldiğinde çağrılır: verileri okur, ardından bu sürece ait işleri kurar
  /// (sayaç bildirimi ve alarmları, hatırlatıcılar, adım sensörü, günlük otomatik yedek).
  Future<void> load() async {
    await _read();
    await fixUnmeasuredEntries();
    // Veriler okundu: bildirim, sensör ya da yedek tarafındaki bir hata uygulamayı açılmaz kılmasın.
    try {
      await _startServices();
    } catch (e, st) {
      debugPrint('Arka plan işleri kurulamadı: $e\n$st');
    }
  }

  /// Verileri veritabanından yeniden okur; load()'un kurduğu işlere dokunmaz. Bildirim aksiyonu ve widget
  /// isolate'ları her işten önce, arayüz de başka bir isolate veriyi değiştirdiğinde (StoreSync) bunu
  /// çağırır. O isolate'larda load() kullanılmaz: her aksiyonda hatırlatıcıları baştan planlar, yedek
  /// alır ve adım sensörünü ikinci bir yerden dinlemeye başlardı.
  Future<void> refresh() => _read();

  Future<void> _read() async {
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
    timerAutoSaveCompleted = settingsMap['timer_auto_save_completed'] != 'false';
    persistentQuickLogEnabled = settingsMap['persistent_quick_log_enabled'] == 'true';

    stepTrackerEnabled = settingsMap['step_tracker_enabled'] == 'true';
    stepDailyGoal = int.tryParse(settingsMap['step_daily_goal'] ?? '10000') ?? 10000;
    llmProvider = settingsMap['llm_provider'] ?? 'gemini';
    llmApiKey = settingsMap['llm_api_key'] ?? '';
    llmModel = settingsMap['llm_model'] ?? '';
    llmCustomEndpoint = settingsMap['llm_custom_endpoint'] ?? '';
    _stepsActivityId = int.tryParse(settingsMap['steps_activity_id'] ?? '');
    _sleepActivityId = int.tryParse(settingsMap['sleep_activity_id'] ?? '');
    _singleWidgetActivityId = int.tryParse(settingsMap['single_widget_activity_id'] ?? '');
    _stepHistory = {
      for (final e in settingsMap.entries)
        if (e.key.startsWith('step_today_')) e.key.substring('step_today_'.length): int.tryParse(e.value) ?? 0,
    };
    final now = DateTime.now();
    if (_stepLive) {
      // Adımları bu kopya sayıyor: bellekteki değer veritabanındakinden yenidir (her adım yazılmaz).
      // Yeniden okuma onu geri almaz; gün değiştiyse devri _rollStepDay yapar.
      await _rollStepDay(now);
    } else {
      final todayKey = _stepDayKey(now);
      _stepDay = todayKey;
      _stepBaseline = int.tryParse(settingsMap['step_baseline_$todayKey'] ?? '');
      _stepManual = int.tryParse(settingsMap['step_manual_$todayKey'] ?? '') ?? 0;
      todaySteps = int.tryParse(settingsMap['step_today_$todayKey'] ?? '0') ?? 0;
      _stepPersisted = todaySteps;
    }
    if (settingsMap['today_collapsed'] == null) {
      collapsedSections = {'routines', 'roadmap'};
    } else {
      collapsedSections = settingsMap['today_collapsed']!.split(',').where((x) => x.isNotEmpty).toSet();
      if (settingsMap['today_collapsed_v2'] == null) {
        collapsedSections.addAll(['routines', 'roadmap']);
        await _putSetting('today_collapsed_v2', '1');
        await _putSetting('today_collapsed', collapsedSections.join(','));
      }
    }

    sleepTrackerEnabled = settingsMap['sleep_tracker_enabled'] == 'true';
    sleepDailyGoalHours = double.tryParse(settingsMap['sleep_daily_goal_hours'] ?? '8.0') ?? 8.0;
    sleepSessionStartTs = int.tryParse(settingsMap['sleep_session_start_ts'] ?? '');

    _habitTargetDays.clear();
    for (final e in settingsMap.entries) {
      if (e.key.startsWith('habit_days_')) {
        final actId = int.tryParse(e.key.substring('habit_days_'.length));
        if (actId != null) {
          final days = e.value.split(',').map(int.tryParse).whereType<int>().toSet();
          if (days.isNotEmpty && days.length < 7) {
            _habitTargetDays[actId] = days;
          }
        }
      }
    }

    customUnits = (await d.query('units')).map(Unit.fromMap).toList();
    measures = (await d.query('measures', orderBy: 'sort, id')).map(Measure.fromMap).toList();
    activities = {
      for (final m in await d.query('activities')) m['id'] as int: Activity.fromMap(m),
    };
    final propRows = await d.query('activity_properties');
    _activityProperties.clear();
    for (final row in propRows) {
      final p = ActivityProperty.fromMap(row);
      (_activityProperties[p.activityId] ??= []).add(p);
    }
    entries = await _readEntries(d);
    _rebuildStats();
    final links = await d.query('goal_links');
    goals = (await d.query('goals', orderBy: 'sort, id')).map((m) {
      final g = Goal.fromMap(m);
      g.links = links.where((l) => l['goal_id'] == g.id).map(GoalLink.fromMap).toList();
      return g;
    }).toList();
    final checkinRows = await d.query('goal_checkins');
    _goalCheckins.clear();
    for (final row in checkinRows) {
      final gId = row['goal_id'] as int;
      final pKey = row['period_key'] as String;
      _goalCheckins.add('${gId}_$pKey');
    }
    quickItems =
        (await d.query('quick_items', orderBy: 'sort, id')).map(QuickItem.fromMap).toList();
    await _cleanupQuickItems();

    final timerRows = await d.query('active_timers', orderBy: 'id ASC');
    activeTimers = timerRows.map((r) {
      final t = ActiveTimer.fromMap(r);
      final prev = getTimer(t.id);
      final collapsed = _timerCollapsed[t.id] ?? prev?.isCollapsed ?? false;
      return t.copyWith(isCollapsed: collapsed);
    }).toList();
    _timerCollapsed.removeWhere((id, _) => !activeTimers.any((t) => t.id == id));

    final stepRows = await d.query('roadmap_steps', orderBy: 'step_order ASC, id ASC');
    final roadmapRows = await d.query('roadmaps', orderBy: 'created_at DESC, id DESC');
    roadmaps = roadmapRows.map((m) {
      final r = Roadmap.fromMap(m);
      r.steps = stepRows.where((s) => s['roadmap_id'] == r.id).map(RoadmapStep.fromMap).toList();
      return r;
    }).toList();

    final reminderRows = await d.query('activity_reminders');
    activityReminders = reminderRows.map(ActivityReminder.fromMap).toList();

    final routineRows = await d.query('routines', orderBy: 'sort ASC, id ASC');
    final routineItemRows = await d.query('routine_items', orderBy: 'sort ASC, id ASC');
    routines = routineRows.map((m) {
      final r = Routine.fromMap(m);
      r.items = routineItemRows
          .where((it) => it['routine_id'] == r.id)
          .map(RoutineItem.fromMap)
          .toList();
      return r;
    }).toList();

    final todoRows = await d.query('todos', orderBy: 'sort_order ASC, created_at ASC, id ASC');
    final todoLinkRows = await d.query('todo_links');
    todos = todoRows.map((m) {
      final t = Todo.fromMap(m);
      t.linkedActivityIds = todoLinkRows
          .where((l) => l['todo_id'] == t.id)
          .map((l) => l['activity_id'] as int)
          .toList();
      return t;
    }).toList();

    // Eski satırlarda (target_unit NULL) birimi bir kez hesaplayıp veritabanına yaz
    for (final t in todos) {
      if (t.targetAmount != null && (t.targetUnit == null || t.targetUnit!.isEmpty)) {
        final firstActId = t.linkedActivityIds.firstOrNull;
        Unit? titleUnit;
        final words = t.title.split(RegExp(r'\s+'));
        for (final w in words) {
          final u = _unitNamed(w);
          if (u != null) {
            titleUnit = u;
            break;
          }
        }
        final derivedUnit = titleUnit?.id ??
            (firstActId != null ? activityBaseUnit(firstActId) : 'adet');
        t.targetUnit = derivedUnit;
        await d.update('todos', {'target_unit': derivedUnit}, where: 'id = ?', whereArgs: [t.id]);
      }
    }

    loaded = true;
    // Kayıtlar başka bir yerde değişmiş olabilir (başka bir isolate, geri yüklenen yedek): adımlar sessizce
    // kayıtlara uydurulur.
    await _syncLinkedSteps(announce: false);
    await _syncTodos(announce: false);
    // Uygulama kapalıyken ya da arka plandayken süresi dolmuş geri sayımlar kaydedilir.
    await checkCompletedTimers();
    _ensureTimerTicker();
    _changed();
  }

  /// Verilerin kendisiyle ilgisi olmayan, sürece ait işler; yalnızca load() ile kurulur.
  Future<void> _startServices() async {
    await NotificationService.updateTimerNotification(activeTimers, activities);
    // Beklerken liste değişebilir (süresi dolan sayaç kaydedilip çıkar, bir başkası duraklatılır):
    // kimlikler gezilir, her sayacın güncel hâline bakılır.
    for (final id in activeTimers.map((t) => t.id).toList()) {
      final t = getTimer(id);
      if (t != null && t.isCountdown && t.isRunning && t.remainingMs > 0) {
        final actName = activities[t.activityId]?.name ?? 'Aktivite';
        await NotificationService.scheduleTimerAlarm(
          timerId: t.id,
          activityName: actName,
          remainingMs: t.remainingMs,
          isPomodoro: t.isPomodoro,
          soundEnabled: timerSoundEnabled,
          autoSaveEnabled: timerAutoSaveCompleted,
        );
      }
    }
    unawaited(NotificationService.scheduleReminders(this));
    if (persistentQuickLogEnabled) {
      unawaited(NotificationService.updatePersistentQuickLogNotification(this));
    }
    if (stepTrackerEnabled) {
      HealthTrackerService.instance.startStepTracking(this);
    }
    unawaited(BackupService.checkAndPerformDailyAutoBackup(this));
    await _checkStepPermission();
  }

  /// Adım sayar açıkken izin eksik mi diye bakar. İzin sonradan (telefonun ayarlarından) verildiyse
  /// sensör yeniden dinlenir: izinsiz kurulan dinleyiciye okuma gelmez.
  Future<void> _checkStepPermission() async {
    final missing = stepTrackerEnabled && !await HealthTrackerService.instance.hasStepPermission();
    if (missing == stepPermissionMissing) return;
    stepPermissionMissing = missing;
    if (!missing && stepTrackerEnabled) {
      HealthTrackerService.instance.stopStepTracking();
      HealthTrackerService.instance.startStepTracking(this);
    }
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    themeMode = mode;
    appThemeNotifier.value = mode;
    final d = await db;
    final val = mode == ThemeMode.dark ? 'dark' : (mode == ThemeMode.light ? 'light' : 'system');
    await d.insert('settings', {'key': 'theme', 'value': val}, conflictAlgorithm: ConflictAlgorithm.replace);
    notifyListeners();
    unawaited(WidgetSync.push());
  }

  Future<void> setLanguage(AppLanguage lang) async {
    language = lang;
    appLanguageNotifier.value = lang;
    strings.value = AppStrings(lang);
    final d = await db;
    final val = lang == AppLanguage.en ? 'en' : 'tr';
    await d.insert('settings', {'key': 'lang', 'value': val}, conflictAlgorithm: ConflictAlgorithm.replace);
    notifyListeners();
    // Planlanmış hatırlatıcılar ve süren sayaç bildirimi yeni dilde yeniden yazılır.
    unawaited(NotificationService.scheduleReminders(this));
    await NotificationService.updateTimerNotification(activeTimers, activities);
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

  Future<void> setTimerAutoSaveCompleted(bool enabled) async {
    timerAutoSaveCompleted = enabled;
    final d = await db;
    await d.insert('settings', {'key': 'timer_auto_save_completed', 'value': enabled.toString()},
        conflictAlgorithm: ConflictAlgorithm.replace);
    notifyListeners();
  }

  Future<void> setPersistentQuickLogEnabled(bool enabled) async {
    persistentQuickLogEnabled = enabled;
    final d = await db;
    await d.insert('settings', {'key': 'persistent_quick_log_enabled', 'value': enabled.toString()},
        conflictAlgorithm: ConflictAlgorithm.replace);
    if (enabled) {
      await NotificationService.updatePersistentQuickLogNotification(this);
    } else {
      await NotificationService.cancelPersistentQuickLogNotification();
    }
    notifyListeners();
  }

  /// Kendi Yapay Zekâ Anahtarını (BYOK) yapılandırır.
  Future<void> setLlmConfig({
    required String provider,
    required String apiKey,
    String? model,
    String? customEndpoint,
  }) async {
    llmProvider = provider;
    llmApiKey = apiKey.trim();
    llmModel = (model ?? '').trim();
    llmCustomEndpoint = (customEndpoint ?? '').trim();

    final d = await db;
    await d.insert('settings', {'key': 'llm_provider', 'value': llmProvider},
        conflictAlgorithm: ConflictAlgorithm.replace);
    await d.insert('settings', {'key': 'llm_api_key', 'value': llmApiKey},
        conflictAlgorithm: ConflictAlgorithm.replace);
    await d.insert('settings', {'key': 'llm_model', 'value': llmModel},
        conflictAlgorithm: ConflictAlgorithm.replace);
    await d.insert('settings', {'key': 'llm_custom_endpoint', 'value': llmCustomEndpoint},
        conflictAlgorithm: ConflictAlgorithm.replace);
    notifyListeners();
  }

  /// Kayıtlı Yapay Zekâ API anahtarını kaldırır (tamamen yerel/çevrimdışı moda döner).
  Future<void> clearLlmConfig() async {
    llmApiKey = '';
    llmModel = '';
    llmCustomEndpoint = '';
    final d = await db;
    await d.delete('settings', where: "key IN ('llm_api_key', 'llm_model', 'llm_custom_endpoint')");
    notifyListeners();
  }

  /// Kilit ekranı / bildirim kutusundan gelen serbest metni (veya sayaç komutunu) kaydeder.
  Future<String?> logFromQuickText(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;

    final multiResult = NaturalLanguageParser.parseMulti(
      trimmed,
      activities: activities.values.toList(),
      measures: measures,
      openTodos: todos,
      defaultMeasureFor: defaultMeasureFor,
      predictCompletedTodos: predictCompletedTodos,
    );

    if (multiResult.items.isEmpty) return null;

    // Açıkça gelecek bir zamanı gösteren kayıt öğeleri hızlı kayıtta yapılacak olarak eklenir
    final itemsToSave = multiResult.items.map((item) {
      if (item is EntryParsedItem && item.isExplicitFuture) {
        return item.toTodoItem();
      }
      return item;
    }).toList();

    // Tek öğeli sayaç komutuysa sayaç başlar
    if (itemsToSave.length == 1 && itemsToSave.first is EntryParsedItem) {
      final item = itemsToSave.first as EntryParsedItem;
      final command = item.timerCommand;
      if (command != null) {
        final act = item.activity ?? exactMatch(item.activityName) ?? await addActivity(item.activityName);
        await startTimer(act.id, mode: command.mode, targetMs: command.targetMs);
        final emoji = act.emoji != null && act.emoji!.trim().isNotEmpty ? '${act.emoji!.trim()} ' : '';
        final mins = command.targetMs ~/ 60000;
        final modeStr = switch (command.mode) {
          'pomodoro' => 'Pomodoro ($mins dk)',
          'countdown' => '$mins dk Geri Sayım',
          _ => strings.value.isTr ? 'Kronometre' : 'Stopwatch',
        };
        return strings.value.isTr ? '$emoji${act.name}: $modeStr başlatıldı' : '$emoji${act.name}: $modeStr started';
      }
    }

    final batchRes = await saveParsedItems(itemsToSave);
    final eCount = batchRes.entries.length;
    final tCount = batchRes.todos.length;

    if (eCount == 0 && tCount == 0) return null;

    if (eCount == 0 && tCount > 0) {
      return strings.value.isTr ? 'Yapılacaklara eklendi' : 'Added to To-dos';
    }

    if (eCount == 1 && tCount == 0) {
      final entry = batchRes.entries.first;
      final act = activities[entry.activityId];
      final emoji = act?.emoji != null && act!.emoji!.trim().isNotEmpty ? '${act.emoji!.trim()} ' : '';
      final amount = amountDetail(entry.measureId, entry.qty);
      final detail = amount.isEmpty ? '' : ' ($amount)';
      return strings.value.isTr ? '$emoji${act?.name ?? ""}$detail kaydedildi' : '$emoji${act?.name ?? ""}$detail logged';
    }

    if (eCount > 0 && tCount > 0) {
      return strings.value.isTr
          ? '$eCount kayıt, $tCount yapılacak eklendi'
          : '$eCount ${eCount == 1 ? "entry" : "entries"}, $tCount ${tCount == 1 ? "to-do" : "to-dos"} added';
    }

    return strings.value.isTr ? '$eCount kayıt eklendi' : '$eCount entries added';
  }

  /// Bildirimdeki hızlı butona tıklandığında ilgili aktiviteye son ölçüsüyle 1 adet kayıt ekler.
  Future<String?> logQuickActivity(int activityId) async {
    final act = activity(activityId);
    final defaultPhys = defaultPhysicalMeasureFor(activityId);
    final lastMId = stats[activityId]?.lastMeasureId ?? defaultPhys?.id;
    final now = DateTime.now();
    final m = measureById(lastMId) ?? defaultMeasureFor(activityId);
    final unitId = m?.unitId;
    DateTime effectiveAt = now;
    DateTime? effectiveEndAt;
    if (unitId == 'dk' || unitId == 'sa' || unitId == 'sn') {
      final durSecs = (m != null ? m.amount * (unitId == 'sa' ? 3600 : (unitId == 'dk' ? 60 : 1)) : 60).round();
      effectiveEndAt = now;
      effectiveAt = now.subtract(Duration(seconds: durSecs));
    }
    await addEntry(
      activityId,
      measureId: lastMId,
      qty: 1.0,
      at: effectiveAt,
      endAt: effectiveEndAt,
    );
    final emoji = act.emoji != null && act.emoji!.trim().isNotEmpty ? '${act.emoji!.trim()} ' : '';
    final amount = amountDetail(lastMId, 1.0);
    final detail = amount.isEmpty ? '' : ' ($amount)';
    return strings.value.isTr ? '$emoji${act.name}$detail kaydedildi' : '$emoji${act.name}$detail logged';
  }

  // ---------------------------------------------------------------- Sağlık & Sensör Takibi

  /// Adım sayarı açar ya da kapatır. Açılırken sensör izni istenir; verilmezse sayar kapalı kalır ve
  /// false döner.
  Future<bool> setStepTrackerEnabled(bool enabled) async {
    if (enabled && !await HealthTrackerService.instance.requestStepPermission()) {
      return false;
    }
    // İzin penceresi kapanınca uygulama öne gelir ve ayarlar yeniden okunur; o okuma eski değeri
    // geri yazmasın diye önce veritabanı, sonra bellek güncellenir.
    await _putSetting('step_tracker_enabled', enabled);
    stepTrackerEnabled = enabled;
    stepPermissionMissing = false;
    if (enabled) {
      HealthTrackerService.instance.startStepTracking(this);
    } else {
      HealthTrackerService.instance.stopStepTracking();
    }
    notifyListeners();
    return true;
  }

  /// Eksik izni ister ve dinleyiciyi baştan kurar. İzin yine verilmezse false döner.
  Future<bool> retryStepTracking() async {
    if (!await HealthTrackerService.instance.requestStepPermission()) return false;
    HealthTrackerService.instance.stopStepTracking();
    stepPermissionMissing = false;
    stepSensorError = null;
    notifyListeners();
    HealthTrackerService.instance.startStepTracking(this);
    return true;
  }

  Future<void> setStepDailyGoal(int goal) async {
    stepDailyGoal = goal;
    final d = await db;
    await d.insert('settings', {'key': 'step_daily_goal', 'value': goal.toString()},
        conflictAlgorithm: ConflictAlgorithm.replace);
    notifyListeners();
  }

  static String _stepDayKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _putSetting(String key, Object value) async {
    try {
      await (await db).insert('settings', {'key': key, 'value': '$value'}, conflictAlgorithm: ConflictAlgorithm.replace);
    } catch (_) {
      // Veritabanı başlatılmamış birim/arayüz testlerinde yazma hatasını yut
    }
  }

  Future<void> _deleteSetting(String key) async {
    try {
      await (await db).delete('settings', where: 'key = ?', whereArgs: [key]);
    } catch (_) {
      // Veritabanı başlatılmamış birim/arayüz testlerinde yazma hatasını yut
    }
  }

  /// Adım durumunu [now] gününe taşır. Gün uygulama açıkken değiştiyse son sensör okuması yeni günün
  /// tabanı olur; böylece gece yarısından sonraki adımlar kaybolmaz.
  Future<void> _rollStepDay(DateTime now) async {
    final day = _stepDayKey(now);
    if (_stepDay == day) return;
    final previousDay = _stepDay;
    final previousTotal = todaySteps;
    final unsaved = previousTotal != _stepPersisted;
    _stepBaseline = _stepBaseline == null ? null : _stepBaseline! + (todaySteps - _stepManual);
    _stepDay = day;
    _stepManual = 0;
    _stepPersisted = -1;
    todaySteps = 0;
    if (previousDay != null) _stepHistory[previousDay] = previousTotal;
    final carried = _stepBaseline;
    // Biten günün son değeri seyrek yazım yüzünden veritabanında eksik kalmış olabilir.
    if (previousDay != null && unsaved) {
      await _putSetting('step_today_$previousDay', previousTotal);
    }
    if (carried != null) await _putSetting('step_baseline_$day', carried);
  }

  /// Sensörün yeni okumasını işler ([totalSteps]: telefon açıldığından beri atılan adım).
  Future<void> handlePedometerStepEvent(int totalSteps, {DateTime? at}) async {
    final now = at ?? DateTime.now();
    _stepLive = true;
    final dayBefore = _stepDay;
    final baselineBefore = _stepBaseline;
    await _rollStepDay(now);

    final counted = todaySteps - _stepManual;
    if (_stepBaseline == null) {
      // Günün ilk okuması
      _stepBaseline = totalSteps - counted;
    } else if (totalSteps < _stepBaseline! + counted) {
      // Sayaç geriye gitti: telefon yeniden başlatılmış ve sensör sıfırdan sayıyor. O ana kadar
      // sayılanlar korunur.
      _stepBaseline = -counted;
    }
    if (_stepBaseline != baselineBefore || _stepDay != dayBefore) {
      await _putSetting('step_baseline_$_stepDay', _stepBaseline!);
    }

    final total = (totalSteps - _stepBaseline! + _stepManual).clamp(0, 500000);
    todaySteps = total;

    // Her adımda veritabanına yazmak gerekmez: değer sensörden yeniden hesaplanabilir.
    final dueByTime = _stepPersistedAt == null || now.difference(_stepPersistedAt!).inSeconds.abs() >= 15;
    if (total != _stepPersisted && ((total - _stepPersisted).abs() >= 25 || dueByTime)) {
      _stepPersisted = total;
      _stepPersistedAt = now;
      await _putSetting('step_today_$_stepDay', total);
    }

    if (stepSensorError != null) {
      stepSensorError = null;
      notifyListeners();
    }
  }

  void handlePedometerError(String error) {
    if (stepSensorError == error) return;
    stepSensorError = error;
    notifyListeners();
  }

  Future<void> addManualSteps(int delta, {DateTime? at}) async {
    final now = at ?? DateTime.now();
    _stepLive = true;
    await _rollStepDay(now);
    final counted = todaySteps - _stepManual;
    _stepManual = (_stepManual + delta).clamp(-counted, 500000 - counted);
    todaySteps = counted + _stepManual;
    _stepPersisted = todaySteps;
    _stepPersistedAt = now;
    await _putSetting('step_manual_$_stepDay', _stepManual);
    await _putSetting('step_today_$_stepDay', todaySteps);
  }

  /// Adım ya da uyku kayıtlarının yazıldığı aktivite; hiç oluşturulmadıysa null.
  /// Kimliği ayarlarda tutulur: ada göre aramak, aktivite yeniden adlandırılınca ya da dil değişince
  /// ikinci bir aktivite açıyordu. Kimliği tutmayan eski sürümlerin aktivitesi adıyla bulunur.
  Activity? _trackerActivity(int? savedId, List<String> legacyNames) =>
      activities[savedId] ?? activities.values.where((a) => legacyNames.contains(a.norm)).firstOrNull;

  Activity? get stepsActivity => _trackerActivity(_stepsActivityId, const ['adim', 'steps']);
  Activity? get sleepActivity => _trackerActivity(_sleepActivityId, const ['uyku', 'sleep']);

  Future<Activity> _ensureStepsActivity() async {
    final act = stepsActivity ??
        await addActivity(language == AppLanguage.en ? 'Steps' : 'Adım', emoji: '👟', category: 'sport');
    if (act.id != _stepsActivityId) {
      _stepsActivityId = act.id;
      await _putSetting('steps_activity_id', act.id);
    }
    return act;
  }

  Future<Activity> _ensureSleepActivity() async {
    final act = sleepActivity ??
        await addActivity(language == AppLanguage.en ? 'Sleep' : 'Uyku', emoji: '🛌', category: 'routine');
    if (act.id != _sleepActivityId) {
      _sleepActivityId = act.id;
      await _putSetting('sleep_activity_id', act.id);
    }
    return act;
  }

  Future<void> setSingleWidgetActivityId(int? actId) async {
    if (actId == null || actId == 0) {
      _singleWidgetActivityId = null;
      await _deleteSetting('single_widget_activity_id');
    } else {
      _singleWidgetActivityId = actId;
      await _putSetting('single_widget_activity_id', actId.toString());
    }
    notifyListeners();
  }

  String singleWidgetActivityLabel(AppStrings s) {
    if (_singleWidgetActivityId == null || _singleWidgetActivityId == 0) {
      return s.isTr ? 'Akıllı / Otomatik Öneri' : 'Smart / Auto Suggestion';
    }
    final act = activities[_singleWidgetActivityId];
    if (act == null) return s.isTr ? 'Akıllı / Otomatik Öneri' : 'Smart / Auto Suggestion';
    final emoji = act.emoji != null && act.emoji!.trim().isNotEmpty ? '${act.emoji!.trim()} ' : '';
    return '$emoji${act.name}';
  }

  Future<Entry?> syncTodayStepsToEntry({int? steps}) async {
    final count = steps ?? todaySteps;
    if (count <= 0) return null;

    final act = await _ensureStepsActivity();

    final now = DateTime.now();
    final start = dayStart(now);
    final end = dayEnd(now);

    final existing = entries.where((e) =>
        e.activityId == act.id &&
        !e.time.isBefore(start) &&
        e.time.isBefore(end)).firstOrNull;

    if (existing != null) {
      await updateEntry(
        existing,
        activityId: act.id,
        time: existing.time,
        qty: count.toDouble(),
        value: count.toDouble(),
        unitId: 'adet',
      );
      return existing;
    } else {
      final res = await addEntry(
        act.id,
        at: now,
        qty: count.toDouble(),
        value: count.toDouble(),
        unitId: 'adet',
      );
      return res.entry;
    }
  }

  Future<void> setSleepTrackerEnabled(bool enabled) async {
    sleepTrackerEnabled = enabled;
    final d = await db;
    await d.insert('settings', {'key': 'sleep_tracker_enabled', 'value': enabled.toString()},
        conflictAlgorithm: ConflictAlgorithm.replace);
    notifyListeners();
  }

  Future<void> setSleepDailyGoalHours(double hours) async {
    sleepDailyGoalHours = hours;
    final d = await db;
    await d.insert('settings', {'key': 'sleep_daily_goal_hours', 'value': hours.toString()},
        conflictAlgorithm: ConflictAlgorithm.replace);
    notifyListeners();
  }

  Future<void> startSleepSession({DateTime? at}) async {
    final startTime = at ?? DateTime.now();
    sleepSessionStartTs = startTime.millisecondsSinceEpoch;
    final d = await db;
    await d.insert('settings', {'key': 'sleep_session_start_ts', 'value': sleepSessionStartTs.toString()},
        conflictAlgorithm: ConflictAlgorithm.replace);
    try {
      await NotificationService.scheduleSleepWakeupReminder(this, startTime);
    } catch (_) {}
    notifyListeners();
  }

  Future<Entry?> stopSleepSession({DateTime? at, String? note}) async {
    if (sleepSessionStartTs == null) return null;
    final start = DateTime.fromMillisecondsSinceEpoch(sleepSessionStartTs!);
    final end = at ?? DateTime.now();
    final diffMins = end.difference(start).inMinutes;
    final mins = diffMins > 0 ? diffMins : 1;
    final hours = (mins / 60.0);

    final act = await _ensureSleepActivity();

    final m = measures.where((x) => x.unitId == 'sa').firstOrNull;

    final res = await addEntry(
      act.id,
      measureId: m?.id,
      qty: double.parse(hours.toStringAsFixed(2)),
      at: start,
      endAt: end,
      note: note,
    );

    sleepSessionStartTs = null;
    final d = await db;
    await d.delete('settings', where: 'key = ?', whereArgs: ['sleep_session_start_ts']);
    try {
      await NotificationService.cancelSleepWakeupReminder();
    } catch (_) {}
    notifyListeners();
    return res.entry;
  }

  Future<Entry> logManualSleep({required DateTime start, required DateTime end, String? note}) async {
    final diffMins = end.difference(start).inMinutes;
    final mins = diffMins > 0 ? diffMins : 1;
    final hours = (mins / 60.0);

    final act = await _ensureSleepActivity();

    final m = measures.where((x) => x.unitId == 'sa').firstOrNull;

    final res = await addEntry(
      act.id,
      measureId: m?.id,
      qty: double.parse(hours.toStringAsFixed(2)),
      at: start,
      endAt: end,
      note: note,
    );
    return res.entry;
  }

  /// [day] gününe yazılan uyku süresi (saat). Uyku, uyanılan güne aittir: 23:30'da yatılıp 07:00'de
  /// kalkılan gece ertesi günün uykusudur. Bitiş saati olmayan kayıtlar girildikleri güne yazılır.
  double getTodaySleepHours(DateTime day) {
    final act = sleepActivity;
    if (act == null) return 0.0;
    final start = dayStart(day);
    final end = addDays(start, 1);

    double totalHours = 0.0;
    // Bir önceki gün başlayan uykular da bu güne düşebilir.
    for (final e in entriesIn(subDays(start, 1), end)) {
      if (e.activityId != act.id) continue;
      final wake = e.endTs != null ? e.endTime! : e.time;
      if (wake.isBefore(start) || !wake.isBefore(end)) continue;

      if (e.duration != null && e.duration!.inMinutes > 0) {
        totalHours += e.duration!.inMinutes / 60.0;
      } else if (e.unitId == 'sa') {
        totalHours += (e.value ?? e.qty);
      } else if (e.unitId == 'dk') {
        totalHours += (e.value ?? e.qty) / 60.0;
      } else {
        totalHours += e.qty;
      }
    }
    return totalHours;
  }

  final Map<String, DaySummary> _daySummaryCache = {};
  final Map<int, HabitStreakInfo> _habitStreakCache = {};
  final Map<int, HabitStreakInfo> _goalStreakCache = {};

  void _changed() {
    _daySummaryCache.clear();
    _habitStreakCache.clear();
    _goalStreakCache.clear();
    _rebuildStats();
    notifyListeners();
  }

  void clearHabitStreakCache() {
    _habitStreakCache.clear();
    _goalStreakCache.clear();
  }

  void _rebuildStats() {
    final s = <int, ActivityStats>{};
    final byAct = <int, List<Entry>>{};
    final recentFrom = DateTime.now().subtract(const Duration(days: 30)).millisecondsSinceEpoch;
    for (final e in entries) {
      (byAct[e.activityId] ??= []).add(e);
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
    _entriesByActivity = byAct;
  }

  // ---------------------------------------------------------------- birimler

  // Hazır birimlerin adı ve kısaltması arayüz diline göre gelir; kimlikleri dilden bağımsızdır.
  List<Unit> get _builtinUnits => language == AppLanguage.en ? builtinUnitsEn : builtinUnits;

  List<Unit> get allUnits => [..._builtinUnits, ...customUnits];

  Unit unit(String id) {
    final lower = id.toLowerCase();
    return _builtinUnits.firstWhere(
      (u) => u.id == id || u.id.toLowerCase() == lower,
      orElse: () => customUnits.firstWhere(
        (u) => u.id == id || u.id.toLowerCase() == lower,
        orElse: () => Unit(id: id, name: id, symbol: id, dim: id, factor: 1),
      ),
    );
  }

  String dimName(String dim) => (language == AppLanguage.en ? dimNamesEn : dimNames)[dim] ?? unit(dim).name;

  String fmtBase(double base, String dim) => fmtAmount(base, dim, customUnit: unit(dim));

  Future<Unit> addUnit(String name, String symbol) async {
    final id = 'u${DateTime.now().millisecondsSinceEpoch}';
    final u = Unit(id: id, name: name, symbol: symbol, dim: id, factor: 1);
    await (await db).insert('units', u.toMap());
    customUnits.add(u);
    _changed();
    return u;
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
      activities[id] ?? Activity(id: id, name: strings.value.isTr ? '(silinmiş)' : '(deleted)', createdAt: 0);

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

  /// Yazarken veya boşken öneriler: zaman ve gün örüntüsü + benzerlik (arşivlenenler hariç).
  List<Activity> suggest(String text, {DateTime? now, int limit = 6}) {
    final q = normalizeTr(text);
    final currentTime = now ?? DateTime.now();
    if (q.isEmpty) return timeBasedSuggestions(now: currentTime, limit: limit);
    final scored = <(Activity, double)>[];
    for (final a in activities.values.where((a) => !a.isArchived)) {
      var s = matchScore(q, a.norm);
      if (s <= 0) continue;
      final st = stats[a.id];
      if (st != null) s += min(10, log(1 + st.count) * 2 + st.recent * 0.3);
      final affinity = TimeSuggestions.timeAffinity(a.id, entries, currentTime);
      s += affinity * 0.5;
      scored.add((a, s));
    }
    scored.sort((a, b) => b.$2.compareTo(a.$2));
    return scored.take(limit).map((e) => e.$1).toList();
  }

  /// Günün saati (±2 saatlik aralık), haftanın günü ve geçmiş sıklığa göre zaman bazlı akıllı öneriler.
  List<Activity> timeBasedSuggestions({DateTime? now, int limit = 8}) {
    return TimeSuggestions.compute(
      activities: activities,
      entries: entries,
      stats: stats,
      now: now,
      limit: limit,
    );
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

  /// Bir aktivitenin son kaydını aynı ölçü, miktar, birim ve notla aynen tekrar kaydeder.
  Future<String?> repeatLastEntry(int activityId, {DateTime? at}) async {
    final act = activities[activityId];
    if (act == null) return null;

    final last = lastEntryForActivity(activityId);
    final targetTime = at ?? DateTime.now();
    DateTime effectiveAt = targetTime;
    DateTime? effectiveEndAt;
    int? effectiveMeasureId;
    double? effectiveValue;
    String? effectiveUnitId;
    double effectiveQty = 1.0;

    if (last != null) {
      effectiveMeasureId = last.measureId;
      effectiveValue = last.value;
      effectiveUnitId = last.unitId;
      effectiveQty = last.qty;
    } else {
      final autoM = defaultPhysicalMeasureFor(activityId);
      if (autoM != null) {
        effectiveMeasureId = autoM.id;
        effectiveUnitId = autoM.unitId;
        effectiveValue = autoM.amount * effectiveQty;
      }
    }

    if (effectiveUnitId != null || effectiveMeasureId != null) {
      final m = measureById(effectiveMeasureId);
      final unitId = m?.unitId ?? effectiveUnitId;
      final val = effectiveValue ?? (m != null ? m.amount * effectiveQty : null);
      if ((unitId == 'dk' || unitId == 'sa' || unitId == 'sn') && val != null && val > 0) {
        final durSecs = (val * (unitId == 'sa' ? 3600 : (unitId == 'dk' ? 60 : 1))).round();
        effectiveEndAt = targetTime;
        effectiveAt = targetTime.subtract(Duration(seconds: durSecs));
      }
    }

    final added = (await addEntry(
      activityId,
      measureId: effectiveMeasureId,
      qty: effectiveQty,
      value: effectiveValue,
      unitId: effectiveUnitId,
      note: last?.note,
      at: effectiveAt,
      endAt: effectiveEndAt,
    )).entry;

    final emoji = act.emoji != null && act.emoji!.trim().isNotEmpty ? '${act.emoji!.trim()} ' : '';
    final isTr = strings.value.isTr;
    String msg;
    if (added.value != null && added.unitId != null) {
      final u = unit(added.unitId!);
      final amt = fmtAmount(added.value! * u.factor, u.dim, customUnit: u);
      msg = isTr ? '$emoji${act.name} tekrarlandı ($amt)' : '$emoji${act.name} repeated ($amt)';
    } else {
      msg = isTr ? '$emoji${act.name} tekrarlandı' : '$emoji${act.name} repeated';
    }

    if (persistentQuickLogEnabled && sameDay(targetTime, DateTime.now())) {
      await NotificationService.updatePersistentQuickLogNotification(this, lastLogMessage: msg);
    }
    return msg;
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

  Future<void> updateActivity(Activity a) async {
    if (_db != null) {
      await (await db).update('activities', a.toMap(), where: 'id=?', whereArgs: [a.id]);
    }
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

    // Bağlı hatırlatıcıların bildirimlerini iptal et
    final matchingReminders = activityReminders.where((r) => r.activityId == id).toList();
    for (final r in matchingReminders) {
      await NotificationService.cancelActivityReminder(r.id);
    }

    await d.transaction((tx) async {
      await tx.delete('entries', where: 'activity_id=?', whereArgs: [id]);
      await tx.delete('goal_links', where: 'activity_id=?', whereArgs: [id]);
      await tx.delete('todo_links', where: 'activity_id=?', whereArgs: [id]);
      await tx.delete('quick_items', where: 'activity_id=?', whereArgs: [id]);
      await tx.delete('activity_properties', where: 'activity_id=?', whereArgs: [id]);
      await tx.delete('activity_reminders', where: 'activity_id=?', whereArgs: [id]);
      await tx.delete('routine_items', where: 'activity_id=?', whereArgs: [id]);
      await tx.update('roadmap_steps', {'linked_activity_id': null}, where: 'linked_activity_id=?', whereArgs: [id]);
      await tx.delete('activities', where: 'id=?', whereArgs: [id]);
    });
    entries.removeWhere((e) => e.activityId == id);
    _activityProperties.remove(id);
    activityReminders.removeWhere((r) => r.activityId == id);
    for (final r in routines) {
      r.items.removeWhere((it) => it.activityId == id);
    }
    for (final r in roadmaps) {
      for (final step in r.steps) {
        if (step.linkedActivityId == id) step.linkedActivityId = null;
      }
    }
    for (final g in goals) {
      g.links.removeWhere((l) => l.activityId == id);
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final t in todos) {
      if (t.linkedActivityIds.remove(id)) {
        if (t.linkedActivityIds.isEmpty) {
          final wasDone = t.doneAt != null || t.manualState == 'done';
          t.manualState = null;
          t.doneAt = wasDone ? (t.doneAt ?? now) : null;
          await d.update('todos', {
            'done_at': t.doneAt,
            'manual_state': null,
          }, where: 'id = ?', whereArgs: [t.id]);
        }
      }
    }
    quickItems.removeWhere((q) => q.activityId == id);
    if (_singleWidgetActivityId == id) {
      _singleWidgetActivityId = null;
      await _deleteSetting('single_widget_activity_id');
    }
    activities.remove(id);
    _changed();
    try {
      await NotificationService.scheduleReminders(this);
    } catch (_) {}
  }

  /// [fromId] kayıtlarını [intoId] altına taşır ve [fromId]'yi siler (yazım hatalı tekrarları birleştirmek için).
  Future<void> mergeActivity(int fromId, int intoId) async {
    if (fromId == intoId) return;
    final d = await db;
    await d.transaction((tx) async {
      // Yalnızca aktivite sütunu yazılır: sayaç satırının tamamını bellekteki kopyadan yazmak, başka bir
      // isolate'ta yapılmış duraklatmayı ezerdi.
      await tx.update('active_timers', {'activity_id': intoId}, where: 'activity_id=?', whereArgs: [fromId]);
      await tx.update('roadmap_steps', {'linked_activity_id': intoId},
          where: 'linked_activity_id=?', whereArgs: [fromId]);
      await tx.update('settings', {'value': '$intoId'},
          where: "key IN ('steps_activity_id', 'sleep_activity_id', 'single_widget_activity_id') AND value=?", whereArgs: ['$fromId']);
      await tx.update('entries', {'activity_id': intoId}, where: 'activity_id=?', whereArgs: [fromId]);
      await tx.update('quick_items', {'activity_id': intoId},
          where: 'activity_id=?', whereArgs: [fromId]);

      // Özellikler (aynı isimli özellik varsa hedefteki korunur, çiftler tekilleşir)
      final existingProps = await tx.query('activity_properties', where: 'activity_id=?', whereArgs: [intoId]);
      final existingPropNames = existingProps.map((p) => (p['name'] as String).toLowerCase()).toSet();
      final fromProps = await tx.query('activity_properties', where: 'activity_id=?', whereArgs: [fromId]);
      for (final p in fromProps) {
        final pName = (p['name'] as String).toLowerCase();
        if (existingPropNames.contains(pName)) {
          await tx.delete('activity_properties', where: 'id=?', whereArgs: [p['id']]);
        } else {
          await tx.update('activity_properties', {'activity_id': intoId}, where: 'id=?', whereArgs: [p['id']]);
        }
      }

      // Hatırlatıcılar (aynı saat ve günlerde olanlar tekilleştirilir)
      final existingReminders = await tx.query('activity_reminders', where: 'activity_id=?', whereArgs: [intoId]);
      final fromReminders = await tx.query('activity_reminders', where: 'activity_id=?', whereArgs: [fromId]);
      for (final r in fromReminders) {
        final rId = r['id'] as int;
        final rTime = r['time'] as String;
        final rDays = (r['days_of_week'] as String?) ?? '1,2,3,4,5,6,7';
        final isDuplicate = existingReminders.any((er) => er['time'] == rTime && ((er['days_of_week'] as String?) ?? '1,2,3,4,5,6,7') == rDays);
        if (isDuplicate) {
          await NotificationService.cancelActivityReminder(rId);
          await tx.delete('activity_reminders', where: 'id=?', whereArgs: [rId]);
        } else {
          await tx.update('activity_reminders', {'activity_id': intoId}, where: 'id=?', whereArgs: [rId]);
        }
      }

      // Rutin öğeleri (aynı rutinde hedef aktivite zaten varsa çiftler tekilleştirilir)
      final routineItemRows = await tx.query('routine_items', orderBy: 'routine_id, id');
      final itemsByRoutine = <int, List<Map<String, Object?>>>{};
      for (final row in routineItemRows) {
        final rId = row['routine_id'] as int;
        itemsByRoutine.putIfAbsent(rId, () => []).add(row);
      }
      for (final entry in itemsByRoutine.entries) {
        final rItems = entry.value;
        final hasInto = rItems.any((it) => it['activity_id'] == intoId);
        final fromMatches = rItems.where((it) => it['activity_id'] == fromId).toList();
        for (final it in fromMatches) {
          if (hasInto) {
            await tx.delete('routine_items', where: 'id=?', whereArgs: [it['id']]);
          } else {
            await tx.update('routine_items', {'activity_id': intoId}, where: 'id=?', whereArgs: [it['id']]);
          }
        }
      }

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
      for (final t in todos) {
        final hasFrom = t.linkedActivityIds.contains(fromId);
        final hasInto = t.linkedActivityIds.contains(intoId);
        if (hasFrom && !hasInto) {
          await tx.update('todo_links', {'activity_id': intoId},
              where: 'todo_id=? AND activity_id=?', whereArgs: [t.id, fromId]);
        } else if (hasFrom) {
          await tx.delete('todo_links',
              where: 'todo_id=? AND activity_id=?', whereArgs: [t.id, fromId]);
        }
      }
      await tx.delete('activities', where: 'id=?', whereArgs: [fromId]);
    });
    await load();
    try {
      await NotificationService.scheduleReminders(this);
    } catch (_) {}
  }

  /// Aktiviteye ait ek bir özellik (örn: kalori, sıvı hacmi, kafein vb.) kaydeder veya günceller.
  Future<ActivityProperty> saveActivityProperty(ActivityProperty prop) async {
    final d = await db;
    if (prop.id == 0) {
      prop.id = await d.insert('activity_properties', prop.toMap());
    } else {
      await d.update('activity_properties', prop.toMap(), where: 'id = ?', whereArgs: [prop.id]);
    }
    final list = _activityProperties[prop.activityId] ??= [];
    final idx = list.indexWhere((p) => p.id == prop.id);
    if (idx >= 0) {
      list[idx] = prop;
    } else {
      list.add(prop);
    }
    _changed();
    return prop;
  }

  /// Aktivite özelliğini siler ve hedeflerdeki bu özelliğe bağlı linkleri temizler.
  Future<void> deleteActivityProperty(int id) async {
    final d = await db;
    await d.delete('activity_properties', where: 'id = ?', whereArgs: [id]);
    await d.update('goal_links', {'property_id': null}, where: 'property_id = ?', whereArgs: [id]);
    for (final g in goals) {
      for (final l in g.links) {
        if (l.propertyId == id) l.propertyId = null;
      }
    }
    for (final list in _activityProperties.values) {
      list.removeWhere((p) => p.id == id);
    }
    _changed();
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

  Future<List<Entry>> _readEntries(DatabaseExecutor d) async =>
      (await d.query('entries', orderBy: 'ts, id')).map(Entry.fromMap).toList();

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
          actVolumes[e.activityId] = (actVolumes[e.activityId] ?? 0) + liters;
        }
      }
    }

    final summary = DaySummary(
      date: dayStart(day),
      count: list.length,
      totalTimeMinutes: totalTimeMinutes,
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

  /// Henüz kaydedilmemiş bir kaydın miktar yazımı (giriş kutusunun önizlemesi). Kayıt eklendiğinde
  /// [entryDetail] aynı metni gösterir.
  String amountDetail(int? measureId, double qty, {int? activityId}) {
    final m = measureById(measureId) ?? (measureId == null && activityId != null ? defaultMeasureFor(activityId) : null);
    return entryDetail(Entry(
      id: 0,
      activityId: activityId ?? 0,
      ts: 0,
      measureId: m?.id,
      qty: qty,
      value: m != null ? m.amount * qty : null,
      unitId: m?.unitId,
    ));
  }

  /// Yeni tamamlanan hedefleri ve yeni aşılan limitleri bildirim olarak gösterir.
  void _notifyGoalChanges(List<Goal> achieved, List<Goal> exceeded) {
    final isTr = strings.value.isTr;
    for (final g in exceeded) {
      NotificationService.showLimitAlert(
        isTr ? '⚠️ Limit Aşıldı!' : '⚠️ Limit Exceeded!',
        isTr ? '${g.name} limitinizi aştınız.' : 'You went over your ${g.name} limit.',
      );
    }
    for (final g in achieved) {
      NotificationService.showLimitAlert(
        isTr ? '🎯 Hedefe Ulaşıldı!' : '🎯 Goal Reached!',
        isTr ? 'Tebrikler! ${g.name} hedefini tamamladınız.' : 'Well done! You completed ${g.name}.',
      );
    }
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
    if (calculatedEndTs == null && (finalUnitId == 'dk' || finalUnitId == 'sa' || finalUnitId == 'sn') && finalValue != null && finalValue > 0) {
      final durationSecs = (finalValue * (finalUnitId == 'sa' ? 3600 : (finalUnitId == 'dk' ? 60 : 1))).round();
      calculatedEndTs = time.add(Duration(seconds: durationSecs)).millisecondsSinceEpoch;
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
    await _syncLinkedSteps();
    await _syncTodos();
    final afterDone = _doneTargetGoalIds(activityId, time);
    final afterExceeded = _exceededLimitGoalIds(activityId, time);
    final achieved = goals.where((g) => afterDone.contains(g.id) && !beforeDone.contains(g.id)).toList();
    final exceeded = goals.where((g) => afterExceeded.contains(g.id) && !beforeExceeded.contains(g.id)).toList();
    _notifyGoalChanges(achieved, exceeded);
    return AddResult(e, achieved, exceeded: exceeded);
  }

  /// Aktivite için varsayılan ölçüyü döner (kısayol, son kullanım veya birim boyutundan).
  Measure? defaultMeasureFor(int activityId) {
    if (!activities.containsKey(activityId)) return null;

    // 1. Kısayollar (QuickItems): kullanıcının bu aktivite için özellikle seçtiği ölçü
    for (final q in quickItems) {
      if (q.activityId == activityId && q.measureId != null) {
        final m = measureById(q.measureId);
        if (m != null) return m;
      }
    }

    // 2. Son kullanılan ölçü (stats.lastMeasureId)
    final lastMId = stats[activityId]?.lastMeasureId;
    if (lastMId != null) {
      final m = measureById(lastMId);
      if (m != null) return m;
    }

    // 3. Daha önce bu aktiviteyle kullanılmış ölçüler (en sık kullanılan)
    final (usedMeasures, otherMeasures) = measuresFor(activityId);
    if (usedMeasures.isNotEmpty) return usedMeasures.first;

    // 4. Aktivitenin özelliklerine veya birimine/boyutuna göre uygun ilk ölçü
    final baseUnit = activityBaseUnit(activityId);
    final targetDim = unit(baseUnit).dim;
    final actNorm = activity(activityId).norm;

    if (actNorm.contains('kahve')) {
      final coffeeM = measures.where((m) {
        final mn = normalizeTr(m.name);
        return mn.contains('fincan') || mn.contains('kupa');
      }).firstOrNull;
      if (coffeeM != null) return coffeeM;
    }
    if (actNorm.contains('cay')) {
      final teaM = measures.where((m) => normalizeTr(m.name).contains('cay')).firstOrNull;
      if (teaM != null) return teaM;
    }
    if (actNorm == 'su' || actNorm.startsWith('su ') || actNorm.endsWith(' su')) {
      final waterM = measures.where((m) {
        final mn = normalizeTr(m.name);
        return mn.contains('su bardag') || mn == 'bardak';
      }).firstOrNull;
      if (waterM != null) return waterM;
    }

    for (final m in measures) {
      if (unit(m.unitId).dim == targetDim) return m;
    }

    if (targetDim == 'count') {
      final adetM = measures.where((m) => m.unitId == 'adet').firstOrNull;
      if (adetM != null) return adetM;
    }

    for (final m in otherMeasures) {
      if (unit(m.unitId).dim == targetDim) return m;
    }
    return null;
  }

  /// Ayrıştırılmış öğeleri (kayıtlar ve yapılacaklar) tek bir toplu işlemde (batch) kaydeder.
  Future<BatchSaveResult> saveParsedItems(
    List<ParsedItem> items, {
    String? note,
    int? overrideMeasureId,
    bool hasMeasureOverride = false,
    double? overrideQty,
    String? draftEmoji,
  }) async {
    final entriesToSave = <BatchEntryInput>[];
    final todosToSave = <BatchTodoInput>[];
    final createdActivityIds = <int>[];

    for (final item in items) {
      if (item is EntryParsedItem) {
        Activity act;
        if (item.activity != null) {
          act = item.activity!;
        } else {
          final existing = exactMatch(item.activityName);
          if (existing != null) {
            act = existing;
          } else {
            act = await addActivity(item.activityName, emoji: draftEmoji);
            if (!createdActivityIds.contains(act.id)) {
              createdActivityIds.add(act.id);
            }
          }
        }
        if (draftEmoji != null && draftEmoji.isNotEmpty && (act.emoji == null || act.emoji!.isEmpty)) {
          act.emoji = draftEmoji;
          final d = await db;
          await d.update('activities', {'emoji': draftEmoji}, where: 'id = ?', whereArgs: [act.id]);
        }

        final defMeasureId = defaultMeasureFor(act.id)?.id;
        final mId = (hasMeasureOverride || overrideMeasureId != null)
            ? overrideMeasureId
            : (item.measure?.id ?? defMeasureId);
        final q = overrideQty ?? item.quantity;

        entriesToSave.add(
          BatchEntryInput(
            activityId: act.id,
            measureId: mId,
            qty: q > 0 ? q : 1.0,
            at: item.at,
            endAt: item.endAt,
            note: note,
          ),
        );
      } else if (item is TodoParsedItem) {
        todosToSave.add(
          BatchTodoInput(
            title: item.title,
            dueDate: item.dueDate,
            linkedActivityId: item.suggestedActivity?.id,
            targetAmount: item.suggestedAmount,
            targetUnit: item.suggestedUnit,
          ),
        );
      }
    }

    if (entriesToSave.isEmpty && todosToSave.isEmpty) {
      return BatchSaveResult(entries: const [], todos: const [], achievedGoals: const [], undo: () async {});
    }

    return saveBatch(
      entries: entriesToSave,
      todos: todosToSave,
      createdActivityIds: createdActivityIds,
    );
  }

  /// Çoklu kayıt ve yapılacakları tek bir SQLite transaction'ında yazar.
  /// Bildirim ve widget senkronizasyonu tek bir kez çalışır.
  Future<BatchSaveResult> saveBatch({
    List<BatchEntryInput> entries = const [],
    List<BatchTodoInput> todos = const [],
    List<int> createdActivityIds = const [],
  }) async {
    final d = await db;
    final createdEntries = <Entry>[];
    final createdTodos = <Todo>[];

    // Önceki hedef durumları
    final beforeDoneMap = <int, Set<int>>{};
    final beforeExceededMap = <int, Set<int>>{};
    for (final input in entries) {
      beforeDoneMap[input.activityId] = _doneTargetGoalIds(input.activityId, input.at);
      beforeExceededMap[input.activityId] = _exceededLimitGoalIds(input.activityId, input.at);
    }

    await d.transaction((tx) async {
      for (final input in entries) {
        final time = input.at;
        final m = measureById(input.measureId);
        final finalUnitId = m?.unitId;
        final finalValue = m != null ? m.amount * input.qty : null;

        int? calculatedEndTs = input.endAt?.millisecondsSinceEpoch;
        DateTime effectiveTime = time;
        if (calculatedEndTs == null &&
            (finalUnitId == 'dk' || finalUnitId == 'sa' || finalUnitId == 'sn') &&
            finalValue != null &&
            finalValue > 0) {
          final durationSecs =
              (finalValue * (finalUnitId == 'sa' ? 3600 : (finalUnitId == 'dk' ? 60 : 1))).round();
          effectiveTime = time;
          calculatedEndTs = time.add(Duration(seconds: durationSecs)).millisecondsSinceEpoch;
        }

        final e = Entry(
          id: 0,
          activityId: input.activityId,
          ts: effectiveTime.millisecondsSinceEpoch,
          endTs: calculatedEndTs,
          measureId: m?.id,
          qty: input.qty,
          value: finalValue,
          unitId: finalUnitId,
          note: (input.note?.trim().isEmpty ?? true) ? null : input.note!.trim(),
        );

        e.id = await tx.insert('entries', e.toMap()..remove('id'));
        createdEntries.add(e);
      }

      for (final tInput in todos) {
        final dueStr = tInput.dueDate != null ? DateFormat('yyyy-MM-dd').format(tInput.dueDate!) : null;
        final actIds = tInput.linkedActivityId != null ? [tInput.linkedActivityId!] : <int>[];
        String? targetUnit = tInput.targetUnit;
        if (tInput.targetAmount != null && (targetUnit == null || targetUnit.isEmpty)) {
          final firstActId = actIds.firstOrNull;
          targetUnit = firstActId != null ? activityBaseUnit(firstActId) : 'adet';
        }

        final todo = Todo(
          id: 0,
          title: tInput.title,
          dueDate: dueStr,
          targetAmount: tInput.targetAmount,
          targetUnit: targetUnit,
          createdAt: DateTime.now().millisecondsSinceEpoch,
          linkedActivityIds: actIds,
        );

        todo.id = await tx.insert('todos', todo.toMap()..remove('id'));
        for (final actId in actIds) {
          await tx.insert('todo_links', {'todo_id': todo.id, 'activity_id': actId});
        }
        createdTodos.add(todo);
      }
    });

    for (final e in createdEntries) {
      _insertSorted(e);
    }
    this.todos.addAll(createdTodos);

    _changed();
    await _syncLinkedSteps();
    await _syncTodos(announce: false);
    WidgetSync.schedule();

    // Hedef değişimleri
    final achieved = <Goal>[];
    final exceeded = <Goal>[];
    for (final e in createdEntries) {
      final afterDone = _doneTargetGoalIds(e.activityId, e.time);
      final afterExceeded = _exceededLimitGoalIds(e.activityId, e.time);
      final beforeDone = beforeDoneMap[e.activityId] ?? const {};
      final beforeExceeded = beforeExceededMap[e.activityId] ?? const {};

      for (final g in goals) {
        if (afterDone.contains(g.id) && !beforeDone.contains(g.id) && !achieved.any((a) => a.id == g.id)) {
          achieved.add(g);
        }
        if (afterExceeded.contains(g.id) && !beforeExceeded.contains(g.id) && !exceeded.any((x) => x.id == g.id)) {
          exceeded.add(g);
        }
      }
    }
    _notifyGoalChanges(achieved, exceeded);

    Future<void> undo() async {
      await d.transaction((tx) async {
        for (final e in createdEntries) {
          await tx.delete('entries', where: 'id = ?', whereArgs: [e.id]);
        }
        for (final t in createdTodos) {
          await tx.delete('todo_links', where: 'todo_id = ?', whereArgs: [t.id]);
          await tx.delete('todos', where: 'id = ?', whereArgs: [t.id]);
        }
      });

      for (final e in createdEntries) {
        this.entries.removeWhere((x) => x.id == e.id);
      }
      for (final t in createdTodos) {
        this.todos.removeWhere((x) => x.id == t.id);
      }

      if (createdActivityIds.isNotEmpty) {
        for (final actId in createdActivityIds) {
          final hasOtherEntries = this.entries.any((e) => e.activityId == actId);
          if (!hasOtherEntries && activities.containsKey(actId)) {
            await deleteActivity(actId);
          }
        }
      }

      _changed();
      await _syncLinkedSteps();
      await _syncTodos(announce: false);
      WidgetSync.schedule();
    }

    return BatchSaveResult(
      entries: createdEntries,
      todos: createdTodos,
      achievedGoals: achieved,
      exceededGoals: exceeded,
      undo: undo,
    );
  }

  /// Kayıt düzenleme penceresindeki ölçü seçicinin bildirdiği (ölçü, miktar) seçimini [updateEntry]'ye
  /// verilecek hâle getirir. Seçici, çip bırakılınca miktarı 1'e çeker; ölçüsü olmayan ya da ölçüsü silinmiş
  /// bir kaydın miktarı ise pencerede düzenlenemez. Böyle bir kayıtta çipin bırakılması kaydın kendi ölçü
  /// ve miktarına dönmek demektir; yoksa o 1, kaydın değerini ezerdi (8.500 adım -> 1 adet).
  (int?, double) entryEditSelection(Entry e, int? pickedMeasureId, double pickedQty) =>
      pickedMeasureId == null && measureById(e.measureId) == null
          ? (e.measureId, e.qty)
          : (pickedMeasureId, pickedQty);

  static const _unset = Object();

  /// Kayıt düzenleme formundaki veya yapılacak dönüştürme işlemindeki güncel alanlara göre
  /// kaydın alacağı durumu (aktivite, zaman, miktar, ölçü, birim, not ve bitiş zamanı) hesaplar.
  /// [updateEntry] ve [convertEntryToTodo] aynı kuralları kullanır:
  /// - Ölçü seçildiyse onun değeri ve birimi kullanılır.
  /// - Değer veya birim doğrudan verildiyse o geçerlidir.
  /// - Aktivite değişmediyse ve ölçü seçimi değişmediyse (ör. adım veya sayaç kaydı) mevcut değer ölçeklenir.
  /// - Aktivite değiştiyse veya ölçü bilerek kaldırıldıysa eski miktar ve birim sıfırlanır.
  /// - Bitiş zamanı açıkça verilmediyse veya süre ölçüsü seçilmediyse kaydın mevcut bitiş zamanı korunur.
  ({
    int activityId,
    DateTime time,
    int ts,
    int? measureId,
    double qty,
    double? value,
    String? unitId,
    String? note,
    int? endTs,
  }) resolveEntryState(
    Entry e, {
    int? activityId,
    DateTime? time,
    Object? measureId = _unset,
    double? qty,
    Object? note = _unset,
    DateTime? endAt,
    int? endTs,
    double? value,
    String? unitId,
  }) {
    final effectiveActId = activityId ?? e.activityId;
    final effectiveTime = time ?? e.time;
    final effectiveMeasureId = identical(measureId, _unset) ? e.measureId : (measureId as int?);
    final effectiveQty = qty ??
        ((effectiveActId != e.activityId || (e.measureId != null && effectiveMeasureId == null))
            ? 1.0
            : e.qty);
    final effectiveNote = identical(note, _unset)
        ? e.note
        : ((note as String?)?.trim().isEmpty ?? true ? null : (note as String).trim());

    int? resolvedMeasureId;
    double? resolvedValue;
    String? resolvedUnitId;
    final resolvedQty = effectiveQty;

    final m = measureById(effectiveMeasureId);
    if (m != null) {
      resolvedMeasureId = m.id;
      resolvedValue = m.amount * resolvedQty;
      resolvedUnitId = m.unitId;
    } else if (value != null || unitId != null) {
      // Değer ve birim açıkça verildi (ör. adım senkronu)
      resolvedMeasureId = null;
      resolvedValue = value;
      resolvedUnitId = unitId;
    } else if (effectiveActId == e.activityId && effectiveMeasureId == e.measureId && e.value != null) {
      // Aynı aktivitede ölçü seçimi değişmedi ama ölçünün kendisi yok (silinmiş ya da hiç
      // olmamış: sayaç ve adım kayıtları): anlık görüntüyü koru, değeri miktarla orantılı ölçekle
      resolvedMeasureId = e.measureId;
      resolvedValue = e.qty != 0 ? (e.value! / e.qty * resolvedQty) : e.value;
      resolvedUnitId = e.unitId;
    } else {
      // Ölçü bilerek kaldırıldı ya da aktivite değiştiğinde eski aktivitenin ölçüsü/değeri sıfırlandı
      resolvedMeasureId = null;
      resolvedValue = null;
      resolvedUnitId = null;
    }

    int? resolvedEndTs;
    if (endTs != null) {
      resolvedEndTs = endTs;
    } else if (endAt != null) {
      resolvedEndTs = endAt.millisecondsSinceEpoch;
    } else if ((resolvedUnitId == 'dk' || resolvedUnitId == 'sa') && resolvedValue != null && resolvedValue > 0) {
      final durationMins = (resolvedValue * (resolvedUnitId == 'sa' ? 60 : 1)).round();
      resolvedEndTs = effectiveTime.add(Duration(minutes: durationMins)).millisecondsSinceEpoch;
    } else {
      resolvedEndTs = e.endTs;
    }

    return (
      activityId: effectiveActId,
      time: effectiveTime,
      ts: effectiveTime.millisecondsSinceEpoch,
      measureId: resolvedMeasureId,
      qty: resolvedQty,
      value: resolvedValue,
      unitId: resolvedUnitId,
      note: effectiveNote,
      endTs: resolvedEndTs,
    );
  }

  Future<void> updateEntry(
    Entry e, {
    required int activityId,
    required DateTime time,
    int? measureId,
    double qty = 1,
    String? note,
    DateTime? endAt,
    int? endTs,
    double? value,
    String? unitId,
  }) async {
    final state = resolveEntryState(
      e,
      activityId: activityId,
      time: time,
      measureId: measureId,
      qty: qty,
      note: note,
      endAt: endAt,
      endTs: endTs,
      value: value,
      unitId: unitId,
    );

    e.activityId = state.activityId;
    e.measureId = state.measureId;
    e.qty = state.qty;
    e.value = state.value;
    e.unitId = state.unitId;
    e.note = state.note;
    if (state.ts != e.ts) {
      entries.remove(e);
      e.ts = state.ts;
      _insertSorted(e);
    }
    e.endTs = state.endTs;

    await (await db).update('entries', e.toMap(), where: 'id=?', whereArgs: [e.id]);
    _changed();
    await _syncLinkedSteps();
    await _syncTodos();
  }

  Future<void> deleteEntry(Entry e) async {
    await (await db).delete('entries', where: 'id=?', whereArgs: [e.id]);
    entries.removeWhere((x) => x.id == e.id);
    _changed();
    await _syncLinkedSteps();
    await _syncTodos();
  }

  Future<void> restoreEntry(Entry e) async {
    if (!activities.containsKey(e.activityId)) return;
    await (await db).insert('entries', e.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
    entries.removeWhere((x) => x.id == e.id);
    _insertSorted(e);
    _changed();
    await _syncLinkedSteps();
    await _syncTodos();
  }

  /// Kaydın yapılacağa çevrilebilir olup olmadığını belirler.
  /// Otomatik adım ve uyku kayıtları yapılacağa çevrilemez.
  bool canConvertEntryToTodo(Entry e) {
    if (stepsActivity != null && e.activityId == stepsActivity!.id) return false;
    if (sleepActivity != null && e.activityId == sleepActivity!.id) return false;
    return true;
  }

  /// Kaydı doğrudan bir yapılacağa çevirir:
  /// Aktivite ve miktar bilgilerinden hedef ve başlık türetilir, tek transaction ile
  /// yapılacak eklenip kayıt silinir. Geri al işlemi kaydı birebir geri yükler ve yapılacağı siler.
  /// Sayfada henüz kaydedilmemiş değişiklikler opsiyonel parametrelerle aktarılır; kayıt nesnesi
  /// mutate edilmez.
  Future<({Todo todo, Future<void> Function() undo})> convertEntryToTodo(
    Entry entry, {
    int? activityId,
    DateTime? time,
    Object? measureId = _unset,
    double? qty,
    Object? note = _unset,
    DateTime? endAt,
    int? endTs,
  }) async {
    final state = resolveEntryState(
      entry,
      activityId: activityId,
      time: time,
      measureId: measureId,
      qty: qty,
      note: note,
      endAt: endAt,
      endTs: endTs,
    );

    final act = activity(state.activityId);
    final d = await db;

    double? targetAmount;
    String? targetUnit;

    final m = measureById(state.measureId);

    // Hedef sırası:
    // 1. Ölçü veya değer varsa o
    if (m != null) {
      final mUnit = unit(m.unitId);
      if (mUnit.id == 'sn') {
        targetAmount = state.value;
        targetUnit = 'sn';
      } else if (mUnit.dim == 'time') {
        targetAmount = m.unitId == 'sa' ? (state.value! * 60) : state.value;
        targetUnit = 'dk';
      } else {
        targetAmount = state.value;
        targetUnit = m.unitId.isNotEmpty ? m.unitId : m.name;
      }
    } else if (state.value != null && state.unitId != null) {
      final vUnit = unit(state.unitId!);
      if (vUnit.dim == 'time') {
        targetAmount = state.unitId == 'sa' ? (state.value! * 60) : state.value;
        targetUnit = 'dk';
      } else {
        targetAmount = state.value;
        targetUnit = state.unitId;
      }
    } else if (state.endTs != null && state.endTs! > state.ts) {
      // 2. Yoksa süresi (endTs)
      final durMins = ((state.endTs! - state.ts) / 60000).round();
      if (durMins > 0) {
        targetAmount = durMins.toDouble();
        targetUnit = 'dk';
      }
    } else if (state.qty > 0 && state.qty != 1.0) {
      // 3. Yoksa adedi
      targetAmount = state.qty;
      targetUnit = state.unitId ?? activityBaseUnit(act.id);
    }

    final actName = act.name;
    final String title;
    if (targetAmount != null && targetUnit != null) {
      final sym = unit(targetUnit).symbol;
      title = '${fmtNum(targetAmount)} $sym $actName'.trim();
    } else {
      title = actName;
    }

    final todo = Todo(
      id: 0,
      title: title,
      note: state.note,
      createdAt: DateTime.now().millisecondsSinceEpoch,
      targetAmount: targetAmount,
      targetUnit: targetUnit,
      linkedActivityIds: [state.activityId],
    );

    int insertedTodoId = 0;
    await d.transaction((tx) async {
      insertedTodoId = await tx.insert('todos', todo.toMap()..remove('id'));
      await tx.insert('todo_links', {'todo_id': insertedTodoId, 'activity_id': state.activityId});
      await tx.delete('entries', where: 'id = ?', whereArgs: [entry.id]);
    });

    todo.id = insertedTodoId;
    todos.add(todo);
    entries.removeWhere((e) => e.id == entry.id);

    _changed();
    await _syncLinkedSteps();
    await _syncTodos();
    WidgetSync.schedule();

    Future<void> undo() async {
      final dbInst = await db;
      await dbInst.transaction((tx) async {
        await tx.delete('todo_links', where: 'todo_id = ?', whereArgs: [todo.id]);
        await tx.delete('todos', where: 'id = ?', whereArgs: [todo.id]);
        await tx.insert('entries', entry.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
      });

      todos.removeWhere((t) => t.id == todo.id);
      entries.removeWhere((e) => e.id == entry.id);
      _insertSorted(entry);

      _changed();
      await _syncLinkedSteps();
      await _syncTodos();
      WidgetSync.schedule();
    }

    return (todo: todo, undo: undo);
  }

  // ---------------------------------------------------------------- kronometre

  ActiveTimer? getTimer(int id) =>
      activeTimers.where((t) => t.id == id).firstOrNull;

  ActiveTimer? getTimerForActivity(int activityId) =>
      activeTimers.where((t) => t.activityId == activityId).firstOrNull;

  // Sayaç kartlarının açık/kapalı durumu yalnızca arayüz durumudur ve sayaç listesinden ayrı tutulur;
  // böylece load() listeyi yenilediğinde kaybolmaz. Kullanıcı bir kartı elle değiştirmedikçe, birden
  // fazla sayaç varken kartlar tek satırlık kompakt görünümde durur.
  final Map<int, bool> _timerCollapsed = {};

  bool isTimerCollapsed(ActiveTimer timer) =>
      _timerCollapsed[timer.id] ?? timer.isCollapsed || (activeTimers.length > 1);

  void toggleTimerCollapse(int id) {
    final timer = getTimer(id);
    if (timer == null) return;
    final next = !isTimerCollapsed(timer);
    _timerCollapsed[id] = next;
    final idx = activeTimers.indexWhere((t) => t.id == id);
    if (idx != -1) {
      activeTimers[idx] = activeTimers[idx].copyWith(isCollapsed: next);
    }
    notifyListeners();
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
        autoSaveEnabled: timerAutoSaveCompleted,
      );
    }
    _ensureTimerTicker();
    notifyListeners();
    return timer;
  }

  /// Sayaç satırını veritabanından taze okur. Sayaçlar bildirim aksiyonu ve widget isolate'larında da
  /// değişebildiği için bellekteki kopya bayat olabilir; karar veritabanındaki satıra göre verilir.
  Future<ActiveTimer?> _readTimerRow(DatabaseExecutor ex, int id) async {
    final rows = await ex.query('active_timers', where: 'id=?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    // isCollapsed yalnızca bellekte tutulan arayüz durumudur
    return ActiveTimer.fromMap(rows.first).copyWith(isCollapsed: getTimer(id)?.isCollapsed);
  }

  /// Bellekteki kopyayı veritabanındaki güncel hâlle eşitler ([fresh] null ise sayaç artık yok).
  /// Bu kopyanın hâlâ bildiği bir sayaç veritabanında yoksa onu başka bir isolate bitirmiştir; yazdığı
  /// kayıtlar burada eksik olacağından kayıtlar da yeniden okunur.
  Future<void> _syncTimer(int id, ActiveTimer? fresh) async {
    final idx = activeTimers.indexWhere((t) => t.id == id);
    if (fresh != null) {
      if (idx != -1) {
        activeTimers[idx] = fresh;
      } else {
        activeTimers.add(fresh);
      }
      return;
    }
    if (idx == -1) return;
    activeTimers.removeAt(idx);
    entries = await _readEntries(await db);
    _changed();
  }

  /// Sayacı tek transaction içinde taze okuyup [change] ile günceller ve belleği sonuçla eşitler.
  /// [change] null dönerse satır olduğu gibi kalır. Güncel sayacı döner (satır yoksa null).
  Future<ActiveTimer?> _updateTimerRow(int id, ActiveTimer? Function(ActiveTimer current) change) async {
    final d = await db;
    ActiveTimer? result;
    await d.transaction((tx) async {
      final current = await _readTimerRow(tx, id);
      if (current == null) return;
      final updated = change(current);
      if (updated != null) {
        await tx.update('active_timers', updated.toMap(), where: 'id=?', whereArgs: [id]);
      }
      result = updated ?? current;
    });
    await _syncTimer(id, result);
    return result;
  }

  Future<void> pauseTimer([int? id]) async {
    final timerId = id ?? activeTimers.where((t) => t.isRunning).firstOrNull?.id;
    if (timerId == null) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    var paused = false;
    await _updateTimerRow(timerId, (timer) {
      if (!timer.isRunning) return null;
      final last = timer.lastResumeTs;
      final diff = last != null ? (now - last).clamp(0, 1000000000) : 0;
      final segs = List<TimerSegment>.from(timer.segments);
      if (last != null && now > last) {
        segs.add(TimerSegment(startTs: last, endTs: now));
      }
      paused = true;
      return timer.copyWith(
        accumulatedMs: timer.accumulatedMs + diff,
        isRunning: false,
        clearLastResumeTs: true,
        segments: segs,
      );
    });

    if (paused) await NotificationService.cancelTimerAlarm(timerId);
    await NotificationService.updateTimerNotification(activeTimers, activities);
    _ensureTimerTicker();
    notifyListeners();
  }

  Future<void> resumeTimer([int? id]) async {
    final timerId = id ?? activeTimers.where((t) => !t.isRunning).firstOrNull?.id;
    if (timerId == null) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    final timer = await _updateTimerRow(
      timerId,
      (timer) => timer.isRunning ? null : timer.copyWith(lastResumeTs: now, isRunning: true),
    );

    await NotificationService.updateTimerNotification(activeTimers, activities);
    if (timer != null && timer.isRunning && timer.isCountdown && timer.remainingMs > 0) {
      final actName = activities[timer.activityId]?.name ?? 'Aktivite';
      await NotificationService.scheduleTimerAlarm(
        timerId: timer.id,
        activityName: actName,
        remainingMs: timer.remainingMs,
        isPomodoro: timer.isPomodoro,
        soundEnabled: timerSoundEnabled,
        autoSaveEnabled: timerAutoSaveCompleted,
      );
    }
    _ensureTimerTicker();
    notifyListeners();
  }

  /// Sayacın notunu değiştirir; boş metin notu siler. Yalnızca not alanı, veritabanındaki güncel satırın
  /// üzerine yazılır: satırın tamamını bellekteki kopyadan yazmak, başka bir isolate'ta yapılmış
  /// duraklatmayı geri alıyordu.
  Future<void> updateTimerNote(dynamic idOrNote, [String? note]) async {
    final int? timerId;
    final String? noteText;
    if (idOrNote is int) {
      timerId = idOrNote;
      noteText = note;
    } else {
      timerId = activeTimer?.id;
      noteText = idOrNote as String?;
    }
    if (timerId == null) return;

    final text = noteText?.trim() ?? '';
    await _updateTimerRow(timerId, (timer) => text.isEmpty ? timer.copyWith(clearNote: true) : timer.copyWith(note: text));
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
    bool cancelAlarmNotification = false,
  ]) =>
      _finishTimer(id, splitChoice, cancelAlarmNotification);

  /// Biten sayaçtan yazılacak kayıtları üretir (gece yarısında bölünürse iki kayıt).
  List<Entry> _timerEntries(ActiveTimer timer, MidnightSplitChoice splitChoice) {
    final actId = timer.activityId;
    final note = timer.note;
    final startTime = timer.startTime;
    final endTime = DateTime.now();

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
      final isCompletedCountdown = timer.isCountdown && timer.isTargetReached;
      final totalMs = isCompletedCountdown ? timer.targetMs : timer.elapsedMs;
      final (finalUnitId, finalQty, measureId) = _calculateTimerUnitAndQty(totalMs);
      final recordTime = splitChoice == MidnightSplitChoice.endDay ? endTime : startTime;
      final m = measureById(measureId) ?? (measureId == null ? defaultMeasureFor(actId) : null);
      final calculatedEndTs = isCompletedCountdown
          ? startTime.add(Duration(milliseconds: timer.targetMs)).millisecondsSinceEpoch
          : endTime.millisecondsSinceEpoch;

      entriesToSave.add(Entry(
        id: 0,
        activityId: actId,
        ts: recordTime.millisecondsSinceEpoch,
        endTs: calculatedEndTs,
        measureId: measureId,
        qty: finalQty,
        value: m != null ? m.amount * finalQty : finalQty,
        unitId: m?.unitId ?? finalUnitId,
        note: note,
      ));
    }

    return entriesToSave;
  }

  /// [onlyIfCompleted] otomatik kayıt içindir: sayaç veritabanında hâlâ çalışan ve hedefine ulaşmış bir
  /// geri sayım değilse (ör. bildirimden duraklatılmışsa) kayıt yazmadan döner.
  Future<AddResult?> _finishTimer(
    int? id,
    MidnightSplitChoice splitChoice,
    bool cancelAlarmNotification, {
    bool onlyIfCompleted = false,
  }) async {
    final timerId = id ?? activeTimer?.id;
    if (timerId == null) return null;

    final d = await db;
    ActiveTimer? current;
    var finished = false;
    var beforeDone = <int>{};
    var beforeExceeded = <int>{};
    final createdEntries = <Entry>[];

    // Atomik SQLite işlemi: sayaç satırı taze okunur, kayıtlar yazılır ve sayaç aynı transaction'da silinir.
    // Satır yoksa sayacı başka bir çağrı ya da başka bir isolate zaten bitirmiştir; ikinci kayıt yazılmaz.
    await d.transaction((tx) async {
      final timer = await _readTimerRow(tx, timerId);
      current = timer;
      if (timer == null) return;
      if (onlyIfCompleted && !(timer.isCountdown && timer.isRunning && timer.isTargetReached)) return;

      final entriesToSave = _timerEntries(timer, splitChoice);
      if (entriesToSave.isEmpty) return;

      beforeDone = _doneTargetGoalIds(timer.activityId, timer.startTime);
      beforeExceeded = _exceededLimitGoalIds(timer.activityId, timer.startTime);
      for (final raw in entriesToSave) {
        raw.id = await tx.insert('entries', raw.toMap()..remove('id'));
        createdEntries.add(raw);
      }
      await tx.delete('active_timers', where: 'id=?', whereArgs: [timerId]);
      finished = true;
    });

    final timer = current;
    if (timer == null || !finished) {
      // Kayıt yazılmadı: bellekteki kopyayı veritabanındaki durumla eşitle.
      await _syncTimer(timerId, timer);
      await NotificationService.updateTimerNotification(activeTimers, activities);
      _ensureTimerTicker();
      notifyListeners();
      return null;
    }

    // Veritabanı başarılı oldu -> belleği hemen güncelle; araya giren bir load() ile çakışmasın.
    activeTimers.removeWhere((t) => t.id == timerId);
    for (final e in createdEntries) {
      _insertSorted(e);
    }
    _changed();
    await _syncLinkedSteps();
    await _syncTodos();

    // Hedef henüz tamamlanmadan manuel bitirildiyse veya açıkça istenmişse alarmı iptal et.
    // Ancak süre bitip otomatik kaydedildiyse bildirim ekranda kalmaya devam etsin!
    final shouldCancelAlarm = cancelAlarmNotification || !timer.isTargetReached;
    if (shouldCancelAlarm) {
      await NotificationService.cancelTimerAlarm(timerId);
    }
    await NotificationService.updateTimerNotification(activeTimers, activities);
    _ensureTimerTicker();

    // Hedef ve limit durumlarını kontrol et
    final actId = timer.activityId;
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

    _notifyGoalChanges(achieved, exceeded);

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
    _ensureTimerTicker();
    notifyListeners();
  }

  Future<void> discardTimer([int? id]) => cancelTimer(id);

  Timer? _timerTicker;

  void _ensureTimerTicker() {
    if (activeTimers.any((t) => t.isRunning)) {
      if (_timerTicker == null || !_timerTicker!.isActive) {
        _timerTicker = Timer.periodic(const Duration(seconds: 1), (_) {
          _onTimerTick();
        });
      }
    } else {
      _timerTicker?.cancel();
      _timerTicker = null;
    }
  }

  void _onTimerTick() {
    if (!activeTimers.any((t) => t.isRunning)) {
      _timerTicker?.cancel();
      _timerTicker = null;
      return;
    }

    if (timerAutoSaveCompleted &&
        activeTimers.any((t) => t.isCountdown && t.isRunning && t.isTargetReached)) {
      checkCompletedTimers();
    }
  }

  Future<void> checkCompletedTimers() async {
    if (!timerAutoSaveCompleted) return;

    final completed = activeTimers
        .where((t) => t.isCountdown && t.isRunning && t.isTargetReached)
        .toList();
    for (final timer in completed) {
      final act = activities[timer.activityId];
      final actName = act?.name ?? 'Aktivite';

      // Otomatik bitir ve kaydet (tamamlama bildirimi açık kalacak şekilde)
      final saved = await _finishTimer(timer.id, MidnightSplitChoice.startDay, false, onlyIfCompleted: true);
      // Sayacı bu arada başka bir çağrı ya da isolate bitirmiş/duraklatmışsa bildirimi tekrarlama.
      if (saved == null) continue;

      // Bildirimin bildirim çekmecesinde görünmeye devam etmesini sağla
      await NotificationService.showTimerCompletedNotification(
        timerId: timer.id,
        activityName: actName,
        isPomodoro: timer.isPomodoro,
        soundEnabled: timerSoundEnabled,
      );

      if (timerSoundEnabled) {
        try {
          HapticFeedback.heavyImpact();
          SystemSound.play(SystemSoundType.alert);
        } catch (_) {}
      }
    }
  }

  // ---------------------------------------------------------------- istatistik

  Map<int, PeriodTotal> totalsByActivity(DateTime from, DateTime to) {
    final res = <int, PeriodTotal>{};
    for (final e in entriesIn(from, to)) {
      res.putIfAbsent(e.activityId, PeriodTotal.new).add(e, e.unitId == null ? null : unit(e.unitId!));
    }
    return res;
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
  double? contribution(Goal g, Entry e, double pct, {GoalLink? link}) {
    final f = pct / 100;
    if (g.isCount) return f;

    final gu = unit(g.unitId ?? 'adet');

    // 1. Hedef bağlantısında özel seçilmiş özellik (propertyId) var mı?
    ActivityProperty? targetProp;
    if (link?.propertyId != null) {
      targetProp = findActivityProperty(link!.propertyId);
    }

    // 2. Eğer kullanıcı hedef bağlantısında belirli bir özellik SEÇMEMİŞSE (propertyId == null):
    // Önce kaydın doğrudan değerinin hedefin boyutuna uyup uymadığına bakalım.
    // Eğer kayıt birimliyse ve boyutu hedef boyutuyla aynıysa (örn: 200 ml vişne suyu -> Litre sıvı alımı hedefi),
    // doğrudan kayıt değeri baz alınır (özelliklere zorla yönlendirilmez).
    if (targetProp == null) {
      if (gu.dim == 'time' && e.duration != null && e.duration!.inMilliseconds > 0) {
        final mins = e.duration!.inMilliseconds / 60000.0;
        return mins * (unit('dk').factor / gu.factor) * f * (link?.customRate ?? 1.0);
      }
      if (e.unitId != null && e.value != null) {
        final eu = unit(e.unitId!);
        if (eu.dim == gu.dim) {
          // Doğrudan kayıt değeri üzerinden katkı
          return e.value! * (eu.factor / gu.factor) * f * (link?.customRate ?? 1.0);
        }
      } else if (gu.dim == 'count') {
        // Hedef adet/sayı boyutunda ve kayıt da ölçüsüz/sayı
        return (e.value ?? e.qty) * f / gu.factor;
      }

      // Kayıt doğrudan hedef boyutuna uymuyorsa (örn: kayıt 200 ml veya 1 adet, ama hedef Kalori/kcal veya C Vitamini/mg):
      // Aktivitenin hedef boyutuna uyan bir özelliği var mı bakalım.
      final props = activityProperties(e.activityId);
      for (final p in props) {
        if (unit(p.unitId).dim == gu.dim) {
          targetProp = p;
          break;
        }
      }
    }

    // 3. Eğer hedef için bir özellik belirlenmişse (veya boyut uyumundan türetilmişse):
    if (targetProp != null) {
      final pu = unit(targetProp.unitId);
      // Hedef birimi ile özellik biriminin boyutu uyuşmalı (örn: ikisi de enerji, ikisi de kütle vb.)
      if (pu.dim != gu.dim) return null;

      final propFactor = pu.factor / gu.factor;
      final perQty = targetProp.perQty > 0 ? targetProp.perQty : 1.0;
      final perUnit = targetProp.perUnitId != null ? unit(targetProp.perUnitId!) : null;

      // Kaydın miktar/değer ölçeklemesi:
      double scale = e.qty;

      if (e.value != null && e.unitId != null) {
        final eu = unit(e.unitId!);
        // Durum A: Özelliğin tanımlandığı temel birim (perUnit) kaydın birimiyle aynı boyutta mı?
        // (örn: Vişne Suyu özellikleri 100 ml için tanımlanmış ve kayıt 200 ml girilmiş)
        if (perUnit != null && perUnit.dim == eu.dim) {
          final baseDimVal = perQty * perUnit.factor;
          final entryDimVal = e.value! * eu.factor;
          if (baseDimVal > 0) {
            scale = entryDimVal / baseDimVal;
          }
        } else if (perUnit == null || perUnit.dim == 'count') {
          // Durum B: Özellik "adet" (porsiyon) başına tanımlanmış (örn: 1 porsiyon/bardak için 76 kcal veya 200 ml hacim).
          // Ancak kayıt ml veya gram olarak girilmiş (örn: 500 ml Ayran).
          if (pu.dim == eu.dim && targetProp.value > 0) {
            final baseDimVal = (targetProp.value / perQty) * pu.factor;
            final entryDimVal = e.value! * eu.factor;
            scale = entryDimVal / baseDimVal;
          } else {
            // Aktivitenin kaydın boyutunda başka bir özelliği var mı? (örn: Kalori hedefi için Hacim = 200 ml / adet)
            final props = activityProperties(e.activityId);
            ActivityProperty? dimProp;
            for (final p in props) {
              if (p.id != targetProp.id && unit(p.unitId).dim == eu.dim) {
                dimProp = p;
                break;
              }
            }
            if (dimProp != null && dimProp.value > 0) {
              final du = unit(dimProp.unitId);
              final dimPerQty = dimProp.perQty > 0 ? dimProp.perQty : 1.0;
              final baseDimVal = (dimProp.value / dimPerQty) * du.factor;
              final entryDimVal = e.value! * eu.factor;
              scale = entryDimVal / baseDimVal;
            }
          }
        }
      } else {
        // Kaydın doğrudan ölçü değeri yok, adet (qty) üzerinden girilmiş.
        // Özellik 1 adetten farklı bir perQty'ye sahipse (örn: perQty = 100 ml),
        // ve aktivitenin varsayılan ölçüsü (measure) varsa onu kullanabiliriz:
        if (perUnit != null && perUnit.dim != 'count') {
          final (usedMeasures, otherMeasures) = measuresFor(e.activityId);
          final defMeasure = usedMeasures.firstOrNull ?? otherMeasures.firstOrNull;
          if (defMeasure != null && unit(defMeasure.unitId).dim == perUnit.dim) {
            final entryDimVal = e.qty * defMeasure.amount * unit(defMeasure.unitId).factor;
            final baseDimVal = perQty * perUnit.factor;
            if (baseDimVal > 0) {
              scale = entryDimVal / baseDimVal;
            }
          } else {
            scale = e.qty / perQty;
          }
        } else {
          scale = e.qty / perQty;
        }
      }

      final result = (scale * targetProp.value) * propFactor * f * (link?.customRate ?? 1.0);
      return result;
    }

    // 4. Klasik doğrudan birim/değer eşleşmesi
    if (e.unitId == null || e.value == null) {
      if (gu.dim == 'count') return (e.value ?? e.qty) * f / gu.factor;
      if (e.unitId == null && (e.value != null || e.qty > 0) && (gu.dim == 'time' || activityBaseUnit(e.activityId) == gu.id)) {
        return (e.value ?? e.qty) * f * (link?.customRate ?? 1.0);
      }
      return null;
    }
    final eu = unit(e.unitId!);
    if (eu.dim != gu.dim) return null;
    return e.value! * (eu.factor / gu.factor) * f * (link?.customRate ?? 1.0);
  }

  (double, int) goalValue(Goal g, DateTime from, DateTime? to, {Map<int, double>? byActivity}) {
    final linkMap = {for (final l in g.links) l.activityId: l};
    var v = 0.0;
    var ignored = 0;
    if (to != null && !to.isAfter(from)) return (0, 0);
    for (final e in entriesIn(from, to)) {
      final link = linkMap[e.activityId];
      if (link == null) continue;
      final c = contribution(g, e, link.pct, link: link);
      if (c == null) {
        ignored++;
      } else {
        v += c;
        if (byActivity != null) byActivity[e.activityId] = (byActivity[e.activityId] ?? 0) + c;
      }
    }
    return (v, ignored);
  }

  /// Bir hedefin periyoduna ve tarihine göre tekil dönem anahtarı (örn: '2026-10-18', 'w_2026-10-12', 'm_2026_10', 'total').
  String goalPeriodKey(Goal g, DateTime at) {
    switch (g.period) {
      case GoalPeriod.day:
        return dayKey(at);
      case GoalPeriod.week:
        return 'w_${dayKey(weekStart(at))}';
      case GoalPeriod.month:
        return 'm_${at.year}_${at.month.toString().padLeft(2, '0')}';
      case GoalPeriod.total:
        return 'total';
    }
  }

  /// Hedefe belirtilen dönemde doğrudan (elle) ulaşıldı işareti verilip verilmediği.
  bool isGoalCheckinDone(Goal g, {DateTime? at}) {
    final key = goalPeriodKey(g, at ?? DateTime.now());
    return _goalCheckins.contains('${g.id}_$key');
  }

  /// Hedefe ulaşıldı durumunu doğrudan açar / kapatır (aktivite kaydı gerektirmeden tamamlama).
  Future<bool> toggleGoalCheckin(Goal g, {DateTime? at, bool? done}) async {
    final targetDate = at ?? DateTime.now();
    final key = goalPeriodKey(g, targetDate);
    final lookup = '${g.id}_$key';
    final currentlyDone = _goalCheckins.contains(lookup);
    final makeDone = done ?? !currentlyDone;

    if (currentlyDone == makeDone) return makeDone;

    final d = await db;
    if (makeDone) {
      _goalCheckins.add(lookup);
      await d.insert(
        'goal_checkins',
        {
          'goal_id': g.id,
          'period_key': key,
          'created_at': targetDate.millisecondsSinceEpoch,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } else {
      _goalCheckins.remove(lookup);
      await d.delete(
        'goal_checkins',
        where: 'goal_id = ? AND period_key = ?',
        whereArgs: [g.id, key],
      );
    }
    _changed();
    await _syncLinkedSteps();
    return makeDone;
  }

  GoalStatus goalStatus(Goal g, {DateTime? at, Map<int, double>? byActivity}) {
    final now = DateTime.now();
    final targetDate = at ?? now;
    final (from, to) = goalRange(g, targetDate);
    var (v, ign) = goalValue(g, from, to, byActivity: byActivity);
    final isManual = isGoalCheckinDone(g, at: targetDate);
    if (isManual && !g.isLimit && v < g.target) {
      v = g.target > 0 ? g.target : 1.0;
    }
    final st = GoalStatus(g, v, from, to, ign, isManual: isManual);
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

  String goalUnitSymbol(Goal g) => g.isCount ? timesWord : unit(g.unitId ?? 'adet').symbol;

  String goalValueText(Goal g, double v) => '${fmtNum(v)} ${g.isCount ? timesUnit(v) : goalUnitSymbol(g)}';

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
    await _syncLinkedSteps();
  }

  Future<void> deleteGoal(Goal g) async {
    final d = await db;
    await d.delete('goal_links', where: 'goal_id=?', whereArgs: [g.id]);
    await d.delete('goal_checkins', where: 'goal_id=?', whereArgs: [g.id]);
    await d.delete('goals', where: 'id=?', whereArgs: [g.id]);
    _goalCheckins.removeWhere((k) => k.startsWith('${g.id}_'));
    goals.removeWhere((x) => x.id == g.id);
    _changed();
    await _syncLinkedSteps();
  }

  Future<void> reorderGoals(int oldIndex, int newIndex) async {
    if (oldIndex < 0 || oldIndex >= goals.length) return;
    if (newIndex < 0 || newIndex >= goals.length) return;
    final item = goals.removeAt(oldIndex);
    goals.insert(newIndex, item);
    final d = await db;
    final batch = d.batch();
    for (var i = 0; i < goals.length; i++) {
      final g = goals[i];
      g.sort = i;
      batch.update('goals', {'sort': g.sort}, where: 'id=?', whereArgs: [g.id]);
    }
    await batch.commit(noResult: true);
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
  Future<void> setActivityGoals(
    int activityId,
    Map<int, double?> goalPcts, {
    Map<int, int?>? goalProperties,
    Map<int, double?>? goalCustomRates,
  }) async {
    for (final entry in goalPcts.entries) {
      final goalId = entry.key;
      final pct = entry.value;
      final g = goals.where((x) => x.id == goalId).firstOrNull;
      if (g == null) continue;
      final existingLink = g.links.where((l) => l.activityId == activityId).firstOrNull;
      g.links.removeWhere((l) => l.activityId == activityId);
      if (pct != null && pct > 0) {
        final propId = goalProperties != null && goalProperties.containsKey(goalId)
            ? goalProperties[goalId]
            : existingLink?.propertyId;
        final customRate = goalCustomRates != null && goalCustomRates.containsKey(goalId)
            ? goalCustomRates[goalId]
            : existingLink?.customRate;
        g.links.add(GoalLink(
          activityId: activityId,
          pct: pct,
          propertyId: propId,
          customRate: customRate,
        ));
      }
      await saveGoal(g);
    }
    _changed();
  }

  // ---------------------------------------------------------------- zinciri kırma (habit tracker)

  final Map<int, Set<int>> _habitTargetDays = {};

  /// Alışkanlığın planlandığı haftalık günler (1 = Pazartesi .. 7 = Pazar).
  /// Boş veya null ise "her gün" geçerlidir.
  Set<int>? habitTargetDays(int activityId) => _habitTargetDays[activityId];

  /// Belirtilen [date] gününün bu alışkanlık için planlı olup olmadığını döner.
  bool isHabitScheduledFor(int activityId, DateTime date) {
    final days = _habitTargetDays[activityId];
    if (days == null || days.isEmpty || days.length == 7) return true;
    return days.contains(date.weekday);
  }

  /// Alışkanlığın planlanan günlerini kaydeder.
  Future<void> setHabitTargetDays(int activityId, Set<int>? days) async {
    if (days == null || days.isEmpty || days.length == 7) {
      _habitTargetDays.remove(activityId);
      await _deleteSetting('habit_days_$activityId');
    } else {
      _habitTargetDays[activityId] = Set<int>.from(days);
      final sorted = days.toList()..sort();
      await _putSetting('habit_days_$activityId', sorted.join(','));
    }
    _changed();
  }

  /// Alışkanlık sıklığının kullanıcı dostu metin karşılığı ("Her gün", "Hafta içi", "Hafta sonu", "Pzt, Çar, Cum").
  String habitScheduleText(int activityId, {required bool isTr}) {
    final days = _habitTargetDays[activityId];
    if (days == null || days.isEmpty || days.length == 7) {
      return isTr ? 'Her gün' : 'Every day';
    }
    if (days.length == 5 &&
        days.contains(1) &&
        days.contains(2) &&
        days.contains(3) &&
        days.contains(4) &&
        days.contains(5)) {
      return isTr ? 'Hafta içi' : 'Weekdays';
    }
    if (days.length == 2 && days.contains(6) && days.contains(7)) {
      return isTr ? 'Hafta sonu' : 'Weekends';
    }
    final trNames = {1: 'Pzt', 2: 'Sal', 3: 'Çar', 4: 'Per', 5: 'Cum', 6: 'Cmt', 7: 'Paz'};
    final enNames = {1: 'Mon', 2: 'Tue', 3: 'Wed', 4: 'Thu', 5: 'Fri', 6: 'Sat', 7: 'Sun'};
    final names = isTr ? trNames : enNames;
    final sorted = days.toList()..sort();
    return sorted.map((d) => names[d] ?? '$d').join(', ');
  }

  List<Activity> get habitActivities => activities.values.where((a) => a.isHabit).toList();

  Future<void> setActivityHabit(int activityId, bool isHabit) async {
    final act = activities[activityId];
    if (act == null) return;
    act.isHabit = isHabit;
    await updateActivity(act);
  }

  HabitStreakInfo habitStreakInfo(int activityId) {
    final cached = _habitStreakCache[activityId];
    if (cached != null) return cached;

    final now = DateTime.now();
    final today = dayStart(now);

    final dailyCounts = <DateTime, int>{};
    final dayEntriesMap = <DateTime, List<Entry>>{};
    bool hasTimedEntry = false;
    for (final e in entries) {
      if (e.activityId == activityId) {
        final d = dayStart(DateTime.fromMillisecondsSinceEpoch(e.ts));
        dailyCounts[d] = (dailyCounts[d] ?? 0) + 1;
        (dayEntriesMap[d] ??= []).add(e);
        if (!hasTimedEntry) {
          if (e.endTs != null || (e.unitId != null && e.value != null && unit(e.unitId!).dim == 'time')) {
            hasTimedEntry = true;
          }
        }
      }
    }

    final todayCount = dailyCounts[today] ?? 0;
    final isDoneToday = todayCount > 0;
    final totalActiveDays = dailyCounts.length;

    // Current streak (bugün yapıldıysa 1'den başlar; planlanmamış günler seriyi bozmaz, atlanır)
    int currentStreak = 0;
    if (isDoneToday) {
      currentStreak = 1;
    }
    DateTime checkDate = DateTime(today.year, today.month, today.day - 1);
    final earliestDay = dailyCounts.isEmpty ? today : (dailyCounts.keys.toList()..sort()).first;
    while (!checkDate.isBefore(earliestDay)) {
      if (dailyCounts.containsKey(checkDate)) {
        currentStreak++;
      } else if (isHabitScheduledFor(activityId, checkDate)) {
        // Planlanmış gündü ama kayıt yok: seri kırılır.
        break;
      }
      // Planlanmamış günde kayıt yoksa zincir kırılmaz, önceki güne geçer.
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
          // prevDay ile day arasında yapılmamış planlı gün var mı?
          bool missedScheduledDay = false;
          var cur = DateTime(prevDay.year, prevDay.month, prevDay.day + 1);
          while (cur.isBefore(day)) {
            if (isHabitScheduledFor(activityId, cur) && !dailyCounts.containsKey(cur)) {
              missedScheduledDay = true;
              break;
            }
            cur = DateTime(cur.year, cur.month, cur.day + 1);
          }
          if (!missedScheduledDay) {
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

    // Consistency in last 30 days (yalnızca planlanan gün sayısına bölünür)
    int activeIn30 = 0;
    int scheduledIn30 = 0;
    for (int i = 0; i < 30; i++) {
      final d = DateTime(today.year, today.month, today.day - i);
      final isScheduled = isHabitScheduledFor(activityId, d);
      if (isScheduled) {
        scheduledIn30++;
        if (dailyCounts.containsKey(d)) activeIn30++;
      } else {
        if (dailyCounts.containsKey(d)) activeIn30++;
      }
    }
    final denom = scheduledIn30 > 0 ? scheduledIn30 : 30;
    final consistencyLast30 = ((activeIn30 / denom) * 100.0).clamp(0.0, 100.0);

    // --- Heatmap Renk Seviyeleri ve Tooltip Hesaplamaları ---
    final relatedGoals = goals.where((g) => g.links.any((l) => l.activityId == activityId)).toList();
    final limitGoal = relatedGoals.cast<Goal?>().firstWhere((g) => g?.isLimit == true, orElse: () => null);
    final targetGoal = relatedGoals.cast<Goal?>().firstWhere((g) => g?.isTarget == true, orElse: () => null);

    final isTimed = hasTimedEntry ||
        (targetGoal?.unitId != null && unit(targetGoal!.unitId!).dim == 'time') ||
        (limitGoal?.unitId != null && unit(limitGoal!.unitId!).dim == 'time');

    final dailyLevels = <DateTime, int>{};
    final dailyTooltips = <DateTime, String>{};
    final isTr = language == AppLanguage.tr;

    for (final entry in dayEntriesMap.entries) {
      final day = entry.key;
      final dayEntries = entry.value;
      final count = dayEntries.length;

      if (limitGoal != null) {
        // 1. Limiti belli olan hedeflerde: limit aşılmamışsa full boyalı (4),
        // limiti geçtiyse limit üstü miktar arttıkça boyanma azalsın (3 -> 2 -> 1 -> 0).
        final linkMap = {for (final l in limitGoal.links) l.activityId: l};
        var val = 0.0;
        for (final e in dayEntries) {
          final link = linkMap[e.activityId];
          if (link == null) continue;
          final c = contribution(limitGoal, e, link.pct, link: link);
          if (c != null) val += c;
        }
        final target = limitGoal.target;
        final unitSym = goalUnitSymbol(limitGoal);
        final valStr = '${fmtNum(val)} $unitSym';
        final targetStr = '${fmtNum(target)} $unitSym';

        int lvl;
        String tip;
        if (val <= target) {
          lvl = 4;
          tip = '$valStr / $targetStr (${isTr ? "Limit korundu ✓" : "Within limit ✓"})';
        } else {
          final excessRatio = (val - target) / (target > 0 ? target : 1.0);
          if (excessRatio <= 0.25) {
            lvl = 3;
          } else if (excessRatio <= 0.50) {
            lvl = 2;
          } else if (excessRatio <= 1.0) {
            lvl = 1;
          } else {
            lvl = 0;
          }
          final diffStr = '+${fmtNum(val - target)} $unitSym';
          tip = '$valStr / $targetStr ($diffStr ${isTr ? "aşıldı ⚠️" : "exceeded ⚠️"})';
        }
        dailyLevels[day] = lvl;
        dailyTooltips[day] = tip;
      } else if (targetGoal != null) {
        // 2. Sayılı/ölçülü hedeflerde: hedefe ulaşınca full boyanacak şekilde olsun (4),
        // altında kaldığında orana göre derecelensin.
        final linkMap = {for (final l in targetGoal.links) l.activityId: l};
        var val = 0.0;
        for (final e in dayEntries) {
          final link = linkMap[e.activityId];
          if (link == null) continue;
          final c = contribution(targetGoal, e, link.pct, link: link);
          if (c != null) val += c;
        }
        final target = targetGoal.target;
        final unitSym = goalUnitSymbol(targetGoal);
        final valStr = '${fmtNum(val)} $unitSym';
        final targetStr = '${fmtNum(target)} $unitSym';

        int lvl;
        String tip;
        if (val >= target) {
          lvl = 4;
          tip = '$valStr / $targetStr (${isTr ? "Hedefe ulaşıldı ✓" : "Goal reached ✓"})';
        } else if (target > 0) {
          final ratio = val / target;
          if (ratio >= 0.66) {
            lvl = 3;
          } else if (ratio >= 0.33) {
            lvl = 2;
          } else if (ratio > 0) {
            lvl = 1;
          } else {
            lvl = 0;
          }
          final pct = (ratio * 100).round();
          tip = '$valStr / $targetStr (${fmtPercent(pct)})';
        } else {
          lvl = val > 0 ? 4 : 0;
          tip = '$valStr / $targetStr';
        }
        dailyLevels[day] = lvl;
        dailyTooltips[day] = tip;
      } else if (isTimed) {
        // 3. Süreli görevler: min 1 dk max >=60 dk süreye göre boyansın.
        double totalMinutes = 0.0;
        for (final e in dayEntries) {
          if (e.duration != null) {
            totalMinutes += e.duration!.inMilliseconds / 60000.0;
          } else if (e.unitId != null && e.value != null) {
            final u = unit(e.unitId!);
            if (u.dim == 'time') {
              totalMinutes += e.value! * u.factor;
            }
          }
        }

        int lvl;
        if (totalMinutes < 1.0) {
          lvl = 0;
        } else if (totalMinutes < 15.0) {
          lvl = 1;
        } else if (totalMinutes < 30.0) {
          lvl = 2;
        } else if (totalMinutes < 60.0) {
          lvl = 3;
        } else {
          lvl = 4;
        }

        String durStr;
        final totalMinInt = totalMinutes.round();
        if (totalMinInt < 60) {
          durStr = '$totalMinInt ${isTr ? "dk" : "min"}';
        } else {
          final h = totalMinInt ~/ 60;
          final m = totalMinInt % 60;
          durStr = m > 0 ? '$h ${isTr ? "sa" : "h"} $m ${isTr ? "dk" : "min"}' : '$h ${isTr ? "sa" : "h"}';
        }
        final logStr = '$count ${isTr ? "kayıt" : "logs"}';
        dailyLevels[day] = lvl;
        dailyTooltips[day] = '$durStr ($logStr)';
      } else {
        // 4. Belli değilse şimdiki gibi (1, 2, 3, >=4).
        int lvl;
        if (count == 0) {
          lvl = 0;
        } else if (count == 1) {
          lvl = 1;
        } else if (count == 2) {
          lvl = 2;
        } else if (count == 3) {
          lvl = 3;
        } else {
          lvl = 4;
        }
        dailyLevels[day] = lvl;
        dailyTooltips[day] = '$count ${isTr ? "kayıt" : "logs"}';
      }
    }

    final result = HabitStreakInfo(
      currentStreak: currentStreak,
      longestStreak: longestStreak,
      totalActiveDays: totalActiveDays,
      isDoneToday: isDoneToday,
      todayCount: todayCount,
      consistencyLast30: consistencyLast30,
      dailyCounts: dailyCounts,
      dailyLevels: dailyLevels,
      dailyTooltips: dailyTooltips,
    );
    _habitStreakCache[activityId] = result;
    return result;
  }

  /// Hedefin geçmiş dönemlerinin sonuçları, en yenisi başta (başarılıysa true). İçinde bulunulan dönem
  /// henüz başarılı değilse listeye alınmaz: bitmemiş bir dönem başarısız sayılmaz.
  List<bool> _periodOutcomes(Goal g, {int limit = 365}) {
    final outcomes = <bool>[];
    if (g.period == GoalPeriod.total) return outcomes;
    final start = dayStart(DateTime.fromMillisecondsSinceEpoch(g.startDate));
    var at = DateTime.now();
    for (var i = 0; i < limit; i++) {
      final st = goalStatus(g, at: at);
      if (st.to != null && !st.to!.isAfter(start)) break;
      if (i > 0 || st.done) outcomes.add(st.done);
      final (from, _) = goalRange(g, at);
      if (!from.isAfter(start)) break;
      at = DateTime(from.year, from.month, from.day - 1, 12);
    }
    return outcomes;
  }

  /// Hedefin ısı haritası ve seri bilgileri.
  ///
  /// Günlük hedefte her gün kendi hedefiyle ölçülür. Haftalık, aylık ve toplam hedeflerde bir günün rengi
  /// o günün ait olduğu dönemin sonucunu gösterir (kayıt olan günler boyanır) ve seriler dönem sayar;
  /// tek bir günü haftalık hedefle kıyaslamak hiçbir günü "tamam" göstermiyordu.
  HabitStreakInfo goalStreakInfo(Goal g) {
    final cached = _goalStreakCache[g.id];
    if (cached != null) return cached;

    final now = DateTime.now();
    final today = dayStart(now);
    final goalStartDate = dayStart(DateTime.fromMillisecondsSinceEpoch(g.startDate));

    final earliest = DateTime(today.year, today.month, today.day - 140);
    final evalStart = earliest.isBefore(goalStartDate) ? goalStartDate : earliest;

    final dailyCounts = <DateTime, int>{};
    final dailyLevels = <DateTime, int>{};
    final dailyTooltips = <DateTime, String>{};
    final isTr = language == AppLanguage.tr;
    final unitSym = goalUnitSymbol(g);
    final isDaily = g.period == GoalPeriod.day;

    final linkMap = {for (final l in g.links) l.activityId: l};
    final dayValues = <DateTime, double>{};
    final dayCounts = <DateTime, int>{};

    final allActiveDays = <DateTime>{};
    for (final e in entries) {
      final d = dayStart(DateTime.fromMillisecondsSinceEpoch(e.ts));
      allActiveDays.add(d);
      final link = linkMap[e.activityId];
      if (link == null) continue;
      final c = contribution(g, e, link.pct, link: link);
      if (c == null) continue;
      dayValues[d] = (dayValues[d] ?? 0.0) + c;
      dayCounts[d] = (dayCounts[d] ?? 0) + 1;
    }

    // Günün ait olduğu dönemin toplamı (dönem başına bir kez hesaplanır).
    final periodValues = <DateTime, double>{};
    double periodValueOf(DateTime day) {
      final (from, to) = goalRange(g, day);
      return periodValues[from] ??= goalValue(g, from, to).$1;
    }

    final periodLabel = switch (g.period) {
      GoalPeriod.day => '',
      GoalPeriod.week => isTr ? 'Hafta' : 'Week',
      GoalPeriod.month => isTr ? 'Ay' : 'Month',
      GoalPeriod.total => isTr ? 'Toplam' : 'Total',
    };

    final target = g.target;
    final targetStr = '${fmtNum(target)} $unitSym';
    final daysCount = daysBetween(evalStart, today) + 1;
    for (int i = 0; i < daysCount; i++) {
      final d = DateTime(evalStart.year, evalStart.month, evalStart.day + i);
      if (d.isAfter(today)) break;

      final dayVal = dayValues[d] ?? 0.0;
      final count = dayCounts[d] ?? 0;
      // Günün ölçüldüğü değer: günlük hedefte günün kendisi, diğerlerinde ait olduğu dönemin toplamı.
      final val = isDaily ? dayVal : periodValueOf(d);
      final valStr = '${fmtNum(val)} $unitSym';
      final measured = isDaily ? '$valStr / $targetStr' : '${fmtNum(dayVal)} $unitSym · $periodLabel: $valStr / $targetStr';
      final checkinDone = isGoalCheckinDone(g, at: d);
      if (checkinDone) {
        dailyCounts[d] = count > 0 ? count : 1;
        dailyLevels[d] = 4;
        dailyTooltips[d] = isDaily
            ? (isTr ? 'Ulaşıldı olarak işaretlendi ✓' : 'Marked as completed ✓')
            : '$periodLabel: ${isTr ? "Ulaşıldı olarak işaretlendi ✓" : "Marked as completed ✓"}';
      } else if (g.isLimit) {
        final hasAnyAppActivity = allActiveDays.contains(d);
        if (count > 0 || hasAnyAppActivity || d == today) {
          dailyCounts[d] = count > 0 ? count : 1;
          if (val <= target) {
            dailyLevels[d] = 4;
            dailyTooltips[d] = '$measured (${isTr ? "Limit korundu ✓" : "Within limit ✓"})';
          } else {
            final excessRatio = (val - target) / (target > 0 ? target : 1.0);
            int lvl;
            if (excessRatio <= 0.25) {
              lvl = 3;
            } else if (excessRatio <= 0.50) {
              lvl = 2;
            } else if (excessRatio <= 1.0) {
              lvl = 1;
            } else {
              lvl = 0;
            }
            dailyLevels[d] = lvl;
            final diffStr = '+${fmtNum(val - target)} $unitSym';
            dailyTooltips[d] = '$measured ($diffStr ${isTr ? "aşıldı ⚠️" : "exceeded ⚠️"})';
          }
        }
      } else {
        if (count > 0 || dayVal > 0) {
          dailyCounts[d] = count > 0 ? count : 1;
          if (val >= target) {
            dailyLevels[d] = 4;
            dailyTooltips[d] = '$measured (${isTr ? "Hedefe ulaşıldı ✓" : "Goal reached ✓"})';
          } else if (target > 0) {
            final ratio = val / target;
            int lvl;
            if (ratio >= 0.66) {
              lvl = 3;
            } else if (ratio >= 0.33) {
              lvl = 2;
            } else if (ratio > 0) {
              lvl = 1;
            } else {
              lvl = 0;
            }
            dailyLevels[d] = lvl;
            final pct = (ratio * 100).round();
            dailyTooltips[d] = '$measured (${fmtPercent(pct)})';
          } else {
            dailyLevels[d] = val > 0 ? 4 : 0;
            dailyTooltips[d] = measured;
          }
        }
      }
    }

    final todayStatus = goalStatus(g, at: today);
    final isDoneToday = todayStatus.done;
    final todayCount = dayCounts[today] ?? 0;

    int currentStreak;
    int longestStreak;
    double consistency;
    if (g.period == GoalPeriod.week || g.period == GoalPeriod.month) {
      // Seriler dönem sayar: art arda tutturulan hafta ya da ay.
      final outcomes = _periodOutcomes(g);
      currentStreak = outcomes.takeWhile((ok) => ok).length;
      longestStreak = 0;
      var run = 0;
      for (final ok in outcomes) {
        run = ok ? run + 1 : 0;
        if (run > longestStreak) longestStreak = run;
      }
      final recent = outcomes.take(12).toList();
      consistency = recent.isEmpty ? 0.0 : recent.where((ok) => ok).length / recent.length * 100.0;
    } else {
      currentStreak = 0;
      DateTime checkDate = isDoneToday ? today : DateTime(today.year, today.month, today.day - 1);
      while (checkDate.isAfter(goalStartDate) || checkDate == goalStartDate) {
        final lvl = dailyLevels[checkDate];
        if (lvl != null && lvl == 4) {
          currentStreak++;
          checkDate = DateTime(checkDate.year, checkDate.month, checkDate.day - 1);
        } else {
          break;
        }
      }

      longestStreak = currentStreak;
      if (dailyLevels.isNotEmpty) {
        final sortedDays = dailyLevels.keys.toList()..sort();
        int temp = 0;
        DateTime? prev;
        for (final day in sortedDays) {
          if (dailyLevels[day] == 4) {
            if (prev == null || daysBetween(prev, day) == 1) {
              temp++;
            } else {
              temp = 1;
            }
            if (temp > longestStreak) longestStreak = temp;
            prev = day;
          } else {
            temp = 0;
            prev = null;
          }
        }
      }

      int successfulIn30 = 0;
      int evaluatedIn30 = 0;
      for (int i = 0; i < 30; i++) {
        final d = DateTime(today.year, today.month, today.day - i);
        if (d.isBefore(goalStartDate)) break;
        evaluatedIn30++;
        final lvl = dailyLevels[d];
        if (lvl != null && lvl == 4) successfulIn30++;
      }
      consistency = evaluatedIn30 > 0 ? (successfulIn30 / evaluatedIn30) * 100.0 : 0.0;
    }

    final result = HabitStreakInfo(
      currentStreak: currentStreak,
      longestStreak: longestStreak,
      totalActiveDays: dailyCounts.length,
      isDoneToday: isDoneToday,
      todayCount: todayCount,
      consistencyLast30: consistency,
      dailyCounts: dailyCounts,
      dailyLevels: dailyLevels,
      dailyTooltips: dailyTooltips,
      streakPeriod: g.period == GoalPeriod.week || g.period == GoalPeriod.month ? g.period : GoalPeriod.day,
    );
    _goalStreakCache[g.id] = result;
    return result;
  }

  Future<AddResult> quickLogHabit(int activityId, {DateTime? date}) async {
    final targetTime = date ?? DateTime.now();
    final last = lastEntryForActivity(activityId);
    if (last != null) {
      return addEntry(
        activityId,
        measureId: last.measureId,
        qty: last.qty,
        value: last.value,
        unitId: last.unitId,
        note: last.note,
        at: targetTime,
      );
    }
    final defaultPhys = defaultPhysicalMeasureFor(activityId);
    final lastMeasureId = stats[activityId]?.lastMeasureId ?? defaultPhys?.id;
    return addEntry(
      activityId,
      measureId: lastMeasureId,
      qty: 1,
      at: targetTime,
    );
  }

  // ---------------------------------------------------------------- hızlı liste

  int todayCount(int activityId) =>
      entriesOfDay(DateTime.now()).where((e) => e.activityId == activityId).length;

  Entry? quickDoneEntry(QuickItem q, {DateTime? at}) {
    if (!q.isTodo) return null;
    final targetDay = at ?? DateTime.now();
    final from = q.daily
        ? dayStart(targetDay)
        : DateTime.fromMillisecondsSinceEpoch(q.createdAt);
    final to = q.daily ? addDays(from, 1) : null;
    Entry? last;
    for (final e in entriesIn(from, to)) {
      if (e.activityId == q.activityId) last = e;
    }
    return last;
  }

  bool quickDone(QuickItem q, {DateTime? at}) => quickDoneEntry(q, at: at) != null;

  Future<QuickTapResult> tapQuickItem(int id, {DateTime? at}) async {
    final q = quickItems.where((x) => x.id == id).firstOrNull;
    if (q == null) return QuickTapResult();
    final done = quickDoneEntry(q, at: at);
    if (done != null) {
      await deleteEntry(done);
      return QuickTapResult(removed: done);
    }
    final targetDay = at ?? DateTime.now();
    final entryTime = sameDay(targetDay, DateTime.now())
        ? DateTime.now()
        : DateTime(targetDay.year, targetDay.month, targetDay.day, 12, 0);

    // Kural: Süreli aktivite çipine dokunulduğunda saatsiz süreli kayıt şimdi biter (başlangıç = şimdi - süre)
    final autoM = defaultPhysicalMeasureFor(q.activityId);
    final effectiveMId = q.measureId ?? autoM?.id;
    final m = measureById(effectiveMId) ?? defaultMeasureFor(q.activityId);
    final unitId = m?.unitId;
    final val = m != null ? m.amount * q.qty : q.qty;
    DateTime effectiveAt = entryTime;
    DateTime? effectiveEndAt;
    if ((unitId == 'dk' || unitId == 'sa' || unitId == 'sn') && val > 0) {
      final durSecs = (val * (unitId == 'sa' ? 3600 : (unitId == 'dk' ? 60 : 1))).round();
      effectiveEndAt = entryTime;
      effectiveAt = entryTime.subtract(Duration(seconds: durSecs));
    }

    final r = await addEntry(
      q.activityId,
      measureId: effectiveMId,
      qty: q.qty,
      at: effectiveAt,
      endAt: effectiveEndAt,
    );
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

  Future<void> reorderQuickItems(int oldIndex, int newIndex) async {
    if (oldIndex < 0 || oldIndex >= quickItems.length) return;
    if (newIndex < 0 || newIndex >= quickItems.length) return;
    final item = quickItems.removeAt(oldIndex);
    quickItems.insert(newIndex, item);
    final d = await db;
    final batch = d.batch();
    for (var i = 0; i < quickItems.length; i++) {
      final q = quickItems[i];
      q.sort = i;
      batch.update('quick_items', {'sort': q.sort}, where: 'id=?', whereArgs: [q.id]);
    }
    await batch.commit(noResult: true);
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

  // ---------------------------------------------------------------- aktivite hatırlatıcıları

  List<ActivityReminder> remindersForActivity(int activityId) =>
      activityReminders.where((r) => r.activityId == activityId).toList();

  Future<ActivityReminder> saveActivityReminder(ActivityReminder reminder) async {
    final d = await db;
    if (reminder.id == 0) {
      reminder.id = await d.insert('activity_reminders', reminder.toMap()..remove('id'));
      activityReminders.add(reminder);
    } else {
      await d.update('activity_reminders', reminder.toMap(),
          where: 'id = ?', whereArgs: [reminder.id]);
      final idx = activityReminders.indexWhere((r) => r.id == reminder.id);
      if (idx != -1) {
        activityReminders[idx] = reminder;
      }
    }
    _changed();
    try {
      await NotificationService.scheduleReminders(this);
    } catch (_) {}
    return reminder;
  }

  Future<void> deleteActivityReminder(int id) async {
    final d = await db;
    await d.delete('activity_reminders', where: 'id = ?', whereArgs: [id]);
    activityReminders.removeWhere((r) => r.id == id);
    _changed();
    try {
      await NotificationService.scheduleReminders(this);
    } catch (_) {}
  }

  Future<void> toggleActivityReminder(int id, bool enabled) async {
    final rem = activityReminders.where((r) => r.id == id).firstOrNull;
    if (rem == null) return;
    rem.isEnabled = enabled;
    final d = await db;
    await d.update('activity_reminders', {'is_enabled': enabled ? 1 : 0},
        where: 'id = ?', whereArgs: [id]);
    _changed();
    try {
      await NotificationService.scheduleReminders(this);
    } catch (_) {}
  }

  // ---------------------------------------------------------------- rutinler (aktivite paketleri)

  Future<Routine> saveRoutine(Routine routine) async {
    final d = await db;
    if (routine.id == 0) {
      routine.sort = routines.isEmpty ? 0 : routines.map((r) => r.sort).reduce(max) + 1;
      routine.id = await d.insert('routines', routine.toMap()..remove('id'));
      routines.add(routine);
    } else {
      await d.update('routines', routine.toMap(), where: 'id = ?', whereArgs: [routine.id]);
      final idx = routines.indexWhere((r) => r.id == routine.id);
      if (idx != -1) {
        routines[idx] = routine;
      }
    }
    await d.delete('routine_items', where: 'routine_id = ?', whereArgs: [routine.id]);
    final batch = d.batch();
    for (var i = 0; i < routine.items.length; i++) {
      final it = routine.items[i];
      it.routineId = routine.id;
      it.sort = i;
      batch.insert('routine_items', it.toMap()..remove('id'));
    }
    await batch.commit(noResult: true);
    _changed();
    return routine;
  }

  Future<void> deleteRoutine(int id) async {
    final d = await db;
    await d.delete('routine_items', where: 'routine_id = ?', whereArgs: [id]);
    await d.delete('routines', where: 'id = ?', whereArgs: [id]);
    routines.removeWhere((r) => r.id == id);
    _changed();
  }

  Future<List<Entry>> executeRoutine(int routineId, {DateTime? at}) async {
    final r = routines.where((x) => x.id == routineId).firstOrNull;
    if (r == null || r.items.isEmpty) return const [];

    final currentRealTime = DateTime.now();
    final DateTime baseTime;
    if (at == null || sameDay(at, currentRealTime)) {
      baseTime = currentRealTime;
    } else {
      baseTime = DateTime(
        at.year,
        at.month,
        at.day,
        currentRealTime.hour,
        currentRealTime.minute,
        currentRealTime.second,
      );
    }

    final createdEntries = <Entry>[];
    for (var i = 0; i < r.items.length; i++) {
      final it = r.items[i];
      if (!activities.containsKey(it.activityId)) continue;

      final itemTime = baseTime.add(Duration(seconds: i));
      int? effectiveMeasureId = it.measureId;
      final double effectiveQty = it.qty > 0 ? it.qty : 1.0;
      double? effectiveValue;
      String? effectiveUnitId;

      if (effectiveMeasureId == null) {
        final lastMId = stats[it.activityId]?.lastMeasureId;
        if (lastMId != null && measureById(lastMId) != null) {
          effectiveMeasureId = lastMId;
        } else {
          final (usedMeasures, otherMeasures) = measuresFor(it.activityId);
          effectiveMeasureId = (usedMeasures.isNotEmpty ? usedMeasures.first : otherMeasures.firstOrNull)?.id;
        }
      }

      if (effectiveMeasureId == null) {
        final last = lastEntryForActivity(it.activityId);
        if (last != null && last.unitId != null && last.value != null) {
          effectiveUnitId = last.unitId;
          effectiveValue = (last.value! / (last.qty > 0 ? last.qty : 1.0)) * effectiveQty;
        }
      }

      if (effectiveMeasureId == null && effectiveValue == null) {
        final autoM = defaultPhysicalMeasureFor(it.activityId);
        if (autoM != null) {
          effectiveMeasureId = autoM.id;
        }
      }

      DateTime effectiveAt = itemTime;
      DateTime? effectiveEndAt;
      final m = measureById(effectiveMeasureId);
      final uId = m?.unitId ?? effectiveUnitId;
      final val = m != null ? m.amount * effectiveQty : effectiveValue;
      if ((uId == 'dk' || uId == 'sa' || uId == 'sn') && val != null && val > 0) {
        final durSecs = (val * (uId == 'sa' ? 3600 : (uId == 'dk' ? 60 : 1))).round();
        effectiveEndAt = itemTime;
        effectiveAt = itemTime.subtract(Duration(seconds: durSecs));
      }

      final res = await addEntry(
        it.activityId,
        measureId: effectiveMeasureId,
        qty: effectiveQty,
        at: effectiveAt,
        endAt: effectiveEndAt,
        note: it.note,
        value: effectiveValue,
        unitId: effectiveUnitId,
      );
      createdEntries.add(res.entry);
    }
    return createdEntries;
  }

  // ---------------------------------------------------------------- widget verisi

  Map<String, Object?> widgetPayload() {
    final now = DateTime.now();
    final isTr = strings.value.isTr;
    final items = <Map<String, Object?>>[];
    final seenActIds = <int>{};

    for (final q in quickItems) {
      final n = todayCount(q.activityId);
      final done = quickDone(q);
      String sub;
      if (!q.isTodo) {
        sub = n > 0 ? (isTr ? 'Bugün $n' : 'Today $n') : '';
      } else {
        sub = q.daily ? '' : (isTr ? 'bir kez' : 'once');
      }
      seenActIds.add(q.activityId);
      items.add({
        'id': q.id,
        't': activityLabel(q.activityId),
        'k': q.kind,
        'd': done,
        's': sub,
        'o': q.isTodo && !q.daily,
        'actId': q.activityId,
      });
      if (items.length >= 8) break;
    }

    // Saate göre öğeler: 4'ten az kısayol varsa saat ve gün örüntüsüne göre tamamla
    if (items.length < 4) {
      final suggestions = timeBasedSuggestions(now: now);
      for (final a in suggestions) {
        if (seenActIds.contains(a.id)) continue;
        final n = todayCount(a.id);
        seenActIds.add(a.id);
        items.add({
          'id': -a.id, // Negatif ID: doğrudan aktivite kaydı
          't': activityLabel(a.id),
          'k': 'suggestion',
          'd': n > 0,
          's': n > 0 ? (isTr ? 'Bugün $n' : 'Today $n') : (isTr ? 'Öneri' : 'Suggested'),
          'o': false,
          'actId': a.id,
        });
        if (items.length >= 8) break;
      }
    }

    // 1x1 Tek Öğe Widget Verisi (Single Widget)
    Activity? singleAct;
    String singleSub = isTr ? 'Hızlı Kayıt' : 'Quick Log';
    if (_singleWidgetActivityId != null && _singleWidgetActivityId! > 0 && activities.containsKey(_singleWidgetActivityId)) {
      singleAct = activities[_singleWidgetActivityId];
      if (singleAct != null) {
        final n = todayCount(singleAct.id);
        singleSub = n > 0 ? (isTr ? 'Bugün $n' : 'Today $n') : (isTr ? 'Dokun: Kaydet' : 'Tap to log');
      }
    } else {
      // Öncelik: Yapılmamış alışkanlık > Kalan günlük hedef > Saate göre öneri > Son kayıt
      final uncompletedHabit = activities.values.where((a) => a.isHabit && !a.isArchived && todayCount(a.id) == 0).firstOrNull;
      if (uncompletedHabit != null) {
        singleAct = uncompletedHabit;
        singleSub = isTr ? 'Alışkanlık' : 'Habit';
      } else {
        final uncompletedGoal = goals.where((g) => g.period == GoalPeriod.day && !goalStatus(g, at: now).done).firstOrNull;
        if (uncompletedGoal != null && uncompletedGoal.links.isNotEmpty) {
          singleAct = activities[uncompletedGoal.links.first.activityId];
          final st = goalStatus(uncompletedGoal, at: now);
          singleSub = isTr ? 'Kalan: ${goalValueText(uncompletedGoal, st.remaining)}' : 'Left: ${goalValueText(uncompletedGoal, st.remaining)}';
        } else {
          singleAct = timeBasedSuggestions(now: now).firstOrNull ?? activities[entries.lastOrNull?.activityId];
          if (singleAct != null) {
            final n = todayCount(singleAct.id);
            singleSub = n > 0 ? (isTr ? 'Bugün $n' : 'Today $n') : (isTr ? 'Dokun: Kaydet' : 'Tap to log');
          }
        }
      }
    }

    final goalParts = <String>[];
    for (final g in goals.where((g) => g.period == GoalPeriod.day)) {
      final st = goalStatus(g);
      if (st.expired) continue;
      if (g.isLimit) {
        goalParts.add(st.isExceeded ? '⚠️ ${g.name}!' : '✓ ${g.name}');
      } else {
        goalParts.add(st.done ? '✓ ${g.name}' : '${g.name} ${fmtPercent((st.ratio * 100).floor())}');
      }
    }
    return {
      'date': dayKey(now),
      'theme': themeModeString,
      'isTr': isTr,
      'items': items,
      'goals': goalParts.isEmpty ? '' : '🎯 ${goalParts.join('  ·  ')}',
      'single_title': singleAct != null ? singleAct.name : (isTr ? 'Kayıt Ekle' : 'Add Entry'),
      'single_sub': singleSub,
      'single_emoji': singleAct?.emoji ?? '⚡',
      'single_act_id': singleAct?.id ?? 0,
      'single_done': singleAct != null && todayCount(singleAct.id) > 0,
      'single_configured_act_id': _singleWidgetActivityId ?? 0,
      'activities': [
        for (final a in activities.values.where((a) => !a.isArchived))
          {
            'id': a.id,
            'name': a.name,
            'emoji': a.emoji ?? '⚡',
            'count': todayCount(a.id),
            'isHabit': a.isHabit,
          }
      ],
    };
  }

  // ---------------------------------------------------------------- yedekleme

  Future<String> exportJson() async {
    final d = await db;
    final out = <String, Object?>{
      'app': 'seyir',
      'version': AppDb.currentVersion,
      'exportedAt': DateTime.now().toIso8601String(),
    };
    for (final t in AppDb.tables) {
      if (t == 'settings') {
        out[t] = await d.query(t, where: "key != 'llm_api_key'");
      } else {
        out[t] = await d.query(t);
      }
    }
    return const JsonEncoder.withIndent(' ').convert(out);
  }

  /// load()'un her tablonun satırlarını okurken kullandığı dönüştürücüler.
  static final Map<String, void Function(Map<String, Object?>)> _backupRowReaders = {
    'units': Unit.fromMap,
    'measures': Measure.fromMap,
    'activities': Activity.fromMap,
    'entries': Entry.fromMap,
    'goals': Goal.fromMap,
    'goal_links': GoalLink.fromMap,
    'quick_items': QuickItem.fromMap,
    'settings': (r) {
      if (r['key'] is! String || r['value'] is! String) throw const FormatException('settings');
    },
    'active_timers': ActiveTimer.fromMap,
    'roadmaps': Roadmap.fromMap,
    'roadmap_steps': RoadmapStep.fromMap,
    'activity_properties': ActivityProperty.fromMap,
    'activity_reminders': ActivityReminder.fromMap,
    'routines': Routine.fromMap,
    'routine_items': RoutineItem.fromMap,
    'goal_checkins': (r) {
      if (r['goal_id'] is! int || r['period_key'] is! String) {
        throw const FormatException('goal_checkins');
      }
    },
    'todos': Todo.fromMap,
    'todo_links': TodoLink.fromMap,
  };

  /// Yedeği veritabanına dokunmadan önce doğrular ve tablo başına satırları döner. load()'un okuyamayacağı
  /// tek bir satır bile içe aktarılırsa uygulama bir daha açılamaz; böyle bir yedek baştan reddedilir.
  Map<String, List<Map<String, Object?>>> _validatedBackupTables(Map<dynamic, dynamic> backup) {
    final tables = <String, List<Map<String, Object?>>>{};
    for (final t in AppDb.tables) {
      final rows = <Map<String, Object?>>[];
      try {
        for (final r in (backup[t] as List?) ?? const []) {
          final row = Map<String, Object?>.from(r as Map);
          _backupRowReaders[t]?.call(row);
          rows.add(row);
        }
      } catch (_) {
        throw FormatException(strings.value.isTr
            ? 'Yedek okunamadı: "$t" tablosunun ${rows.length + 1}. satırı geçersiz.'
            : 'The backup cannot be read: row ${rows.length + 1} of table "$t" is invalid.');
      }
      tables[t] = rows;
    }
    return tables;
  }

  /// Yedekteki çalışan sayaçları, yedeğin alındığı andaki süreleriyle duraklatılmış hâle getirir.
  /// Olduğu gibi geri yüklenen bir sayaç yedekten beri hep çalışmış sayılırdı: geri sayımlar "tamamlandı"
  /// diye kendiliğinden kaydedilir, kronometreler günlerce süre gösterirdi.
  void _pauseBackupTimers(List<Map<String, Object?>> rows, Object? exportedAt) {
    final exportedMs = exportedAt is String ? DateTime.tryParse(exportedAt)?.millisecondsSinceEpoch : null;
    for (final row in rows) {
      if (row['is_running'] != 1) continue;
      final resumedAt = row['last_resume_ts'];
      if (exportedMs != null && resumedAt is int && exportedMs > resumedAt) {
        row['accumulated_ms'] = ((row['accumulated_ms'] as int?) ?? 0) + (exportedMs - resumedAt);
        var segments = <Object?>[];
        try {
          final decoded = jsonDecode(row['segments'] as String? ?? '[]');
          if (decoded is List) segments = decoded;
        } catch (_) {}
        row['segments'] = jsonEncode([...segments, TimerSegment(startTs: resumedAt, endTs: exportedMs).toMap()]);
      }
      row['is_running'] = 0;
      row['last_resume_ts'] = null;
    }
  }

  Future<void> importJson(String json) async {
    final m = jsonDecode(json);
    if (m is! Map || (m['app'] != 'takip' && m['app'] != 'seyir')) {
      throw FormatException(strings.value.isTr ? 'Bu dosya bir Seyir yedeği değil.' : 'This file is not a Seyir backup.');
    }
    final version = m['version'];
    if (version is int && version > AppDb.currentVersion) {
      throw FormatException(
        strings.value.isTr
            ? 'Bu yedek uygulamanın daha yeni bir sürümüyle alınmış. Önce uygulamayı güncelleyin.'
            : 'This backup was made with a newer version of the app. Update the app first.',
      );
    }
    final tables = _validatedBackupTables(m);
    _pauseBackupTimers(tables['active_timers']!, m['exportedAt']);

    // Geri yükleme öncesinde mevcut verileri korumak için güvenlik yedeği al
    try {
      await BackupService.createPreRestoreSnapshot(this);
    } catch (e) {
      throw StateError(
        strings.value.isTr
            ? 'Geri yükleme öncesi güvenlik yedeği alınamadı. Verilerinizin kaybolmaması için işlem durduruldu: $e'
            : 'Failed to create safety backup before restore. Aborted to prevent data loss: $e',
      );
    }

    final d = await db;
    final existingSettingsRows = await d.query('settings');
    final existingSettings = {
      for (final r in existingSettingsRows) r['key'] as String: r['value'] as String,
    };
    final currentKey = (existingSettings['llm_api_key'] ?? llmApiKey).trim();
    final hasCurrentKey = currentKey.isNotEmpty;

    final settingsRows = List<Map<String, Object?>>.from(tables['settings']!);
    if (hasCurrentKey) {
      // Cihazda API anahtarı varsa: cihazdaki dört yapay zekâ ayarının hepsi
      // (sağlayıcı, anahtar, model, uç nokta) korunur; yedektekiler yok sayılır.
      const aiKeys = {'llm_provider', 'llm_api_key', 'llm_model', 'llm_custom_endpoint'};
      settingsRows.removeWhere((r) => aiKeys.contains(r['key']));
      for (final k in aiKeys) {
        final val = existingSettings[k] ??
            switch (k) {
              'llm_provider' => llmProvider,
              'llm_api_key' => llmApiKey,
              'llm_model' => llmModel,
              'llm_custom_endpoint' => llmCustomEndpoint,
              _ => null,
            };
        if (val != null) {
          settingsRows.add({'key': k, 'value': val});
        }
      }
    }

    await d.transaction((tx) async {
      for (final t in AppDb.tables.reversed) {
        await tx.delete(t);
      }
      for (final t in AppDb.tables) {
        final rows = t == 'settings' ? settingsRows : tables[t]!;
        for (final row in rows) {
          await tx.insert(t, row);
        }
      }
      // Geri yüklemeden sonra var olmayan bir aktiviteye, rutine ya da hedefe işaret eden yetim satırları temizle
      await tx.delete('routine_items',
          where: 'activity_id NOT IN (SELECT id FROM activities) OR routine_id NOT IN (SELECT id FROM routines)');
      await tx.delete('activity_reminders',
          where: 'activity_id NOT IN (SELECT id FROM activities)');
      await tx.delete('goal_checkins',
          where: 'goal_id NOT IN (SELECT id FROM goals)');
      await tx.delete('todo_links',
          where: 'activity_id NOT IN (SELECT id FROM activities) OR todo_id NOT IN (SELECT id FROM todos)');
      await tx.delete('goal_links',
          where: 'activity_id NOT IN (SELECT id FROM activities) OR goal_id NOT IN (SELECT id FROM goals)');
      await tx.delete('activity_properties',
          where: 'activity_id NOT IN (SELECT id FROM activities)');
      await tx.update('roadmap_steps', {'linked_activity_id': null},
          where: 'linked_activity_id IS NOT NULL AND linked_activity_id NOT IN (SELECT id FROM activities)');
    });
    // Adım durumu da yedektekiyle değişir.
    _stepLive = false;
    await load();
    try {
      await NotificationService.scheduleReminders(this);
    } catch (_) {}
  }

  /// Aktivitenin varsayılan ölçüsünün boyutunu denetler.
  /// Hacim (volume), kütle (mass), mesafe (distance) ve özel (custom) boyutundaki ölçüler tek dokunuşluk yollarda
  /// otomatik uygulanır; süre (time) ve adet/olay (count/times) boyutlu aktivitelere dokunulmaz.
  bool isAutoApplyDimension(String dim) {
    return dim == 'volume' || dim == 'mass' || dim == 'distance' || dim == 'custom';
  }

  /// Verilen aktivite için otomatik uygulanacak varsayılan fiziksel ölçüyü döner;
  /// eğer aktivitenin varsayılan ölçüsü yoksa veya boyutu süre/adet ise null döner.
  Measure? defaultPhysicalMeasureFor(int activityId) {
    final defM = defaultMeasureFor(activityId);
    if (defM == null) return null;
    final dim = unit(defM.unitId).dim;
    return isAutoApplyDimension(dim) ? defM : null;
  }

  /// Eski ölçüsüz kayıtları (measure_id ve value boş olanlar) varsayılan ölçüyle bir defalık düzeltir.
  /// Ölçülü aktiviteler (hacim, kütle, mesafe, özel ölçü) kapsanır.
  /// Olay/adet, süreli aktiviteler ve dolu kayıtlar atlanır.
  Future<int> fixUnmeasuredEntries() async {
    final d = await db;
    // Düzeltme yalnızca bir kez çalışır (ayarlar tablosunda bayrak tutulur).
    final settingsRows = await d.query('settings', where: 'key = ?', whereArgs: ['unmeasured_entries_fixed']);
    if (settingsRows.isNotEmpty && settingsRows.first['value'] == 'true') {
      return 0;
    }

    final toFix = <Entry>[];
    for (final e in entries) {
      if (e.measureId != null || e.value != null) continue;
      if (!activities.containsKey(e.activityId)) continue;

      final defM = defaultPhysicalMeasureFor(e.activityId);
      if (defM != null) {
        toFix.add(e);
      }
    }

    if (toFix.isEmpty) {
      await d.insert(
        'settings',
        {'key': 'unmeasured_entries_fixed', 'value': 'true'},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      return 0;
    }

    // Güvenlik: Veri kaybını önlemek için değiştirilecek kayıt varsa önce tam bir yedek al
    try {
      await BackupService.createBackup(this, prefix: 'pre_fix_unmeasured');
    } catch (err, st) {
      debugPrint('Güvenlik yedeği alınamadığı için ölçüsüz kayıt düzeltmesi iptal edildi: $err\n$st');
      return 0;
    }

    // Değişikliği tek transaction'da yap
    try {
      await d.transaction((tx) async {
        for (final e in toFix) {
          final defM = defaultPhysicalMeasureFor(e.activityId)!;
          final finalVal = defM.amount * e.qty;
          await tx.update(
            'entries',
            {
              'measure_id': defM.id,
              'unit_id': defM.unitId,
              'value': finalVal,
            },
            where: 'id = ?',
            whereArgs: [e.id],
          );
        }
        await tx.insert(
          'settings',
          {'key': 'unmeasured_entries_fixed', 'value': 'true'},
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      });
    } catch (err, st) {
      debugPrint('Ölçüsüz kayıt düzeltme transaction hatası: $err\n$st');
      return 0;
    }

    // Bellek nesnelerini güncelle
    for (final e in toFix) {
      final defM = defaultPhysicalMeasureFor(e.activityId)!;
      e.measureId = defM.id;
      e.unitId = defM.unitId;
      e.value = defM.amount * e.qty;
    }

    // Hedefler, yapılacaklar, yol haritası ve widget'ı yenile
    await _syncLinkedSteps(announce: false);
    await _syncTodos(announce: false);
    WidgetSync.schedule();
    _changed();

    final count = toFix.length;
    final msg = formatUnmeasuredFixMessage(count, isTr: strings.value.isTr);
    unmeasuredFixMessageNotifier.value = msg;
    return count;
  }

  /// Ölçüsüz kayıt düzeltme bildirim mesajını biçimlendirir.
  String formatUnmeasuredFixMessage(int count, {required bool isTr}) {
    return isTr
        ? '$count eski kayıt varsayılan ölçüyle düzeltildi; öncesinin yedeği alındı (Ayarlar › Yedekleme & Raporlama › Yerel Yedekler)'
        : '$count old unmeasured entries updated with default measure; backup saved before changes (Settings › Backup & Reports › Local Backups)';
  }

  /// Süreli aktivitelerdeki ölçüsüz kayıt sayısını ve şu an nasıl sayıldıklarını raporlamak için yardımcı sayaç.
  int countUnmeasuredDurationEntries() {
    int count = 0;
    for (final e in entries) {
      if (e.measureId != null || e.value != null) continue;
      if (!activities.containsKey(e.activityId)) continue;
      final act = activities[e.activityId]!;
      final defM = defaultMeasureFor(act.id);
      final dim = defM != null ? unit(defM.unitId).dim : null;
      final format = activityFormat(act.id);
      if (dim == 'time' || format == ActivityFormat.duration) {
        count++;
      }
    }
    return count;
  }

  // ---------------------------------------------------------------- yol haritaları (roadmaps)

  Future<Roadmap> createRoadmap(Roadmap roadmap) async {
    final d = await db;
    final id = await d.insert('roadmaps', roadmap.toMap());
    roadmap.id = id;
    for (var i = 0; i < roadmap.steps.length; i++) {
      final step = roadmap.steps[i];
      step.roadmapId = id;
      step.order = i + 1;
      final stepId = await d.insert('roadmap_steps', step.toMap());
      step.id = stepId;
    }
    roadmaps.insert(0, roadmap);
    _changed();
    return roadmap;
  }

  Future<void> deleteRoadmap(int roadmapId) async {
    final d = await db;
    await d.delete('roadmap_steps', where: 'roadmap_id = ?', whereArgs: [roadmapId]);
    await d.delete('roadmaps', where: 'id = ?', whereArgs: [roadmapId]);
    roadmaps.removeWhere((r) => r.id == roadmapId);
    _changed();
  }

  Future<void> setRoadmapStatus(int roadmapId, String status) async {
    final r = roadmaps.where((x) => x.id == roadmapId).firstOrNull;
    if (r == null) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    final d = await db;

    if (status == 'active') {
      r.startedAt ??= now;
    } else if (status == 'completed') {
      r.completedAt = now;
    }

    r.status = status;
    await d.update('roadmaps', {
      'status': status,
      if (r.startedAt != null) 'started_at': r.startedAt,
      if (r.completedAt != null) 'completed_at': r.completedAt,
    }, where: 'id = ?', whereArgs: [roadmapId]);

    _changed();
    // Yolculuk sürmeye başladıysa bağlı adımlar kayıtlara göre işaretlenir.
    await _syncLinkedSteps();
  }

  /// Adımı elle işaretler ya da işaretini kaldırır.
  Future<void> toggleRoadmapStep(int stepId, {bool? completed}) async {
    for (final r in roadmaps) {
      final step = r.steps.where((s) => s.id == stepId).firstOrNull;
      if (step != null) {
        final targetState = completed ?? !step.isCompleted;
        step.isCompleted = targetState;
        step.completedAt = targetState ? DateTime.now().millisecondsSinceEpoch : null;
        // Elle verilen karar uygulamanınkinin yerine geçer. Hedefi dolmuş adımın işaretini kaldıran
        // kullanıcı onu açık tutmak istiyordur; bu not düşülmezse adım ilk kayıtta yeniden işaretlenirdi.
        step.autoCompleted = false;
        step.keptOpen = !targetState && (stepProgress(r, step)?.reached ?? false);
        final d = await db;
        await d.update('roadmap_steps', {
          'is_completed': step.isCompleted ? 1 : 0,
          'completed_at': step.completedAt,
          'auto_completed': 0,
          'kept_open': step.keptOpen ? 1 : 0,
        }, where: 'id = ?', whereArgs: [stepId]);

        await _settleRoadmapStatus(r, reopened: !targetState);
        _changed();
        break;
      }
    }
  }

  /// Adımların durumuna göre yolculuğu kapatır ya da yeniden açar: bütün adımlar tamamlandıysa yolculuk
  /// tamamlanır; tamamlanmış bir yolculuğun adımı geri alındıysa ([reopened]) yolculuk sürmeye döner.
  Future<void> _settleRoadmapStatus(Roadmap r, {required bool reopened}) async {
    final allDone = r.steps.isNotEmpty && r.steps.every((s) => s.isCompleted);
    if (allDone && !r.isCompleted) {
      r.status = 'completed';
      r.completedAt = DateTime.now().millisecondsSinceEpoch;
    } else if (!allDone && r.isCompleted && reopened) {
      r.status = 'active';
      r.completedAt = null;
    } else {
      return;
    }
    await (await db).update('roadmaps', {'status': r.status, 'completed_at': r.completedAt},
        where: 'id = ?', whereArgs: [r.id]);
  }

  /// [text] ile yazılmış birim ("dk", "dakika", "min", "km", kullanıcının kendi birimi); tanınmıyorsa null.
  Unit? _unitNamed(String? text) {
    final t = normalizeTr(text ?? '');
    if (t.isEmpty) return null;
    final id = NaturalLanguageParser.unitIdForWord(t);
    if (id != null) return unit(id);
    return allUnits
        .where((u) => normalizeTr(u.id) == t || normalizeTr(u.symbol) == t || normalizeTr(u.name) == t)
        .firstOrNull;
  }

  /// Adımın, bağlı hedefinden, bağlı aktivitesinin kayıtlarından ya da geçen süreden hesaplanan ilerlemesi.
  /// Adım herhangi bir hedefe/aktiviteye bağlı değilse ve başlatılmış bir süresi yoksa veya yolculuk başlamadıysa null döner.
  StepProgress? stepProgress(Roadmap r, RoadmapStep step) {
    if (r.isNotStarted) return null;

    final hasGoal = step.linkedGoalId != null && goals.any((g) => g.id == step.linkedGoalId);
    final hasActivity = step.linkedActivityId != null && activities.containsKey(step.linkedActivityId);
    final hasStarted = step.startedAt != null;

    if (!hasGoal && !hasActivity && !hasStarted) return null;

    // Başlangıç anı: Adıma özel başlatma zamanı varsa o, yoksa haritanın başlangıcı.
    final since = step.startedAt ?? r.startedAt ?? r.createdAt;
    final isTr = strings.value.isTr;
    final hasTarget = (step.target ?? 0) > 0;
    final targetVal = hasTarget ? step.target! : 1.0;
    final defaultUnit = isDayUnit(step.unit) ? (isTr ? 'gün' : 'days') : (step.unit ?? '').trim();

    // 1. DURUM: Adım bir HEDEFE (Goal) bağlı (Örn: "Sıvı Alımı" günlük 2.5L hedefine ulaşma - 270 gün)
    if (hasGoal) {
      final g = goals.firstWhere((x) => x.id == step.linkedGoalId);
      final startDate = dayStart(DateTime.fromMillisecondsSinceEpoch(since));
      final today = dayStart(DateTime.now());
      var done = 0.0;

      if (!startDate.isAfter(today)) {
        final totalDays = today.difference(startDate).inDays;
        for (var i = 0; i <= totalDays; i++) {
          final day = startDate.add(Duration(days: i));
          final st = goalStatus(g, at: day);
          if (st.done) {
            done += 1.0;
          }
        }
      }
      return StepProgress(done, targetVal, defaultUnit);
    }

    // 2. DURUM: Adım bir AKTİVİTEYE bağlı
    if (hasActivity) {
      // 2A: Birimi GÜN ise (Aynı takvim gününde birden fazla kayıt olsa da yalnızca 1 gün sayılır!)
      if (isDayUnit(step.unit)) {
        final daysWithActivity = <String>{};
        for (final e in entriesForActivity(step.linkedActivityId!)) {
          if (e.ts < since) continue;
          daysWithActivity.add(_stepDayKey(DateTime.fromMillisecondsSinceEpoch(e.ts)));
        }
        final done = daysWithActivity.length.toDouble();
        return StepProgress(done, targetVal, defaultUnit);
      }

      // 2B: Birimi gün değilse: Ölçülü (L, ml, kg, dk, km vb.) veya adetli klasik hesaplama
      final goalUnit = hasTarget ? _unitNamed(step.unit) : null;
      final measured = goalUnit != null && goalUnit.dim != 'count';

      var done = 0.0;
      for (final e in entriesForActivity(step.linkedActivityId!)) {
        if (e.ts < since) continue;
        final u = e.unitId == null ? null : unit(e.unitId!);
        if (measured) {
          if (u != null && e.value != null && u.dim == goalUnit.dim) {
            done += e.value! * u.factor / goalUnit.factor;
          } else {
            final props = activityProperties(step.linkedActivityId!);
            final targetProp = props.where((p) => unit(p.unitId).dim == goalUnit.dim).firstOrNull;
            if (targetProp != null) {
              final pu = unit(targetProp.unitId);
              final perQty = targetProp.perQty > 0 ? targetProp.perQty : 1.0;
              double scale = e.qty;
              if (e.value != null && u != null) {
                final dimProp = props.where((p) => p.id != targetProp.id && unit(p.unitId).dim == u.dim).firstOrNull;
                if (dimProp != null && dimProp.value > 0) {
                  final du = unit(dimProp.unitId);
                  final dimPerQty = dimProp.perQty > 0 ? dimProp.perQty : 1.0;
                  scale = (e.value! * u.factor) / ((dimProp.value / dimPerQty) * du.factor);
                }
              }
              done += scale * (targetProp.value / perQty) * (pu.factor / goalUnit.factor);
            }
          }
        } else if (u == null) {
          done += e.qty;
        } else if (u.dim == 'count') {
          done += e.value ?? e.qty;
        } else {
          done += 1;
        }
      }
      return StepProgress(done, targetVal, (step.unit ?? '').trim());
    }

    // 3. DURUM: Süreli Adım / Meydan Okuma (Ne hedef ne aktivite bağlı, sadece süre başlatılmış)
    if (hasStarted) {
      final startDate = dayStart(DateTime.fromMillisecondsSinceEpoch(step.startedAt!));
      final today = dayStart(DateTime.now());
      final daysPassed = today.isBefore(startDate) ? 0 : today.difference(startDate).inDays + 1;
      final done = daysPassed.clamp(0, targetVal.toInt()).toDouble();
      return StepProgress(done, targetVal, defaultUnit);
    }

    return null;
  }

  /// Bağlı aktivitesi olan adımları kayıtlara uydurur. Hedefine ulaşan adım tamamlanır; uygulamanın
  /// tamamladığı bir adım, kayıt silinip hedefin altına düşülürse yeniden açılır (yanlışlıkla eklenip geri
  /// alınan bir kayıt adımı tamamlanmış bırakmasın). Kullanıcının kararına dokunulmaz: elle işaretlenmiş adım
  /// işaretli, hedefi dolduğu hâlde işareti elle kaldırılmış adım açık kalır. Başlamış bütün yolculuklara
  /// bakılır; tamamlanmış olanlara da, geri alma onları yeniden açabilsin diye.
  ///
  /// [announce] ise yeni tamamlanan adımlar bildirilir; veriler yeniden okunurken sessizce yapılır.
  Future<void> _syncLinkedSteps({bool announce = true}) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final flipped = <(Roadmap, RoadmapStep)>[];
    for (final r in roadmaps) {
      for (final step in r.steps) {
        final progress = stepProgress(r, step);
        if (progress == null) continue;
        if (progress.reached && !step.isCompleted && !step.keptOpen) {
          step.isCompleted = true;
          step.completedAt = now;
          step.autoCompleted = true;
        } else if (!progress.reached && step.isCompleted && step.autoCompleted) {
          step.isCompleted = false;
          step.completedAt = null;
          step.autoCompleted = false;
        } else {
          continue;
        }
        flipped.add((r, step));
      }
    }
    if (flipped.isEmpty) return;

    // Bellek yukarıda hemen güncellendi: araya giren ikinci bir çağrı aynı adımı yeniden çevirmez.
    final d = await db;
    for (final (_, step) in flipped) {
      await d.update('roadmap_steps', {
        'is_completed': step.isCompleted ? 1 : 0,
        'completed_at': step.completedAt,
        'auto_completed': step.autoCompleted ? 1 : 0,
      }, where: 'id = ?', whereArgs: [step.id]);
    }
    for (final r in {for (final (r, _) in flipped) r}) {
      final wasCompleted = r.isCompleted;
      await _settleRoadmapStatus(r, reopened: flipped.any((f) => f.$1 == r && !f.$2.isCompleted));
      if (announce && r.isCompleted && !wasCompleted) {
        final isTr = strings.value.isTr;
        NotificationService.showLimitAlert(
          isTr ? '🏁 Yol Haritası Tamamlandı!' : '🏁 Roadmap Completed!',
          isTr ? '"${r.title}" yolculuğunun bütün adımları tamam.' : 'Every step of "${r.title}" is done.',
        );
      }
    }
    if (announce) {
      final isTr = strings.value.isTr;
      for (final (r, step) in flipped) {
        // Yolculuk bittiyse onun bildirimi yeter; duraklatılmış yolculuğun adımı sessizce işaretlenir.
        if (!step.isCompleted || !r.isActive) continue;
        NotificationService.showLimitAlert(
          isTr ? '🗺️ Adım Tamamlandı' : '🗺️ Step Completed',
          '${step.title} · ${r.title}',
        );
      }
    }
    _changed();
  }

  Future<void> addRoadmapStep(int roadmapId, RoadmapStep step) async {
    final r = roadmaps.where((x) => x.id == roadmapId).firstOrNull;
    if (r == null) return;
    final d = await db;
    step.roadmapId = roadmapId;
    step.order = r.steps.length + 1;
    final stepId = await d.insert('roadmap_steps', step.toMap());
    step.id = stepId;
    r.steps.add(step);
    _changed();
    await _syncLinkedSteps();
  }

  /// Adımı bir aktiviteye bağlar ([activityId] null ise bağlantıyı kaldırır). Bağlı aktivitenin kayıtları
  /// adımın ilerlemesini belirler ([stepProgress]) ve hedefe ulaşınca adımı kendiliğinden tamamlar;
  /// aktivite Günlük ekranındaki yol haritası panelinden de tek dokunuşla kaydedilir.
  Future<void> setRoadmapStepActivity(int stepId, int? activityId) async {
    for (final r in roadmaps) {
      final step = r.steps.where((s) => s.id == stepId).firstOrNull;
      if (step == null) continue;
      step.linkedActivityId = activityId;
      // Açık tutma kararı eski aktivitenin kayıtları içindi.
      step.keptOpen = false;
      await (await db).update('roadmap_steps', {'linked_activity_id': activityId, 'kept_open': 0},
          where: 'id = ?', whereArgs: [stepId]);
      _changed();
      await _syncLinkedSteps();
      return;
    }
  }

  /// Adımı bir hedefe bağlar ([goalId] null ise bağlantıyı kaldırır). Bağlı hedefin tamamlanan günleri
  /// adımın ilerlemesini belirler ve hedefe ulaşılınca adımı kendiliğinden tamamlar.
  Future<void> setRoadmapStepGoal(int stepId, int? goalId) async {
    for (final r in roadmaps) {
      final step = r.steps.where((s) => s.id == stepId).firstOrNull;
      if (step == null) continue;
      step.linkedGoalId = goalId;
      step.keptOpen = false;
      await (await db).update('roadmap_steps', {'linked_goal_id': goalId, 'kept_open': 0},
          where: 'id = ?', whereArgs: [stepId]);
      _changed();
      await _syncLinkedSteps();
      return;
    }
  }

  /// Süreli adım veya meydan okuma için geri sayım / takip süresini başlatır.
  Future<void> startRoadmapStepDuration(int stepId, {int? startTs}) async {
    final ts = startTs ?? DateTime.now().millisecondsSinceEpoch;
    for (final r in roadmaps) {
      final step = r.steps.where((s) => s.id == stepId).firstOrNull;
      if (step == null) continue;
      step.startedAt = ts;
      step.keptOpen = false;
      await (await db).update('roadmap_steps', {'started_at': ts, 'kept_open': 0},
          where: 'id = ?', whereArgs: [stepId]);
      _changed();
      await _syncLinkedSteps();
      return;
    }
  }

  /// Süreli adımın başlangıç zamanını sıfırlayarak baştan başlatır.
  Future<void> resetRoadmapStepDuration(int stepId) async {
    final ts = DateTime.now().millisecondsSinceEpoch;
    for (final r in roadmaps) {
      final step = r.steps.where((s) => s.id == stepId).firstOrNull;
      if (step == null) continue;
      step.startedAt = ts;
      step.isCompleted = false;
      step.autoCompleted = false;
      step.completedAt = null;
      step.keptOpen = false;
      await (await db).update('roadmap_steps', {
        'started_at': ts,
        'is_completed': 0,
        'auto_completed': 0,
        'completed_at': null,
        'kept_open': 0,
      }, where: 'id = ?', whereArgs: [stepId]);
      _changed();
      await _syncLinkedSteps();
      return;
    }
  }

  Future<void> updateRoadmapStep(RoadmapStep step) async {
    final d = await db;
    await d.update('roadmap_steps', step.toMap(), where: 'id = ?', whereArgs: [step.id]);
    for (final r in roadmaps) {
      final idx = r.steps.indexWhere((s) => s.id == step.id);
      if (idx != -1) {
        r.steps[idx] = step;
        break;
      }
    }
    _changed();
    await _syncLinkedSteps();
  }

  Future<void> reorderRoadmapSteps(int roadmapId, int oldIndex, int newIndex) async {
    final r = roadmaps.where((x) => x.id == roadmapId).firstOrNull;
    if (r == null) return;
    if (oldIndex < 0 || oldIndex >= r.steps.length) return;
    if (newIndex < 0 || newIndex >= r.steps.length) return;
    final item = r.steps.removeAt(oldIndex);
    r.steps.insert(newIndex, item);
    final d = await db;
    final batch = d.batch();
    for (var i = 0; i < r.steps.length; i++) {
      final s = r.steps[i];
      s.order = i + 1;
      batch.update('roadmap_steps', {'step_order': s.order}, where: 'id = ?', whereArgs: [s.id]);
    }
    await batch.commit(noResult: true);
    _changed();
  }

  Future<void> deleteRoadmapStep(int roadmapId, int stepId) async {
    final r = roadmaps.where((x) => x.id == roadmapId).firstOrNull;
    if (r == null) return;
    final d = await db;
    await d.delete('roadmap_steps', where: 'id = ?', whereArgs: [stepId]);
    r.steps.removeWhere((s) => s.id == stepId);
    _changed();
  }

  /// Yolculuğu başlatılmamış hâline döndürür: adımların işareti kalkar ve başlangıç anı silinir. Yeniden
  /// başlatıldığında bağlı aktivitelerin yalnızca o andan sonraki kayıtları sayılır; eski başlangıç kalsaydı
  /// adımlar eski kayıtlarla hemen yeniden tamamlanırdı.
  Future<void> resetRoadmapProgress(int roadmapId) async {
    final r = roadmaps.where((x) => x.id == roadmapId).firstOrNull;
    if (r == null) return;
    final d = await db;
    for (final s in r.steps) {
      s.isCompleted = false;
      s.completedAt = null;
      s.autoCompleted = false;
      s.keptOpen = false;
    }
    await d.update('roadmap_steps', {
      'is_completed': 0,
      'completed_at': null,
      'auto_completed': 0,
      'kept_open': 0,
    }, where: 'roadmap_id = ?', whereArgs: [roadmapId]);
    r.status = 'not_started';
    r.startedAt = null;
    r.completedAt = null;
    await d.update('roadmaps', {
      'status': 'not_started',
      'started_at': null,
      'completed_at': null,
    }, where: 'id = ?', whereArgs: [roadmapId]);
    _changed();
  }

  // ---------------------------------------------------------------- YAPILACAKLAR (TODOS)

  /// Aktivitenin kayıt biçimini (süre, miktar, olay) döner.
  ActivityFormat activityFormat(int activityId) {
    final act = activity(activityId);
    final actEntries = entriesForActivity(activityId);
    if (actEntries.isNotEmpty) {
      return ActivityFormatAnalysis.detectFormat(
        activity: act,
        entries: actEntries,
        unitOf: unit,
      );
    }

    // İstatistikte kayıtlı ana boyut varsa
    final mainDim = stats[activityId]?.mainDim;
    if (mainDim == 'time') return ActivityFormat.duration;
    if (mainDim != null && mainDim != 'count' && mainDim != 'times') return ActivityFormat.quantity;

    // Bağlı hedefler
    final linkedGoals = goalsForActivity(activityId);
    for (final (g, _) in linkedGoals) {
      if (!g.isCount && g.unitId != null) {
        final u = unit(g.unitId!);
        if (u.dim == 'time') return ActivityFormat.duration;
        if (u.dim != 'count') return ActivityFormat.quantity;
      }
    }

    // Bağlı yol haritası adımları
    for (final r in roadmaps) {
      for (final step in r.steps) {
        if (step.linkedActivityId == activityId && step.unit != null) {
          final u = _unitNamed(step.unit);
          if (u?.dim == 'time') return ActivityFormat.duration;
          if (u != null && u.dim != 'count') return ActivityFormat.quantity;
        }
      }
    }

    // Aktivitenin tanımlı özellikleri
    for (final p in activityProperties(activityId)) {
      final u = unit(p.unitId);
      if (u.dim == 'time') return ActivityFormat.duration;
      if (u.dim != 'count') return ActivityFormat.quantity;
    }

    // Aktivitenin var olan kayıtlarındaki birimler
    for (final e in entries.where((e) => e.activityId == activityId && e.unitId != null)) {
      final u = unit(e.unitId!);
      if (u.dim == 'time') return ActivityFormat.duration;
      if (u.dim != 'count') return ActivityFormat.quantity;
    }

    // Daha önce bu aktiviteyle kullanılmış ölçüler
    final (usedMeasures, _) = measuresFor(activityId);
    for (final m in usedMeasures) {
      final u = unit(m.unitId);
      if (u.dim == 'time') return ActivityFormat.duration;
      if (u.dim != 'count') return ActivityFormat.quantity;
    }

    // Adından akıllı çıkarım (koşu, yürüyüş, çalışma vb. süre odaklı; su, çay vb. miktar odaklı)
    final norm = act.norm;
    if (norm.contains('yuru') || norm.contains('kos') || norm.contains('spor') ||
        norm.contains('calis') || norm.contains('ders') || norm.contains('uyku') ||
        norm.contains('odak') || norm.contains('yuz') || norm.contains('bisiklet')) {
      return ActivityFormat.duration;
    }
    if (norm.contains('su') || norm.contains('cay') || norm.contains('kahve') ||
        norm.contains('sut') || norm.contains('ayran') || norm.contains('icecek')) {
      return ActivityFormat.quantity;
    }

    return ActivityFormat.event;
  }

  /// Aktivitenin temel depolama birim kimliğini döner ('dk', 'l', 'g', 'adet' vb.).
  String activityBaseUnit(int activityId) {
    final format = activityFormat(activityId);
    if (format == ActivityFormat.duration) return 'dk';

    // Aktiviteye bağlı bir hedef varsa onun birimi önceliklidir
    final linkedGoals = goalsForActivity(activityId);
    for (final (g, _) in linkedGoals) {
      if (!g.isCount && g.unitId != null && g.unitId!.isNotEmpty) {
        return g.unitId!;
      }
    }

    // Bağlı yol haritası adımları
    for (final r in roadmaps) {
      for (final step in r.steps) {
        if (step.linkedActivityId == activityId && step.unit != null) {
          final u = _unitNamed(step.unit);
          if (u != null && u.dim != 'count') return u.id;
        }
      }
    }

    // Aktivitenin tanımlı özellikleri
    for (final p in activityProperties(activityId)) {
      final u = unit(p.unitId);
      if (u.dim == 'volume') return 'l';
      if (u.dim == 'mass') return u.factor >= 1000 ? 'kg' : 'g';
      if (u.dim == 'distance') return u.factor >= 1000 ? 'km' : 'm';
      if (u.dim == 'time') return 'dk';
      if (u.dim != 'count') return p.unitId;
    }

    // Aktivitenin var olan kayıtlarındaki birimler
    for (final e in entries.where((e) => e.activityId == activityId && e.unitId != null)) {
      final u = unit(e.unitId!);
      if (u.dim == 'volume') return 'l';
      if (u.dim == 'mass') return u.factor >= 1000 ? 'kg' : 'g';
      if (u.dim == 'distance') return u.factor >= 1000 ? 'km' : 'm';
      if (u.dim == 'time') return 'dk';
      if (u.dim != 'count') return e.unitId!;
    }

    // Daha önce bu aktiviteyle kullanılmış ölçüler
    final (usedMeasures, _) = measuresFor(activityId);
    for (final m in usedMeasures) {
      final u = unit(m.unitId);
      if (u.dim == 'volume') return 'l';
      if (u.dim == 'mass') return u.factor >= 1000 ? 'kg' : 'g';
      if (u.dim == 'distance') return u.factor >= 1000 ? 'km' : 'm';
      if (u.dim == 'time') return 'dk';
      if (u.dim != 'count') return m.unitId;
    }

    final norm = activity(activityId).norm;
    if (norm.contains('su') || norm.contains('cay') || norm.contains('kahve') ||
        norm.contains('sut') || norm.contains('ayran') || norm.contains('icecek')) {
      return 'l';
    }

    return 'adet';
  }

  /// Yapılacağa karşılık gelen sanal Hedef nesnesini döner.
  /// Bütün birim, dönüşüm ve ilerleme hesapları hedeflerin yardımcılarıyla ortaklaşır.
  Goal todoGoal(Todo todo) {
    final firstActId = todo.linkedActivityIds.firstOrNull;
    final format = firstActId != null ? activityFormat(firstActId) : ActivityFormat.event;

    // Hedefin birimi: öncelikle todo.targetUnit (veya başlıktan türetilen), yoksa aktivitenin temel birimi
    String? resolvedUnitId = todo.targetUnit;
    if (resolvedUnitId == null || resolvedUnitId.isEmpty) {
      if (todo.targetAmount != null) {
        final words = todo.title.split(RegExp(r'\s+'));
        for (final w in words) {
          final u = _unitNamed(w);
          if (u != null) {
            resolvedUnitId = u.id;
            break;
          }
        }
      }
      resolvedUnitId ??= (firstActId != null ? activityBaseUnit(firstActId) : 'adet');
    }

    final isCount = (todo.targetAmount == null && format == ActivityFormat.event) ||
        (format == ActivityFormat.event && resolvedUnitId == 'adet' && todo.targetAmount == null);

    return Goal(
      id: -todo.id,
      name: todo.title,
      mode: isCount ? 'count' : 'amount',
      unitId: isCount ? null : resolvedUnitId,
      target: todo.targetAmount ?? 1.0,
      period: GoalPeriod.total,
      startDate: todo.createdAt,
      createdAt: todo.createdAt,
      links: [
        for (final actId in todo.linkedActivityIds)
          GoalLink(activityId: actId, pct: 100),
      ],
    );
  }

/// Hedef miktara ulaşılıp ulaşılmadığını kayan noktalı sayı toleransıyla (epsilon) kontrol eder.
bool isTargetReached(double current, double target, {double epsilon = 1e-9}) =>
    current >= target - epsilon;

  /// Yapılacağın hesaplanan ilerleme ve tamamlanma durumu.
  TodoProgress todoProgress(Todo todo) {
    if (!todo.isLinked) {
      return TodoProgress(
        todo: todo,
        isCompleted: todo.doneAt != null,
      );
    }

    final goal = todoGoal(todo);
    final actIds = todo.linkedActivityIds.toSet();
    final matchingEntries = entries.where((e) => e.ts >= todo.createdAt && actIds.contains(e.activityId)).toList();

    double current = 0.0;
    final contributing = <Entry>[];

    if (todo.targetAmount != null) {
      for (final e in matchingEntries) {
        final c = contribution(goal, e, 100);
        if (c != null && c > 0) {
          current += c;
          contributing.add(e);
        }
      }
    } else {
      current = matchingEntries.length.toDouble();
      contributing.addAll(matchingEntries);
    }

    final derivedDone = (todo.targetAmount != null)
        ? isTargetReached(current, todo.targetAmount!)
        : matchingEntries.isNotEmpty;

    bool isDone;
    if (todo.manualState == 'done') {
      isDone = true;
    } else if (todo.manualState == 'open') {
      isDone = false;
    } else {
      isDone = derivedDone;
    }

    final unitSym = todo.targetAmount != null ? goalUnitSymbol(goal) : null;

    return TodoProgress(
      todo: todo,
      isCompleted: isDone,
      currentAmount: current,
      targetAmount: todo.targetAmount,
      unitSymbol: unitSym,
      contributingEntries: contributing,
    );
  }

  /// Henüz kaydedilmemiş bir veya birden fazla girdinin (EntryParsedItem veya BatchEntryInput)
  /// kaydedildiğinde hangi açık yapılacakları tamamlayacağını tahmin eder.
  /// Gerçek tamamlanma hesabı (todoProgress & contribution) ile birebir aynı kuralları uygular.
  List<Todo> predictCompletedTodos(Iterable<dynamic> items) {
    if (items.isEmpty) return const [];
    final openLinked = todos.where((t) => t.isLinked && !todoProgress(t).isCompleted).toList();
    if (openLinked.isEmpty) return const [];

    final simulatedEntries = <Entry>[];
    for (final it in items) {
      int? actId;
      int? measureId;
      double qty = 1.0;
      DateTime at = DateTime.now();
      DateTime? endAt;

      // EntryParsedItem veya BatchEntryInput nesnelerini destekler
      try {
        final dynamic dyn = it;
        if (dyn.activity != null) {
          actId = dyn.activity.id;
        } else if (dyn.activityId != null) {
          actId = dyn.activityId;
        }
        if (dyn.measure != null) {
          measureId = dyn.measure.id;
        } else if (dyn.measureId != null) {
          measureId = dyn.measureId;
        }
        if (dyn.quantity != null) {
          qty = (dyn.quantity as num).toDouble();
        } else if (dyn.qty != null) {
          qty = (dyn.qty as num).toDouble();
        }
        if (dyn.at != null) {
          at = dyn.at as DateTime;
        }
        if (dyn.endAt != null) {
          endAt = dyn.endAt as DateTime;
        }
      } catch (_) {}

      if (actId == null || !activities.containsKey(actId)) continue;

      final m = measureById(measureId) ?? defaultMeasureFor(actId);
      final format = activityFormat(actId);
      final unitId = m?.unitId ?? (format == ActivityFormat.duration ? 'dk' : null);
      final val = m != null ? m.amount * qty : (format == ActivityFormat.duration ? qty : null);

      simulatedEntries.add(
        Entry(
          id: -999,
          activityId: actId,
          ts: at.millisecondsSinceEpoch,
          endTs: endAt?.millisecondsSinceEpoch,
          measureId: m?.id,
          qty: qty,
          value: val,
          unitId: unitId,
        ),
      );
    }

    if (simulatedEntries.isEmpty) return const [];

    final willCompleteList = <Todo>[];
    for (final t in openLinked) {
      final goal = todoGoal(t);
      final currentProg = todoProgress(t);
      double additional = 0.0;
      int addCount = 0;

      for (final sim in simulatedEntries) {
        if (!t.linkedActivityIds.contains(sim.activityId)) continue;
        // Yapılacağın oluşturulmasından önceki kayıtlar sayılmaz
        if (sim.ts < t.createdAt) continue;

        if (t.targetAmount != null) {
          final c = contribution(goal, sim, 100);
          if (c != null && c > 0) {
            additional += c;
          }
        } else {
          addCount++;
        }
      }

      if (t.targetAmount != null) {
        if (additional > 0 && isTargetReached(currentProg.currentAmount + additional, t.targetAmount!)) {
          willCompleteList.add(t);
        }
      } else {
        if (addCount > 0) {
          willCompleteList.add(t);
        }
      }
    }
    return willCompleteList;
  }

  /// Bağlı bir yapılacağı tamamlarken ilgili miktar ve birimde kayıt açar.
  /// Biçim ve birim hedeflerin temel birimiyle eşleşir.
  Future<AddResult> completeTodoWithEntry(
    Todo todo, {
    int? activityId,
    double? amount,
    String? note,
    DateTime? at,
  }) async {
    final actId = activityId ?? todo.linkedActivityIds.firstOrNull;
    if (actId == null) {
      await toggleTodo(todo.id, completed: true);
      throw StateError('Todo has no linked activity');
    }

    final goal = todoGoal(todo);
    final progress = todoProgress(todo);
    final val = amount ?? (progress.remainingAmount > 0 ? progress.remainingAmount : (todo.targetAmount ?? 1.0));
    final targetUnitId = todo.targetUnit ?? goal.unitId ?? activityBaseUnit(actId);
    final targetU = unit(targetUnitId);

    // Aynı miktar "Ne yaptın?" kutusuna yazılsaydı açılacak 1.0 temel ölçüyü bul
    final m = measures.where((m) => m.unitId == targetUnitId && m.amount == 1.0).firstOrNull;

    AddResult result;
    if (m != null) {
      result = await addEntry(
        actId,
        measureId: m.id,
        qty: val,
        note: note,
        at: at,
      );
    } else if (targetU.dim == 'count') {
      result = await addEntry(
        actId,
        qty: val,
        value: val,
        unitId: targetUnitId,
        note: note,
        at: at,
      );
    } else {
      result = await addEntry(
        actId,
        value: val,
        unitId: targetUnitId,
        qty: 1,
        note: note,
        at: at,
      );
    }

    return result;
  }

  /// Kayıt değişimlerinde bağlı yapılacakların durumunu günceller.
  Future<void> _syncTodos({bool announce = true}) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final newlyCompleted = <Todo>[];
    final d = await db;

    for (final todo in todos) {
      if (!todo.isLinked) continue;
      final progress = todoProgress(todo);
      final derivedDone = (todo.targetAmount != null)
          ? isTargetReached(progress.currentAmount, todo.targetAmount!)
          : progress.contributingEntries.isNotEmpty;

      // Elle durum türetilen durumla aynıysa manualState temizlenir
      if (todo.manualState != null) {
        if ((todo.manualState == 'done' && derivedDone) ||
            (todo.manualState == 'open' && !derivedDone)) {
          todo.manualState = null;
          await d.update('todos', {'manual_state': null}, where: 'id = ?', whereArgs: [todo.id]);
        }
      }

      final isNowDone = todo.manualState == 'done' || (todo.manualState == null && derivedDone);
      if (isNowDone && todo.doneAt == null) {
        todo.doneAt = now;
        await d.update('todos', {'done_at': now}, where: 'id = ?', whereArgs: [todo.id]);
        newlyCompleted.add(todo);
      } else if (!isNowDone && todo.doneAt != null && todo.manualState != 'done') {
        todo.doneAt = null;
        await d.update('todos', {'done_at': null}, where: 'id = ?', whereArgs: [todo.id]);
      }
    }

    if (announce && newlyCompleted.isNotEmpty) {
      for (final t in newlyCompleted) {
        todoCompletedNotifier.value = t.title;
      }
    }
    _changed();
  }

  /// Yeni bir yapılacak ekler.
  Future<Todo> createTodo(Todo todo, {List<int>? activityIds}) async {
    final d = await db;
    if (activityIds != null) todo.linkedActivityIds = List.from(activityIds);
    if (todo.targetAmount != null && (todo.targetUnit == null || todo.targetUnit!.isEmpty)) {
      final firstActId = todo.linkedActivityIds.firstOrNull;
      Unit? titleUnit;
      final words = todo.title.split(RegExp(r'\s+'));
      for (final w in words) {
        final u = _unitNamed(w);
        if (u != null) {
          titleUnit = u;
          break;
        }
      }
      todo.targetUnit = titleUnit?.id ??
          (firstActId != null ? activityBaseUnit(firstActId) : 'adet');
    }
    final id = await d.insert('todos', todo.toMap());
    todo.id = id;
    for (final actId in todo.linkedActivityIds) {
      await d.insert('todo_links', {'todo_id': id, 'activity_id': actId});
    }
    todos.add(todo);
    await _syncTodos(announce: false);
    WidgetSync.schedule();
    _changed();
    return todo;
  }

  /// Mevcut bir yapılacağı günceller.
  Future<void> updateTodo(Todo todo, {List<int>? activityIds}) async {
    final d = await db;
    if (activityIds != null) todo.linkedActivityIds = List.from(activityIds);
    await d.update('todos', todo.toMap(), where: 'id = ?', whereArgs: [todo.id]);
    await d.delete('todo_links', where: 'todo_id = ?', whereArgs: [todo.id]);
    for (final actId in todo.linkedActivityIds) {
      await d.insert('todo_links', {'todo_id': todo.id, 'activity_id': actId});
    }
    final idx = todos.indexWhere((t) => t.id == todo.id);
    if (idx >= 0) todos[idx] = todo;
    await _syncTodos(announce: false);
    WidgetSync.schedule();
    _changed();
  }

  /// Yapılacağın tamamlanma durumunu değiştirir.
  Future<void> toggleTodo(int id, {bool? completed}) async {
    final todo = todos.where((t) => t.id == id).firstOrNull;
    if (todo == null) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final d = await db;

    if (!todo.isLinked) {
      final target = completed ?? (todo.doneAt == null);
      todo.doneAt = target ? now : null;
      todo.manualState = null;
      await d.update('todos', {
        'done_at': todo.doneAt,
        'manual_state': null,
      }, where: 'id = ?', whereArgs: [id]);
    } else {
      final progress = todoProgress(todo);
      final derivedDone = (todo.targetAmount != null)
          ? isTargetReached(progress.currentAmount, todo.targetAmount!)
          : progress.contributingEntries.isNotEmpty;

      final currentDone = todo.manualState == 'done' || (todo.manualState == null && derivedDone);
      final target = completed ?? !currentDone;

      if (target == derivedDone) {
        todo.manualState = null;
        todo.doneAt = target ? (todo.doneAt ?? now) : null;
      } else {
        todo.manualState = target ? 'done' : 'open';
        todo.doneAt = target ? now : null;
      }

      await d.update('todos', {
        'done_at': todo.doneAt,
        'manual_state': todo.manualState,
      }, where: 'id = ?', whereArgs: [id]);
    }

    _changed();
    WidgetSync.schedule();
  }

  /// Yapılacağı bir sonraki güne erteler: yeni son gün = max(son gün, bugün) + 1 gün; tarihsizse yarın.
  Future<void> postponeTodo(int id) async {
    final todo = todos.where((t) => t.id == id).firstOrNull;
    if (todo == null) return;
    final now = DateTime.now();
    DateTime baseDate;
    if (todo.dueDate == null || todo.dueDate!.isEmpty) {
      baseDate = now;
    } else {
      final cur = DateTime.tryParse(todo.dueDate!) ?? now;
      final curDay = DateTime(cur.year, cur.month, cur.day);
      final todayDay = DateTime(now.year, now.month, now.day);
      baseDate = curDay.isAfter(todayDay) ? curDay : todayDay;
    }
    final nextDate = baseDate.add(const Duration(days: 1));
    final nextDueDate = DateFormat('yyyy-MM-dd').format(nextDate);
    todo.dueDate = nextDueDate;
    await (await db).update('todos', {'due_date': nextDueDate}, where: 'id = ?', whereArgs: [id]);
    _changed();
    WidgetSync.schedule();
  }

  /// Yapılacağı siler ve geri alabilmek için silinen nesneyle bağlantılarını döner.
  Future<(Todo, List<int>)?> deleteTodo(int id) async {
    final todo = todos.where((t) => t.id == id).firstOrNull;
    if (todo == null) return null;
    final d = await db;
    final links = List<int>.from(todo.linkedActivityIds);
    await d.transaction((tx) async {
      await tx.delete('todo_links', where: 'todo_id = ?', whereArgs: [id]);
      await tx.delete('todos', where: 'id = ?', whereArgs: [id]);
    });
    todos.removeWhere((t) => t.id == id);
    _changed();
    WidgetSync.schedule();
    return (todo, links);
  }

  /// Silinmiş bir yapılacağı geri yükler.
  Future<void> restoreTodo(Todo todo, List<int> links) async {
    final d = await db;
    await d.transaction((tx) async {
      await tx.insert('todos', todo.toMap());
      for (final actId in links) {
        await tx.insert('todo_links', {'todo_id': todo.id, 'activity_id': actId});
      }
    });
    todo.linkedActivityIds = List.from(links);
    todos.add(todo);
    await _syncTodos(announce: false);
    _changed();
    WidgetSync.schedule();
  }

  /// Android ana ekran Todo widget'ı için veri paketi üretir.
  Map<String, Object?> todoWidgetPayload({DateTime? at}) {
    final now = at ?? DateTime.now();
    final todayStr = DateFormat('yyyy-MM-dd').format(now);
    final isTr = strings.value.isTr;

    final openTodos = todos.where((t) => !todoProgress(t).isCompleted).toList();

    final overdue = <Todo>[];
    final today = <Todo>[];
    final upcoming = <Todo>[];
    final dateless = <Todo>[];

    for (final t in openTodos) {
      if (t.dueDate == null || t.dueDate!.isEmpty) {
        dateless.add(t);
      } else if (t.dueDate!.compareTo(todayStr) < 0) {
        overdue.add(t);
      } else if (t.dueDate == todayStr) {
        today.add(t);
      } else {
        upcoming.add(t);
      }
    }

    overdue.sort((a, b) {
      final c = (a.dueDate ?? '').compareTo(b.dueDate ?? '');
      return c != 0 ? c : a.createdAt.compareTo(b.createdAt);
    });
    today.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    upcoming.sort((a, b) {
      final c = (a.dueDate ?? '').compareTo(b.dueDate ?? '');
      return c != 0 ? c : a.createdAt.compareTo(b.createdAt);
    });
    dateless.sort((a, b) => a.createdAt.compareTo(b.createdAt));

    final sorted = [...overdue, ...today, ...upcoming, ...dateless];

    final items = <Map<String, Object?>>[];
    for (final t in sorted) {
      final p = todoProgress(t);
      final isOverdue = t.dueDate != null && t.dueDate!.compareTo(todayStr) < 0;
      String sub = '';
      if (t.isLinked) {
        if (t.targetAmount != null) {
          sub = '${fmtNum(p.currentAmount)}/${fmtNum(t.targetAmount!)}';
          if (p.unitSymbol != null && p.unitSymbol!.isNotEmpty) {
            sub += ' ${p.unitSymbol}';
          }
        }
      }

      items.add({
        'id': t.id,
        't': t.title,
        'due': t.dueDate ?? '',
        'overdue': isOverdue,
        'linked': t.isLinked,
        'sub': sub,
      });
    }

    return {
      'count': openTodos.length,
      'theme': themeModeString,
      'isTr': isTr,
      'items': items,
    };
  }
}
