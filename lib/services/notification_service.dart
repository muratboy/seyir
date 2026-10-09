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

      final androidImpl = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (androidImpl != null) {
        await androidImpl.createNotificationChannel(
          const AndroidNotificationChannel(
            'takip_timers_channel',
            'Canlı Kronometre & Sayaçlar',
            description: 'Devam eden kronometre ve geri sayımları gösterir',
            importance: Importance.low,
            playSound: false,
            enableVibration: false,
          ),
        );
        await androidImpl.createNotificationChannel(
          const AndroidNotificationChannel(
            'takip_alerts_channel',
            'Limit ve Hedef Uyarıları',
            description: 'Günlük limit aşımları ve hedef başarı bildirimleri',
            importance: Importance.high,
          ),
        );
        await androidImpl.createNotificationChannel(
          const AndroidNotificationChannel(
            'takip_reminders_channel',
            'Akıllı Hatırlatıcılar',
            description: 'Su ve aktivite hatırlatıcıları',
            importance: Importance.defaultImportance,
          ),
        );
      }
      _initialized = true;
    } catch (e) {
      debugPrint('NotificationService init error: $e');
    }
  }

  /// Android 13+ için bildirim izni ister
  static Future<bool> requestPermission() async {
    if (kIsWeb || !Platform.isAndroid) return true;
    await init();
    try {
      final androidImpl = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      final granted = await androidImpl?.requestNotificationsPermission();
      return granted ?? false;
    } catch (e) {
      debugPrint('Notification permission error: $e');
      return false;
    }
  }

  /// Bildirim izninin açık olup olmadığını kontrol eder
  static Future<bool> areNotificationsEnabled() async {
    if (kIsWeb || !Platform.isAndroid) return true;
    await init();
    try {
      final androidImpl = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      final enabled = await androidImpl?.areNotificationsEnabled();
      return enabled ?? false;
    } catch (e) {
      return false;
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
          ? (firstTimer.isRunning ? '$firstAct (Çalışıyor)' : '$firstAct (Duraklatıldı: ${firstTimer.displayDuration})')
          : '$runningCount/${timers.length} Aktif Zamanlayıcı';

      final body = timers.map((t) {
        final act = activities[t.activityId]?.name ?? 'Aktivite';
        final status = t.isRunning ? '' : '⏸️ ';
        return '$status$act: ${t.displayDuration}';
      }).join(' • ');

      // Canlı kronometre desteği: tek aktif çalışan kronometre varsa sistem saatiyle otomatik akar
      final bool isSingleRunningStopwatch =
          timers.length == 1 && firstTimer.isRunning && !firstTimer.isCountdown;
      final int? chronometerWhen = isSingleRunningStopwatch
          ? DateTime.now().millisecondsSinceEpoch - firstTimer.elapsedMs
          : null;

      final androidDetails = AndroidNotificationDetails(
        'takip_timers_channel',
        'Canlı Kronometre & Sayaçlar',
        channelDescription: 'Devam eden kronometre ve geri sayımları gösterir',
        importance: Importance.low,
        priority: Priority.low,
        ongoing: true,
        autoCancel: false,
        showWhen: isSingleRunningStopwatch,
        when: chronometerWhen,
        usesChronometer: isSingleRunningStopwatch,
      );

      await _plugin.show(
        1001,
        title,
        body,
        NotificationDetails(android: androidDetails),
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
