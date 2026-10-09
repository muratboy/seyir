import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../data/models.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  static Future<void> init() async {
    if (_initialized) return;
    try {
      const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
      const initSettings = InitializationSettings(android: androidSettings);
      await _plugin.initialize(initSettings);
      _initialized = true;
    } catch (e) {
      debugPrint('NotificationService init error: $e');
    }
  }

  static Future<void> updateTimerNotification(
    List<ActiveTimer> timers,
    Map<int, Activity> activities,
  ) async {
    if (kIsWeb || !Platform.isAndroid) return;
    await init();

    if (timers.isEmpty) {
      await _plugin.cancel(1001);
      return;
    }

    try {
      final runningCount = timers.where((t) => t.isRunning).length;
      final firstTimer = timers.first;
      final firstAct = activities[firstTimer.activityId]?.name ?? 'Aktivite';

      final title = timers.length == 1
          ? '$firstAct: ${firstTimer.displayDuration}'
          : '$runningCount/${timers.length} Aktif Zamanlayıcı';

      final body = timers.map((t) {
        final act = activities[t.activityId]?.name ?? 'Aktivite';
        final status = t.isRunning ? '' : '⏸️ ';
        return '$status$act: ${t.displayDuration}';
      }).join(' • ');

      const androidDetails = AndroidNotificationDetails(
        'takip_timers_channel',
        'Canlı Kronometre & Sayaçlar',
        channelDescription: 'Devam eden kronometre ve geri sayımları gösterir',
        importance: Importance.low,
        priority: Priority.low,
        ongoing: true,
        autoCancel: false,
        showWhen: false,
      );

      await _plugin.show(
        1001,
        title,
        body,
        const NotificationDetails(android: androidDetails),
      );
    } catch (e) {
      debugPrint('Error updating timer notification: $e');
    }
  }

  static Future<void> showLimitAlert(String title, String body) async {
    if (kIsWeb || !Platform.isAndroid) return;
    await init();
    try {
      const androidDetails = AndroidNotificationDetails(
        'takip_alerts_channel',
        'Limit ve Hedef Uyarıları',
        channelDescription: 'Günlük limit aşımları ve hedef başarı bildirimleri',
        importance: Importance.high,
        priority: Priority.high,
      );
      await _plugin.show(
        2001,
        title,
        body,
        const NotificationDetails(android: androidDetails),
      );
    } catch (e) {
      debugPrint('Error showing limit alert: $e');
    }
  }

  static Future<void> showReminder(String title, String body) async {
    if (kIsWeb || !Platform.isAndroid) return;
    await init();
    try {
      const androidDetails = AndroidNotificationDetails(
        'takip_reminders_channel',
        'Akıllı Hatırlatıcılar',
        channelDescription: 'Su ve aktivite hatırlatıcıları',
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
      );
      await _plugin.show(
        3001,
        title,
        body,
        const NotificationDetails(android: androidDetails),
      );
    } catch (e) {
      debugPrint('Error showing reminder: $e');
    }
  }
}
