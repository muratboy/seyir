import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/store.dart';
import '../logic/format.dart';
import '../logic/l10n.dart';
import '../widget_sync.dart';
import 'common.dart';
import 'settings_pages.dart';
import 'app_font.dart';
import 'activity_page.dart';
import 'activity_merge_page.dart';

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
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: AppFont.small),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: SegmentedButton<ThemeMode>(
                          // Seçim zaten dolgu rengiyle görünür; onay işareti "Sistem"i iki satıra bölüyordu. Etiketler dar
                          // ekranda bölünmek yerine küçülür.
                          showSelectedIcon: false,
                          style: const ButtonStyle(visualDensity: VisualDensity.compact),
                          segments: [
                            ButtonSegment(
                              value: ThemeMode.system,
                              icon: const Icon(Icons.brightness_auto, size: 16),
                              label: FittedBox(fit: BoxFit.scaleDown, child: Text(s.isTr ? 'Sistem' : 'System', maxLines: 1)),
                            ),
                            ButtonSegment(
                              value: ThemeMode.light,
                              icon: const Icon(Icons.light_mode_outlined, size: 16),
                              label: FittedBox(fit: BoxFit.scaleDown, child: Text(s.isTr ? 'Açık' : 'Light', maxLines: 1)),
                            ),
                            ButtonSegment(
                              value: ThemeMode.dark,
                              icon: const Icon(Icons.dark_mode_outlined, size: 16),
                              label: FittedBox(fit: BoxFit.scaleDown, child: Text(s.isTr ? 'Koyu' : 'Dark', maxLines: 1)),
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
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: AppFont.small),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: SegmentedButton<AppLanguage>(
                          showSelectedIcon: false,
                          style: const ButtonStyle(visualDensity: VisualDensity.compact),
                          segments: const [
                            ButtonSegment(
                              value: AppLanguage.tr,
                              icon: Text('🇹🇷', style: TextStyle(fontSize: AppFont.subtitle)),
                              label: Text('Türkçe'),
                            ),
                            ButtonSegment(
                              value: AppLanguage.en,
                              icon: Text('🇬🇧', style: TextStyle(fontSize: AppFont.subtitle)),
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
                          showModalBottomSheet(
                            context: context,
                            showDragHandle: true,
                            builder: (ctx) => SafeArea(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  ListTile(
                                    leading: const Icon(Icons.grid_view_rounded),
                                    title: Text(s.isTr ? 'Geniş Widget (4x2)' : 'Grid Widget (4x2)'),
                                    subtitle: Text(
                                      s.isTr
                                          ? 'Kısayollar, hedefler ve sesli kayıt'
                                          : 'Shortcuts, goals and voice log',
                                    ),
                                    onTap: () async {
                                      Navigator.pop(ctx);
                                      final pinned = await WidgetSync.requestPin();
                                      if (context.mounted && !pinned) {
                                        showSnack(
                                          context,
                                          s.isTr
                                              ? 'Ana ekrana basılı tutup Widgetlar > Takip seçebilirsiniz.'
                                              : 'Long press home screen -> Widgets -> Takip to add.',
                                        );
                                      }
                                    },
                                  ),
                                  ListTile(
                                    leading: const Icon(Icons.crop_square_rounded),
                                    title: Text(s.isTr ? 'Mini Widget (1x1)' : 'Mini Widget (1x1)'),
                                    subtitle: Text(
                                      s.isTr
                                          ? 'Tek dokunuşla sıradaki/öncelikli aktivite kaydı'
                                          : 'One-tap next/priority activity log',
                                    ),
                                    onTap: () async {
                                      Navigator.pop(ctx);
                                      final pinned = await WidgetSync.requestPinSingle();
                                      if (context.mounted && !pinned) {
                                        showSnack(
                                          context,
                                          s.isTr
                                              ? 'Ana ekrana basılı tutup Widgetlar > Takip seçebilirsiniz.'
                                              : 'Long press home screen -> Widgets -> Takip to add.',
                                        );
                                      }
                                    },
                                  ),
                                  const SizedBox(height: 12),
                                ],
                              ),
                            ),
                          );
                        },
                        child: Text(s.isTr ? 'Ekle' : 'Add'),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // 3. Bildirimler, sağlık ve yedekler kendi sayfalarındadır; burada durumları özetlenir. Hepsi tek
              // sayfadayken Ayarlar telefon ekranında defalarca kaydırılıyordu.
              SectionTitle(s.isTr ? 'Diğer Ayarlar' : 'More Settings'),
              Card(
                child: Column(
                  children: [
                    _SettingsLink(
                      icon: Icons.notifications_active_outlined,
                      color: Colors.amber,
                      title: s.sectionNotificationsReminders,
                      summary: _notificationSummary(s),
                      page: const NotificationSettingsPage(),
                    ),
                    const Divider(height: 1),
                    _SettingsLink(
                      icon: Icons.monitor_heart_outlined,
                      color: Colors.teal,
                      title: s.sectionHealthTracking,
                      summary: _healthSummary(s),
                      warning: store.stepTrackerEnabled && store.stepPermissionMissing,
                      page: const HealthSettingsPage(),
                    ),
                    const Divider(height: 1),
                    _SettingsLink(
                      icon: Icons.backup_outlined,
                      color: Colors.blue,
                      title: s.sectionBackupReports,
                      summary: s.isTr
                          ? 'PDF ve CSV raporu, JSON yedek, yerel yedekler'
                          : 'PDF and CSV reports, JSON backup, local backups',
                      page: const BackupSettingsPage(),
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
                            Text(
                              s.privacyCardTitle,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: AppFont.body),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              s.privacyCardSubtitle,
                              style: TextStyle(
                                fontSize: AppFont.caption,
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
                icon: const Icon(Icons.call_merge_rounded),
                tooltip: s.isTr ? 'Aktiviteleri Birleştir' : 'Merge Activities',
                onPressed: () => Navigator.push(
                  c,
                  MaterialPageRoute(builder: (_) => const ActivityMergePage()),
                ),
              ),
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
                                    child: Text(emoji ?? '✨', style: const TextStyle(fontSize: AppFont.headline)),
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
                    onTap: () => Navigator.push(
                      c,
                      MaterialPageRoute(builder: (_) => ActivityPage(activity: act)),
                    ),
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
                              style: const TextStyle(fontSize: AppFont.micro, color: Colors.grey, fontWeight: FontWeight.bold),
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
                                      Flexible(
                                        child: Text(
                                          g.name,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: AppFont.micro,
                                            fontWeight: FontWeight.w500,
                                            color: g.isLimit ? Colors.amber.shade900 : Colors.blue.shade900,
                                          ),
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


  /// "Sayaç alarmı açık · 1 hatırlatıcı açık"
  String _notificationSummary(AppStrings s) {
    final reminders = [store.waterReminderEnabled, store.dailySummaryReminderEnabled].where((on) => on).length;
    final alarm = store.timerSoundEnabled
        ? (s.isTr ? 'Sayaç alarmı açık' : 'Timer alarm on')
        : (s.isTr ? 'Sayaç alarmı kapalı' : 'Timer alarm off');
    final reminderText = reminders == 0
        ? (s.isTr ? 'hatırlatıcılar kapalı' : 'reminders off')
        : (s.isTr ? '$reminders hatırlatıcı açık' : '$reminders reminder${reminders == 1 ? '' : 's'} on');
    final quickLog = store.persistentQuickLogEnabled
        ? (s.isTr ? ' · Hızlı kayıt açık' : ' · Quick log on')
        : '';
    return '$alarm · $reminderText$quickLog';
  }

  /// "Adım sayar açık · Uyku takibi kapalı"; adım izni eksikse bunu söyler.
  String _healthSummary(AppStrings s) {
    final steps = !store.stepTrackerEnabled
        ? (s.isTr ? 'Adım sayar kapalı' : 'Step counter off')
        : store.stepPermissionMissing
            ? (s.isTr ? 'Adım sayar izin bekliyor' : 'Step counter needs permission')
            : (s.isTr ? 'Adım sayar açık' : 'Step counter on');
    final sleep = store.sleepTrackerEnabled
        ? (s.isTr ? 'uyku takibi açık' : 'sleep tracking on')
        : (s.isTr ? 'uyku takibi kapalı' : 'sleep tracking off');
    return '$steps · $sleep';
  }
}

/// Ayarlar'da bir alt sayfaya giden satır: başlık ve o bölümün o anki durumunun kısa özeti.
class _SettingsLink extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String summary;
  final Widget page;

  /// Özette dikkat gerektiren bir durum var (izin eksik gibi).
  final bool warning;

  const _SettingsLink({
    required this.icon,
    required this.color,
    required this.title,
    required this.summary,
    required this.page,
    this.warning = false,
  });

  @override
  Widget build(BuildContext context) => ListTile(
        leading: Icon(icon, color: color),
        title: Text(title),
        subtitle: Text(
          summary,
          style: TextStyle(
            fontSize: AppFont.caption,
            color: warning ? Theme.of(context).colorScheme.error : null,
          ),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => page)),
      );
}
