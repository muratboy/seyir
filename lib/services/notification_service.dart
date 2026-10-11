import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import '../data/models.dart';
import '../data/store.dart';

/// Arka planda bildirim aksiyon butonuna basıldığında çağrılan sistem callback'i
@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse notificationResponse) async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService.handleNotificationAction(notificationResponse);
}

class NotificationService {
  static final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  static Future<void> init() async {
    if (_initialized) return;
    try {
      // Saat dilimi yapılandırması
      tz.initializeTimeZones();
      try {
        if (!kIsWeb && Platform.isAndroid) {
          final tzInfo = await FlutterTimezone.getLocalTimezone();
          tz.setLocalLocation(tz.getLocation(tzInfo.identifier));
        }
      } catch (e) {
        debugPrint('Local timezone setup warning: $e');
      }

      const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
      const initSettings = InitializationSettings(android: androidSettings);

      await _plugin.initialize(
        initSettings,
        onDidReceiveNotificationResponse: handleNotificationAction,
        onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
      );

      final androidImpl = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (androidImpl != null) {
        // 1. Canlı Kronometre & Sayaçlar kanalı (Sessiz, bildirim çubuğunda sürekli)
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

        // 2. Pomodoro & Sayaç Bitiş Alarmları (Yüksek öncelikli, sesli ve titreşimli)
        await androidImpl.createNotificationChannel(
          const AndroidNotificationChannel(
            'takip_alarms_channel',
            'Sayaç ve Pomodoro Alarmları',
            description: 'Pomodoro ve geri sayım süresi tamamlandığında çalar',
            importance: Importance.max,
            playSound: true,
            enableVibration: true,
          ),
        );

        // 3. Limit ve Hedef Uyarıları kanalı
        await androidImpl.createNotificationChannel(
          const AndroidNotificationChannel(
            'takip_alerts_channel',
            'Limit ve Hedef Uyarıları',
            description: 'Günlük limit aşımları ve hedef başarı bildirimleri',
            importance: Importance.high,
          ),
        );

        // 4. Akıllı Hatırlatıcılar kanalı
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

  /// Bildirim aksiyonları veya tıklamalarını işler (Durdur, Devam Et, Bitir)
  @pragma('vm:entry-point')
  static Future<void> handleNotificationAction(NotificationResponse response) async {
    final actionId = response.actionId;
    final payload = response.payload;
    debugPrint('Notification action: actionId=$actionId, payload=$payload');

    final timerId = int.tryParse(payload ?? '');
    if (timerId == null && actionId != 'alarm_dismiss') return;

    if (store.activities.isEmpty) {
      await store.load();
    }

    if (actionId == 'timer_pause') {
      if (timerId != null) await store.pauseTimer(timerId);
    } else if (actionId == 'timer_resume') {
      if (timerId != null) await store.resumeTimer(timerId);
    } else if (actionId == 'timer_finish' || actionId == 'alarm_finish') {
      if (timerId != null) {
        await cancelTimerAlarm(timerId);
        await store.finishTimer(timerId);
      }
    } else if (actionId == 'alarm_dismiss') {
      if (timerId != null) {
        await cancelTimerAlarm(timerId);
      }
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

  /// Canlı kronometre bildirimini günceller (Saniyeyi Android sistemi akar, aksiyon düğmeleri ekler)
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
          ? (firstTimer.isRunning
              ? '$firstAct (Çalışıyor)'
              : '$firstAct (Duraklatıldı: ${firstTimer.displayDuration})')
          : '$runningCount/${timers.length} Aktif Zamanlayıcı';

      final body = timers.map((t) {
        final act = activities[t.activityId]?.name ?? 'Aktivite';
        final status = t.isRunning ? '' : '⏸️ ';
        return '$status$act: ${t.displayDuration}';
      }).join(' • ');

      final bool isSingleTimer = timers.length == 1;
      final bool isRunning = firstTimer.isRunning;
      final bool isCountdown = firstTimer.isCountdown;

      // Android'in yerel chronometer sayacı:
      // - Kronometrede başlangıçtan ileriye sayar
      // - Geri sayımda hedeften geriye sayar
      final bool useChronometer = isSingleTimer && isRunning;
      final int? chronometerWhen = useChronometer
          ? (isCountdown
              ? DateTime.now().millisecondsSinceEpoch + firstTimer.remainingMs
              : DateTime.now().millisecondsSinceEpoch - firstTimer.elapsedMs)
          : null;

      // Bildirim aksiyonları (Durdur/Devam Et ve Bitir)
      final actions = <AndroidNotificationAction>[
        if (isRunning)
          const AndroidNotificationAction(
            'timer_pause',
            '⏸️ Duraklat',
            showsUserInterface: false,
            cancelNotification: false,
          )
        else
          const AndroidNotificationAction(
            'timer_resume',
            '▶️ Devam Et',
            showsUserInterface: false,
            cancelNotification: false,
          ),
        const AndroidNotificationAction(
          'timer_finish',
          '⏹️ Bitir',
          showsUserInterface: false,
          cancelNotification: true,
        ),
      ];

      final androidDetails = AndroidNotificationDetails(
        'takip_timers_channel',
        'Canlı Kronometre & Sayaçlar',
        channelDescription: 'Devam eden kronometre ve geri sayımları gösterir',
        importance: Importance.low,
        priority: Priority.low,
        ongoing: isRunning,
        autoCancel: false,
        showWhen: useChronometer,
        when: chronometerWhen,
        usesChronometer: useChronometer,
        chronometerCountDown: useChronometer && isCountdown,
        actions: actions,
      );

      await _plugin.show(
        1001,
        title,
        body,
        NotificationDetails(android: androidDetails),
        payload: firstTimer.id.toString(),
      );
    } catch (e) {
      debugPrint('Error updating timer notification: $e');
    }
  }

  /// Pomodoro veya Geri Sayım bittiğinde çalacak alarmı tam zamanına planlar
  static Future<void> scheduleTimerAlarm({
    required int timerId,
    required String activityName,
    required int remainingMs,
    required bool isPomodoro,
    bool soundEnabled = true,
    bool autoSaveEnabled = true,
  }) async {
    if (kIsWeb || !Platform.isAndroid || remainingMs <= 0) return;
    await init();

    try {
      final finishTime = tz.TZDateTime.now(tz.local).add(Duration(milliseconds: remainingMs));
      final alarmId = 10000 + timerId;

      final title = isPomodoro ? '🍅 Pomodoro Tamamlandı!' : '⏱️ Süre Doldu!';
      final body = autoSaveEnabled
          ? '$activityName oturumu tamamlandı ve otomatik kaydedildi.'
          : '$activityName için hedeflenen süre tamamlandı. Oturumu kaydetmek için dokun.';

      final actions = autoSaveEnabled
          ? const [
              AndroidNotificationAction(
                'alarm_dismiss',
                'Tamam',
                showsUserInterface: false,
                cancelNotification: true,
              ),
            ]
          : const [
              AndroidNotificationAction(
                'alarm_finish',
                '⏹️ Bitir & Kaydet',
                showsUserInterface: true,
                cancelNotification: true,
              ),
              AndroidNotificationAction(
                'alarm_dismiss',
                'Kapat',
                showsUserInterface: false,
                cancelNotification: true,
              ),
            ];

      final androidDetails = AndroidNotificationDetails(
        'takip_alarms_channel',
        'Sayaç ve Pomodoro Alarmları',
        channelDescription: 'Pomodoro ve geri sayım süresi tamamlandığında çalar',
        importance: Importance.max,
        priority: Priority.high,
        playSound: soundEnabled,
        enableVibration: true,
        vibrationPattern: Int64List.fromList([0, 1000, 500, 1000]),
        category: AndroidNotificationCategory.alarm,
        actions: actions,
      );

      await _plugin.zonedSchedule(
        alarmId,
        title,
        body,
        finishTime,
        NotificationDetails(android: androidDetails),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        payload: timerId.toString(),
      );
      debugPrint('Timer alarm scheduled at $finishTime for timer #$timerId');
    } catch (e) {
      debugPrint('Error scheduling timer alarm: $e');
    }
  }

  /// Pomodoro veya Geri Sayım tamamlandığında bildirimin ekranda kalmasını sağlayan anlık bildirim
  static Future<void> showTimerCompletedNotification({
    required int timerId,
    required String activityName,
    required bool isPomodoro,
    bool soundEnabled = true,
  }) async {
    if (kIsWeb || !Platform.isAndroid) return;
    await init();
    try {
      final title = isPomodoro ? '🍅 Pomodoro Tamamlandı!' : '⏱️ Süre Doldu!';
      final body = '$activityName oturumu tamamlandı ve otomatik kaydedildi.';

      final androidDetails = AndroidNotificationDetails(
        'takip_alarms_channel',
        'Sayaç ve Pomodoro Alarmları',
        channelDescription: 'Pomodoro ve geri sayım süresi tamamlandığında çalar',
        importance: Importance.max,
        priority: Priority.high,
        playSound: soundEnabled,
        enableVibration: true,
        vibrationPattern: Int64List.fromList([0, 1000, 500, 1000]),
        category: AndroidNotificationCategory.alarm,
        actions: const [
          AndroidNotificationAction(
            'alarm_dismiss',
            'Tamam',
            showsUserInterface: false,
            cancelNotification: true,
          ),
        ],
      );

      await _plugin.show(
        10000 + timerId,
        title,
        body,
        NotificationDetails(android: androidDetails),
        payload: timerId.toString(),
      );
    } catch (e) {
      debugPrint('Error showing timer completed notification: $e');
    }
  }

  /// Pomodoro / sayaç alarmını iptal eder
  static Future<void> cancelTimerAlarm(int timerId) async {
    if (kIsWeb || !Platform.isAndroid) return;
    await init();
    try {
      await _plugin.cancel(10000 + timerId);
    } catch (e) {
      debugPrint('Error cancelling timer alarm: $e');
    }
  }

  /// Akıllı hatırlatıcıları (Su ve Gün Sonu Özeti) planlar
  static Future<void> scheduleReminders(AppStore store) async {
    if (kIsWeb || !Platform.isAndroid) return;
    await init();

    try {
      // 1. Su Hatırlatıcıları (ID aralığı: 3101 - 3106)
      for (int i = 3101; i <= 3106; i++) {
        await _plugin.cancel(i);
      }

      if (store.waterReminderEnabled) {
        final interval = store.waterReminderIntervalHours.clamp(1, 6).toInt();
        int id = 3101;
        for (int hour = 9 + interval; hour <= 21; hour += interval) {
          if (id > 3106) break;
          final scheduledDate = _nextInstanceOfTime(hour, 0);

          const androidDetails = AndroidNotificationDetails(
            'takip_reminders_channel',
            'Akıllı Hatırlatıcılar',
            channelDescription: 'Su ve aktivite hatırlatıcıları',
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
          );

          await _plugin.zonedSchedule(
            id,
            '💧 Su İçme Vakti',
            'Günün hedefine ulaşmak için bir bardak su içmeyi unutma!',
            scheduledDate,
            const NotificationDetails(android: androidDetails),
            androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
            uiLocalNotificationDateInterpretation:
                UILocalNotificationDateInterpretation.absoluteTime,
            matchDateTimeComponents: DateTimeComponents.time,
          );
          id++;
        }
      }

      // 2. Gün Sonu / Aktivite Özeti Hatırlatıcısı (ID: 3200)
      await _plugin.cancel(3200);
      if (store.dailySummaryReminderEnabled) {
        final parts = store.dailySummaryReminderTime.split(':');
        final hour = parts.isNotEmpty ? (int.tryParse(parts[0]) ?? 21) : 21;
        final minute = parts.length > 1 ? (int.tryParse(parts[1]) ?? 30) : 30;
        final scheduledDate = _nextInstanceOfTime(hour, minute);

        const androidDetails = AndroidNotificationDetails(
          'takip_reminders_channel',
          'Akıllı Hatırlatıcılar',
          channelDescription: 'Su ve aktivite hatırlatıcıları',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        );

        await _plugin.zonedSchedule(
          3200,
          '📋 Günlük Takip Özeti',
          'Günün bitmeden aktivitelerini kaydettin mi? Bugün neler yaptığını kontrol et.',
          scheduledDate,
          const NotificationDetails(android: androidDetails),
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
          matchDateTimeComponents: DateTimeComponents.time,
        );
      }
    } catch (e) {
      debugPrint('Error scheduling reminders: $e');
    }
  }

  static tz.TZDateTime _nextInstanceOfTime(int hour, int minute) {
    final tz.TZDateTime now = tz.TZDateTime.now(tz.local);
    tz.TZDateTime scheduledDate =
        tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    if (scheduledDate.isBefore(now)) {
      scheduledDate = scheduledDate.add(const Duration(days: 1));
    }
    return scheduledDate;
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
