import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import '../data/models.dart';
import '../data/store.dart';
import '../logic/l10n.dart';
import '../widget_sync.dart';
import 'store_sync.dart';

/// Arka planda bildirim aksiyon butonuna basıldığında çağrılan sistem callback'i
@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse notificationResponse) async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService.handleNotificationAction(notificationResponse);
}

class NotificationService {
  // Bildirim metinleri arayüz diliyle yazılır (arka plan isolate'larında dil, store.refresh() ile gelir).
  static bool get _tr => strings.value.isTr;

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

      // Bildirim simgesi tek renkli ayrı bir çizimdir (res/drawable/ic_stat_takip.xml). Uygulama simgesi
      // burada kullanılamaz: Android yalnızca saydamlığına bakar ve renkli simgeyi beyaz kare yapar.
      const androidSettings = AndroidInitializationSettings('ic_stat_takip');
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
          AndroidNotificationChannel(
            'takip_timers_channel',
            (_tr ? 'Canlı Kronometre & Sayaçlar' : 'Live Stopwatch & Timers'),
            description: (_tr ? 'Devam eden kronometre ve geri sayımları gösterir' : 'Shows running stopwatches and countdowns'),
            importance: Importance.low,
            playSound: false,
            enableVibration: false,
          ),
        );

        // 2. Pomodoro & Sayaç Bitiş Alarmları (Yüksek öncelikli, sesli ve titreşimli)
        await androidImpl.createNotificationChannel(
          AndroidNotificationChannel(
            'takip_alarms_channel',
            (_tr ? 'Sayaç ve Pomodoro Alarmları' : 'Timer and Pomodoro Alarms'),
            description: (_tr ? 'Pomodoro ve geri sayım süresi tamamlandığında çalar' : 'Rings when a pomodoro or countdown finishes'),
            importance: Importance.max,
            playSound: true,
            enableVibration: true,
          ),
        );

        // 3. Limit ve Hedef Uyarıları kanalı
        await androidImpl.createNotificationChannel(
          AndroidNotificationChannel(
            'takip_alerts_channel',
            (_tr ? 'Limit ve Hedef Uyarıları' : 'Limit and Goal Alerts'),
            description: (_tr ? 'Günlük limit aşımları ve hedef başarı bildirimleri' : 'Daily limit overruns and reached goals'),
            importance: Importance.high,
          ),
        );

        // 4. Akıllı Hatırlatıcılar kanalı
        await androidImpl.createNotificationChannel(
          AndroidNotificationChannel(
            'takip_reminders_channel',
            (_tr ? 'Akıllı Hatırlatıcılar' : 'Smart Reminders'),
            description: (_tr ? 'Su ve aktivite hatırlatıcıları' : 'Water and activity reminders'),
            importance: Importance.defaultImportance,
          ),
        );

        // 5. Kilit Ekranı Hızlı Kayıt kanalı (Sessiz, kalıcı bildirim)
        await androidImpl.createNotificationChannel(
          AndroidNotificationChannel(
            'takip_quick_log_channel',
            (_tr ? 'Kilit Ekranı Hızlı Kayıt' : 'Lock Screen Quick Log'),
            description: (_tr
                ? 'Kilit ekranında ve bildirim panelinde hızlı kayıt çubuğu'
                : 'Quick log bar on lock screen and notification shade'),
            importance: Importance.low,
            playSound: false,
            enableVibration: false,
            showBadge: false,
          ),
        );
      }
      _initialized = true;
    } catch (e) {
      debugPrint('NotificationService init error: $e');
    }
  }

  /// Bildirim aksiyonları veya tıklamalarını işler (Durdur, Devam Et, Bitir, Hızlı Kayıt)
  @pragma('vm:entry-point')
  static Future<void> handleNotificationAction(NotificationResponse response) async {
    final actionId = response.actionId;
    final payload = response.payload;
    debugPrint('Notification action: actionId=$actionId');

    final timerId = int.tryParse(payload ?? '');
    final isQuickLog = actionId != null && actionId.startsWith('quick_log_');
    final isSleepFinish = actionId == 'finish_sleep';
    if (timerId == null && actionId != 'alarm_dismiss' && !isQuickLog && !isSleepFinish) return;

    // Arka plan isolate'ı süreç boyunca yaşar ve kendi AppStore kopyasını taşır. Uygulama bu arada
    // sayaçları veya verileri değiştirmiş olabileceği için her aksiyondan önce veriler yeniden okunur.
    const storeActions = {'timer_pause', 'timer_resume', 'timer_finish', 'alarm_finish'};
    final changesStore = (timerId != null && storeActions.contains(actionId)) || isQuickLog || isSleepFinish;
    if (changesStore) {
      await store.refresh();
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
    } else if (isQuickLog) {
      String? logMsg;
      if (actionId == 'quick_log_input') {
        final text = response.input;
        if (text != null && text.trim().isNotEmpty) {
          logMsg = await store.logFromQuickText(text.trim());
        }
      } else if (actionId.startsWith('quick_log_item_')) {
        final itemId = int.tryParse(actionId.replaceFirst('quick_log_item_', ''));
        if (itemId != null) {
          final res = await store.tapQuickItem(itemId);
          if (res.added != null) {
            final act = store.activity(res.added!.activityId);
            final emoji = act.emoji != null && act.emoji!.trim().isNotEmpty ? '${act.emoji!.trim()} ' : '';
            logMsg = _tr ? '$emoji${act.name} kaydedildi' : '$emoji${act.name} logged';
          }
        }
      } else if (actionId.startsWith('quick_log_act_')) {
        final actId = int.tryParse(actionId.replaceFirst('quick_log_act_', ''));
        if (actId != null) {
          logMsg = await store.logQuickActivity(actId);
        }
      }

      if (store.persistentQuickLogEnabled) {
        await updatePersistentQuickLogNotification(store, lastLogMessage: logMsg);
      }
    } else if (isSleepFinish) {
      await store.stopSleepSession();
      await cancelSleepWakeupReminder();
    }

    // Açık duran uygulama ve ana ekran widget'ları, arka planda yapılan değişikliği böyle öğrenir.
    if (changesStore) {
      StoreSync.notifyChanged();
      await WidgetSync.push();
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
              ? (_tr ? '$firstAct (Çalışıyor)' : '$firstAct (Running)')
              : (_tr ? '$firstAct (Duraklatıldı: ${firstTimer.displayDuration})' : '$firstAct (Paused: ${firstTimer.displayDuration})'))
          : (_tr ? '$runningCount/${timers.length} Aktif Zamanlayıcı' : '$runningCount/${timers.length} Active Timers');

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
          AndroidNotificationAction(
            'timer_pause',
            (_tr ? '⏸️ Duraklat' : '⏸️ Pause'),
            showsUserInterface: false,
            cancelNotification: false,
          )
        else
          AndroidNotificationAction(
            'timer_resume',
            (_tr ? '▶️ Devam Et' : '▶️ Resume'),
            showsUserInterface: false,
            cancelNotification: false,
          ),
        AndroidNotificationAction(
          'timer_finish',
          (_tr ? '⏹️ Bitir' : '⏹️ Finish'),
          showsUserInterface: false,
          cancelNotification: true,
        ),
      ];

      final androidDetails = AndroidNotificationDetails(
        'takip_timers_channel',
        (_tr ? 'Canlı Kronometre & Sayaçlar' : 'Live Stopwatch & Timers'),
        channelDescription: (_tr ? 'Devam eden kronometre ve geri sayımları gösterir' : 'Shows running stopwatches and countdowns'),
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

  /// Sayaç ve Pomodoro alarmlarının kanalı ve ayarları: ses, titreşim, alarm önceliği.
  static AndroidNotificationDetails _alarmDetails({
    required bool soundEnabled,
    List<AndroidNotificationAction>? actions,
  }) =>
      AndroidNotificationDetails(
        'takip_alarms_channel',
        (_tr ? 'Sayaç ve Pomodoro Alarmları' : 'Timer and Pomodoro Alarms'),
        channelDescription: (_tr ? 'Pomodoro ve geri sayım süresi tamamlandığında çalar' : 'Rings when a pomodoro or countdown finishes'),
        importance: Importance.max,
        priority: Priority.high,
        playSound: soundEnabled,
        enableVibration: true,
        vibrationPattern: Int64List.fromList([0, 1000, 500, 1000]),
        category: AndroidNotificationCategory.alarm,
        actions: actions,
      );

  static const _testNotificationId = 9000;

  /// Ayarlar'daki "Bildirimi Dene": birkaç saniye sonra, sayaç alarmıyla aynı kanaldan ve aynı yoldan (tam
  /// zamanlı alarm, ses, titreşim) bir deneme bildirimi gönderir. Böylece bildirim izni, alarm izni ve ses tek
  /// seferde sınanır. Sayaçla bağı olmadığı için üzerinde "Bitir & Kaydet" gibi düğmeler yoktur.
  static Future<void> scheduleTestNotification({
    bool soundEnabled = true,
    Duration after = const Duration(seconds: 3),
  }) async {
    if (kIsWeb || !Platform.isAndroid) return;
    await init();
    try {
      await _plugin.zonedSchedule(
        _testNotificationId,
        _tr ? '🔔 Deneme Bildirimi' : '🔔 Test Notification',
        _tr
            ? 'Bildirimler çalışıyor; bir sayaç bittiğinde de böyle haber verilir.'
            : 'Notifications work; this is how you will hear that a timer has finished.',
        tz.TZDateTime.now(tz.local).add(after),
        NotificationDetails(android: _alarmDetails(soundEnabled: soundEnabled)),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      );
    } catch (e) {
      debugPrint('Error scheduling test notification: $e');
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

      final title = isPomodoro ? (_tr ? '🍅 Pomodoro Tamamlandı!' : '🍅 Pomodoro Completed!') : (_tr ? '⏱️ Süre Doldu!' : '⏱️ Time is Up!');
      final body = autoSaveEnabled
          ? (_tr ? '$activityName oturumu tamamlandı ve otomatik kaydedildi.' : 'The $activityName session is complete and was saved automatically.')
          : (_tr ? '$activityName için hedeflenen süre tamamlandı. Oturumu kaydetmek için dokun.' : 'The target time for $activityName is over. Tap to save the session.');

      final actions = autoSaveEnabled
          ? [
              AndroidNotificationAction(
                'alarm_dismiss',
                (_tr ? 'Tamam' : 'OK'),
                showsUserInterface: false,
                cancelNotification: true,
              ),
            ]
          : [
              AndroidNotificationAction(
                'alarm_finish',
                (_tr ? '⏹️ Bitir & Kaydet' : '⏹️ Finish & Save'),
                showsUserInterface: true,
                cancelNotification: true,
              ),
              AndroidNotificationAction(
                'alarm_dismiss',
                (_tr ? 'Kapat' : 'Dismiss'),
                showsUserInterface: false,
                cancelNotification: true,
              ),
            ];

      final androidDetails = _alarmDetails(soundEnabled: soundEnabled, actions: actions);

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
      final title = isPomodoro ? (_tr ? '🍅 Pomodoro Tamamlandı!' : '🍅 Pomodoro Completed!') : (_tr ? '⏱️ Süre Doldu!' : '⏱️ Time is Up!');
      final body = (_tr ? '$activityName oturumu tamamlandı ve otomatik kaydedildi.' : 'The $activityName session is complete and was saved automatically.');

      final androidDetails = _alarmDetails(
        soundEnabled: soundEnabled,
        actions: [
          AndroidNotificationAction(
            'alarm_dismiss',
            (_tr ? 'Tamam' : 'OK'),
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

          final androidDetails = AndroidNotificationDetails(
            'takip_reminders_channel',
            (_tr ? 'Akıllı Hatırlatıcılar' : 'Smart Reminders'),
            channelDescription: (_tr ? 'Su ve aktivite hatırlatıcıları' : 'Water and activity reminders'),
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
          );

          await _plugin.zonedSchedule(
            id,
            (_tr ? '💧 Su İçme Vakti' : '💧 Time for Water'),
            (_tr ? 'Günün hedefine ulaşmak için bir bardak su içmeyi unutma!' : 'Remember a glass of water to reach your goal for today!'),
            scheduledDate,
            NotificationDetails(android: androidDetails),
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

        final androidDetails = AndroidNotificationDetails(
          'takip_reminders_channel',
          (_tr ? 'Akıllı Hatırlatıcılar' : 'Smart Reminders'),
          channelDescription: (_tr ? 'Su ve aktivite hatırlatıcıları' : 'Water and activity reminders'),
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        );

        await _plugin.zonedSchedule(
          3200,
          (_tr ? '📋 Günlük Seyir Özeti' : '📋 Daily Summary'),
          (_tr ? 'Günün bitmeden aktivitelerini kaydettin mi? Bugün neler yaptığını kontrol et.' : 'Have you logged your activities before the day ends? Check what you did today.'),
          scheduledDate,
          NotificationDetails(android: androidDetails),
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
          matchDateTimeComponents: DateTimeComponents.time,
        );
      }

      // 3. Aktivite Bazlı Hatırlatıcılar (ID aralığı: 4000 + reminder.id)
      for (final reminder in store.activityReminders) {
        final notifId = 4000 + reminder.id;
        await _plugin.cancel(notifId);
        if (reminder.isEnabled) {
          final act = store.activity(reminder.activityId);
          final parts = reminder.time.split(':');
          final hour = parts.isNotEmpty ? (int.tryParse(parts[0]) ?? 9) : 9;
          final minute = parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0;
          final scheduledDate = _nextInstanceOfTime(hour, minute);

          final actEmoji = act.emoji != null && act.emoji!.trim().isNotEmpty ? '${act.emoji!.trim()} ' : '';
          final title = '⏰ $actEmoji${act.name}';
          final body = reminder.customMessage ?? (_tr ? 'Aktiviteni kaydetme zamanı geldi.' : 'Time to log your activity.');

          final androidDetails = AndroidNotificationDetails(
            'takip_reminders_channel',
            (_tr ? 'Akıllı Hatırlatıcılar' : 'Smart Reminders'),
            channelDescription: (_tr ? 'Su ve aktivite hatırlatıcıları' : 'Water and activity reminders'),
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
            actions: [
              AndroidNotificationAction(
                'quick_log_act_${reminder.activityId}',
                _tr ? 'Hızlı Kaydet' : 'Quick Log',
                showsUserInterface: false,
                cancelNotification: true,
              ),
            ],
          );

          await _plugin.zonedSchedule(
            notifId,
            title,
            body,
            scheduledDate,
            NotificationDetails(android: androidDetails),
            androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
            uiLocalNotificationDateInterpretation:
                UILocalNotificationDateInterpretation.absoluteTime,
            matchDateTimeComponents: DateTimeComponents.time,
          );
        }
      }
    } catch (e) {
      debugPrint('Error scheduling reminders: $e');
    }
  }

  static const int _sleepWakeupNotificationId = 3300;

  /// Uyku seansı devam ederken uyanış hatırlatıcısı planlar
  static Future<void> scheduleSleepWakeupReminder(AppStore store, DateTime startTime) async {
    if (kIsWeb || !Platform.isAndroid) return;
    await init();
    try {
      await cancelSleepWakeupReminder();
      final goalMinutes = (store.sleepDailyGoalHours * 60).round();
      final wakeTime = startTime.add(Duration(minutes: goalMinutes));
      final tzWake = tz.TZDateTime.from(wakeTime, tz.local);
      final tzNow = tz.TZDateTime.now(tz.local);
      final targetTz = tzWake.isBefore(tzNow) ? tzNow.add(const Duration(minutes: 1)) : tzWake;

      final androidDetails = AndroidNotificationDetails(
        'takip_reminders_channel',
        (_tr ? 'Akıllı Hatırlatıcılar' : 'Smart Reminders'),
        channelDescription: (_tr ? 'Su ve aktivite hatırlatıcıları' : 'Water and activity reminders'),
        importance: Importance.high,
        priority: Priority.high,
        actions: [
          AndroidNotificationAction(
            'finish_sleep',
            _tr ? 'Uykuyu Bitir' : 'Finish Sleep',
            showsUserInterface: false,
            cancelNotification: true,
          ),
        ],
      );

      final title = _tr ? '🌅 Günaydın! Uykunu tamamladın mı?' : '🌅 Good morning! Did you finish sleeping?';
      final body = _tr
          ? 'Hedeflenen ${store.sleepDailyGoalHours.toStringAsFixed(1)} saatlik uyku seansını tamamlamak için dokun.'
          : 'Tap to complete your targeted ${store.sleepDailyGoalHours.toStringAsFixed(1)}h sleep session.';

      await _plugin.zonedSchedule(
        _sleepWakeupNotificationId,
        title,
        body,
        targetTz,
        NotificationDetails(android: androidDetails),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
    } catch (e) {
      debugPrint('Error scheduling sleep wakeup reminder: $e');
    }
  }

  /// Uyku uyanış hatırlatıcısını iptal eder
  static Future<void> cancelSleepWakeupReminder() async {
    if (kIsWeb || !Platform.isAndroid) return;
    await init();
    try {
      await _plugin.cancel(_sleepWakeupNotificationId);
    } catch (e) {
      debugPrint('Error cancelling sleep reminder: $e');
    }
  }

  /// Belirli bir aktivite hatırlatıcısına ait planlanmış bildirimi iptal eder (ID: 4000 + reminderId).
  static Future<void> cancelActivityReminder(int reminderId) async {
    if (kIsWeb || !Platform.isAndroid) return;
    await init();
    try {
      await _plugin.cancel(4000 + reminderId);
    } catch (e) {
      debugPrint('Error cancelling activity reminder: $e');
    }
  }

  static tz.TZDateTime _nextInstanceOfTime(int hour, int minute) {
    final tz.TZDateTime now = tz.TZDateTime.now(tz.local);
    tz.TZDateTime scheduledDate =
        tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    if (scheduledDate.isBefore(now)) {
      scheduledDate =
          tz.TZDateTime(tz.local, now.year, now.month, now.day + 1, hour, minute);
    }
    return scheduledDate;
  }

  static Future<void> showLimitAlert(String title, String body) async {
    if (kIsWeb || !Platform.isAndroid) return;
    await init();
    try {
      final androidDetails = AndroidNotificationDetails(
        'takip_alerts_channel',
        (_tr ? 'Limit ve Hedef Uyarıları' : 'Limit and Goal Alerts'),
        channelDescription: (_tr ? 'Günlük limit aşımları ve hedef başarı bildirimleri' : 'Daily limit overruns and reached goals'),
        importance: Importance.high,
        priority: Priority.high,
      );
      await _plugin.show(
        2001,
        title,
        body,
        NotificationDetails(android: androidDetails),
      );
    } catch (e) {
      debugPrint('Error showing limit alert: $e');
    }
  }

  static Future<void> showReminder(String title, String body) async {
    if (kIsWeb || !Platform.isAndroid) return;
    await init();
    try {
      final androidDetails = AndroidNotificationDetails(
        'takip_reminders_channel',
        (_tr ? 'Akıllı Hatırlatıcılar' : 'Smart Reminders'),
        channelDescription: (_tr ? 'Su ve aktivite hatırlatıcıları' : 'Water and activity reminders'),
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
      );
      await _plugin.show(
        3001,
        title,
        body,
        NotificationDetails(android: androidDetails),
      );
    } catch (e) {
      debugPrint('Error showing reminder: $e');
    }
  }

  static const int _quickLogNotificationId = 1002;

  /// Kilit ekranı ve bildirim panelinde sürekli duran hızlı kayıt çubuğunu günceller.
  static Future<void> updatePersistentQuickLogNotification(
    AppStore store, {
    String? lastLogMessage,
  }) async {
    if (kIsWeb || !Platform.isAndroid || !store.persistentQuickLogEnabled) return;
    await init();

    try {
      final s = strings.value;
      final title = s.quickLogNotificationTitle;
      final body = lastLogMessage != null
          ? (_tr ? 'Son: $lastLogMessage' : 'Last: $lastLogMessage')
          : s.quickLogNotificationBodyEmpty;

      // Hızlı aksiyon düğmeleri (En fazla 2 düğme + 1 RemoteInput = toplam 3)
      final quickActions = <AndroidNotificationAction>[
        AndroidNotificationAction(
          'quick_log_input',
          s.quickLogActionType,
          inputs: [
            AndroidNotificationActionInput(
              label: s.quickLogInputLabel,
              allowFreeFormInput: true,
            ),
          ],
          showsUserInterface: false,
          cancelNotification: false,
        ),
      ];

      // Kısayollardan veya sık yapılan aktivitelerden ilk 2 tanesini buton yap
      final items = store.quickItems.where((i) => !i.isTodo).take(2).toList();
      if (items.isNotEmpty) {
        for (final item in items) {
          final act = store.activity(item.activityId);
          final emoji = act.emoji != null && act.emoji!.trim().isNotEmpty ? '${act.emoji!.trim()} ' : '';
          quickActions.add(
            AndroidNotificationAction(
              'quick_log_item_${item.id}',
              '$emoji${act.name}'.trim(),
              showsUserInterface: false,
              cancelNotification: false,
            ),
          );
        }
      } else {
        final topActs = store.timeBasedSuggestions(limit: 2);
        for (final act in topActs) {
          final emoji = act.emoji != null && act.emoji!.trim().isNotEmpty ? '${act.emoji!.trim()} ' : '';
          quickActions.add(
            AndroidNotificationAction(
              'quick_log_act_${act.id}',
              '$emoji${act.name}'.trim(),
              showsUserInterface: false,
              cancelNotification: false,
            ),
          );
        }
      }

      final androidDetails = AndroidNotificationDetails(
        'takip_quick_log_channel',
        (_tr ? 'Kilit Ekranı Hızlı Kayıt' : 'Lock Screen Quick Log'),
        channelDescription: (_tr
            ? 'Kilit ekranında ve bildirim panelinde hızlı kayıt çubuğu'
            : 'Quick log bar on lock screen and notification shade'),
        importance: Importance.low,
        priority: Priority.low,
        ongoing: true,
        autoCancel: false,
        visibility: NotificationVisibility.public,
        actions: quickActions,
      );

      await _plugin.show(
        _quickLogNotificationId,
        title,
        body,
        NotificationDetails(android: androidDetails),
      );
    } catch (e) {
      debugPrint('Error updating persistent quick log notification: $e');
    }
  }

  /// Kilit ekranı hızlı kayıt bildirimini kaldırır.
  static Future<void> cancelPersistentQuickLogNotification() async {
    if (kIsWeb || !Platform.isAndroid) return;
    await init();
    try {
      await _plugin.cancel(_quickLogNotificationId);
    } catch (e) {
      debugPrint('Error cancelling quick log notification: $e');
    }
  }
}
