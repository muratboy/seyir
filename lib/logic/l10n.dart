import 'package:flutter/material.dart';

enum AppLanguage { tr, en }

class AppStrings {
  final AppLanguage lang;
  const AppStrings(this.lang);

  bool get isTr => lang == AppLanguage.tr;

  // Tabs
  String get tabToday => isTr ? 'Günlük' : 'Journal';
  String get tabGoals => isTr ? 'Hedefler' : 'Goals';
  String get tabStats => isTr ? 'İstatistik' : 'Stats';
  String get tabSettings => isTr ? 'Ayarlar' : 'Settings';

  // Composer
  String get composerHint => isTr ? 'Ne yaptın?' : 'What did you do?';

  /// Hiç aktivite yokken giriş kutusunun üstünde gösterilen, dokununca kutuya yazılan örnekler.
  List<String> get composerExamples =>
      isTr ? const ['2 bardak su', '30 dk koşu', 'pomodoro ders'] : const ['Coffee', '30 min run', 'pomodoro study'];

  // Composer preview: what the submit button is about to do
  String get startTimerAction => isTr ? 'Sayacı Başlat' : 'Start Timer';
  String get previewAsEntry => isTr ? 'Kayıt olarak ekle' : 'Add as entry';
  String get previewAsTimer => isTr ? 'Sayaç başlat' : 'Start timer';
  String get newActivityMark => isTr ? 'yeni aktivite' : 'new activity';
  String get timerNoteTitle => isTr ? 'Sayaç Notu' : 'Timer Note';
  String get addNewAction => isTr ? 'Yeni Olarak Ekle' : 'Add as New';
  String get selectMeasure => isTr ? 'Ölçü / Miktar Seçeneği' : 'Measure / Option';
  String get quantity => isTr ? 'Miktar' : 'Quantity';
  String get noteHint => isTr ? 'Not (isteğe bağlı)...' : 'Note (optional)...';
  String get logButton => isTr ? 'Kaydet' : 'Log';
  String get quickListTitle => isTr ? 'Sık Yapılanlar & Yapılacaklar' : 'Shortcuts & To-Dos';
  String get quickListEmpty => isTr ? 'Henüz hızlı öğe eklenmedi. + ile ekleyebilirsin.' : 'No shortcuts yet. Tap + to add.';
  String get timelineTitle => isTr ? 'Günün Akışı' : "Today's Timeline";
  String get timelineEmpty => isTr ? 'Bugün henüz bir kayıt yok.' : 'No entries logged today.';

  // Emoji picker
  String get chooseEmoji => isTr ? 'Simge / Emoji Seç' : 'Choose Icon / Emoji';
  String get noEmoji => isTr ? 'Simgesiz' : 'No icon';
  String get customEmoji => isTr ? 'Özel Emoji' : 'Custom Emoji';

  // Measures & Units
  String get newMeasure => isTr ? 'Yeni Ölçü / Kap' : 'New Measure / Cup';
  String get measureName => isTr ? 'Ölçü Adı' : 'Measure Name';
  String get measureAmount => isTr ? 'Birim Karşılığı' : 'Equivalent Amount';
  String get unit => isTr ? 'Birim' : 'Unit';
  String get newUnit => isTr ? 'Yeni Birim' : 'New Unit';
  String get qtyModeTitle => isTr ? 'Miktar Belirtme Türü' : 'Quantity Input Mode';
  String get qtyModeStepper => isTr ? 'Klavye / Stepper' : 'Keyboard / Stepper';
  String get qtyModeChoices => isTr ? 'Çoktan Seçmeli' : 'Quick Choices';
  String get qtyModeGrid => isTr ? 'Izgara Boyama' : 'Grid Painter';
  String get gridSize => isTr ? 'Izgara Boyutu' : 'Grid Size';
  String get paintedCount => isTr ? 'kare boyandı' : 'squares painted';
  String get choicesLabel => isTr ? 'Çoktan Seçmeli Sayılar' : 'Choice Numbers';
  String get choicesHint => isTr ? 'örn: 1, 2, 3, 4, 5' : 'e.g. 1, 2, 3, 4, 5';

  // Goals & Limits
  String get newGoal => isTr ? 'Yeni Hedef / Limit' : 'New Goal / Limit';
  String get editGoal => isTr ? 'Hedefi / Limiti Düzenle' : 'Edit Goal / Limit';
  String get goalName => isTr ? 'Hedef / Limit Adı' : 'Goal / Limit Name';
  String get goalTarget => isTr ? 'Hedef Miktar' : 'Target Amount';
  String get limitTarget => isTr ? 'Azami Limit' : 'Max Limit';
  String get goalKind => isTr ? 'Hedef / Limit Çeşidi' : 'Goal / Limit Type';
  String get goalKindTarget => isTr ? 'Hedef' : 'Target';
  String get goalKindLimit => isTr ? 'Limit' : 'Limit';
  String get goalKindTargetDesc => isTr
      ? 'Belirlenen değere ulaşılınca veya geçilince başarılı sayılır (örn: 2.5 L su).'
      : 'Achieved when reaching or exceeding target (e.g. 2.5 L water).';
  String get goalKindLimitDesc => isTr
      ? 'Belirlenen değer aşılmadığı sürece başarılı sayılır (örn: 400 mg kafein).'
      : 'Achieved as long as limit is not exceeded (e.g. 400 mg caffeine).';
  String get limitWithin => isTr ? 'Limit Dahilinde' : 'Within Limit';
  String get limitExceeded => isTr ? 'Limit Aşıldı!' : 'Limit Exceeded!';
  String get remainingLimit => isTr ? 'Kalan Limit' : 'Remaining Limit';
  String get exceededAmount => isTr ? 'Aşım' : 'Exceeded';
  String get linkedGoals => isTr ? 'Bağlı Hedefler & Limitler' : 'Linked Goals & Limits';
  String get noGoalsYet => isTr ? 'Henüz hedef veya limit oluşturulmadı.' : 'No goals or limits created yet.';
  String get goalType => isTr ? 'Ölçüm Şekli' : 'Measurement Mode';
  String get period => isTr ? 'Periyot' : 'Period';
  String get periodDaily => isTr ? 'Günlük (Her gün sıfırlanır)' : 'Daily (Resets every day)';
  String get periodWeekly => isTr ? 'Haftalık' : 'Weekly';
  String get periodMonthly => isTr ? 'Aylık' : 'Monthly';
  String get periodTotal => isTr ? 'Toplam (Sıfırlanmaz, örn: 100 deneme)' : 'Total (Cumulative, e.g. 100 tests)';
  String get hasEndDate => isTr ? 'Bitiş Tarihi Var mı?' : 'Has End Date?';
  String get endDate => isTr ? 'Bitiş Tarihi' : 'End Date';
  String get linkedActivities => isTr ? 'Hedefe Bağlı Aktiviteler' : 'Connected Activities';
  String get addActivityToGoal => isTr ? 'Aktivite Bağla' : 'Connect Activity';
  String get contributionPct => isTr ? 'Hedefe Katkısı (%)' : 'Contribution (%)';
  String get daysLeft => isTr ? 'kaldı' : 'left';
  String get expired => isTr ? 'Süre doldu' : 'Expired';
  String get streak => isTr ? 'Seri' : 'Streak';

  // Habits (Zinciri Kırma)
  String get habitTitle => isTr ? 'Zinciri Kırma' : 'Habit Tracker';
  String get enableHabit => isTr ? 'Zinciri Kırma Takibi (Alışkanlık)' : 'Habit Tracking (Streak)';
  String get enableHabitDesc => isTr ? 'Her gün takip et ve seriyi bozma' : 'Track daily and maintain streak';
  String get currentStreak => isTr ? 'Mevcut Seri' : 'Current Streak';
  String get longestStreak => isTr ? 'En Uzun Seri' : 'Best Streak';
  String get totalActiveDays => isTr ? 'Aktif Gün' : 'Active Days';
  String get consistency30 => isTr ? '30 Günlük Başarı' : '30-Day Rate';
  String get doneToday => isTr ? 'Bugün Yapıldı' : 'Done Today';
  String get noHabitsTitle => isTr ? 'Henüz Alışkanlık Eklenmedi' : 'No Habits Set Yet';
  String get noHabitsDesc => isTr
      ? 'İstediğin aktiviteleri alışkanlığa dönüştürerek günlük serilerini ve GitHub katkı grafiğini takip edebilirsin.'
      : 'Turn activities into habits to track your daily streaks and GitHub-style contribution heatmap.';
  String get addHabit => isTr ? 'Alışkanlık Ekle / Seç' : 'Add / Pick Habit';
  String get timeSpreadView => isTr ? 'Zamana Yayılmış Görünüm (Isı Haritası)' : 'Timeline Heatmap View';
  String get heatmapLess => isTr ? 'Daha az' : 'Less';
  String get heatmapMore => isTr ? 'Daha çok' : 'More';

  // Stats
  String get statsTitle => isTr ? 'İstatistikler & Özet' : 'Statistics & Summary';
  String get viewDay => isTr ? 'Günlük' : 'Daily';
  String get viewWeek => isTr ? 'Haftalık' : 'Weekly';
  String get viewMonth => isTr ? 'Aylık' : 'Monthly';
  String get viewYear => isTr ? 'Yıllık' : 'Yearly';

  // Settings
  String get settingsTheme => isTr ? 'Tema Seçeneği' : 'Theme Mode';
  String get settingsLanguage => isTr ? 'Arayüz Dili' : 'Interface Language';
  String get activitiesManagement => isTr ? 'Aktiviteleri Yönet' : 'Manage Activities';
  String get activitiesSub => isTr ? 'İsim, simge/emoji ve kategori düzenle' : 'Edit name, icon/emoji and category';
  String get measuresManagement => isTr ? 'Ölçüleri & Kapları Yönet' : 'Manage Measures & Cups';
  String get widgetSetup => isTr ? 'Ana Ekran Widget Ekle' : 'Add Home Screen Widget';
  String get backupExport => isTr ? 'Yedek Al (JSON Dosyası)' : 'Export Backup (JSON File)';
  String get backupImport => isTr ? 'Yedekten Geri Yükle' : 'Restore from Backup';
  String get backupSuccess => isTr ? 'Yedek başarıyla yüklendi' : 'Backup restored successfully';

  String get healthTitle => isTr ? 'Sağlık' : 'Health';

  // Step counter permission
  String get stepSensorUnavailable => isTr
      ? 'Adım sensörü okunamıyor; bu cihazda olmayabilir. Adımları elle ekleyebilirsin.'
      : 'The step sensor cannot be read; this device may not have one. You can add steps by hand.';
  String get stepPermissionMissing => isTr
      ? 'Fiziksel aktivite izni olmadığı için adımlar sayılamıyor.'
      : 'Steps cannot be counted without the physical activity permission.';
  String get grantPermission => isTr ? 'İzin Ver' : 'Grant';
  String get stepPermissionDenied => isTr
      ? 'Adım saymak için fiziksel aktivite izni gerekiyor. Pencere açılmıyorsa izni telefonun uygulama ayarlarından verebilirsin.'
      : 'Counting steps needs the physical activity permission. If no dialog opens, grant it in the app settings of your phone.';

  // Startup recovery
  String get startupErrorTitle => isTr ? 'Veriler yüklenemedi' : 'Could not load your data';
  String get startupErrorDesc => isTr
      ? 'Veritabanı okunurken bir hata oluştu. Yeniden deneyebilir ya da aşağıdaki yerel yedeklerden birine '
          'dönebilirsin; geri yüklemeden önce mevcut veriler güvenlik yedeğine alınır.'
      : 'Reading the database failed. You can retry or go back to one of the local backups below; '
          'a safety snapshot of the current data is taken before restoring.';
  String get retry => isTr ? 'Yeniden Dene' : 'Retry';
  String get localBackups => isTr ? 'Yerel Yedekler' : 'Local Backups';
  String get noLocalBackups => isTr ? 'Henüz kaydedilmiş yerel yedek yok' : 'No local backups found';
  String get restore => isTr ? 'Geri Yükle' : 'Restore';
  String get restoreBackupTitle => isTr ? 'Yedeği Geri Yükle' : 'Restore Backup';
  String get restoreBackupConfirm => isTr
      ? 'Bu yedeği geri yüklemek istediğine emin misin?'
      : 'Are you sure you want to restore this backup?';

  // Stopwatch Mode
  String get stopwatch => isTr ? 'Kronometre' : 'Stopwatch';
  String get startStopwatch => isTr ? 'Kronometre Başlat' : 'Start Stopwatch';
  String get pause => isTr ? 'Durdur' : 'Pause';
  String get resume => isTr ? 'Devam Et' : 'Resume';
  String get finishAndSave => isTr ? 'Bitir & Kaydet' : 'Finish & Save';
  String get cancelStopwatch => isTr ? 'İptal Et' : 'Discard';
  String get cancelStopwatchConfirm => isTr
      ? 'Kronometreyi iptal etmek istediğine emin misin? Geçen süre kaydedilmeyecek.'
      : 'Are you sure you want to discard the timer? Elapsed duration will not be saved.';

  // General Dialogs
  String get cancel => isTr ? 'Vazgeç' : 'Cancel';
  String get save => isTr ? 'Kaydet' : 'Save';
  String get delete => isTr ? 'Sil' : 'Delete';
  String get edit => isTr ? 'Düzenle' : 'Edit';
  String get undo => isTr ? 'Geri al' : 'Undo';
  String get deleteConfirmTitle => isTr ? 'Silmek istediğine emin misin?' : 'Are you sure you want to delete?';
  String get deleteConfirmDesc => isTr ? 'Bu işlem geri alınamaz.' : 'This action cannot be undone.';
  String get nameRequired => isTr ? 'Lütfen bir ad girin' : 'Please enter a name';

  // Stats & Metrics
  String get metricCount => isTr ? 'Kayıt' : 'Entries';
  String get dailyAverage => isTr ? 'Günlük Ortalama' : 'Daily Average';
  String get entriesPerDay => isTr ? 'kayıt/gün' : 'entries/day';

  // Day Summary & Formatting
  String get entriesCountSuffix => isTr ? 'kayıt' : 'entries';
  String get timesSuffix => isTr ? 'kez' : 'times';

  // Privacy & Settings Groups
  String get privacyCardTitle => isTr ? 'Verilerin Cihazında Kalır' : 'Your Data Stays on Your Device';
  String get privacyCardSubtitle => isTr
      ? 'Tüm kayıtlar cihazdaki SQLite veritabanında saklanır; sunucu ya da analiz takipçisi yoktur. İnternet '
          'yalnızca bir bağlantıdan yol haritası eklendiğinde, o bağlantıyı indirmek için kullanılır.'
      : 'All records are stored in a local SQLite database on your device; there are no servers or analytics '
          'trackers. The internet is used only to download a link when you add a roadmap from one.';
  String get sectionAppearanceLanguage => isTr ? 'Görünüm & Dil' : 'Appearance & Language';
  String get sectionActivitiesData => isTr ? 'Aktiviteler & Veriler' : 'Activities & Data';
  String get sectionNotificationsReminders => isTr ? 'Akıllı Hatırlatıcılar & Bildirimler' : 'Smart Reminders & Notifications';
  String get sectionBackupReports => isTr ? 'Yedekleme & Raporlama' : 'Backup & Reports';
  String get sectionPrivacySecurity => isTr ? 'Gizlilik & Güvenlik' : 'Privacy & Security';
  String get sectionHealthTracking => isTr ? 'Sağlık & Sensör Takibi' : 'Health & Sensor Tracking';
  String get stepTrackerTitle => isTr ? 'Adım Sayar (Otomatik)' : 'Step Counter (Automatic)';
  String get stepTrackerSubtitle => isTr ? 'Telefonun sensörüyle günlük adımlarını takip et' : 'Track daily steps with phone sensor';
  String get stepDailyGoal => isTr ? 'Günlük Adım Hedefi' : 'Daily Step Goal';
  String get steps => isTr ? 'adım' : 'steps';
  String get sleepTrackerTitle => isTr ? 'Uyku Takibi' : 'Sleep Tracking';
  String get sleepTrackerSubtitle => isTr ? 'Gece uykusu oturumu ve uyku süresi takibi' : 'Night sleep session and duration tracking';
  String get sleepDailyGoal => isTr ? 'Günlük Uyku Hedefi' : 'Daily Sleep Goal';
  String get sleepSessionActive => isTr ? 'Uyku Oturumu Aktif 😴' : 'Sleep Session Active 😴';
  String get startSleepSession => isTr ? 'Uyumaya Başla' : 'Start Sleeping';
  String get wakeUp => isTr ? 'Uyandım' : 'Wake Up';
  String get logSleep => isTr ? 'Uyku Kaydet' : 'Log Sleep';
  String get syncSteps => isTr ? 'Adımı Senkronize Et' : 'Sync Steps';

  // Roadmaps (Yol Haritaları)
  String get tabRoadmaps => isTr ? 'Yol Haritası' : 'Roadmaps';
  String get roadmapsTitle => isTr ? 'Yol Haritaları' : 'Roadmaps';
  String get newRoadmap => isTr ? 'Yeni Yol Haritası Ekle' : 'Add New Roadmap';
  String get nextStep => isTr ? 'Sıradaki:' : 'Next:';
  String get completedStepsCount => isTr ? 'adım tamamlandı' : 'steps completed';
  String get activeRoadmapTargets => isTr ? 'Yol Haritası Hedefleri' : 'Roadmap Targets';

  // Timer & Pomodoro Auto-Save
  String get timerAutoSaveTitle => isTr ? 'Bitişte Otomatik Kaydet' : 'Auto-Save on Finish';
  String get timerAutoSaveSubtitle => isTr
      ? 'Geri sayım ve Pomodoro bitince otomatik kaydeder, bildirim açık kalır'
      : 'Automatically saves countdown and Pomodoro on finish while keeping notification';

  // Kilit Ekranı Hızlı Kayıt Bildirimi
  String get persistentQuickLogTitle =>
      isTr ? 'Kilit Ekranı Hızlı Kayıt Bildirimi' : 'Lock Screen Quick Log Notification';
  String get persistentQuickLogSubtitle => isTr
      ? 'Kilit ekranında ve bildirim panelinde sürekli durur; uygulamayı açmadan yazarak veya tek dokunuşla kaydetmenizi sağlar'
      : 'Stays on lock screen and notification shade; log by typing or one-tap without opening the app';
  String get quickLogNotificationTitle => isTr ? 'Takip — Hızlı Kayıt' : 'Takip — Quick Log';
  String get quickLogNotificationBodyEmpty =>
      isTr ? 'Yazarak veya düğmeye dokunarak kaydet' : 'Log by typing or tapping a button';
  String get quickLogActionType => isTr ? '✍️ Yaz' : '✍️ Type';
  String get quickLogInputLabel =>
      isTr ? 'Ne yaptın? (örn: 2 bardak su, koşu)' : 'What did you do? (e.g. 2 glasses water)';
}

final strings = ValueNotifier<AppStrings>(const AppStrings(AppLanguage.tr));
