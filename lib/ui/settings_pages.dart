import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../data/store.dart';
import '../logic/format.dart';
import '../logic/l10n.dart';
import '../services/ai_service.dart';
import '../services/backup_service.dart';
import '../services/notification_service.dart';
import 'app_font.dart';
import 'common.dart';
import 'components/activity_reminders_sheet.dart';
import 'components/export_filter_sheet.dart';

// Ayarlar'ın alt sayfaları. Bildirimler, sağlık takibi ve yedekleme eskiden Ayarlar'ın tek uzun sayfasındaydı.

/// Bildirim izni, sayaç alarmı, otomatik kaydetme, hatırlatıcılar ve bir deneme bildirimi.
class NotificationSettingsPage extends StatefulWidget {
  const NotificationSettingsPage({super.key});

  @override
  State<NotificationSettingsPage> createState() => _NotificationSettingsPageState();
}

class _NotificationSettingsPageState extends State<NotificationSettingsPage> {
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final s = strings.value;
        return Scaffold(
          appBar: AppBar(title: Text(s.sectionNotificationsReminders)),
          body: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            children: [
              Card(
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.notifications_active_outlined, color: Colors.amber),
                      title: Text(s.isTr ? 'Bildirim İzni (Android)' : 'Notification Permission'),
                      // İzin düğmesi yalnızca izin yokken, durum satırının altında görünür.
                      subtitle: FutureBuilder<bool>(
                        future: NotificationService.areNotificationsEnabled(),
                        builder: (ctx, snap) {
                          final enabled = snap.data ?? false;
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                enabled
                                    ? (s.isTr ? 'Bildirimler etkinleştirildi\u00A0✓' : 'Notifications enabled\u00A0✓')
                                    : (s.isTr ? 'Bildirimler kapalı (İzin gerekiyor)' : 'Notifications disabled (Requires permission)'),
                                style: TextStyle(
                                  color: enabled ? Colors.green : Colors.orange,
                                  fontSize: AppFont.caption,
                                ),
                              ),
                              if (snap.hasData && !enabled) ...[
                                const SizedBox(height: 6),
                                FilledButton.tonal(
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
                              ],
                            ],
                          );
                        },
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
                        style: const TextStyle(fontSize: AppFont.caption),
                      ),
                      value: store.timerSoundEnabled,
                      onChanged: (val) {
                        store.setTimerSoundEnabled(val);
                        setState(() {});
                      },
                    ),
                    const Divider(height: 1),
                    SwitchListTile(
                      secondary: const Icon(Icons.save_as_outlined, color: Colors.teal),
                      title: Text(s.timerAutoSaveTitle),
                      subtitle: Text(
                        s.timerAutoSaveSubtitle,
                        style: const TextStyle(fontSize: AppFont.caption),
                      ),
                      value: store.timerAutoSaveCompleted,
                      onChanged: (val) {
                        store.setTimerAutoSaveCompleted(val);
                        setState(() {});
                      },
                    ),
                    const Divider(height: 1),
                    SwitchListTile(
                      secondary: const Icon(Icons.flash_on_outlined, color: Colors.amber),
                      title: Text(s.persistentQuickLogTitle),
                      subtitle: Text(
                        s.persistentQuickLogSubtitle,
                        style: const TextStyle(fontSize: AppFont.caption),
                      ),
                      value: store.persistentQuickLogEnabled,
                      onChanged: (val) async {
                        if (val) {
                          final granted = await NotificationService.requestPermission();
                          if (!granted && context.mounted) {
                            showSnack(
                              context,
                              s.isTr
                                  ? 'Kilit ekranında bildirim göstermek için bildirim izni gerekiyor.'
                                  : 'Notification permission is needed to show lock screen quick log.',
                            );
                            return;
                          }
                        }
                        await store.setPersistentQuickLogEnabled(val);
                        if (!mounted) return;
                        setState(() {});
                      },
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.dashboard_customize_outlined, color: Colors.indigo),
                      title: Text(s.isTr ? 'Hızlı Ayarlar Kutucuğu' : 'Quick Settings Tile'),
                      subtitle: Text(
                        s.isTr
                            ? 'Kilit ekranından hızlı kayıt paneli'
                            : 'Quick log panel from lock screen',
                        style: const TextStyle(fontSize: AppFont.caption),
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => _showQuickSettingsTileDialog(context, s.isTr),
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
                        style: const TextStyle(fontSize: AppFont.caption),
                      ),
                      value: store.waterReminderEnabled,
                      onChanged: (val) async {
                        await store.setWaterReminder(enabled: val);
                        if (!mounted) return;
                        setState(() {});
                      },
                    ),
                    if (store.waterReminderEnabled) ...[
                      Padding(
                        padding: const EdgeInsets.only(left: 16, right: 16, bottom: 12),
                        // Dar ekranda seçenekler etiketin altına geçer.
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              s.isTr ? 'Aralık:' : 'Interval:',
                              style: const TextStyle(fontSize: AppFont.caption, fontWeight: FontWeight.bold),
                            ),
                            Wrap(
                              spacing: 6,
                              children: [2, 3, 4].map((hours) {
                                final isSelected = store.waterReminderIntervalHours == hours;
                                return ChoiceChip(
                                  label: Text('${fmtNum1(hours.toDouble())} $hourWord'),
                                  selected: isSelected,
                                  onSelected: (_) async {
                                    await store.setWaterReminder(enabled: true, intervalHours: hours);
                                    if (!mounted) return;
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
                      title: Text(s.isTr ? 'Gün Sonu Seyir Hatırlatıcısı' : 'End of Day Reminder'),
                      subtitle: Text(
                        store.dailySummaryReminderEnabled
                            ? (s.isTr
                                ? 'Her gün ${store.dailySummaryReminderTime} saatinde'
                                : 'Every day at ${store.dailySummaryReminderTime}')
                            : (s.isTr ? 'Kapalı' : 'Disabled'),
                        style: const TextStyle(fontSize: AppFont.caption),
                      ),
                      value: store.dailySummaryReminderEnabled,
                      onChanged: (val) async {
                        await store.setDailySummaryReminder(enabled: val);
                        if (!mounted) return;
                        setState(() {});
                      },
                    ),
                    if (store.dailySummaryReminderEnabled) ...[
                      Padding(
                        padding: const EdgeInsets.only(left: 16, right: 16, bottom: 12),
                        // Dar ekranda büyük yazıyla saat düğmesi etiketin altına geçer; yan yana taşıyordu.
                        child: Wrap(
                          spacing: 12,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              s.isTr ? 'Hatırlatma Saati:' : 'Reminder Time:',
                              style: const TextStyle(fontSize: AppFont.caption, fontWeight: FontWeight.bold),
                            ),
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
                                if (!mounted) return;
                                if (picked != null) {
                                  final h = picked.hour.toString().padLeft(2, '0');
                                  final m = picked.minute.toString().padLeft(2, '0');
                                  await store.setDailySummaryReminder(enabled: true, time: '$h:$m');
                                  if (!mounted) return;
                                  setState(() {});
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.alarm_on_rounded, color: Colors.teal),
                      title: Text(s.isTr ? 'Aktivite Hatırlatıcıları' : 'Activity Reminders'),
                      subtitle: Text(
                        store.activityReminders.isEmpty
                            ? (s.isTr ? 'Özel hatırlatıcı kurulmamış' : 'No custom reminders set')
                            : '${store.activityReminders.length} ${s.isTr ? "özel hatırlatıcı kurulu" : "custom reminders"}',
                        style: const TextStyle(fontSize: AppFont.caption),
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.add_circle_outline, size: 22),
                        tooltip: s.isTr ? 'Hatırlatıcı Ekle' : 'Add Reminder',
                        onPressed: () async {
                          final act = await showActivityPicker(context, title: s.isTr ? 'Hatırlatıcı İçin Aktivite Seç' : 'Choose Activity for Reminder');
                          if (act != null && context.mounted) {
                            ActivityRemindersSheet.show(context, act);
                          }
                        },
                      ),
                    ),
                    if (store.activityReminders.isNotEmpty) ...[
                      for (final rem in store.activityReminders)
                        ListTile(
                          dense: true,
                          contentPadding: const EdgeInsets.only(left: 32, right: 16),
                          leading: Text(store.activity(rem.activityId).emoji ?? '⏰', style: const TextStyle(fontSize: 18)),
                          title: Text('${store.activity(rem.activityId).name} · ${rem.time}'),
                          subtitle: Text(
                            rem.daysOfWeek.split(',').length == 7 ? (s.isTr ? 'Her gün' : 'Every day') : '${rem.daysOfWeek.split(',').length} ${s.isTr ? "gün/hafta" : "days/week"}',
                            style: const TextStyle(fontSize: AppFont.micro),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Switch(
                                value: rem.isEnabled,
                                onChanged: (val) => store.toggleActivityReminder(rem.id, val),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline, size: 18),
                                onPressed: () => store.deleteActivityReminder(rem.id),
                              ),
                            ],
                          ),
                        ),
                    ],
                    const Divider(height: 1),
                    // Tek bir deneme: izin yoksa önce izin istenir, sonra sayaç alarmının yolundan bir bildirim gelir.
                    // Eskiden "Su Testi" ve "Alarm Testi" diye iki geliştirici düğmesi vardı.
                    ListTile(
                      leading: const Icon(Icons.notification_add_outlined, color: Colors.deepOrange),
                      title: Text(s.isTr ? 'Bildirimi Dene' : 'Try a Notification'),
                      subtitle: Text(
                        s.isTr
                            ? '3 saniye sonra, sayaç alarmının ses ve titreşim ayarlarıyla bir deneme bildirimi gelir'
                            : 'A test notification arrives in 3 seconds, with the sound and vibration of the timer alarm',
                        style: const TextStyle(fontSize: AppFont.caption),
                      ),
                      onTap: () => _tryNotification(context),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        );
      },
    );
  }

  /// İzin yoksa önce izin ister; varsa birkaç saniye sonra bir deneme bildirimi planlar.
  Future<void> _tryNotification(BuildContext context) async {
    final s = strings.value;
    var allowed = await NotificationService.areNotificationsEnabled();
    if (!allowed) allowed = await NotificationService.requestPermission();
    if (!context.mounted) return;
    setState(() {}); // izin satırı yeni durumu göstersin
    if (!allowed) {
      showSnack(
        context,
        s.isTr
            ? 'Bildirim izni yok. Telefonun ayarlarında Seyir için bildirimleri açabilirsin.'
            : 'Notifications are not allowed. You can turn them on for Seyir in the phone settings.',
      );
      return;
    }
    await NotificationService.scheduleTestNotification(soundEnabled: store.timerSoundEnabled);
    if (context.mounted) {
      showSnack(
        context,
        s.isTr ? '3 saniye içinde bir deneme bildirimi gelecek.' : 'A test notification arrives in 3 seconds.',
      );
    }
  }

  Future<void> _showQuickSettingsTileDialog(BuildContext context, bool isTr) async {
    try {
      final added = await const MethodChannel('dev.takip.takip/permissions')
          .invokeMethod<bool>('requestAddQuickSettingsTile');
      if (added == true && context.mounted) {
        showSnack(
          context,
          isTr
              ? 'Hızlı Ayarlar kutucuğu eklendi!'
              : 'Quick Settings tile added!',
        );
        return;
      }
    } catch (_) {}

    if (!context.mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.dashboard_customize_rounded, color: Colors.indigo),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                isTr ? 'Hızlı Ayarlar Kutucuğu' : 'Quick Settings Tile',
                style: const TextStyle(fontSize: 17),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isTr
                  ? 'Telefonunuzun kilit ekranından ve herhangi bir uygulamanın içinden tek dokunuşla kayıt yapabilirsiniz:\n\n'
                    '1. Bildirim panelini en üstten iki kez aşağı çekin.\n'
                    '2. Kalem (Düzenle) simgesine dokunun.\n'
                    '3. "Hızlı Kayıt" kutucuğunu aktif alana sürükleyin.\n\n'
                    'Artık telefon kilitliyken bile kutucuğa dokunarak sesle veya yazıyla anında kayıt ekleyebilirsiniz.'
                  : 'Log activities in 1 second from lock screen or anywhere:\n\n'
                    '1. Swipe down twice from the top of the screen.\n'
                    '2. Tap the Pencil (Edit) icon.\n'
                    '3. Drag "Quick Log" into your active tiles.\n\n'
                    'You can then tap the tile to record by voice or text even while locked.',
              style: const TextStyle(fontSize: 14, height: 1.4),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(isTr ? 'Anladım' : 'Got it'),
          ),
        ],
      ),
    );
  }
}

/// Adım sayar ve uyku takibi.
class HealthSettingsPage extends StatefulWidget {
  const HealthSettingsPage({super.key});

  @override
  State<HealthSettingsPage> createState() => _HealthSettingsPageState();
}

class _HealthSettingsPageState extends State<HealthSettingsPage> {
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final s = strings.value;
        return Scaffold(
          appBar: AppBar(title: Text(s.sectionHealthTracking)),
          body: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            children: [
              Card(
                child: Column(
                  children: [
                    // Adım Sayar
                    SwitchListTile(
                      secondary: const Icon(Icons.directions_walk_rounded, color: Colors.teal),
                      title: Text(s.stepTrackerTitle),
                      subtitle: ValueListenableBuilder<int>(
                        valueListenable: store.stepsNotifier,
                        builder: (context, steps, _) {
                          // Sayar açık ama sayamıyorsa "Aktif" demek yanıltır.
                          final problem = !store.stepTrackerEnabled
                              ? null
                              : store.stepPermissionMissing
                                  ? s.stepPermissionMissing
                                  : (store.stepSensorError != null ? s.stepSensorUnavailable : null);
                          return Text(
                            problem ??
                                (store.stepTrackerEnabled
                                    ? (s.isTr
                                        ? 'Aktif · Bugün: ${fmtNum(steps.toDouble())} / ${fmtNum(store.stepDailyGoal.toDouble())} adım'
                                        : 'Active · Today: ${fmtNum(steps.toDouble())} / ${fmtNum(store.stepDailyGoal.toDouble())} steps')
                                    : s.stepTrackerSubtitle),
                            style: TextStyle(
                              fontSize: AppFont.caption,
                              color: problem == null ? null : Theme.of(context).colorScheme.error,
                            ),
                          );
                        },
                      ),
                      value: store.stepTrackerEnabled,
                      onChanged: (val) async {
                        final ok = await store.setStepTrackerEnabled(val);
                        if (!context.mounted) return;
                        if (!ok) showSnack(context, s.stepPermissionDenied);
                        setState(() {});
                      },
                    ),
                    if (store.stepTrackerEnabled) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${s.stepDailyGoal}:',
                              style: const TextStyle(fontSize: AppFont.caption, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              children: [6000, 8000, 10000, 12000].map((goal) {
                                final isSelected = store.stepDailyGoal == goal;
                                return ChoiceChip(
                                  label: Text('$goal'),
                                  selected: isSelected,
                                  onSelected: (_) async {
                                    await store.setStepDailyGoal(goal);
                                    if (!mounted) return;
                                    setState(() {});
                                  },
                                );
                              }).toList(),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
                                  icon: const Icon(Icons.add, size: 14),
                                  label: Text(s.isTr ? '+500 Adım' : '+500 Steps'),
                                  onPressed: () async {
                                    await store.addManualSteps(500);
                                    if (!mounted) return;
                                    setState(() {});
                                  },
                                ),
                                OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
                                  icon: const Icon(Icons.add, size: 14),
                                  label: Text(s.isTr ? '+1000 Adım' : '+1000 Steps'),
                                  onPressed: () async {
                                    await store.addManualSteps(1000);
                                    if (!mounted) return;
                                    setState(() {});
                                  },
                                ),
                                FilledButton.tonalIcon(
                                  style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
                                  icon: const Icon(Icons.sync, size: 14),
                                  label: Text(s.syncSteps),
                                  onPressed: () async {
                                    final res = await store.syncTodayStepsToEntry();
                                    if (context.mounted) {
                                      showSnack(
                                        context,
                                        res != null
                                            ? (s.isTr
                                                ? '${fmtNum(store.todaySteps.toDouble())} adım aktivite olarak kaydedildi ✓'
                                                : '${fmtNum(store.todaySteps.toDouble())} steps synced to journal ✓')
                                            : (s.isTr ? 'Adım sayısı henüz 0.' : 'Step count is currently 0.'),
                                      );
                                    }
                                  },
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                    const Divider(height: 1),
                    // Uyku Takibi
                    SwitchListTile(
                      secondary: const Icon(Icons.bedtime_outlined, color: Colors.indigo),
                      title: Text(s.sleepTrackerTitle),
                      subtitle: Text(
                        store.sleepTrackerEnabled
                            ? (s.isTr
                                ? 'Aktif · Hedef: ${fmtNum1(store.sleepDailyGoalHours)} saat'
                                : 'Active · Goal: ${store.sleepDailyGoalHours} hrs')
                            : s.sleepTrackerSubtitle,
                        style: const TextStyle(fontSize: AppFont.caption),
                      ),
                      value: store.sleepTrackerEnabled,
                      onChanged: (val) async {
                        await store.setSleepTrackerEnabled(val);
                        if (!mounted) return;
                        setState(() {});
                      },
                    ),
                    if (store.sleepTrackerEnabled) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${s.sleepDailyGoal}:',
                              style: const TextStyle(fontSize: AppFont.caption, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              children: [7.0, 7.5, 8.0, 8.5, 9.0].map((hours) {
                                final isSelected = store.sleepDailyGoalHours == hours;
                                return ChoiceChip(
                                  label: Text('${fmtNum1(hours.toDouble())} $hourWord'),
                                  selected: isSelected,
                                  onSelected: (_) async {
                                    await store.setSleepDailyGoalHours(hours);
                                    if (!mounted) return;
                                    setState(() {});
                                  },
                                );
                              }).toList(),
                            ),
                            const SizedBox(height: 8),
                            if (store.sleepSessionStartTs != null) ...[
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: Colors.indigo.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: Colors.indigo.withValues(alpha: 0.3)),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.nightlight_round, color: Colors.indigo, size: 20),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            s.sleepSessionActive,
                                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: AppFont.small),
                                          ),
                                          Text(
                                            '${s.isTr ? "Başlangıç" : "Started"}: ${fmtTime(DateTime.fromMillisecondsSinceEpoch(store.sleepSessionStartTs!))}',
                                            style: const TextStyle(fontSize: AppFont.micro),
                                          ),
                                        ],
                                      ),
                                    ),
                                    FilledButton.icon(
                                      style: FilledButton.styleFrom(
                                        backgroundColor: Colors.indigo,
                                        visualDensity: VisualDensity.compact,
                                      ),
                                      icon: const Icon(Icons.wb_sunny_outlined, size: 15),
                                      label: Text(s.wakeUp),
                                      onPressed: () async {
                                        final entry = await store.stopSleepSession();
                                        if (context.mounted && entry != null) {
                                          showSnack(
                                            context,
                                            s.isTr
                                                ? 'Günaydın! ${entry.qty} saat uyku kaydedildi 🛌'
                                                : 'Good morning! ${entry.qty} hrs sleep logged 🛌',
                                          );
                                          setState(() {});
                                        }
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            ] else ...[
                              // Yan yana sığmazlarsa alt alta dizilir; eşit genişlikte iki düğme dar ekranda yazılarını
                              // satır satır bölüyordu.
                              OverflowBar(
                                spacing: 8,
                                overflowSpacing: 8,
                                children: [
                                  OutlinedButton.icon(
                                    icon: const Icon(Icons.nights_stay_outlined, size: 16, color: Colors.indigo),
                                    label: Text(s.startSleepSession),
                                    onPressed: () async {
                                      await store.startSleepSession();
                                      if (context.mounted) {
                                        showSnack(context, s.isTr ? 'İyi geceler! Uyku oturumu başlatıldı 🌙' : 'Good night! Sleep session started 🌙');
                                        setState(() {});
                                      }
                                    },
                                  ),
                                  OutlinedButton.icon(
                                    icon: const Icon(Icons.post_add_outlined, size: 16),
                                    label: Text(s.logSleep),
                                    onPressed: () async {
                                      _showManageSleepDialog(context, s);
                                    },
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        );
      },
    );
  }

  void _showManageSleepDialog(BuildContext context, AppStrings s) {
    TimeOfDay bedTime = const TimeOfDay(hour: 23, minute: 30);
    TimeOfDay wakeTime = const TimeOfDay(hour: 7, minute: 30);

    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) {
          final bedDt = DateTime(2026, 1, 1, bedTime.hour, bedTime.minute);
          var wakeDt = DateTime(2026, 1, 2, wakeTime.hour, wakeTime.minute);
          if (wakeDt.isBefore(bedDt)) {
            wakeDt = wakeDt.add(const Duration(days: 1));
          }
          final durMins = wakeDt.difference(bedDt).inMinutes;
          final durHours = durMins / 60.0;

          return AlertDialog(
            title: Row(
              children: [
                const Text('🛌 '),
                Text(s.isTr ? 'Uyku Kaydı Gir' : 'Log Sleep'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  title: Text(s.isTr ? 'Yatma Saati' : 'Bedtime'),
                  trailing: TextButton(
                    child: Text(bedTime.format(ctx)),
                    onPressed: () async {
                      final picked = await showTimePicker(context: ctx, initialTime: bedTime);
                      if (picked != null) setD(() => bedTime = picked);
                    },
                  ),
                ),
                ListTile(
                  title: Text(s.isTr ? 'Uyanma Saati' : 'Wake Time'),
                  trailing: TextButton(
                    child: Text(wakeTime.format(ctx)),
                    onPressed: () async {
                      final picked = await showTimePicker(context: ctx, initialTime: wakeTime);
                      if (picked != null) setD(() => wakeTime = picked);
                    },
                  ),
                ),
                const Divider(),
                Text(
                  '${s.isTr ? "Toplam Süre" : "Total Duration"}: ${fmtNum1(durHours)} $hourWord ($durMins $minuteWord)',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: AppFont.small),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(s.isTr ? 'İptal' : 'Cancel'),
              ),
              FilledButton(
                onPressed: () async {
                  Navigator.pop(ctx);
                  final today = DateTime.now();
                  final end = DateTime(today.year, today.month, today.day, wakeTime.hour, wakeTime.minute);
                  final start = end.subtract(Duration(minutes: durMins));
                  await store.logManualSleep(start: start, end: end);
                  if (context.mounted) {
                    showSnack(
                      context,
                      s.isTr
                          ? 'Dün geceki uyku başarıyla kaydedildi ✓'
                          : 'Sleep logged successfully ✓',
                    );
                    setState(() {});
                  }
                },
                child: Text(s.isTr ? 'Kaydet' : 'Save'),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Raporlar, dışa aktarma, JSON yedek ve yerel yedekler.
class BackupSettingsPage extends StatefulWidget {
  const BackupSettingsPage({super.key});

  @override
  State<BackupSettingsPage> createState() => _BackupSettingsPageState();
}

class _BackupSettingsPageState extends State<BackupSettingsPage> {
  bool _exporting = false;

  Future<void> _handleBackupExport() async {
    if (_exporting) return;
    _exporting = true;
    try {
      final s = strings.value;
      final choice = await showModalBottomSheet<String>(
        context: context,
        showDragHandle: true,
        builder: (sheetContext) => SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                  child: Text(
                    s.backupExport,
                    style: const TextStyle(fontSize: AppFont.title, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(height: 8),
                ListTile(
                  leading: const Icon(Icons.save_alt),
                  title: Text(s.isTr ? 'Telefona kaydet' : 'Save to phone'),
                  onTap: () => Navigator.pop(sheetContext, 'save'),
                ),
                ListTile(
                  leading: const Icon(Icons.share_outlined),
                  title: Text(s.isTr ? 'Paylaş' : 'Share'),
                  onTap: () => Navigator.pop(sheetContext, 'share'),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      );

      if (choice == null || !mounted) return;

      final file = await BackupService.createBackup(store, prefix: 'manual');
      if (choice == 'share') {
        await SharePlus.instance.share(
          ShareParams(
            files: [XFile(file.path)],
            text: '${s.isTr ? "Seyir JSON Yedeği" : "Seyir JSON backup"} (${file.uri.pathSegments.last})',
          ),
        );
      } else if (choice == 'save') {
        final res = await BackupService.saveToDevice(file, isTr: s.isTr);
        if (!mounted) return;
        if (res.isSaved) {
          showSnack(context, s.isTr ? 'Yedek telefona kaydedildi' : 'Backup saved to your phone');
        } else if (res.isFailure) {
          showSnack(
            context,
            s.isTr ? 'Yedek kaydedilemedi: ${res.error}' : 'Couldn\'t save the backup: ${res.error}',
          );
        }
      }
    } finally {
      if (mounted) {
        setState(() => _exporting = false);
      } else {
        _exporting = false;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final s = strings.value;
        return Scaffold(
          appBar: AppBar(title: Text(s.sectionBackupReports)),
          body: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            children: [
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
                        style: const TextStyle(fontSize: AppFont.caption),
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => ExportFilterSheet.show(context, store, initialFormat: 'pdf'),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.table_chart_outlined),
                      title: Text(s.isTr ? 'Excel (CSV) Tablosu' : 'Excel (CSV) Spreadsheet'),
                      subtitle: Text(
                        s.isTr
                            ? 'Tüm günlük geçmişi CSV formatında dışa aktar'
                            : 'Export complete timeline history to CSV',
                        style: const TextStyle(fontSize: AppFont.caption),
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => ExportFilterSheet.show(context, store, initialFormat: 'csv'),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.file_upload_outlined),
                      title: Text(s.backupExport),
                      subtitle: Text(
                        s.isTr
                            ? 'Yedek dosyası oluştur; telefona kaydet ya da paylaş'
                            : 'Create a backup file to save on your phone or share',
                        style: const TextStyle(fontSize: AppFont.caption),
                      ),
                      // Yedek dosya olarak verilir: pano birkaç bin kayıtlık bir JSON'u taşıyamaz.
                      onTap: _exporting ? null : _handleBackupExport,
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.file_download_outlined),
                      title: Text(s.backupImport),
                      subtitle: Text(
                        s.isTr ? 'JSON yedeğinden geri yükle' : 'Restore from JSON backup',
                        style: const TextStyle(fontSize: AppFont.caption),
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
                        style: const TextStyle(fontSize: AppFont.caption),
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _showLocalBackupsSheet(context),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  s.isTr
                      ? 'Yapay zekâ API anahtarı yedeğe dahil edilmez; geri yüklemede bu cihazdaki anahtar korunur.'
                      : 'The AI API key is not included in backups; restoring keeps the key on this device.',
                  style: TextStyle(
                    fontSize: AppFont.caption,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
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

  void _showImportDialog(BuildContext context) {
    final s = strings.value;
    final jsonCtrl = TextEditingController();

    // [read] yedeğin JSON metnini verir (seçilen dosyadan ya da yapıştırılan metinden).
    Future<void> restore(BuildContext c, Future<String?> Function() read) async {
      try {
        final json = await read();
        if (json == null) return;
        await store.importJson(json);
        if (c.mounted) {
          Navigator.pop(c);
          showSnack(context, s.backupSuccess);
        }
      } catch (e) {
        if (c.mounted) {
          showSnack(context, 'Hata: $e');
        }
      }
    }

    showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(s.backupImport),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              s.isTr
                  ? 'Bir yedek dosyası seçin. Mevcut veriler önce güvenlik yedeğine alınır.'
                  : 'Choose a backup file. Your current data is saved to a safety backup first.',
            ),
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              icon: const Icon(Icons.folder_open_outlined, size: 18),
              label: Text(s.isTr ? 'Dosya Seç' : 'Choose File'),
              onPressed: () => restore(c, () async {
                final picked = await FilePicker.pickFile();
                return picked == null ? null : utf8.decode(await picked.readAsBytes());
              }),
            ),
            const SizedBox(height: 16),
            Text(
              s.isTr ? 'Ya da yedek metnini yapıştırın:' : 'Or paste the backup text:',
              style: TextStyle(fontSize: AppFont.caption, color: Theme.of(c).colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: jsonCtrl,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: '{"app": "seyir", ...}',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: Text(s.cancel)),
          FilledButton(
            onPressed: () => restore(c, () async {
              final text = jsonCtrl.text.trim();
              return text.isEmpty ? null : text;
            }),
            child: Text(s.isTr ? 'Geri Yükle' : 'Restore'),
          ),
        ],
      ),
    );
  }

  void _showLocalBackupsSheet(BuildContext context) {
    final s = strings.value;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (bottomContext) {
        bool sheetBusy = false;
        return StatefulBuilder(
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
                          Expanded(
                            child: Text(
                              s.isTr ? 'Yerel Yedekler' : 'Local Backups',
                              style: const TextStyle(fontSize: AppFont.title, fontWeight: FontWeight.bold),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          FilledButton.icon(
                            icon: const Icon(Icons.add, size: 16),
                            label: Text(s.isTr ? 'Yeni Yedek Al' : 'Backup Now'),
                            onPressed: () async {
                              if (sheetBusy) return;
                              sheetBusy = true;
                              try {
                                await BackupService.createBackup(store, prefix: 'manual');
                                setSheetState(() {});
                                if (bottomContext.mounted) {
                                  showSnack(bottomContext, s.isTr ? 'Yedek başarıyla oluşturuldu' : 'Backup created');
                                }
                              } finally {
                                sheetBusy = false;
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
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: AppFont.small),
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
                                            style: TextStyle(fontSize: AppFont.micro, fontWeight: FontWeight.bold, color: typeColor),
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          b.sizeLabel,
                                          style: const TextStyle(fontSize: AppFont.micro, fontWeight: FontWeight.w500),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      b.name,
                                      style: TextStyle(fontSize: AppFont.micro, color: Theme.of(c).colorScheme.onSurfaceVariant),
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
                                          ok: s.restore,
                                        );
                                        if (ok) {
                                          // Geçersiz ya da uyumsuz yedek reddedilir; veriler olduğu gibi kalır. Açık sayfanın
                                          // altında kalan snackbar görünmediği için sonuç sayfa kapatıldıktan sonra gösterilir.
                                          var message = s.backupSuccess;
                                          try {
                                            await BackupService.restoreFromFile(store, b.file);
                                          } catch (e) {
                                            message = 'Hata: $e';
                                          }
                                          if (bottomContext.mounted) {
                                            Navigator.pop(bottomContext);
                                            showSnack(context, message);
                                          }
                                        }
                                      },
                                    ),
                                    PopupMenuButton<String>(
                                      icon: const Icon(Icons.more_vert, size: 20),
                                      onSelected: (val) async {
                                        if (sheetBusy) return;
                                        sheetBusy = true;
                                        try {
                                          if (val == 'share') {
                                            await SharePlus.instance.share(
                                              ShareParams(
                                                files: [XFile(b.file.path)],
                                                text: '${s.isTr ? "Seyir JSON Yedeği" : "Seyir JSON backup"} (${b.name})',
                                              ),
                                            );
                                          } else if (val == 'save') {
                                            final res = await BackupService.saveToDevice(
                                              b.file,
                                              createdAt: b.createdAt,
                                              isTr: s.isTr,
                                            );
                                            if (bottomContext.mounted) {
                                              if (res.isSaved) {
                                                showSnack(
                                                  bottomContext,
                                                  s.isTr ? 'Yedek telefona kaydedildi' : 'Backup saved to your phone',
                                                );
                                              } else if (res.isFailure) {
                                                showSnack(
                                                  bottomContext,
                                                  s.isTr
                                                      ? 'Yedek kaydedilemedi: ${res.error}'
                                                      : 'Couldn\'t save the backup: ${res.error}',
                                                );
                                              }
                                            }
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
                                        } finally {
                                          sheetBusy = false;
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
                                          value: 'save',
                                          child: Row(
                                            children: [
                                              const Icon(Icons.save_alt, size: 18),
                                              const SizedBox(width: 8),
                                              Text(s.isTr ? 'Telefona kaydet' : 'Save to phone'),
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
      );
    },
  );
}
}

/// Kullanıcının kendi yapay zekâ anahtarını (BYOK) tanımladığı ve yönettiği sayfa.
class AiSettingsPage extends StatefulWidget {
  const AiSettingsPage({super.key});

  @override
  State<AiSettingsPage> createState() => _AiSettingsPageState();
}

class _AiSettingsPageState extends State<AiSettingsPage> {
  late String _selectedProvider;
  late final TextEditingController _apiKeyCtrl;
  late final TextEditingController _modelCtrl;
  late final TextEditingController _endpointCtrl;

  bool _obscureKey = true;
  bool _isTesting = false;
  String? _testSuccess;
  String? _testError;

  @override
  void initState() {
    super.initState();
    _selectedProvider = store.llmProvider;
    _apiKeyCtrl = TextEditingController(text: store.llmApiKey);
    _modelCtrl = TextEditingController(text: store.llmModel);
    _endpointCtrl = TextEditingController(text: store.llmCustomEndpoint);
  }

  @override
  void dispose() {
    _apiKeyCtrl.dispose();
    _modelCtrl.dispose();
    _endpointCtrl.dispose();
    super.dispose();
  }

  Future<void> _testConnection() async {
    final s = strings.value;
    final isTr = s.isTr;

    setState(() {
      _isTesting = true;
      _testSuccess = null;
      _testError = null;
    });

    try {
      final ok = await AiService.testConnection(
        provider: _selectedProvider,
        apiKey: _apiKeyCtrl.text,
        model: _modelCtrl.text.trim().isEmpty ? null : _modelCtrl.text.trim(),
        customEndpoint: _endpointCtrl.text.trim().isEmpty ? null : _endpointCtrl.text.trim(),
        isTr: isTr,
      );

      if (mounted) {
        setState(() {
          _isTesting = false;
          if (ok) {
            _testSuccess = isTr
                ? '✓ Bağlantı başarılı! ${AiService.providerDisplayName(_selectedProvider, isTr: true)} yanıt verdi.'
                : '✓ Connection successful! ${AiService.providerDisplayName(_selectedProvider, isTr: false)} responded.';
          }
        });
      }
    } on AiException catch (e) {
      if (mounted) {
        setState(() {
          _isTesting = false;
          _testError = e.message;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isTesting = false;
          _testError = isTr ? 'Bağlantı başarısız: $e' : 'Connection failed: $e';
        });
      }
    }
  }

  Future<void> _save() async {
    final s = strings.value;
    final isTr = s.isTr;

    await store.setLlmConfig(
      provider: _selectedProvider,
      apiKey: _apiKeyCtrl.text.trim(),
      model: _modelCtrl.text.trim().isEmpty ? null : _modelCtrl.text.trim(),
      customEndpoint: _endpointCtrl.text.trim().isEmpty ? null : _endpointCtrl.text.trim(),
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(isTr ? 'Yapay zekâ ayarları kaydedildi.' : 'AI settings saved.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _clearKey() async {
    final s = strings.value;
    final isTr = s.isTr;

    final ok = await confirm(
      context,
      isTr ? 'Anahtarı Kaldır' : 'Remove Key',
      isTr
          ? 'Kayıtlı API anahtarınız silinecek ve uygulama tamamen çevrimdışı moda dönecektir. Devam edilsin mi?'
          : 'Your saved API key will be deleted and the app will return to full offline mode. Continue?',
    );

    if (ok && mounted) {
      await store.clearLlmConfig();
      if (!mounted) return;
      setState(() {
        _apiKeyCtrl.clear();
        _modelCtrl.clear();
        _endpointCtrl.clear();
        _testSuccess = null;
        _testError = null;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isTr ? 'API anahtarı kaldırıldı.' : 'API key removed.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = strings.value;
    final isTr = s.isTr;
    final scheme = Theme.of(context).colorScheme;

    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final hasKey = store.hasLlmKey;

        return Scaffold(
          appBar: AppBar(
            title: Text(isTr ? 'Yapay Zekâ & API (BYOK)' : 'AI & API Key (BYOK)'),
          ),
          body: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            children: [
              // Gizlilik & Çevrimdışı Bilgi Kartı
              Card(
                elevation: 0,
                color: scheme.primaryContainer.withValues(alpha: 0.35),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.shield_outlined, color: Colors.amber, size: 24),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isTr ? 'Gizlilik & Çevrimdışı İlkeli' : 'Privacy & Offline-First',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: AppFont.small),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              isTr
                                  ? 'Seyir verilerinizi asla harici sunuculara göndermez. Bu özellik tamamen isteğe bağlıdır; kendi API anahtarınızı tanımladığınızda sadece tek tıkla yol haritası üretmek için kullanılır. Anahtarınız yalnızca cihazınızda güvenle saklanır.'
                                  : 'Seyir never sends your data to external servers. This feature is completely optional; your API key is stored only on your device and used solely when generating roadmaps.',
                              style: const TextStyle(fontSize: AppFont.caption),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // Sağlayıcı ve Yapılandırma Kartı
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        isTr ? 'Sağlayıcı ve Model' : 'Provider and Model',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: AppFont.subtitle),
                      ),
                      const SizedBox(height: 12),

                      DropdownButtonFormField<String>(
                        isExpanded: true,
                        initialValue: _selectedProvider,
                        decoration: InputDecoration(
                          labelText: isTr ? 'Yapay Zekâ Sağlayıcısı' : 'AI Provider',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                        items: [
                          DropdownMenuItem(
                            value: 'gemini',
                            child: Text(
                              isTr ? 'Google Gemini (Önerilen - Ücretsiz)' : 'Google Gemini (Recommended - Free)',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          DropdownMenuItem(
                            value: 'openai',
                            child: const Text('OpenAI (ChatGPT)', overflow: TextOverflow.ellipsis),
                          ),
                          DropdownMenuItem(
                            value: 'openrouter',
                            child: Text(
                              isTr ? 'OpenRouter (Çoklu Model)' : 'OpenRouter (Multi-Model)',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          DropdownMenuItem(
                            value: 'custom',
                            child: Text(
                              isTr ? 'Özel / Yerel Uç Nokta (Ollama)' : 'Custom / Local (Ollama)',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                        onChanged: (val) {
                          if (val != null) {
                            setState(() {
                              _selectedProvider = val;
                              _testSuccess = null;
                              _testError = null;
                              // Eğer model boşsa veya varsayılan model yazılıysa yenisini öner
                              if (_modelCtrl.text.trim().isEmpty) {
                                _modelCtrl.text = AiService.defaultModelFor(val);
                              }
                            });
                          }
                        },
                      ),

                      const SizedBox(height: 14),

                      // API Anahtarı
                      TextField(
                        controller: _apiKeyCtrl,
                        obscureText: _obscureKey,
                        decoration: InputDecoration(
                          labelText: isTr ? 'API Anahtarı' : 'API Key',
                          hintText: _selectedProvider == 'gemini' ? 'AIzaSy...' : 'sk-...',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                          suffixIcon: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: Icon(_obscureKey ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                                onPressed: () => setState(() => _obscureKey = !_obscureKey),
                                tooltip: isTr ? 'Göster / Gizle' : 'Show / Hide',
                              ),
                              IconButton(
                                icon: const Icon(Icons.paste_rounded),
                                onPressed: () async {
                                  final data = await Clipboard.getData(Clipboard.kTextPlain);
                                  if (!mounted) return;
                                  if (data?.text != null && data!.text!.isNotEmpty) {
                                    _apiKeyCtrl.text = data.text!.trim();
                                    setState(() {
                                      _testSuccess = null;
                                      _testError = null;
                                    });
                                  }
                                },
                                tooltip: isTr ? 'Panodan Yapıştır' : 'Paste from clipboard',
                              ),
                            ],
                          ),
                        ),
                        onChanged: (_) {
                          if (_testSuccess != null || _testError != null) {
                            setState(() {
                              _testSuccess = null;
                              _testError = null;
                            });
                          }
                        },
                      ),

                      const SizedBox(height: 14),

                      // Model Adı
                      TextField(
                        controller: _modelCtrl,
                        decoration: InputDecoration(
                          labelText: isTr ? 'Model Adı (İsteğe bağlı)' : 'Model Name (Optional)',
                          hintText: AiService.defaultModelFor(_selectedProvider),
                          helperText: isTr
                              ? 'Boş bırakılırsa varsayılan model kullanılır: ${AiService.defaultModelFor(_selectedProvider)}'
                              : 'Leave empty for default: ${AiService.defaultModelFor(_selectedProvider)}',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                          suffixIcon: _modelCtrl.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear, size: 18),
                                  onPressed: () {
                                    setState(() {
                                      _modelCtrl.clear();
                                      _testSuccess = null;
                                      _testError = null;
                                    });
                                  },
                                  tooltip: isTr ? 'Varsayılana sıfırla' : 'Reset to default',
                                )
                              : null,
                        ),
                        onChanged: (_) {
                          if (_testSuccess != null || _testError != null) {
                            setState(() {
                              _testSuccess = null;
                              _testError = null;
                            });
                          }
                        },
                      ),

                      // Önerilen Hızlı Modeller
                      if (AiService.recommendedModelsFor(_selectedProvider).isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: AiService.recommendedModelsFor(_selectedProvider, isTr: isTr).map((opt) {
                            final currentActive = _modelCtrl.text.trim().isEmpty
                                ? AiService.defaultModelFor(_selectedProvider)
                                : AiService.normalizeModelName(_selectedProvider, _modelCtrl.text.trim());
                            final isSelected = currentActive == opt.id;

                            return ChoiceChip(
                              label: Text(
                                '${opt.displayName}${opt.badge != null ? ' (${opt.badge})' : ''}',
                                style: const TextStyle(fontSize: AppFont.caption),
                              ),
                              selected: isSelected,
                              onSelected: (_) {
                                setState(() {
                                  _modelCtrl.text = opt.id;
                                  _testSuccess = null;
                                  _testError = null;
                                });
                              },
                            );
                          }).toList(),
                        ),
                      ],

                      if (_selectedProvider == 'custom') ...[
                        const SizedBox(height: 14),
                        TextField(
                          controller: _endpointCtrl,
                          decoration: InputDecoration(
                            labelText: isTr ? 'Uç Nokta Adresi (URL)' : 'Endpoint URL',
                            hintText: 'http://localhost:11434/v1',
                            helperText: isTr
                                ? 'Örn: http://192.168.1.10:11434/v1/chat/completions'
                                : 'E.g. http://192.168.1.10:11434/v1/chat/completions',
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                          ),
                        ),
                      ],

                      if (_testSuccess != null) ...[
                        const SizedBox(height: 14),
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.green.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.green.withValues(alpha: 0.4)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.check_circle_rounded, color: Colors.green, size: 20),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _testSuccess!,
                                  style: const TextStyle(color: Colors.green, fontSize: AppFont.caption, fontWeight: FontWeight.w600),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],

                      if (_testError != null) ...[
                        const SizedBox(height: 14),
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: scheme.errorContainer.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: scheme.error.withValues(alpha: 0.4)),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.error_outline, color: scheme.error, size: 20),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _testError!,
                                  style: TextStyle(color: scheme.onErrorContainer, fontSize: AppFont.caption),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],

                      const SizedBox(height: 16),

                      // İşlem Butonları
                      OverflowBar(
                        alignment: MainAxisAlignment.spaceBetween,
                        spacing: 8,
                        overflowSpacing: 8,
                        children: [
                          OutlinedButton.icon(
                            onPressed: _isTesting ? null : _testConnection,
                            icon: _isTesting
                                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                                : const Icon(Icons.network_check_rounded, size: 18),
                            label: Text(isTr ? 'Bağlantıyı Test Et' : 'Test Connection'),
                          ),
                          FilledButton.icon(
                            onPressed: _save,
                            icon: const Icon(Icons.save_rounded, size: 18),
                            label: Text(isTr ? 'Kaydet' : 'Save'),
                          ),
                        ],
                      ),

                      if (hasKey) ...[
                        const SizedBox(height: 8),
                        const Divider(),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            onPressed: _clearKey,
                            icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                            label: Text(
                              isTr ? 'Anahtarı Kaldır (Çevrimdışıya Dön)' : 'Remove Key (Back to Offline)',
                              style: const TextStyle(color: Colors.red),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // Rehber Kartı: Google AI Studio'dan Ücretsiz Anahtar Alma
              Card(
                elevation: 0,
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.help_outline_rounded, color: Colors.purpleAccent, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              isTr ? 'Nasıl Ücretsiz Gemini Anahtarı Alınır?' : 'How to Get a Free Gemini Key?',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: AppFont.small),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        isTr
                            ? '1. Tarayıcınızda "aistudio.google.com" adresini açın.\n'
                              '2. Google hesabınızla giriş yapın ve "Get API key" butonuna tıklayın.\n'
                              '3. "Create API key" diyerek yeni anahtarınızı oluşturun ve kopyalayın.\n'
                              '4. Kopyaladığınız anahtarı buradaki API Anahtarı alanına yapıştırıp "Kaydet"e basın.\n\n'
                              '🎉 Kredi kartı gerekmez; Google ücretsiz katmanda dakikada 15 istek sınırı ile kişisel kullanım için tamamen ücretsiz kota sunar.'
                            : '1. Open "aistudio.google.com" in your browser.\n'
                              '2. Sign in with your Google account and click "Get API key".\n'
                              '3. Click "Create API key", copy the generated key.\n'
                              '4. Paste it into the API Key field above and click "Save".\n\n'
                              '🎉 No credit card required; Google provides a generous free tier for personal use.',
                        style: TextStyle(
                          fontSize: AppFont.caption,
                          height: 1.45,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
