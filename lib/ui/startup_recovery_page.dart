import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/store.dart';
import '../logic/l10n.dart';
import '../services/backup_service.dart';
import 'common.dart';
import 'app_font.dart';

/// Açılışta veriler okunamadığında ana ekran yerine gösterilir: uygulama hiç açılmamak yerine
/// yeniden denemeyi ve yerel yedeklerden birine dönmeyi sunar.
class StartupRecoveryPage extends StatefulWidget {
  final Object error;
  const StartupRecoveryPage({super.key, required this.error});

  @override
  State<StartupRecoveryPage> createState() => _StartupRecoveryPageState();
}

class _StartupRecoveryPageState extends State<StartupRecoveryPage> {
  late Object _error = widget.error;
  late final Future<List<BackupFileInfo>> _backups = _listBackups();
  bool _busy = false;

  Future<List<BackupFileInfo>> _listBackups() async {
    try {
      return await BackupService.listBackups();
    } catch (_) {
      return const [];
    }
  }

  /// [action] başarılı olursa store yüklenmiş olur ve uygulama ana ekrana geçer.
  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore(BackupFileInfo backup) async {
    final s = strings.value;
    final ok = await confirm(context, s.restoreBackupTitle, s.restoreBackupConfirm, ok: s.restore, destructive: false);
    if (ok) await _run(() => BackupService.restoreFromFile(store, backup.file));
  }

  @override
  Widget build(BuildContext context) {
    final s = strings.value;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text(s.startupErrorTitle, style: const TextStyle(fontWeight: FontWeight.bold))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Icon(Icons.error_outline_rounded, size: 48, color: scheme.error),
          const SizedBox(height: 12),
          Text(s.startupErrorDesc, textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text(
            '$_error',
            textAlign: TextAlign.center,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: AppFont.caption, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _busy ? null : () => _run(store.load),
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: Text(s.retry),
          ),
          SectionTitle(s.localBackups),
          FutureBuilder<List<BackupFileInfo>>(
            future: _backups,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              final backups = snap.data ?? const [];
              if (backups.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    s.noLocalBackups,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                );
              }
              return Column(
                children: [
                  for (final b in backups)
                    Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: Icon(
                          b.isAutomatic
                              ? Icons.schedule
                              : (b.isPreRestore ? Icons.shield_outlined : Icons.save_outlined),
                        ),
                        title: Text(
                          DateFormat('dd.MM.yyyy HH:mm').format(b.createdAt),
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: AppFont.small),
                        ),
                        subtitle: Text(
                          '${b.name} · ${b.sizeLabel}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: AppFont.micro),
                        ),
                        trailing: TextButton(
                          onPressed: _busy ? null : () => _restore(b),
                          child: Text(s.restore),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
