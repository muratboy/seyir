import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../data/models.dart';
import '../data/store.dart';
import '../logic/format.dart';
import '../logic/l10n.dart';
import '../services/backup_service.dart';
import '../services/export_service.dart';
import '../services/notification_service.dart';
import '../widget_sync.dart';
import 'common.dart';

class ManagePage extends StatefulWidget {
  const ManagePage({super.key});

  @override
  State<ManagePage> createState() => _ManagePageState();
}

class _ManagePageState extends State<ManagePage> {
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final s = strings.value;
        return Scaffold(
          appBar: AppBar(
            title: Text(s.tabSettings, style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
          body: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            children: [
              // 1. Görünüm & Dil
              SectionTitle(s.sectionAppearanceLanguage),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        s.settingsTheme,
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: SegmentedButton<ThemeMode>(
                          style: const ButtonStyle(visualDensity: VisualDensity.compact),
                          segments: [
                            ButtonSegment(
                              value: ThemeMode.system,
                              icon: const Icon(Icons.brightness_auto, size: 16),
                              label: Text(s.isTr ? 'Sistem' : 'System'),
                            ),
                            ButtonSegment(
                              value: ThemeMode.light,
                              icon: const Icon(Icons.light_mode_outlined, size: 16),
                              label: Text(s.isTr ? 'Açık' : 'Light'),
                            ),
                            ButtonSegment(
                              value: ThemeMode.dark,
                              icon: const Icon(Icons.dark_mode_outlined, size: 16),
                              label: Text(s.isTr ? 'Koyu' : 'Dark'),
                            ),
                          ],
                          selected: {store.themeMode},
                          onSelectionChanged: (set) => store.setThemeMode(set.first),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Divider(height: 1, thickness: 0.5, color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.3)),
                      const SizedBox(height: 12),
                      Text(
                        s.settingsLanguage,
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: SegmentedButton<AppLanguage>(
                          style: const ButtonStyle(visualDensity: VisualDensity.compact),
                          segments: const [
                            ButtonSegment(
                              value: AppLanguage.tr,
                              icon: Text('🇹🇷', style: TextStyle(fontSize: 15)),
                              label: Text('Türkçe'),
                            ),
                            ButtonSegment(
                              value: AppLanguage.en,
                              icon: Text('🇬🇧', style: TextStyle(fontSize: 15)),
                              label: Text('English'),
                            ),
                          ],
                          selected: {store.language},
                          onSelectionChanged: (set) => store.setLanguage(set.first),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // 2. Aktiviteler & Veriler
              SectionTitle(s.sectionActivitiesData),
              Card(
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.category_outlined),
                      title: Text(s.activitiesManagement),
                      subtitle: Text(s.activitiesSub),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _openActivitiesManager(context),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.straighten_outlined),
                      title: Text(s.measuresManagement),
                      subtitle: Text(
                        s.isTr
                            ? '${store.measures.length} ölçü seçeneği kayıtlı'
                            : '${store.measures.length} measure options defined',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _openMeasuresManager(context),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.widgets_outlined),
                      title: Text(s.widgetSetup),
                      subtitle: Text(
                        s.isTr
                            ? 'Ana ekrandan tek dokunuşla hızlı kayıt'
                            : 'Quick logging from your home screen',
                      ),
                      trailing: FilledButton.tonal(
                        onPressed: () async {
                          final pinned = await WidgetSync.requestPin();
                          if (context.mounted && !pinned) {
                            showSnack(
                              context,
                              s.isTr
                                  ? 'Ana ekrana boş bir alana basılı tutup Widgetlar > Takip seçebilirsiniz.'
                                  : 'Long press home screen -> Widgets -> Takip to add.',
                            );
                          }
                        },
                        child: Text(s.isTr ? 'Ekle' : 'Add'),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // 3. Smart Alerts & Reminders
              SectionTitle(s.sectionNotificationsReminders),
              Card(
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.notifications_active_outlined, color: Colors.amber),
                      title: Text(s.isTr ? 'Bildirim İzni (Android)' : 'Notification Permission'),
                      subtitle: FutureBuilder<bool>(
                        future: NotificationService.areNotificationsEnabled(),
                        builder: (ctx, snap) {
                          final enabled = snap.data ?? false;
                          return Text(
                            enabled
                                ? (s.isTr ? 'Bildirimler etkinleştirildi ✓' : 'Notifications enabled ✓')
                                : (s.isTr ? 'Bildirimler kapalı (İzin gerekiyor)' : 'Notifications disabled (Requires permission)'),
                            style: TextStyle(
                              color: enabled ? Colors.green : Colors.orange,
                              fontSize: 12,
                            ),
                          );
                        },
                      ),
                      trailing: FilledButton.tonal(
                        onPressed: () async {
                          final granted = await NotificationService.requestPermission();
                          if (context.mounted) {
                            showSnack(
                              context,
                              granted
                                  ? (s.isTr ? 'Bildirim izni verildi!' : 'Notification permission granted!')
                                  : (s.isTr ? 'Bildirim izni reddedildi veya ayarlardan açılmalı.' : 'Notification permission denied.'),
                            );
                            setState(() {});
                          }
                        },
                        child: Text(s.isTr ? 'İzin İste' : 'Request'),
                      ),
                    ),
                    const Divider(height: 1),
                    SwitchListTile(
                      secondary: const Icon(Icons.alarm_on_outlined, color: Colors.deepOrange),
                      title: Text(s.isTr ? 'Sayaç & Pomodoro Bitiş Alarmı' : 'Timer & Pomodoro Finish Alarm'),
                      subtitle: Text(
                        s.isTr
                            ? 'Süre dolduğunda ses, titreşim ve alarm bildirimi'
                            : 'Sound, vibration and alarm alert when time ends',
                        style: const TextStyle(fontSize: 12),
                      ),
                      value: store.timerSoundEnabled,
                      onChanged: (val) {
                        store.setTimerSoundEnabled(val);
                        setState(() {});
                      },
                    ),
                    const Divider(height: 1),
                    SwitchListTile(
                      secondary: const Icon(Icons.water_drop_outlined, color: Colors.blue),
                      title: Text(s.isTr ? 'Gün İçi Su Hatırlatıcısı' : 'Daily Hydration Reminder'),
                      subtitle: Text(
                        store.waterReminderEnabled
                            ? (s.isTr
                                ? 'Her ${store.waterReminderIntervalHours} saatte bir (09:00–21:00)'
                                : 'Every ${store.waterReminderIntervalHours} hours (09:00–21:00)')
                            : (s.isTr ? 'Kapalı' : 'Disabled'),
                        style: const TextStyle(fontSize: 12),
                      ),
                      value: store.waterReminderEnabled,
                      onChanged: (val) async {
                        await store.setWaterReminder(enabled: val);
                        setState(() {});
                      },
                    ),
                    if (store.waterReminderEnabled) ...[
                      Padding(
                        padding: const EdgeInsets.only(left: 16, right: 16, bottom: 12),
                        child: Row(
                          children: [
                            Text(
                              s.isTr ? 'Aralık:' : 'Interval:',
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(width: 8),
                            Wrap(
                              spacing: 6,
                              children: [2, 3, 4].map((hours) {
                                final isSelected = store.waterReminderIntervalHours == hours;
                                return ChoiceChip(
                                  label: Text('$hours sa'),
                                  selected: isSelected,
                                  onSelected: (_) async {
                                    await store.setWaterReminder(enabled: true, intervalHours: hours);
                                    setState(() {});
                                  },
                                );
                              }).toList(),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const Divider(height: 1),
                    SwitchListTile(
                      secondary: const Icon(Icons.fact_check_outlined, color: Colors.teal),
                      title: Text(s.isTr ? 'Gün Sonu Takip Hatırlatıcısı' : 'End of Day Tracker Reminder'),
                      subtitle: Text(
                        store.dailySummaryReminderEnabled
                            ? (s.isTr
                                ? 'Her gün ${store.dailySummaryReminderTime} saatinde'
                                : 'Every day at ${store.dailySummaryReminderTime}')
                            : (s.isTr ? 'Kapalı' : 'Disabled'),
                        style: const TextStyle(fontSize: 12),
                      ),
                      value: store.dailySummaryReminderEnabled,
                      onChanged: (val) async {
                        await store.setDailySummaryReminder(enabled: val);
                        setState(() {});
                      },
                    ),
                    if (store.dailySummaryReminderEnabled) ...[
                      Padding(
                        padding: const EdgeInsets.only(left: 16, right: 16, bottom: 12),
                        child: Row(
                          children: [
                            Text(
                              s.isTr ? 'Hatırlatma Saati:' : 'Reminder Time:',
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(width: 12),
                            OutlinedButton.icon(
                              icon: const Icon(Icons.schedule, size: 16),
                              label: Text(store.dailySummaryReminderTime),
                              onPressed: () async {
                                final parts = store.dailySummaryReminderTime.split(':');
                                final initH = parts.isNotEmpty ? (int.tryParse(parts[0]) ?? 21) : 21;
                                final initM = parts.length > 1 ? (int.tryParse(parts[1]) ?? 30) : 30;
                                final picked = await showTimePicker(
                                  context: context,
                                  initialTime: TimeOfDay(hour: initH, minute: initM),
                                );
                                if (picked != null) {
                                  final h = picked.hour.toString().padLeft(2, '0');
                                  final m = picked.minute.toString().padLeft(2, '0');
                                  await store.setDailySummaryReminder(enabled: true, time: '$h:$m');
                                  setState(() {});
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      child: Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              icon: const Icon(Icons.water_drop, size: 16, color: Colors.blue),
                              label: Text(s.isTr ? 'Su Testi' : 'Water Test'),
                              onPressed: () {
                                NotificationService.showReminder(
                                  s.isTr ? '💧 Su İçme Zamanı' : '💧 Hydration Time',
                                  s.isTr
                                      ? 'Günlük sıvı hedefinize ulaşmak için bir bardak su için.'
                                      : 'Drink a glass of water to reach your daily goal.',
                                );
                                showSnack(context, s.isTr ? 'Su testi bildirimi gönderildi!' : 'Water test notification sent!');
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              icon: const Icon(Icons.alarm, size: 16, color: Colors.deepOrange),
                              label: Text(s.isTr ? 'Alarm Testi (3s)' : 'Alarm Test (3s)'),
                              onPressed: () {
                                NotificationService.scheduleTimerAlarm(
                                  timerId: 9999,
                                  activityName: s.isTr ? 'Test Pomodoro' : 'Test Pomodoro',
                                  remainingMs: 3000,
                                  isPomodoro: true,
                                  soundEnabled: store.timerSoundEnabled,
                                );
                                showSnack(
                                  context,
                                  s.isTr
                                      ? '3 saniye sonra test alarmı çalacak...'
                                      : 'Test alarm will ring in 3 seconds...',
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // 4. Yedekleme & Raporlama
              SectionTitle(s.sectionBackupReports),
              Card(
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.picture_as_pdf_outlined),
                      title: Text(s.isTr ? 'PDF Sağlık & Alışkanlık Raporu' : 'PDF Health & Habit Report'),
                      subtitle: Text(
                        s.isTr
                            ? 'Grafikler, hedefler ve son kayıtları içeren PDF oluştur'
                            : 'Generate PDF with stats, goals and recent logs',
                        style: const TextStyle(fontSize: 12),
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => ExportService.exportPdf(context, store),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.table_chart_outlined),
                      title: Text(s.isTr ? 'Excel (CSV) Tablosu' : 'Excel (CSV) Spreadsheet'),
                      subtitle: Text(
                        s.isTr
                            ? 'Tüm günlük geçmişi CSV formatında dışa aktar'
                            : 'Export complete timeline history to CSV',
                        style: const TextStyle(fontSize: 12),
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => ExportService.exportCsv(context, store),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.file_upload_outlined),
                      title: Text(s.backupExport),
                      subtitle: Text(
                        s.isTr ? 'JSON verisini panoya kopyala' : 'Copy JSON data to clipboard',
                        style: const TextStyle(fontSize: 12),
                      ),
                      onTap: () async {
                        final jsonStr = await store.exportJson();
                        await Clipboard.setData(ClipboardData(text: jsonStr));
                        if (context.mounted) {
                          showSnack(context, s.backupExported);
                        }
                      },
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.file_download_outlined),
                      title: Text(s.backupImport),
                      subtitle: Text(
                        s.isTr ? 'JSON yedeğinden geri yükle' : 'Restore from JSON backup',
                        style: const TextStyle(fontSize: 12),
                      ),
                      onTap: () => _showImportDialog(context),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.backup_outlined),
                      title: Text(s.isTr ? 'Yerel Yedekler & Geçmiş' : 'Local Backups & History'),
                      subtitle: Text(
                        s.isTr
                            ? 'Otomatik ve güvenlik yedeklerini incele / geri yükle'
                            : 'View or restore auto and safety backups',
                        style: const TextStyle(fontSize: 12),
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _showLocalBackupsSheet(context),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // 5. Gizlilik & Güvenlik
              SectionTitle(s.sectionPrivacySecurity),
              Card(
                elevation: 0,
                color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.25)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.verified_user_outlined,
                          size: 24,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Takip v2.1.0',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              s.privacyCardSubtitle,
                              style: TextStyle(
                                fontSize: 12,
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24),
            ],
          ),
        );
      },
    );
  }

  void _openActivitiesManager(BuildContext context) {
    final s = strings.value;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (c) => Scaffold(
          appBar: AppBar(
            title: Text(s.activitiesManagement),
            actions: [
              IconButton(
                icon: const Icon(Icons.add),
                tooltip: s.isTr ? 'Yeni aktivite' : 'New activity',
                onPressed: () async {
                  final nameCtrl = TextEditingController();
                  String? emoji;
                  await showDialog<void>(
                    context: c,
                    builder: (dialogContext) => StatefulBuilder(
                      builder: (dialogContext, setS) => AlertDialog(
                        title: Text(s.isTr ? 'Yeni Aktivite' : 'New Activity'),
                        content: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              children: [
                                InkWell(
                                  borderRadius: BorderRadius.circular(20),
                                  onTap: () async {
                                    final chosen = await showEmojiPicker(dialogContext);
                                    if (chosen != null) setS(() => emoji = chosen);
                                  },
                                  child: Container(
                                    width: 48,
                                    height: 48,
                                    decoration: BoxDecoration(
                                      color: Theme.of(dialogContext).colorScheme.primaryContainer,
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    alignment: Alignment.center,
                                    child: Text(emoji ?? '✨', style: const TextStyle(fontSize: 22)),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: TextField(
                                    controller: nameCtrl,
                                    autofocus: true,
                                    textCapitalization: TextCapitalization.sentences,
                                    decoration: InputDecoration(
                                      labelText: s.isTr ? 'Aktivite Adı' : 'Activity Name',
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text(s.cancel)),
                          FilledButton(
                            onPressed: () async {
                              final name = nameCtrl.text.trim();
                              if (name.isNotEmpty) {
                                await store.addActivity(name, emoji: emoji);
                                if (dialogContext.mounted) Navigator.pop(dialogContext);
                              }
                            },
                            child: Text(s.save),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
          body: AnimatedBuilder(
            animation: store,
            builder: (c, _) {
              final acts = store.activities.values.toList()
                ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

              return ListView.builder(
                itemCount: acts.length,
                itemBuilder: (c, i) {
                  final act = acts[i];
                  final count = store.stats[act.id]?.count ?? 0;
                  final linked = store.goalsForActivity(act.id);
                  return ListTile(
                    onTap: () => showActivityEditDialog(c, act),
                    leading: ActivityAvatar(act.id, size: 40),
                    title: Row(
                      children: [
                        Flexible(
                          child: Text(act.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                        ),
                        if (act.isArchived) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.grey.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              s.isTr ? 'Arşivde' : 'Archived',
                              style: const TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ],
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('$count ${s.isTr ? "kayıt" : "entries"}'),
                        if (linked.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Wrap(
                            spacing: 4,
                            runSpacing: 4,
                            children: [
                              for (final (g, _) in linked)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: (g.isLimit ? Colors.amber : Colors.blue).withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        g.isLimit ? Icons.shield_outlined : Icons.track_changes,
                                        size: 11,
                                        color: g.isLimit ? Colors.amber.shade800 : Colors.blue.shade800,
                                      ),
                                      const SizedBox(width: 3),
                                      Text(
                                        g.name,
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w500,
                                          color: g.isLimit ? Colors.amber.shade900 : Colors.blue.shade900,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ],
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (act.isArchived)
                          IconButton(
                            icon: const Icon(Icons.unarchive_outlined, color: Colors.teal),
                            tooltip: s.isTr ? 'Arşivden Çıkar' : 'Unarchive',
                            onPressed: () {
                              store.archiveActivity(act.id, archived: false);
                              showSnack(context, s.isTr ? '${act.name} arşivden çıkarıldı' : '${act.name} unarchived');
                            },
                          ),
                        IconButton(
                          icon: const Icon(Icons.edit_outlined),
                          tooltip: s.edit,
                          onPressed: () => showActivityEditDialog(c, act),
                        ),
                        IconButton(
                          icon: Icon(Icons.delete_outline, color: Theme.of(c).colorScheme.error),
                          tooltip: s.delete,
                          onPressed: () => _handleDeleteOrArchiveActivity(c, act),
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }

  void _openMeasuresManager(BuildContext context) {
    final s = strings.value;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (c) => Scaffold(
          appBar: AppBar(
            title: Text(s.measuresManagement),
            actions: [
              IconButton(
                icon: const Icon(Icons.add),
                tooltip: s.newMeasure,
                onPressed: () => showMeasureDialog(c),
              ),
            ],
          ),
          body: AnimatedBuilder(
            animation: store,
            builder: (c, _) {
              final list = store.measures;
              return ListView.builder(
                itemCount: list.length,
                itemBuilder: (c, i) {
                  final m = list[i];
                  final u = store.unit(m.unitId);
                  return ListTile(
                    leading: const CircleAvatar(child: Icon(Icons.local_cafe_outlined)),
                    title: Text(m.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text('${fmtNum(m.amount)} ${u.symbol} (${u.name})'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit_outlined),
                          onPressed: () => showMeasureDialog(c, existing: m),
                        ),
                        IconButton(
                          icon: Icon(Icons.delete_outline, color: Theme.of(c).colorScheme.error),
                          onPressed: () async {
                            final ok = await confirm(
                              c,
                              s.deleteConfirmTitle,
                              '${m.name} ${s.deleteConfirmDesc}',
                            );
                            if (ok) store.deleteMeasure(m);
                          },
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }

  void _showImportDialog(BuildContext context) {
    final s = strings.value;
    final jsonCtrl = TextEditingController();

    showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(s.backupImport),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              s.isTr
                  ? 'Daha önce kopyaladığınız JSON yedek metnini buraya yapıştırın:'
                  : 'Paste your previously copied backup JSON string here:',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: jsonCtrl,
              maxLines: 5,
              decoration: const InputDecoration(
                hintText: '{"app": "takip", ...}',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: Text(s.cancel)),
          FilledButton(
            onPressed: () async {
              try {
                await store.importJson(jsonCtrl.text.trim());
                if (c.mounted) {
                  Navigator.pop(c);
                  showSnack(context, s.backupSuccess);
                }
              } catch (e) {
                if (c.mounted) {
                  showSnack(context, 'Hata: $e');
                }
              }
            },
            child: Text(s.isTr ? 'Geri Yükle' : 'Restore'),
          ),
        ],
      ),
    );
  }

  void _handleDeleteOrArchiveActivity(BuildContext context, Activity act) {
    final s = strings.value;
    final entriesCount = store.entries.where((e) => e.activityId == act.id).length;

    if (entriesCount > 0 && !act.isArchived) {
      showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(s.isTr ? 'Aktiviteyi Yönet' : 'Manage Activity'),
          content: Text(
            s.isTr
                ? '"${act.name}" aktivitesine ait $entriesCount adet geçmiş kayıt bulunuyor.\n\n'
                  '• Arşivle (Önerilen): Geçmiş kayıtlarınız ve istatistikleriniz korunur, ancak yeni kayıt oluştururken önerilmez.\n\n'
                  '• Kalıcı Sil: Aktivite ve ona ait TÜM $entriesCount geçmiş kayıt geri dönüşsüz olarak silinir.'
                : '"${act.name}" has $entriesCount recorded entries.\n\n'
                  '• Archive (Recommended): Keeps historical data and statistics, but hides from quick suggestions.\n\n'
                  '• Permanently Delete: Deletes the activity and all historical entries permanently.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: Text(s.cancel),
            ),
            OutlinedButton(
              onPressed: () {
                Navigator.pop(c);
                store.archiveActivity(act.id, archived: true);
                showSnack(context, s.isTr ? '${act.name} arşivlendi' : '${act.name} archived');
              },
              child: Text(s.isTr ? 'Arşivle (Önerilen)' : 'Archive'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Theme.of(c).colorScheme.error),
              onPressed: () {
                Navigator.pop(c);
                store.deleteActivity(act.id);
                showSnack(context, s.isTr ? '${act.name} silindi' : '${act.name} deleted');
              },
              child: Text(s.isTr ? 'Kalıcı Olarak Sil' : 'Permanently Delete'),
            ),
          ],
        ),
      );
    } else {
      confirm(
        context,
        s.deleteConfirmTitle,
        '${act.name} ${s.deleteConfirmDesc}',
      ).then((ok) {
        if (ok) store.deleteActivity(act.id);
      });
    }
  }

  void _showLocalBackupsSheet(BuildContext context) {
    final s = strings.value;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (bottomContext) => StatefulBuilder(
        builder: (bottomContext, setSheetState) => FutureBuilder<List<BackupFileInfo>>(
          future: BackupService.listBackups(),
          builder: (context, snap) {
            final backups = snap.data ?? [];
            return DraggableScrollableSheet(
              expand: false,
              initialChildSize: 0.6,
              maxChildSize: 0.9,
              builder: (c, scrollCtrl) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Column(
                  children: [
                    Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          s.isTr ? 'Yerel Yedekler' : 'Local Backups',
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        FilledButton.icon(
                          icon: const Icon(Icons.add, size: 16),
                          label: Text(s.isTr ? 'Yeni Yedek Al' : 'Backup Now'),
                          onPressed: () async {
                            await BackupService.createBackup(store, prefix: 'manual');
                            setSheetState(() {});
                            if (bottomContext.mounted) {
                              showSnack(bottomContext, s.isTr ? 'Yedek başarıyla oluşturuldu' : 'Backup created');
                            }
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (snap.connectionState == ConnectionState.waiting)
                      const Expanded(child: Center(child: CircularProgressIndicator()))
                    else if (backups.isEmpty)
                      Expanded(
                        child: Center(
                          child: Text(
                            s.isTr ? 'Henüz kaydedilmiş yerel yedek yok' : 'No local backups found',
                            style: TextStyle(color: Theme.of(c).colorScheme.onSurfaceVariant),
                          ),
                        ),
                      )
                    else
                      Expanded(
                        child: ListView.builder(
                          controller: scrollCtrl,
                          itemCount: backups.length,
                          itemBuilder: (c, i) {
                            final b = backups[i];
                            String typeLabel = s.isTr ? 'Manuel' : 'Manual';
                            Color typeColor = Colors.blue;
                            if (b.isAutomatic) {
                              typeLabel = s.isTr ? 'Otomatik' : 'Auto';
                              typeColor = Colors.green;
                            } else if (b.isPreRestore) {
                              typeLabel = s.isTr ? 'Güvenlik' : 'Safety';
                              typeColor = Colors.orange;
                            }

                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ListTile(
                                leading: Icon(
                                  b.isAutomatic
                                      ? Icons.schedule
                                      : (b.isPreRestore ? Icons.shield_outlined : Icons.save_outlined),
                                  color: typeColor,
                                ),
                                title: Text(
                                  DateFormat('dd.MM.yyyy HH:mm').format(b.createdAt),
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const SizedBox(height: 3),
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                          decoration: BoxDecoration(
                                            color: typeColor.withValues(alpha: 0.15),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            typeLabel,
                                            style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: typeColor),
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          b.sizeLabel,
                                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      b.name,
                                      style: TextStyle(fontSize: 10.5, color: Theme.of(c).colorScheme.onSurfaceVariant),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.restore, size: 22, color: Colors.teal),
                                      tooltip: s.isTr ? 'Geri Yükle' : 'Restore',
                                      onPressed: () async {
                                        final ok = await confirm(
                                          c,
                                          s.isTr ? 'Yedeği Geri Yükle' : 'Restore Backup',
                                          s.isTr
                                              ? 'Bu yedeği geri yüklemek istediğinize emin misiniz? Mevcut verileriniz öncesinde otomatik güvenlik yedeğine alınacaktır.'
                                              : 'Restore this backup? A safety snapshot will be taken first.',
                                        );
                                        if (ok) {
                                          await BackupService.restoreFromFile(store, b.file);
                                          if (bottomContext.mounted) {
                                            Navigator.pop(bottomContext);
                                            showSnack(context, s.backupSuccess);
                                          }
                                        }
                                      },
                                    ),
                                    PopupMenuButton<String>(
                                      icon: const Icon(Icons.more_vert, size: 20),
                                      onSelected: (val) async {
                                        if (val == 'share') {
                                          SharePlus.instance.share(
                                            ShareParams(
                                              files: [XFile(b.file.path)],
                                              text: 'Takip JSON Yedeği (${b.name})',
                                            ),
                                          );
                                        } else if (val == 'delete') {
                                          final ok = await confirm(
                                            c,
                                            s.deleteConfirmTitle,
                                            s.isTr ? 'Bu yedek dosyasını silmek istediğinize emin misiniz?' : 'Delete this backup file?',
                                          );
                                          if (ok) {
                                            await b.file.delete();
                                            setSheetState(() {});
                                          }
                                        }
                                      },
                                      itemBuilder: (c) => [
                                        PopupMenuItem(
                                          value: 'share',
                                          child: Row(
                                            children: [
                                              const Icon(Icons.share_outlined, size: 18),
                                              const SizedBox(width: 8),
                                              Text(s.isTr ? 'Paylaş' : 'Share'),
                                            ],
                                          ),
                                        ),
                                        PopupMenuItem(
                                          value: 'delete',
                                          child: Row(
                                            children: [
                                              Icon(Icons.delete_outline, size: 18, color: Theme.of(c).colorScheme.error),
                                              const SizedBox(width: 8),
                                              Text(s.delete, style: TextStyle(color: Theme.of(c).colorScheme.error)),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
