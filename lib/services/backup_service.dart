import 'dart:io';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../data/store.dart';

class BackupFileInfo {
  final File file;
  final String name;
  final DateTime createdAt;
  final int sizeBytes;
  final bool isAutomatic;
  final bool isPreRestore;

  const BackupFileInfo({
    required this.file,
    required this.name,
    required this.createdAt,
    required this.sizeBytes,
    required this.isAutomatic,
    required this.isPreRestore,
  });

  String get sizeLabel {
    if (sizeBytes < 1024) return '$sizeBytes B';
    if (sizeBytes < 1024 * 1024) return '${(sizeBytes / 1024).toStringAsFixed(1)} KB';
    return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

class BackupService {
  static const int maxAutoBackups = 7;

  static Future<Directory> getBackupDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'backups'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Mevcut veritabanının JSON yedeğini dosyaya kaydeder.
  static Future<File> createBackup(AppStore store, {String prefix = 'backup'}) async {
    final dir = await getBackupDir();
    final jsonStr = await store.exportJson();
    final dateStr = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final fileName = '${prefix}_$dateStr.json';
    final file = File(p.join(dir.path, fileName));
    await file.writeAsString(jsonStr);

    if (prefix == 'auto') {
      await _pruneOldAutoBackups();
    }
    return file;
  }

  /// Geri yükleme öncesinde mevcut verileri kaybetmemek için otomatik güvenlik yedeği alır.
  static Future<File> createPreRestoreSnapshot(AppStore store) async {
    return createBackup(store, prefix: 'pre_restore');
  }

  /// Son 24 saat içinde otomatik yedek alınmamışsa yeni bir otomatik yedek oluşturur.
  static Future<File?> checkAndPerformDailyAutoBackup(AppStore store) async {
    try {
      final list = await listBackups();
      final autoBackups = list.where((b) => b.isAutomatic).toList();
      final now = DateTime.now();
      if (autoBackups.isNotEmpty) {
        final newest = autoBackups.first.createdAt;
        if (now.difference(newest).inHours < 24) {
          return null; // Zaten son 24 saat içinde alınmış
        }
      }
      return await createBackup(store, prefix: 'auto');
    } catch (_) {
      return null;
    }
  }

  /// Mevcut yerel yedek dosyalarını listeler (en yeniden en eskiye sıralı).
  static Future<List<BackupFileInfo>> listBackups() async {
    final dir = await getBackupDir();
    if (!await dir.exists()) return [];

    final files = dir.listSync().whereType<File>().where((f) => f.path.endsWith('.json')).toList();
    final result = <BackupFileInfo>[];

    for (final f in files) {
      final stat = await f.stat();
      final baseName = p.basename(f.path);
      final isAuto = baseName.startsWith('auto_');
      final isPre = baseName.startsWith('pre_restore_');
      result.add(BackupFileInfo(
        file: f,
        name: baseName,
        createdAt: stat.modified,
        sizeBytes: stat.size,
        isAutomatic: isAuto,
        isPreRestore: isPre,
      ));
    }

    result.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return result;
  }

  /// Bir yedek dosyasını geri yükler. store.importJson kendi içinde işlem öncesi güvenlik yedeği alır.
  static Future<void> restoreFromFile(AppStore store, File file) async {
    final jsonStr = await file.readAsString();
    await store.importJson(jsonStr);
  }

  static Future<void> _pruneOldAutoBackups() async {
    try {
      final list = await listBackups();
      final autoBackups = list.where((b) => b.isAutomatic).toList();
      if (autoBackups.length > maxAutoBackups) {
        for (var i = maxAutoBackups; i < autoBackups.length; i++) {
          await autoBackups[i].file.delete();
        }
      }
    } catch (_) {}
  }
}
