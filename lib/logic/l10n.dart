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
  String get composerHint => isTr ? 'Ne yaptın? (örn: Çay, Kitap...)' : 'What did you do? (e.g. Tea, Book...)';
  String get suggestionsTitle => isTr ? 'Öneriler' : 'Suggestions';
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
  String get catDrinks => isTr ? 'İçecekler' : 'Drinks';
  String get catFood => isTr ? 'Yiyecekler' : 'Food';
  String get catSport => isTr ? 'Spor & Sağlık' : 'Fitness & Health';
  String get catStudy => isTr ? 'Çalışma & Zihin' : 'Study & Mind';
  String get catDaily => isTr ? 'Günlük & Ev' : 'Daily & Home';
  String get catHobbies => isTr ? 'Hobi & Eğlence' : 'Hobbies & Fun';
  String get catOther => isTr ? 'Semboller' : 'Symbols';

  // Measures & Units
  String get measuresTitle => isTr ? 'Ölçü Seçenekleri' : 'Measure Options';
  String get newMeasure => isTr ? 'Yeni Ölçü / Kap' : 'New Measure / Cup';
  String get measureName => isTr ? 'Ölçü Adı' : 'Measure Name';
  String get measureAmount => isTr ? 'Birim Karşılığı' : 'Equivalent Amount';
  String get unit => isTr ? 'Birim' : 'Unit';
  String get newUnit => isTr ? 'Yeni Birim' : 'New Unit';
  String get unitName => isTr ? 'Birim Adı' : 'Unit Name';
  String get unitSymbol => isTr ? 'Kısaltma / Sembol' : 'Symbol';
  String get qtyModeTitle => isTr ? 'Miktar Belirtme Türü' : 'Quantity Input Mode';
  String get qtyModeStepper => isTr ? 'Klavye / Stepper' : 'Keyboard / Stepper';
  String get qtyModeChoices => isTr ? 'Çoktan Seçmeli' : 'Quick Choices';
  String get qtyModeGrid => isTr ? 'Izgara Boyama' : 'Grid Painter';
  String get gridSize => isTr ? 'Izgara Boyutu' : 'Grid Size';
  String get paintedCount => isTr ? 'kare boyandı' : 'squares painted';
  String get choicesLabel => isTr ? 'Çoktan Seçmeli Sayılar' : 'Choice Numbers';
  String get choicesHint => isTr ? 'örn: 1, 2, 3, 4, 5' : 'e.g. 1, 2, 3, 4, 5';

  // Goals & Limits
  String get goalsTitle => isTr ? 'Hedefler & Limitler' : 'Goals & Limits';
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
  String get linkGoal => isTr ? 'Hedefe Bağla' : 'Link to Goal';
  String get noGoalsYet => isTr ? 'Henüz hedef veya limit oluşturulmadı.' : 'No goals or limits created yet.';
  String get goalType => isTr ? 'Ölçüm Şekli' : 'Measurement Mode';
  String get goalTypeAmount => isTr ? 'Miktar / Hacim bazlı (Litre, km vb.)' : 'Amount / Volume based (Liters, km etc.)';
  String get goalTypeCount => isTr ? 'Adet / Sayı bazlı (Kaç kez yapıldı)' : 'Count based (Number of times)';
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
  String get goalAchieved => isTr ? 'Hedefe ulaşıldı!' : 'Goal achieved!';
  String get daysLeft => isTr ? 'kaldı' : 'left';
  String get expired => isTr ? 'Süre doldu' : 'Expired';
  String get dailyNeeded => isTr ? 'Gereken günlük ortalama' : 'Daily pace needed';
  String get streak => isTr ? 'Seri' : 'Streak';

  // Habits (Zinciri Kırma)
  String get tabHabits => isTr ? 'Zinciri Kırma' : 'Habits';
  String get habitTitle => isTr ? 'Zinciri Kırma' : 'Habit Tracker';
  String get habitSubtitle => isTr ? 'GitHub tarzı katkı grafiği ve seri takibi' : 'GitHub-style heatmap and streak tracking';
  String get enableHabit => isTr ? 'Zinciri Kırma Takibi (Alışkanlık)' : 'Habit Tracking (Streak)';
  String get enableHabitDesc => isTr ? 'Her gün takip et ve seriyi bozma' : 'Track daily and maintain streak';
  String get currentStreak => isTr ? 'Mevcut Seri' : 'Current Streak';
  String get longestStreak => isTr ? 'En Uzun Seri' : 'Best Streak';
  String get totalActiveDays => isTr ? 'Aktif Gün' : 'Active Days';
  String get consistency30 => isTr ? '30 Günlük Başarı' : '30-Day Rate';
  String get doneToday => isTr ? 'Bugün Yapıldı' : 'Done Today';
  String get notDoneToday => isTr ? 'Bugün Henüz Yapılmadı' : 'Not Done Today';
  String get completeToday => isTr ? 'Bugün Tamamla' : 'Complete Today';
  String get noHabitsTitle => isTr ? 'Henüz Alışkanlık Eklenmedi' : 'No Habits Set Yet';
  String get noHabitsDesc => isTr
      ? 'İstediğin aktiviteleri alışkanlığa dönüştürerek günlük serilerini ve GitHub katkı grafiğini takip edebilirsin.'
      : 'Turn activities into habits to track your daily streaks and GitHub-style contribution heatmap.';
  String get addHabit => isTr ? 'Alışkanlık Ekle / Seç' : 'Add / Pick Habit';
  String get addToHabits => isTr ? 'Zinciri Kırma\'ya Ekle' : 'Add to Habits';
  String get viewInHabits => isTr ? 'Zinciri Kırma\'da Görüntüle' : 'View in Habits';
  String get removeFromHabits => isTr ? 'Zinciri Kırma\'dan Çıkar' : 'Remove from Habits';
  String get timeSpreadView => isTr ? 'Zamana Yayılmış Görünüm (Isı Haritası)' : 'Timeline Heatmap View';
  String get allHabits => isTr ? 'Tümü' : 'All';
  String get habitGoalsTitle => isTr ? 'Hedef & Limitler' : 'Goals & Limits';
  String get habitActivitiesTitle => isTr ? 'Aktiviteler' : 'Activities';
  String get heatmapLess => isTr ? 'Daha az' : 'Less';
  String get heatmapMore => isTr ? 'Daha çok' : 'More';

  // Stats
  String get statsTitle => isTr ? 'İstatistikler & Özet' : 'Statistics & Summary';
  String get viewDay => isTr ? 'Günlük' : 'Daily';
  String get viewWeek => isTr ? 'Haftalık' : 'Weekly';
  String get viewMonth => isTr ? 'Aylık' : 'Monthly';
  String get viewYear => isTr ? 'Yıllık' : 'Yearly';
  String get filterAll => isTr ? 'Tüm Kayıtlar' : 'All Activities';
  String get totalCount => isTr ? 'Toplam Giriş' : 'Total Entries';
  String get byMeasureBreakdown => isTr ? 'Ölçülere Göre Dağılım' : 'Breakdown by Measure';

  // Settings
  String get settingsTheme => isTr ? 'Tema Seçeneği' : 'Theme Mode';
  String get themeSystem => isTr ? 'Sistem Varsayılanı' : 'System Default';
  String get themeLight => isTr ? 'Açık Tema' : 'Light Theme';
  String get themeDark => isTr ? 'Karanlık Tema' : 'Dark Theme';
  String get settingsLanguage => isTr ? 'Arayüz Dili' : 'Interface Language';
  String get langTr => isTr ? 'Türkçe' : 'Turkish';
  String get langEn => isTr ? 'İngilizce' : 'English';
  String get activitiesManagement => isTr ? 'Aktiviteleri Yönet' : 'Manage Activities';
  String get activitiesSub => isTr ? 'İsim, simge/emoji düzenle veya birleştir' : 'Edit name, icon/emoji or merge';
  String get measuresManagement => isTr ? 'Ölçüleri & Kapları Yönet' : 'Manage Measures & Cups';
  String get widgetSetup => isTr ? 'Ana Ekran Widget Ekle' : 'Add Home Screen Widget';
  String get backupExport => isTr ? 'Yedek Al (JSON Dışa Aktar)' : 'Export Backup (JSON)';
  String get backupImport => isTr ? 'Yedekten Geri Yükle' : 'Restore from Backup';
  String get backupSuccess => isTr ? 'Yedek başarıyla yüklendi' : 'Backup restored successfully';
  String get backupExported => isTr ? 'Yedek panoya kopyalandı veya kaydedildi' : 'Backup copied or saved';

  // Stopwatch Mode
  String get stopwatch => isTr ? 'Kronometre' : 'Stopwatch';
  String get startStopwatch => isTr ? 'Kronometre Başlat' : 'Start Stopwatch';
  String get stopwatchRunning => isTr ? 'Kronometre Çalışıyor' : 'Stopwatch Running';
  String get stopwatchPaused => isTr ? 'Duraklatıldı' : 'Paused';
  String get pause => isTr ? 'Durdur' : 'Pause';
  String get resume => isTr ? 'Devam Et' : 'Resume';
  String get finishAndSave => isTr ? 'Bitir & Kaydet' : 'Finish & Save';
  String get cancelStopwatch => isTr ? 'İptal Et' : 'Discard';
  String get cancelStopwatchConfirm => isTr
      ? 'Kronometreyi iptal etmek istediğine emin misin? Geçen süre kaydedilmeyecek.'
      : 'Are you sure you want to discard the timer? Elapsed duration will not be saved.';
  String get stopwatchSaved => isTr ? 'Süre kaydedildi' : 'Duration saved';

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
  String get metricTime => isTr ? 'Süre' : 'Duration';
  String get metricVolume => isTr ? 'Hacim' : 'Volume';
  String get peakPoint => isTr ? 'Zirve Noktası' : 'Peak Point';
  String get dailyAverage => isTr ? 'Günlük Ortalama' : 'Daily Average';
  String get entriesPerDay => isTr ? 'kayıt/gün' : 'entries/day';
  String get noCategoryChart => isTr
      ? 'Kategori dağılımı için en az 2 farklı kategori gereklidir.'
      : 'At least 2 different categories are needed for category distribution.';
  String get assignCategoryHint => isTr
      ? 'Aktivitelerine kategori atayarak dağılımı görebilirsin.'
      : 'Assign categories to your activities to view category distribution.';

  // Day Summary & Formatting
  String get entriesCountSuffix => isTr ? 'kayıt' : 'entries';
  String get timesSuffix => isTr ? 'kez' : 'times';
  String get backToToday => isTr ? 'Bugüne Dön' : 'Back to Today';

  // Privacy & Settings Groups
  String get privacyCardTitle => isTr ? 'Takip %100 Çevrimdışı & Yerel' : 'Takip 100% Offline & Local';
  String get privacyCardSubtitle => isTr
      ? 'Tüm verileriniz cihazınızdaki SQLite veritabanında saklanır. Harici sunucu veya analiz takipçisi yoktur.'
      : 'All your data is stored in a local SQLite database on your device. No cloud servers, no analytics trackers.';
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
  String get startSleepSession => isTr ? 'Uyumaya Başla 🌙' : 'Start Sleeping 🌙';
  String get wakeUp => isTr ? 'Uyandım ☀️' : 'Wake Up ☀️';
  String get logSleep => isTr ? 'Uyku Kaydet 🛌' : 'Log Sleep 🛌';
  String get syncSteps => isTr ? 'Adımı Senkronize Et' : 'Sync Steps';

  // Roadmaps (Yol Haritaları)
  String get tabRoadmaps => isTr ? 'Yol Haritası' : 'Roadmaps';
  String get roadmapsTitle => isTr ? 'Yol Haritaları' : 'Roadmaps';
  String get newRoadmap => isTr ? 'Yeni Yol Haritası Ekle' : 'Add New Roadmap';
  String get roadmapDesc => isTr ? 'Kişisel gelişim veya hedef yol haritası' : 'Personal growth or goal roadmap';
  String get startJourney => isTr ? 'Yolculuğu Başlat' : 'Start Journey';
  String get continueJourney => isTr ? 'Yolculuğa Devam Et' : 'Continue Journey';
  String get pauseJourney => isTr ? 'Yolculuğu Duraklat' : 'Pause Journey';
  String get journeyActive => isTr ? 'Yolculukta' : 'In Progress';
  String get journeyCompleted => isTr ? 'Tamamlandı' : 'Completed';
  String get roadmapEmpty => isTr ? 'Henüz bir yol haritası eklenmedi.' : 'No roadmaps added yet.';
  String get copyTemplate => isTr ? 'Kalıbı Kopyala' : 'Copy Template';
  String get pasteRoadmap => isTr ? 'Yol Haritası Yükle' : 'Import Roadmap';
  String get nextStep => isTr ? 'Sıradaki:' : 'Next:';
  String get completedStepsCount => isTr ? 'adım tamamlandı' : 'steps completed';
  String get activeRoadmapTargets => isTr ? 'Yol Haritası Hedefleri' : 'Roadmap Targets';
  String get allRoadmaps => isTr ? 'Tüm Haritalar' : 'All Roadmaps';

  // Timer & Pomodoro Auto-Save
  String get timerAutoSaveTitle => isTr ? 'Bitişte Otomatik Kaydet' : 'Auto-Save on Finish';
  String get timerAutoSaveSubtitle => isTr
      ? 'Geri sayım ve Pomodoro bitince otomatik kaydeder, bildirim açık kalır'
      : 'Automatically saves countdown and Pomodoro on finish while keeping notification';
  String get timerCompletedTitle => isTr ? '⏱️ Süre Doldu!' : '⏱️ Time is Up!';
  String get pomodoroCompletedTitle => isTr ? '🍅 Pomodoro Tamamlandı!' : '🍅 Pomodoro Completed!';
  String get timerCompletedBody => isTr
      ? 'Oturum tamamlandı ve otomatik kaydedildi.'
      : 'Session completed and automatically logged.';
}

final strings = ValueNotifier<AppStrings>(const AppStrings(AppLanguage.tr));
