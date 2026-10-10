import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class AppDb {
  static const int currentVersion = 2;

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
        await seed(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        await upgradeSchema(db, oldVersion, newVersion);
      },
      onOpen: (db) async {
        await ensureUpToDate(db);
      },
    );
  }

  static Future<void> upgradeSchema(DatabaseExecutor db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      try {
        await db.execute('ALTER TABLE entries ADD COLUMN end_ts INTEGER');
      } catch (_) {}
      try {
        await db.execute('ALTER TABLE activities ADD COLUMN is_archived INTEGER NOT NULL DEFAULT 0');
      } catch (_) {}
      try {
        await db.execute("ALTER TABLE active_timers ADD COLUMN segments TEXT DEFAULT '[]'");
      } catch (_) {}
      try {
        await db.execute('CREATE INDEX IF NOT EXISTS idx_entries_activity_ts ON entries(activity_id, ts)');
      } catch (_) {}
      try {
        await db.execute('CREATE INDEX IF NOT EXISTS idx_entries_end_ts ON entries(end_ts)');
      } catch (_) {}
    }
  }

  static Future<void> ensureUpToDate(DatabaseExecutor db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS settings(
      key TEXT PRIMARY KEY, value TEXT NOT NULL)''');
    try {
      await db.execute("ALTER TABLE measures ADD COLUMN qty_mode TEXT NOT NULL DEFAULT 'stepper'");
    } catch (_) {}
    try {
      await db.execute("ALTER TABLE measures ADD COLUMN choices TEXT DEFAULT '1,2,3,4,5'");
    } catch (_) {}
    try {
      await db.execute("ALTER TABLE measures ADD COLUMN grid_rows INTEGER NOT NULL DEFAULT 2");
    } catch (_) {}
    try {
      await db.execute("ALTER TABLE measures ADD COLUMN grid_cols INTEGER NOT NULL DEFAULT 5");
    } catch (_) {}
    try {
      await db.execute("ALTER TABLE goals ADD COLUMN type TEXT NOT NULL DEFAULT 'target'");
    } catch (_) {}
    try {
      await db.execute("ALTER TABLE goals ADD COLUMN is_habit INTEGER NOT NULL DEFAULT 0");
    } catch (_) {}
    try {
      await db.execute("ALTER TABLE activities ADD COLUMN category TEXT");
    } catch (_) {}
    try {
      await db.execute("ALTER TABLE activities ADD COLUMN color INTEGER");
    } catch (_) {}
    try {
      await db.execute("ALTER TABLE activities ADD COLUMN is_habit INTEGER NOT NULL DEFAULT 0");
    } catch (_) {}
    try {
      await db.execute("ALTER TABLE activities ADD COLUMN is_archived INTEGER NOT NULL DEFAULT 0");
    } catch (_) {}
    try {
      await db.execute("ALTER TABLE entries ADD COLUMN end_ts INTEGER");
    } catch (_) {}
    await db.execute('''CREATE TABLE IF NOT EXISTS active_timers(
      id INTEGER PRIMARY KEY AUTOINCREMENT, activity_id INTEGER NOT NULL,
      start_ts INTEGER NOT NULL, accumulated_ms INTEGER NOT NULL DEFAULT 0,
      last_resume_ts INTEGER, is_running INTEGER NOT NULL DEFAULT 1,
      note TEXT, mode TEXT NOT NULL DEFAULT 'stopwatch', target_ms INTEGER NOT NULL DEFAULT 0,
      segments TEXT DEFAULT '[]')''');
    try {
      await db.execute("ALTER TABLE active_timers ADD COLUMN mode TEXT NOT NULL DEFAULT 'stopwatch'");
    } catch (_) {}
    try {
      await db.execute("ALTER TABLE active_timers ADD COLUMN target_ms INTEGER NOT NULL DEFAULT 0");
    } catch (_) {}
    try {
      await db.execute("ALTER TABLE active_timers ADD COLUMN segments TEXT DEFAULT '[]'");
    } catch (_) {}
    try {
      await db.execute('CREATE INDEX IF NOT EXISTS idx_entries_activity_ts ON entries(activity_id, ts)');
    } catch (_) {}
    try {
      await db.execute('CREATE INDEX IF NOT EXISTS idx_entries_end_ts ON entries(end_ts)');
    } catch (_) {}
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
      sort INTEGER NOT NULL DEFAULT 0,
      is_habit INTEGER NOT NULL DEFAULT 0)''');
    await db.execute('''CREATE TABLE goal_links(
      goal_id INTEGER NOT NULL, activity_id INTEGER NOT NULL,
      pct REAL NOT NULL DEFAULT 100, PRIMARY KEY(goal_id, activity_id))''');
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
  }

  static Future<void> seed(DatabaseExecutor db) async {
    const measures = [
      ['Çay bardağı', 'l', 0.1],
      ['Su bardağı', 'l', 0.2],
      ['Fincan', 'l', 0.08],
      ['Kupa', 'l', 0.3],
      ['Şişe', 'l', 0.5],
      ['Kase', 'l', 0.25],
      ['Litre', 'l', 1.0],
      ['Dakika', 'dk', 1.0],
      ['Saat', 'sa', 1.0],
      ['Adet', 'adet', 1.0],
      ['Gram', 'g', 1.0],
      ['Kilometre', 'km', 1.0],
    ];
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
  ];
}
