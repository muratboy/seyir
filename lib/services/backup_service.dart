import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../data/store.dart';

enum BackupSaveStatus { saved, cancelled, failure }

class BackupSaveResult {
  final BackupSaveStatus status;
  final Object? error;

  const BackupSaveResult.saved()
      : status = BackupSaveStatus.saved,
        error = null;

  const BackupSaveResult.cancelled()
      : status = BackupSaveStatus.cancelled,
        error = null;

  const BackupSaveResult.failure(this.error)
      : status = BackupSaveStatus.failure;

  bool get isSaved => status == BackupSaveStatus.saved;
  bool get isCancelled => status == BackupSaveStatus.cancelled;
  bool get isFailure => status == BackupSaveStatus.failure;
}

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

  /// Testlerde güvenlik yedeği hatasını simüle etmek için kullanılır.
  static Future<File> Function(AppStore store)? snapshotOverrideForTest;

  /// Testlerde sistem kaydetme penceresini taklit etmek için kullanılır.
  @visibleForTesting
  static Future<Uri?> Function({
    required String fileName,
    required Uint8List bytes,
  })? saveFileOverrideForTest;

  /// Yedeğin cihaza kaydedilmesi için önerilen dosya adı:
  /// Türkçe: seyir-yedek-YYYY-AA-GG-SSDD.json
  /// İngilizce: seyir-backup-YYYY-MM-DD-HHmm.json
  static String formatBackupFileName(DateTime dateTime, {bool isTr = true}) {
    final timePart = DateFormat('yyyy-MM-dd-HHmm').format(dateTime);
    final prefix = isTr ? 'seyir-yedek' : 'seyir-backup';
    return '$prefix-$timePart.json';
  }

  /// Android'in sistem kaydetme penceresini (Storage Access Framework) açıp
  /// yedeğin baytlarını kullanıcının seçtiği konuma yazar.
  static Future<BackupSaveResult> saveToDevice(
    File backup, {
    DateTime? createdAt,
    bool isTr = true,
  }) async {
    try {
      final dt = createdAt ?? (await backup.lastModified());
      final fileName = formatBackupFileName(dt, isTr: isTr);
      final bytes = await backup.readAsBytes();

      final Uri? uri;
      if (saveFileOverrideForTest != null) {
        uri = await saveFileOverrideForTest!(
          fileName: fileName,
          bytes: bytes,
        );
      } else {
        uri = await FilePicker.saveFile(
          fileName: fileName,
          bytes: bytes,
          mimeType: 'application/json',
          type: FileType.custom,
          allowedExtensions: const ['json'],
        );
      }

      if (uri == null) {
        return const BackupSaveResult.cancelled();
      }
      return const BackupSaveResult.saved();
    } catch (e) {
      return BackupSaveResult.failure(e);
    }
  }

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
    if (snapshotOverrideForTest != null) {
      return snapshotOverrideForTest!(store);
    }
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
    if (snapshotOverrideForTest != null) {
      return snapshotOverrideForTest!(store);
    }
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
      final isPre = baseName.startsWith('pre_restore_') || baseName.startsWith('pre_fix_');
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
