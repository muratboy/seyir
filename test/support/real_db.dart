import 'dart:io';
import 'dart:isolate';
import 'dart:ui';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:takip/data/store.dart';

/// Gives every isolate of the test process the same SQLite worker, found through the isolate name server.
///
/// This is what the Android plugin does: all isolates of the app share one connection per database
/// file. Without it an isolate started by a test would get a worker of its own, and sqflite_common_ffi
/// then closes the connections of the first worker, taking them for leftovers of a hot restart.
class _SharedWorker implements SqfliteFfiIsolatePortServer {
  const _SharedWorker();

  static const _name = 'takip_test.sqflite_worker';

  @override
  SendPort? lookupPort() => IsolateNameServer.lookupPortByName(_name);

  @override
  bool registerPort(SendPort sendPort) => IsolateNameServer.registerPortWithName(sendPort, _name);

  @override
  bool unregisterPort() => IsolateNameServer.removePortNameMapping(_name);
}

void _useSharedWorker() {
  sqfliteFfiInit();
  databaseFactory = createDatabaseFactoryFfi(isolatePortServer: const _SharedWorker());
}

/// Connects an isolate started by a test to the database of that test; [dbDir] is the databases path of
/// the test isolate. The connection is shared with the test isolate, so it must not be closed here.
Future<void> joinRealDatabase(String dbDir) async {
  _useSharedWorker();
  await databaseFactory.setDatabasesPath(dbDir);
}

/// Runs the tests of a file against real SQLite (sqflite_common_ffi) instead of in-memory lists.
///
/// Call once at the top of `main()`. Every test starts with an empty database. Several [AppStore]
/// instances opened within one test share that database, which is how the app's separate isolates
/// (notification actions, home screen widget) behave: each has its own store copy over the same file.
///
/// The process-wide [store] (used by the pages and by `NotificationService.handleNotificationAction`) is
/// detached from its database before every test, so it opens the database of the current test too.
void useRealDatabase() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _useSharedWorker();

  late Directory root;
  var seq = 0;

  setUpAll(() {
    root = Directory.systemTemp.createTempSync('takip_test_');
    // BackupService writes below the app documents directory; keep that inside the temp folder.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => root.path,
    );
  });

  setUp(() async {
    final dir = Directory('${root.path}/db_${seq++}')..createSync();
    await databaseFactory.setDatabasesPath(dir.path);
    await store.resetForTest();
  });

  tearDownAll(() {
    root.deleteSync(recursive: true);
  });
}

/// An [AppStore] on the current test database that has not read anything yet, like the store of an
/// isolate that has just started.
///
/// Timers still open when the test ends are discarded so the store's ticker stops.
AppStore newStore() {
  final s = AppStore();
  addTearDown(() async {
    await s.refresh();
    for (final t in List.of(s.activeTimers)) {
      await s.cancelTimer(t.id);
    }
  });
  return s;
}

/// A loaded [AppStore] on the current test database.
Future<AppStore> openStore() async {
  final s = newStore();
  await s.load();
  return s;
}
