import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class AppDb {
  static const int currentVersion = 3;

  /// Yeni kurulumda (veritabanı ilk kez oluşturulurken) kullanılacak dil tercihi ('tr' veya 'en').
  /// main() içinden cihaz diline göre bildirilir; bildirilmezse (null) bugünkü gibi Türkçe kurulur.
  static String? preferredLanguage;

  static Future<Database> open() async {
    final path = p.join(await getDatabasesPath(), 'takip.db');
    return openDatabase(
      path,
      version: currentVersion,
      onConfigure: (db) async {
        await db.rawQuery('PRAGMA journal_mode=WAL');
        await db.rawQuery('PRAGMA busy_timeout=5000');
      },
      onCreate: (db, _) async {
        await createSchema(db);
        final lang = preferredLanguage == null
            ? null
            : (preferredLanguage!.toLowerCase() == 'tr' ? 'tr' : 'en');
        if (lang != null) {
          await db.insert('settings', {'key': 'lang', 'value': lang});
        }
        await seed(db, lang ?? 'tr');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        await upgradeSchema(db, oldVersion, newVersion);
      },
      onOpen: (db) async {
        await ensureUpToDate(db);
      },
    );
  }

  static Future<bool> hasColumn(DatabaseExecutor db, String table, String column) async {
    try {
      final cols = await db.rawQuery('PRAGMA table_info($table)');
      return cols.any((c) => c['name'] == column);
    } catch (_) {
      return false;
    }
  }

  static Future<void> ensureColumn(
    DatabaseExecutor db,
    String table,
    String column,
    String typeDef,
  ) async {
    if (!await hasColumn(db, table, column)) {
      try {
        await db.execute('ALTER TABLE $table ADD COLUMN $column $typeDef');
      } catch (_) {}
    }
  }

  static Future<void> upgradeSchema(DatabaseExecutor db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await _upgradeToV2(db);
    }
    if (oldVersion < 3) {
      await _upgradeToV3(db);
    }
  }

  static Future<void> _upgradeToV2(DatabaseExecutor db) async {
    await ensureColumn(db, 'entries', 'end_ts', 'INTEGER');
    await ensureColumn(db, 'activities', 'is_archived', 'INTEGER NOT NULL DEFAULT 0');
    await ensureColumn(db, 'active_timers', 'segments', "TEXT DEFAULT '[]'");
    try {
      await db.execute('CREATE INDEX IF NOT EXISTS idx_entries_activity_ts ON entries(activity_id, ts)');
    } catch (_) {}
    try {
      await db.execute('CREATE INDEX IF NOT EXISTS idx_entries_end_ts ON entries(end_ts)');
    } catch (_) {}
  }

  static Future<void> _upgradeToV3(DatabaseExecutor db) async {
    await ensureColumn(db, 'measures', 'qty_mode', "TEXT NOT NULL DEFAULT 'stepper'");
    await ensureColumn(db, 'measures', 'choices', "TEXT DEFAULT '1,2,3,4,5'");
    await ensureColumn(db, 'measures', 'grid_rows', 'INTEGER NOT NULL DEFAULT 2');
    await ensureColumn(db, 'measures', 'grid_cols', 'INTEGER NOT NULL DEFAULT 5');
    await ensureColumn(db, 'goals', 'type', "TEXT NOT NULL DEFAULT 'target'");
    await ensureColumn(db, 'activities', 'category', 'TEXT');
    await ensureColumn(db, 'activities', 'color', 'INTEGER');
    await ensureColumn(db, 'activities', 'is_habit', 'INTEGER NOT NULL DEFAULT 0');
    await ensureColumn(db, 'activities', 'is_archived', 'INTEGER NOT NULL DEFAULT 0');
    await ensureColumn(db, 'entries', 'end_ts', 'INTEGER');
    await ensureColumn(db, 'active_timers', 'mode', "TEXT NOT NULL DEFAULT 'stopwatch'");
    await ensureColumn(db, 'active_timers', 'target_ms', 'INTEGER NOT NULL DEFAULT 0');
    await ensureColumn(db, 'active_timers', 'segments', "TEXT DEFAULT '[]'");

    await db.execute('''CREATE TABLE IF NOT EXISTS settings(
      key TEXT PRIMARY KEY, value TEXT NOT NULL)''');
    await db.execute('''CREATE TABLE IF NOT EXISTS active_timers(
      id INTEGER PRIMARY KEY AUTOINCREMENT, activity_id INTEGER NOT NULL,
      start_ts INTEGER NOT NULL, accumulated_ms INTEGER NOT NULL DEFAULT 0,
      last_resume_ts INTEGER, is_running INTEGER NOT NULL DEFAULT 1,
      note TEXT, mode TEXT NOT NULL DEFAULT 'stopwatch', target_ms INTEGER NOT NULL DEFAULT 0,
      segments TEXT DEFAULT '[]')''');
    await db.execute('''CREATE TABLE IF NOT EXISTS roadmaps(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      title TEXT NOT NULL,
      description TEXT NOT NULL DEFAULT '',
      category TEXT NOT NULL DEFAULT '',
      emoji TEXT NOT NULL DEFAULT '🗺️',
      status TEXT NOT NULL DEFAULT 'not_started',
      created_at INTEGER NOT NULL,
      started_at INTEGER,
      completed_at INTEGER)''');
    await db.execute('''CREATE TABLE IF NOT EXISTS roadmap_steps(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      roadmap_id INTEGER NOT NULL,
      step_order INTEGER NOT NULL,
      title TEXT NOT NULL,
      description TEXT NOT NULL DEFAULT '',
      is_completed INTEGER NOT NULL DEFAULT 0,
      completed_at INTEGER,
      type TEXT NOT NULL DEFAULT 'task',
      target REAL,
      unit TEXT,
      linked_activity_id INTEGER,
      linked_goal_id INTEGER,
      started_at INTEGER)''');
    try {
      await db.execute('CREATE INDEX IF NOT EXISTS idx_entries_activity_ts ON entries(activity_id, ts)');
    } catch (_) {}
    try {
      await db.execute('CREATE INDEX IF NOT EXISTS idx_entries_end_ts ON entries(end_ts)');
    } catch (_) {}
    await db.execute('''CREATE TABLE IF NOT EXISTS goal_checkins(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      goal_id INTEGER NOT NULL,
      period_key TEXT NOT NULL,
      created_at INTEGER NOT NULL)''');
    try {
      await db.execute('CREATE UNIQUE INDEX IF NOT EXISTS idx_goal_checkins ON goal_checkins(goal_id, period_key)');
    } catch (_) {}
  }

  /// Adımın "kendiliğinden tamamlandı" ve "elle açık bırakıldı" işaretleri. Yalnızca eklenen sütunlardır ve
  /// eski sürümler onları görmezden gelir; bu yüzden sürüm numarası yükseltilmeden, açılışta yoksa eklenirler.
  /// Sürüm yükseltilseydi aynı veritabanını uygulamanın daha eski bir derlemesi artık açamazdı.
  static Future<void> _ensureRoadmapStepColumns(DatabaseExecutor db) async {
    await ensureColumn(db, 'roadmap_steps', 'auto_completed', 'INTEGER NOT NULL DEFAULT 0');
    await ensureColumn(db, 'roadmap_steps', 'kept_open', 'INTEGER NOT NULL DEFAULT 0');
    await ensureColumn(db, 'roadmap_steps', 'linked_goal_id', 'INTEGER');
    await ensureColumn(db, 'roadmap_steps', 'started_at', 'INTEGER');
  }

  static Future<void> ensureUpToDate(DatabaseExecutor db) async {
    // onOpen yalnızca eksik temel tabloların varlığını teyit eder; log kirleten gereksiz ALTER çalıştırmaz
    await db.execute('''CREATE TABLE IF NOT EXISTS settings(
      key TEXT PRIMARY KEY, value TEXT NOT NULL)''');
    await db.execute('''CREATE TABLE IF NOT EXISTS active_timers(
      id INTEGER PRIMARY KEY AUTOINCREMENT, activity_id INTEGER NOT NULL,
      start_ts INTEGER NOT NULL, accumulated_ms INTEGER NOT NULL DEFAULT 0,
      last_resume_ts INTEGER, is_running INTEGER NOT NULL DEFAULT 1,
      note TEXT, mode TEXT NOT NULL DEFAULT 'stopwatch', target_ms INTEGER NOT NULL DEFAULT 0,
      segments TEXT DEFAULT '[]')''');
    await db.execute('''CREATE TABLE IF NOT EXISTS roadmaps(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      title TEXT NOT NULL,
      description TEXT NOT NULL DEFAULT '',
      category TEXT NOT NULL DEFAULT '',
      emoji TEXT NOT NULL DEFAULT '🗺️',
      status TEXT NOT NULL DEFAULT 'not_started',
      created_at INTEGER NOT NULL,
      started_at INTEGER,
      completed_at INTEGER)''');
    await db.execute('''CREATE TABLE IF NOT EXISTS roadmap_steps(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      roadmap_id INTEGER NOT NULL,
      step_order INTEGER NOT NULL,
      title TEXT NOT NULL,
      description TEXT NOT NULL DEFAULT '',
      is_completed INTEGER NOT NULL DEFAULT 0,
      completed_at INTEGER,
      type TEXT NOT NULL DEFAULT 'task',
      target REAL,
      unit TEXT,
      linked_activity_id INTEGER,
      linked_goal_id INTEGER,
      started_at INTEGER,
      auto_completed INTEGER NOT NULL DEFAULT 0,
      kept_open INTEGER NOT NULL DEFAULT 0)''');
    await _ensureRoadmapStepColumns(db);
    await db.execute('''CREATE TABLE IF NOT EXISTS activity_properties(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      activity_id INTEGER NOT NULL,
      name TEXT NOT NULL,
      value REAL NOT NULL,
      unit_id TEXT NOT NULL,
      per_qty REAL NOT NULL DEFAULT 1.0,
      per_unit_id TEXT)''');
    await ensureColumn(db, 'activity_properties', 'per_unit_id', 'TEXT');
    await ensureColumn(db, 'goal_links', 'property_id', 'INTEGER');
    await ensureColumn(db, 'goal_links', 'custom_rate', 'REAL');
    await db.execute('''CREATE TABLE IF NOT EXISTS activity_reminders(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      activity_id INTEGER NOT NULL,
      time TEXT NOT NULL,
      days_of_week TEXT NOT NULL DEFAULT '1,2,3,4,5,6,7',
      is_enabled INTEGER NOT NULL DEFAULT 1,
      custom_message TEXT)''');
    await db.execute('''CREATE TABLE IF NOT EXISTS routines(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      emoji TEXT NOT NULL DEFAULT '⚡',
      sort INTEGER NOT NULL DEFAULT 0)''');
    await db.execute('''CREATE TABLE IF NOT EXISTS routine_items(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      routine_id INTEGER NOT NULL,
      activity_id INTEGER NOT NULL,
      measure_id INTEGER,
      qty REAL NOT NULL DEFAULT 1.0,
      note TEXT,
      sort INTEGER NOT NULL DEFAULT 0)''');
    await db.execute('''CREATE TABLE IF NOT EXISTS goal_checkins(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      goal_id INTEGER NOT NULL,
      period_key TEXT NOT NULL,
      created_at INTEGER NOT NULL)''');
    try {
      await db.execute('CREATE UNIQUE INDEX IF NOT EXISTS idx_goal_checkins ON goal_checkins(goal_id, period_key)');
    } catch (_) {}
    await _ensureTodoTables(db);
    await _ensureDefaultMeasures(db);
  }

  static Future<void> _ensureTodoTables(DatabaseExecutor db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS todos(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      title TEXT NOT NULL,
      note TEXT,
      created_at INTEGER NOT NULL,
      due_date TEXT,
      target_amount REAL,
      target_unit TEXT,
      done_at INTEGER,
      manual_state TEXT,
      sort_order INTEGER NOT NULL DEFAULT 0)''');
    await ensureColumn(db, 'todos', 'target_unit', 'TEXT');
    await db.execute('''CREATE TABLE IF NOT EXISTS todo_links(
      todo_id INTEGER NOT NULL,
      activity_id INTEGER NOT NULL,
      PRIMARY KEY(todo_id, activity_id))''');
  }

  /// Doğal dilde yazılan birimlerin ("500 ml", "2 kg", "45 sn", "500 m") doğru ölçüye bağlanabilmesi için
  /// 1 birimlik temel ölçülerin veritabanında bulunmasını sağlar.
  static Future<void> _ensureDefaultMeasures(DatabaseExecutor db) async {
    final settingsRows = await db.query('settings', where: 'key = ?', whereArgs: ['lang'], limit: 1);
    final isEn = settingsRows.isNotEmpty && settingsRows.first['value'] == 'en';
    final essentialMeasures = [
      [isEn ? 'Millilitre' : 'Mililitre', 'ml', 1.0],
      [isEn ? 'Milligram' : 'Miligram', 'mg', 1.0],
      [isEn ? 'Kilogram' : 'Kilogram', 'kg', 1.0],
      [isEn ? 'Second' : 'Saniye', 'sn', 1.0],
      [isEn ? 'Metre' : 'Metre', 'm', 1.0],
      [isEn ? 'Calorie' : 'Kalori', 'kcal', 1.0],
    ];
    for (final m in essentialMeasures) {
      final existing = await db.query(
        'measures',
        where: 'unit_id = ? AND amount = 1.0',
        whereArgs: [m[1]],
        limit: 1,
      );
      if (existing.isEmpty) {
        await db.insert('measures', {
          'name': m[0],
          'unit_id': m[1],
          'amount': m[2],
          'sort': 50,
        });
      }
    }
  }

  static Future<void> createSchema(DatabaseExecutor db) async {
    await db.execute('''CREATE TABLE units(
      id TEXT PRIMARY KEY, name TEXT NOT NULL, symbol TEXT NOT NULL,
      dim TEXT NOT NULL, factor REAL NOT NULL)''');
    await db.execute('''CREATE TABLE measures(
      id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL,
      unit_id TEXT NOT NULL, amount REAL NOT NULL, sort INTEGER NOT NULL DEFAULT 0,
      qty_mode TEXT NOT NULL DEFAULT 'stepper', choices TEXT DEFAULT '1,2,3,4,5',
      grid_rows INTEGER NOT NULL DEFAULT 2, grid_cols INTEGER NOT NULL DEFAULT 5)''');
    await db.execute('''CREATE TABLE activities(
      id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, emoji TEXT,
      category TEXT, color INTEGER, is_habit INTEGER NOT NULL DEFAULT 0,
      is_archived INTEGER NOT NULL DEFAULT 0, created_at INTEGER NOT NULL)''');
    await db.execute('''CREATE TABLE entries(
      id INTEGER PRIMARY KEY AUTOINCREMENT, activity_id INTEGER NOT NULL,
      ts INTEGER NOT NULL, end_ts INTEGER, measure_id INTEGER, qty REAL NOT NULL DEFAULT 1,
      value REAL, unit_id TEXT, note TEXT)''');
    await db.execute('CREATE INDEX idx_entries_ts ON entries(ts)');
    await db.execute('CREATE INDEX idx_entries_activity_ts ON entries(activity_id, ts)');
    await db.execute('CREATE INDEX idx_entries_end_ts ON entries(end_ts)');
    await db.execute('''CREATE TABLE goals(
      id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL,
      type TEXT NOT NULL DEFAULT 'target', mode TEXT NOT NULL,
      unit_id TEXT, target REAL NOT NULL, period TEXT NOT NULL,
      start_date INTEGER NOT NULL, end_date INTEGER, created_at INTEGER NOT NULL,
      sort INTEGER NOT NULL DEFAULT 0)''');
    await db.execute('''CREATE TABLE goal_links(
      goal_id INTEGER NOT NULL, activity_id INTEGER NOT NULL,
      pct REAL NOT NULL DEFAULT 100,
      property_id INTEGER,
      custom_rate REAL,
      PRIMARY KEY(goal_id, activity_id))''');
    await db.execute('''CREATE TABLE activity_properties(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      activity_id INTEGER NOT NULL,
      name TEXT NOT NULL,
      value REAL NOT NULL,
      unit_id TEXT NOT NULL,
      per_qty REAL NOT NULL DEFAULT 1.0,
      per_unit_id TEXT)''');
    await db.execute('''CREATE TABLE quick_items(
      id INTEGER PRIMARY KEY AUTOINCREMENT, activity_id INTEGER NOT NULL,
      kind TEXT NOT NULL, daily INTEGER NOT NULL DEFAULT 1, measure_id INTEGER,
      qty REAL NOT NULL DEFAULT 1, sort INTEGER NOT NULL DEFAULT 0,
      created_at INTEGER NOT NULL)''');
    await db.execute('''CREATE TABLE IF NOT EXISTS settings(
      key TEXT PRIMARY KEY, value TEXT NOT NULL)''');
    await db.execute('''CREATE TABLE IF NOT EXISTS active_timers(
      id INTEGER PRIMARY KEY AUTOINCREMENT, activity_id INTEGER NOT NULL,
      start_ts INTEGER NOT NULL, accumulated_ms INTEGER NOT NULL DEFAULT 0,
      last_resume_ts INTEGER, is_running INTEGER NOT NULL DEFAULT 1,
      note TEXT, mode TEXT NOT NULL DEFAULT 'stopwatch', target_ms INTEGER NOT NULL DEFAULT 0,
      segments TEXT DEFAULT '[]')''');
    await db.execute('''CREATE TABLE IF NOT EXISTS roadmaps(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      title TEXT NOT NULL,
      description TEXT NOT NULL DEFAULT '',
      category TEXT NOT NULL DEFAULT '',
      emoji TEXT NOT NULL DEFAULT '🗺️',
      status TEXT NOT NULL DEFAULT 'not_started',
      created_at INTEGER NOT NULL,
      started_at INTEGER,
      completed_at INTEGER)''');
    await db.execute('''CREATE TABLE IF NOT EXISTS roadmap_steps(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      roadmap_id INTEGER NOT NULL,
      step_order INTEGER NOT NULL,
      title TEXT NOT NULL,
      description TEXT NOT NULL DEFAULT '',
      is_completed INTEGER NOT NULL DEFAULT 0,
      completed_at INTEGER,
      type TEXT NOT NULL DEFAULT 'task',
      target REAL,
      unit TEXT,
      linked_activity_id INTEGER,
      auto_completed INTEGER NOT NULL DEFAULT 0,
      kept_open INTEGER NOT NULL DEFAULT 0)''');
    await db.execute('''CREATE TABLE IF NOT EXISTS activity_reminders(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      activity_id INTEGER NOT NULL,
      time TEXT NOT NULL,
      days_of_week TEXT NOT NULL DEFAULT '1,2,3,4,5,6,7',
      is_enabled INTEGER NOT NULL DEFAULT 1,
      custom_message TEXT)''');
    await db.execute('''CREATE TABLE IF NOT EXISTS routines(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      emoji TEXT NOT NULL DEFAULT '⚡',
      sort INTEGER NOT NULL DEFAULT 0)''');
    await db.execute('''CREATE TABLE IF NOT EXISTS routine_items(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      routine_id INTEGER NOT NULL,
      activity_id INTEGER NOT NULL,
      measure_id INTEGER,
      qty REAL NOT NULL DEFAULT 1.0,
      note TEXT,
      sort INTEGER NOT NULL DEFAULT 0)''');
  }

  static Future<void> seed(DatabaseExecutor db, [String languageCode = 'tr']) async {
    const measuresTr = [
      ['Çay bardağı', 'l', 0.1],
      ['Su bardağı', 'l', 0.2],
      ['Fincan', 'l', 0.08],
      ['Kupa', 'l', 0.3],
      ['Şişe', 'l', 0.5],
      ['Kase', 'l', 0.25],
      ['Litre', 'l', 1.0],
      ['Mililitre', 'ml', 1.0],
      ['Dakika', 'dk', 1.0],
      ['Saat', 'sa', 1.0],
      ['Saniye', 'sn', 1.0],
      ['Adet', 'adet', 1.0],
      ['Gram', 'g', 1.0],
      ['Kilogram', 'kg', 1.0],
      ['Metre', 'm', 1.0],
      ['Kilometre', 'km', 1.0],
      ['Kalori', 'kcal', 1.0],
    ];

    const measuresEn = [
      ['Tea glass', 'l', 0.1],
      ['Glass', 'l', 0.2],
      ['Cup', 'l', 0.08],
      ['Mug', 'l', 0.3],
      ['Bottle', 'l', 0.5],
      ['Bowl', 'l', 0.25],
      ['Litre', 'l', 1.0],
      ['Millilitre', 'ml', 1.0],
      ['Minute', 'dk', 1.0],
      ['Hour', 'sa', 1.0],
      ['Second', 'sn', 1.0],
      ['Piece', 'adet', 1.0],
      ['Gram', 'g', 1.0],
      ['Kilogram', 'kg', 1.0],
      ['Metre', 'm', 1.0],
      ['Kilometre', 'km', 1.0],
      ['Calorie', 'kcal', 1.0],
    ];

    final measures = languageCode == 'en' ? measuresEn : measuresTr;
    for (var i = 0; i < measures.length; i++) {
      final m = measures[i];
      await db.insert('measures', {'name': m[0], 'unit_id': m[1], 'amount': m[2], 'sort': i});
    }
  }

  static const tables = [
    'units',
    'measures',
    'activities',
    'entries',
    'goals',
    'goal_links',
    'quick_items',
    'settings',
    'active_timers',
    'roadmaps',
    'roadmap_steps',
    'activity_properties',
    'activity_reminders',
    'routines',
    'routine_items',
    'goal_checkins',
    'todos',
    'todo_links',
  ];
}
