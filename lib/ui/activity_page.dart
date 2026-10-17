import 'dart:math';

import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/store.dart';
import '../logic/activity_format_analysis.dart';
import '../logic/activity_rhythm.dart';
import '../logic/format.dart';
import '../logic/l10n.dart';
import '../logic/period_stats.dart';
import '../logic/text_match.dart';
import 'app_font.dart';
import 'common.dart';
import 'components/activity_dot_strip.dart';
import 'components/activity_format_views.dart';
import 'components/activity_reminders_sheet.dart';
import 'components/stats_common.dart';
import 'components/stats_correlations_card.dart';
import 'components/today_timeline.dart';
import 'contribution_heatmap.dart';
import 'activity_merge_page.dart';
import '../logic/correlation_analysis.dart';

/// Aktivite Sayfası: Kayıt biçimine (Süre, Miktar, Olay) göre özelleşmiş
/// detaylı görünüm, istatistikler, takvim, hedefler ve geçmiş kayıtlar.
class ActivityPage extends StatefulWidget {
  final Activity activity;
  final StatRange initialRange;

  const ActivityPage({
    super.key,
    required this.activity,
    this.initialRange = StatRange.week,
  });

  @override
  State<ActivityPage> createState() => _ActivityPageState();
}

class _ActivityPageState extends State<ActivityPage> {
  late StatRange _range;
  late DateTime _anchor;
  ActivityFormat? _overrideFormat;

  @override
  void initState() {
    super.initState();
    _range = widget.initialRange;
    _anchor = DateTime.now();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final s = strings.value;
        final scheme = Theme.of(context).colorScheme;
        final isTr = s.isTr;
        final now = DateTime.now();

        // Aktivite silinmiş olabilir
        final act = store.activities[widget.activity.id];
        if (act == null) {
          return Scaffold(
            appBar: AppBar(title: Text(s.isTr ? 'Aktivite Bulunamadı' : 'Activity Not Found')),
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.delete_outline, size: 48, color: scheme.error),
                  const SizedBox(height: 12),
                  Text(
                    s.isTr ? 'Bu aktivite silinmiş.' : 'This activity has been deleted.',
                    style: const TextStyle(fontSize: AppFont.body),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(s.isTr ? 'Geri Dön' : 'Go Back'),
                  ),
                ],
              ),
            ),
          );
        }

        final period = StatPeriod.containing(_range, _anchor);
        final allEntries = store.entriesForActivity(act.id);
        final fromTs = period.from.millisecondsSinceEpoch;
        final toTs = period.to.millisecondsSinceEpoch;
        final periodEntries = allEntries.where((e) => e.ts >= fromTs && e.ts < toTs).toList();

        // Karşılaştırma için elapsedDays
        final elapsedDays = max(1, period.to.difference(period.from).inDays);

        final analysis = ActivityFormatAnalysis.compute(
          activity: act,
          entries: periodEntries,
          unitOf: store.unit,
          measureNameOf: (id) => store.measureById(id)?.name,
          now: now,
          elapsedDays: elapsedDays,
          isTr: isTr,
          overrideFormat: _overrideFormat,
        );

        final rhythm = ActivityRhythm.compute(
          entries: allEntries,
          now: now,
          isTr: isTr,
        );

        final linkedGoals = store.goalsForActivity(act.id);
        final streakInfo = store.habitStreakInfo(act.id);

        return Scaffold(
          appBar: AppBar(
            titleSpacing: 0,
            title: Row(
              children: [
                ActivityAvatar(act.id, size: 32),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    act.name,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: AppFont.title),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            actions: [
              IconButton(
                tooltip: act.isHabit
                    ? (isTr ? 'Alışkanlık takibinden çıkar' : 'Remove from habits')
                    : (isTr ? 'Alışkanlık olarak takip et' : 'Track as habit'),
                icon: Icon(
                  act.isHabit ? Icons.local_fire_department_rounded : Icons.local_fire_department_outlined,
                  color: act.isHabit ? Colors.orange : scheme.onSurfaceVariant,
                ),
                onPressed: () => store.setActivityHabit(act.id, !act.isHabit),
              ),
              IconButton(
                tooltip: isTr ? 'Hatırlatıcılar' : 'Reminders',
                icon: const Icon(Icons.notifications_active_outlined),
                onPressed: () => ActivityRemindersSheet.show(context, act),
              ),
              IconButton(
                tooltip: isTr ? 'Aktiviteyi düzenle' : 'Edit activity',
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => showActivityEditDialog(context, act),
              ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert_rounded),
                onSelected: (val) async {
                  if (val == 'merge') {
                    final merged = await Navigator.push<bool>(
                      context,
                      MaterialPageRoute(builder: (_) => ActivityMergePage(initialFromActivity: act)),
                    );
                    if (merged == true && context.mounted) {
                      Navigator.pop(context);
                    }
                  } else if (val == 'archive') {
                    await store.archiveActivity(act.id, archived: !act.isArchived);
                  }
                },
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: 'merge',
                    child: Row(
                      children: [
                        const Icon(Icons.call_merge_rounded, size: 20),
                        const SizedBox(width: 10),
                        Text(isTr ? 'Başka aktiviteyle birleştir' : 'Merge with another'),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'archive',
                    child: Row(
                      children: [
                        Icon(act.isArchived ? Icons.unarchive_outlined : Icons.archive_outlined, size: 20),
                        const SizedBox(width: 10),
                        Text(act.isArchived ? (isTr ? 'Arşivden Çıkar' : 'Unarchive') : (isTr ? 'Arşivle' : 'Archive')),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 80),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 1. Aktivite Başlık & Ritim Bilgi Kartı
                _buildHeaderCard(context, act, rhythm, isTr),

                // 2. Dönem Seçici (SegmentedButton)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: SegmentedButton<StatRange>(
                    showSelectedIcon: false,
                    style: ButtonStyle(
                      visualDensity: VisualDensity.compact,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      padding: WidgetStateProperty.all(const EdgeInsets.symmetric(horizontal: 4)),
                      textStyle: WidgetStateProperty.all(
                        Theme.of(context).textTheme.labelLarge?.copyWith(
                              fontSize: AppFont.small,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ),
                    segments: [
                      ButtonSegment(
                        value: StatRange.day,
                        label: FittedBox(fit: BoxFit.scaleDown, child: Text(s.viewDay, maxLines: 1)),
                      ),
                      ButtonSegment(
                        value: StatRange.week,
                        label: FittedBox(fit: BoxFit.scaleDown, child: Text(s.viewWeek, maxLines: 1)),
                      ),
                      ButtonSegment(
                        value: StatRange.month,
                        label: FittedBox(fit: BoxFit.scaleDown, child: Text(s.viewMonth, maxLines: 1)),
                      ),
                      ButtonSegment(
                        value: StatRange.year,
                        label: FittedBox(fit: BoxFit.scaleDown, child: Text(s.viewYear, maxLines: 1)),
                      ),
                    ],
                    selected: {_range},
                    onSelectionChanged: (set) => setState(() => _range = set.first),
                  ),
                ),

                // 3. Dönem Çubuğu (‹ 12 – 18 Eki ›)
                _buildPeriodBar(context, period, now, isTr),

                // 4. Kayıt Biçimine Göre Görünüm (Süre, Miktar, Olay)
                ActivityFormatView(
                  activity: act,
                  analysis: analysis,
                  isTr: isTr,
                  onFormatChanged: (format) => setState(() => _overrideFormat = format),
                ),

                const SizedBox(height: 8),

                // 5. Takvim & Zincir (Streak) Kartı
                _buildCalendarCard(context, act, streakInfo, isTr),

                // 6. Özellikler & Metrikler (Kalori, Sıvı/Hacim, Protein vb.)
                _buildPropertiesCard(context, act, isTr),

                // 7. Bağlı Hedefler ve Limitler (varsa veya hedefler tanımlıysa)
                if (linkedGoals.isNotEmpty || store.goals.isNotEmpty)
                  _buildLinkedGoalsCard(context, act, linkedGoals, isTr),

                // 7b. Korelasyonlar & Tetikleyiciler
                StatsCorrelationsCard(
                  insights: CorrelationEngine.analyze(store, activityId: act.id, isTr: isTr),
                ),

                // 8. Bu Dönemdeki Kayıtlar Listesi
                _buildEntriesSection(context, periodEntries, isTr),
              ],
            ),
          ),
          floatingActionButton: FloatingActionButton.extended(
            icon: const Icon(Icons.add),
            label: Text(isTr ? 'Kayıt Ekle' : 'Add Entry'),
            onPressed: () => _showQuickAddDialog(context, act, isTr),
          ),
        );
      },
    );
  }

  // ---------------------------------------------------------------- BİLEŞENLER

  Widget _buildHeaderCard(BuildContext context, Activity act, ActivityRhythm rhythm, bool isTr) {
    final scheme = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      elevation: 0,
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.25)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: act.displayColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '${act.categoryDef.emoji} ${act.categoryDef.name(isTr)}',
                          style: TextStyle(
                            fontSize: AppFont.caption,
                            fontWeight: FontWeight.bold,
                            color: act.displayColor,
                          ),
                        ),
                      ),
                      if (act.isHabit)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.orange.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            isTr ? '🔥 Alışkanlık' : '🔥 Habit',
                            style: const TextStyle(
                              fontSize: AppFont.caption,
                              fontWeight: FontWeight.bold,
                              color: Colors.orange,
                            ),
                          ),
                        ),
                      if (act.isArchived)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.grey.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            isTr ? 'Arşivde' : 'Archived',
                            style: const TextStyle(
                              fontSize: AppFont.caption,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text(
                    rhythm.lastTimeText != null
                        ? '${rhythm.cadenceText} · ${rhythm.lastTimeText}'
                        : rhythm.cadenceText,
                    style: TextStyle(fontSize: AppFont.caption, color: scheme.onSurfaceVariant),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ActivityDotStrip(
              dots: rhythm.last30Days,
              color: act.displayColor,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPeriodBar(BuildContext context, StatPeriod period, DateTime now, bool isTr) {
    final s = strings.value;
    final scheme = Theme.of(context).colorScheme;
    final isCurrent = period.contains(now);
    final canGoForward = !now.isBefore(period.to);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left_rounded),
            visualDensity: VisualDensity.compact,
            tooltip: s.isTr ? 'Önceki' : 'Previous',
            onPressed: () => setState(() => _anchor = period.previous.from),
          ),
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: isCurrent ? null : () => setState(() => _anchor = DateTime.now()),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.calendar_today_rounded, size: 15, color: scheme.primary),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        periodTitle(period),
                        style: const TextStyle(fontSize: AppFont.body, fontWeight: FontWeight.bold),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (!isCurrent) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: scheme.primaryContainer,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          s.isTr ? 'Bugün' : 'Today',
                          style: TextStyle(
                            fontSize: AppFont.micro,
                            fontWeight: FontWeight.bold,
                            color: scheme.onPrimaryContainer,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right_rounded),
            visualDensity: VisualDensity.compact,
            tooltip: s.isTr ? 'Sonraki' : 'Next',
            onPressed: canGoForward ? () => setState(() => _anchor = period.shifted(1).from) : null,
          ),
        ],
      ),
    );
  }

  Widget _buildCalendarCard(BuildContext context, Activity act, HabitStreakInfo info, bool isTr) {
    final s = strings.value;
    final scheme = Theme.of(context).colorScheme;
    final days = isTr ? 'gün' : 'days';

    Widget pill(String text) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(text, style: const TextStyle(fontSize: AppFont.caption, fontWeight: FontWeight.w600)),
        );

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.calendar_month_rounded, size: 20, color: scheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    isTr ? 'Aktivite Takvimi' : 'Activity Calendar',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: AppFont.subtitle),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                pill('🔥 ${s.currentStreak}: ${info.currentStreak} $days'),
                pill('🏆 ${s.longestStreak}: ${info.longestStreak} $days'),
              ],
            ),
            const SizedBox(height: 12),
            ContributionHeatmap(
              dailyCounts: info.dailyCounts,
              dailyLevels: info.dailyLevels,
              dailyTooltips: info.dailyTooltips,
              baseColor: act.displayColor,
              weekCount: 16,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPropertiesCard(BuildContext context, Activity act, bool isTr) {
    final scheme = Theme.of(context).colorScheme;
    final props = store.activityProperties(act.id);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 16, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  isTr ? 'Özellikler & Metrikler' : 'Properties & Metrics',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: AppFont.subtitle),
                ),
              ),
              TextButton.icon(
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                icon: const Icon(Icons.add, size: 18),
                label: Text(isTr ? 'Özellik Ekle' : 'Add Property'),
                onPressed: () => _showPropertyDialog(context, act, isTr: isTr),
              ),
            ],
          ),
        ),
        Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.3)),
          ),
          child: props.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Icon(Icons.tune_rounded, color: scheme.onSurfaceVariant, size: 28),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          isTr
                              ? 'Kalori, sıvı/hacim, protein gibi özellikler ekleyerek farklı hedeflere bağlayabilirsiniz (örn: 1 bardak Ayran = 200 ml, 76 kcal).'
                              : 'Add properties like calories, volume, or protein to link with goals (e.g. 1 glass = 200 ml, 76 kcal).',
                          style: TextStyle(
                            fontSize: AppFont.small,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              : Column(
                  children: [
                    for (var i = 0; i < props.length; i++) ...[
                      if (i > 0) Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: 0.25)),
                      Builder(builder: (context) {
                        final p = props[i];
                        final u = store.unit(p.unitId);
                        IconData icon;
                        Color iconColor;
                        switch (u.dim) {
                          case 'energy':
                            icon = Icons.bolt_rounded;
                            iconColor = Colors.amber.shade700;
                            break;
                          case 'volume':
                            icon = Icons.water_drop_outlined;
                            iconColor = Colors.blue.shade600;
                            break;
                          case 'mass':
                            icon = Icons.scale_outlined;
                            iconColor = Colors.green.shade700;
                            break;
                          case 'distance':
                            icon = Icons.straighten_outlined;
                            iconColor = Colors.purple.shade600;
                            break;
                          case 'time':
                            icon = Icons.timer_outlined;
                            iconColor = Colors.teal.shade600;
                            break;
                          default:
                            icon = Icons.label_outline_rounded;
                            iconColor = scheme.primary;
                        }
                        final perText = p.perUnitId != null && p.perUnitId != 'adet'
                            ? '${fmtNum(p.perQty)} ${store.unit(p.perUnitId!).symbol} ${isTr ? "için" : "per"}'
                            : (p.perQty == 1.0
                                ? (isTr ? '1 adet / porsiyon' : '1 piece / serving')
                                : '${fmtNum(p.perQty)} ${isTr ? "adet için" : "pcs"}');

                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                          leading: CircleAvatar(
                            radius: 18,
                            backgroundColor: iconColor.withValues(alpha: 0.15),
                            child: Icon(icon, color: iconColor, size: 20),
                          ),
                          title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text(
                            '${fmtNum(p.value)} ${u.symbol} · $perText',
                            style: TextStyle(fontSize: AppFont.caption, color: scheme.onSurfaceVariant),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit_outlined, size: 20),
                                tooltip: isTr ? 'Düzenle' : 'Edit',
                                onPressed: () => _showPropertyDialog(context, act, existing: p, isTr: isTr),
                              ),
                              IconButton(
                                icon: Icon(Icons.delete_outline, size: 20, color: scheme.error),
                                tooltip: isTr ? 'Sil' : 'Delete',
                                onPressed: () async {
                                  final ok = await confirm(
                                    context,
                                    isTr ? 'Özelliği Sil' : 'Delete Property',
                                    isTr
                                        ? '"${p.name}" özelliğini silmek istediğinize emin misiniz? Bu özelliğe bağlı hedefler doğrudan kayıt değerini kullanacaktır.'
                                        : 'Are you sure you want to delete "${p.name}"? Linked goals will fall back to direct entry value.',
                                  );
                                  if (ok) {
                                    await store.deleteActivityProperty(p.id);
                                  }
                                },
                              ),
                            ],
                          ),
                        );
                      }),
                    ],
                  ],
                ),
        ),
      ],
    );
  }

  Future<void> _showPropertyDialog(
    BuildContext context,
    Activity act, {
    ActivityProperty? existing,
    required bool isTr,
  }) async {
    final s = strings.value;
    final (usedM, otherM) = store.measuresFor(act.id);
    final firstMeasure = usedM.firstOrNull ?? otherM.firstOrNull;
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final valCtrl = TextEditingController(text: existing != null ? fmtNum(existing.value) : '');
    final perQtyCtrl = TextEditingController(text: existing != null ? fmtNum(existing.perQty) : '1');
    var selectedUnitId = existing?.unitId ?? 'kcal';
    var selectedPerUnitId = existing?.perUnitId ?? (firstMeasure?.unitId ?? 'adet');

    final presets = [
      (isTr ? 'Kalori' : 'Calories', 'kcal', Icons.bolt_rounded, 'kcal', 'adet', 50.0, 1.0),
      (isTr ? 'Sıvı / Hacim' : 'Liquid / Volume', 'ml', Icons.water_drop_outlined, 'ml', 'ml', 90.0, 100.0),
      (isTr ? 'C Vitamini' : 'Vitamin C', 'mg', Icons.health_and_safety_rounded, 'mg', 'ml', 10.0, 100.0),
      (isTr ? 'Protein' : 'Protein', 'g', Icons.fitness_center_rounded, 'g', 'g', 10.0, 100.0),
      (isTr ? 'Kafein' : 'Caffeine', 'mg', Icons.coffee_rounded, 'mg', 'adet', 80.0, 1.0),
      (isTr ? 'Karbonhidrat' : 'Carbs', 'g', Icons.grain_rounded, 'g', 'g', 15.0, 100.0),
      (isTr ? 'Yağ' : 'Fat', 'g', Icons.opacity_rounded, 'g', 'g', 5.0, 100.0),
    ];

    await showDialog<void>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setS) => AlertDialog(
          title: Text(existing == null
              ? (isTr ? 'Yeni Özellik Ekle' : 'Add New Property')
              : (isTr ? 'Özelliği Düzenle' : 'Edit Property')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (existing == null) ...[
                  Text(
                    isTr ? 'Hızlı Şablonlar:' : 'Quick Presets:',
                    style: TextStyle(
                      fontSize: AppFont.caption,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(c).colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: presets.map((pre) {
                      return ActionChip(
                        avatar: Icon(pre.$3, size: 16),
                        label: Text(pre.$1, style: const TextStyle(fontSize: AppFont.caption)),
                        onPressed: () {
                          setS(() {
                            nameCtrl.text = pre.$1;
                            selectedUnitId = pre.$4;
                            selectedPerUnitId = pre.$5;
                            if (valCtrl.text.isEmpty) valCtrl.text = fmtNum(pre.$6);
                            if (perQtyCtrl.text == '1' || perQtyCtrl.text.isEmpty) {
                              perQtyCtrl.text = fmtNum(pre.$7);
                            }
                          });
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 12),
                ],
                TextField(
                  controller: nameCtrl,
                  autofocus: existing == null && nameCtrl.text.isEmpty,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    labelText: isTr ? 'Özellik Adı' : 'Property Name',
                    hintText: isTr ? 'örn: Kalori, Su, C Vitamini, Kafein' : 'e.g. Calories, Water, Vitamin C, Caffeine',
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextField(
                        controller: valCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(
                          labelText: isTr ? 'Değer' : 'Value',
                          hintText: '50',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 3,
                      child: DropdownButtonFormField<String>(
                        initialValue: selectedUnitId,
                        isExpanded: true,
                        decoration: InputDecoration(labelText: s.unit),
                        items: store.allUnits.map((u) {
                          return DropdownMenuItem(
                            value: u.id,
                            child: Text('${u.symbol} (${u.name})', overflow: TextOverflow.ellipsis),
                          );
                        }).toList(),
                        onChanged: (v) {
                          if (v != null) setS(() => selectedUnitId = v);
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextField(
                        controller: perQtyCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(
                          labelText: isTr ? 'Temel Miktar' : 'Base Quantity',
                          hintText: '100',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 3,
                      child: DropdownButtonFormField<String>(
                        initialValue: selectedPerUnitId,
                        isExpanded: true,
                        decoration: InputDecoration(labelText: isTr ? 'Temel Birim' : 'Base Unit'),
                        items: store.allUnits.map((u) {
                          return DropdownMenuItem(
                            value: u.id,
                            child: Text('${u.symbol} (${u.name})', overflow: TextOverflow.ellipsis),
                          );
                        }).toList(),
                        onChanged: (v) {
                          if (v != null) setS(() => selectedPerUnitId = v);
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  isTr
                      ? 'Örn: 100 ml için 50 kalori, 100 ml için 10 mg C vitamini veya 1 adet için değer.'
                      : 'E.g. 50 kcal for 100 ml, 10 mg Vitamin C for 100 ml, or per 1 item.',
                  style: TextStyle(fontSize: AppFont.micro, color: Theme.of(c).colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: Text(s.cancel),
            ),
            FilledButton(
              onPressed: () async {
                final name = nameCtrl.text.trim();
                final val = parseNum(valCtrl.text);
                final perQty = parseNum(perQtyCtrl.text) ?? 1.0;
                if (name.isEmpty || val == null || val <= 0) return;

                final prop = existing ??
                    ActivityProperty(
                      activityId: act.id,
                      name: name,
                      value: val,
                      unitId: selectedUnitId,
                      perQty: perQty > 0 ? perQty : 1.0,
                      perUnitId: selectedPerUnitId,
                    );
                prop.name = name;
                prop.value = val;
                prop.unitId = selectedUnitId;
                prop.perQty = perQty > 0 ? perQty : 1.0;
                prop.perUnitId = selectedPerUnitId;

                await store.saveActivityProperty(prop);
                if (c.mounted) Navigator.pop(c);
              },
              child: Text(s.save),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLinkedGoalsCard(BuildContext context, Activity act, List<(Goal, GoalLink)> linkedGoals, bool isTr) {
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 16, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  isTr ? 'Bağlı Hedefler ve Limitler' : 'Linked Goals & Limits',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: AppFont.subtitle),
                ),
              ),
              TextButton.icon(
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                icon: const Icon(Icons.add, size: 18),
                label: Text(isTr ? 'Hedefe Bağla' : 'Link to Goal'),
                onPressed: () => _showLinkGoalDialog(context, act, isTr: isTr),
              ),
            ],
          ),
        ),
        Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.3)),
          ),
          child: linkedGoals.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Icon(Icons.track_changes_outlined, color: scheme.onSurfaceVariant, size: 28),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          isTr
                              ? 'Bu aktivite henüz bir hedef veya limite bağlı değil. Yukarıdaki "Hedefe Bağla" düğmesiyle bağlayabilirsiniz.'
                              : 'Not linked to any goals or limits yet. Tap "Link to Goal" above to connect.',
                          style: TextStyle(color: scheme.onSurfaceVariant, fontSize: AppFont.small),
                        ),
                      ),
                    ],
                  ),
                )
              : Column(
                  children: [
                    for (var i = 0; i < linkedGoals.length; i++) ...[
                      if (i > 0) Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: 0.25)),
                      Builder(builder: (context) {
                        final (goal, link) = linkedGoals[i];
                        final isLimit = goal.isLimit;
                        final prop = store.findActivityProperty(link.propertyId);
                        final propText = prop != null
                            ? (isTr ? ' · Ölçü: ${prop.name}' : ' · Measure: ${prop.name}')
                            : (goal.isAmount ? (isTr ? ' · Ölçü: Doğrudan Miktar' : ' · Measure: Direct Amount') : '');
                        return ListTile(
                          onTap: () => _showEditGoalLinkDialog(context, act, goal, link, isTr: isTr),
                          leading: Icon(
                            isLimit ? Icons.shield_outlined : Icons.track_changes,
                            color: isLimit ? Colors.amber.shade800 : Colors.blue.shade800,
                          ),
                          title: Text(goal.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text(
                            isTr
                                ? '${periodNames[goal.period]} ${isLimit ? "Limit" : "Hedef"} · Katkı: %${fmtNum(link.pct)}$propText'
                                : '${periodNamesEn[goal.period]} ${isLimit ? "Limit" : "Goal"} · Contribution: %${fmtNum(link.pct)}$propText',
                            style: const TextStyle(fontSize: AppFont.caption),
                          ),
                          trailing: const Icon(Icons.chevron_right, size: 18),
                        );
                      }),
                    ],
                  ],
                ),
        ),
      ],
    );
  }

  Future<void> _showEditGoalLinkDialog(
    BuildContext context,
    Activity act,
    Goal goal,
    GoalLink link, {
    required bool isTr,
  }) async {
    final s = strings.value;
    final props = store.activityProperties(act.id);
    var selectedPropId = props.any((p) => p.id == link.propertyId) ? link.propertyId : null;
    var currentPct = link.pct;

    await showDialog<void>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setS) => AlertDialog(
          title: Text(isTr ? 'Hedef Bağlantısını Düzenle' : 'Edit Goal Link'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      goal.isLimit ? Icons.shield_outlined : Icons.track_changes,
                      color: goal.isLimit ? Colors.amber.shade800 : Colors.blue.shade800,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${goal.name} (${fmtNum(goal.target)} ${store.goalUnitSymbol(goal)})',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  isTr ? 'Ölçü Alınacak Özellik:' : 'Property to Measure:',
                  style: TextStyle(
                    fontSize: AppFont.caption,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(c).colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 6),
                DropdownButtonFormField<int?>(
                  initialValue: selectedPropId,
                  isExpanded: true,
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  items: [
                    DropdownMenuItem<int?>(
                      value: null,
                      child: Text(
                        isTr
                            ? (goal.isAmount
                                ? 'Doğrudan Aktivite Miktarı / Hacmi (${act.name})'
                                : 'Otomatik / Doğrudan Değer')
                            : (goal.isAmount
                                ? 'Direct Activity Amount / Volume (${act.name})'
                                : 'Automatic / Direct Value'),
                        style: const TextStyle(fontSize: AppFont.small),
                      ),
                    ),
                    for (final p in props)
                      DropdownMenuItem<int?>(
                        value: p.id,
                        child: Text(
                          p.perUnitId != null && p.perUnitId != 'adet'
                              ? '${p.name}: ${fmtNum(p.value)} ${store.unit(p.unitId).symbol} (her ${fmtNum(p.perQty)} ${store.unit(p.perUnitId!).symbol})'
                              : '${p.name}: ${fmtNum(p.value)} ${store.unit(p.unitId).symbol} (her ${fmtNum(p.perQty)} adet)',
                          style: const TextStyle(fontSize: AppFont.small),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (v) => setS(() => selectedPropId = v),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(isTr ? 'Katkı Oranı:' : 'Contribution:'),
                    Text('%${fmtNum(currentPct)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                  ],
                ),
                Slider(
                  value: currentPct.clamp(5.0, 100.0),
                  min: 5,
                  max: 100,
                  divisions: 19,
                  label: '%${currentPct.round()}',
                  onChanged: (v) => setS(() => currentPct = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              style: TextButton.styleFrom(foregroundColor: Theme.of(c).colorScheme.error),
              onPressed: () async {
                final ok = await confirm(
                  context,
                  isTr ? 'Bağlantıyı Kaldır' : 'Unlink Goal',
                  isTr
                      ? '"${act.name}" aktivitesini "${goal.name}" hedefinden kaldırmak istediğinize emin misiniz?'
                      : 'Are you sure you want to unlink "${act.name}" from "${goal.name}"?',
                );
                if (ok) {
                  await store.setActivityGoals(act.id, {goal.id: null});
                  if (c.mounted) Navigator.pop(c);
                }
              },
              child: Text(isTr ? 'Kaldır' : 'Unlink'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: Text(s.cancel),
            ),
            FilledButton(
              onPressed: () async {
                await store.setActivityGoals(
                  act.id,
                  {goal.id: currentPct},
                  goalProperties: {goal.id: selectedPropId},
                );
                if (c.mounted) Navigator.pop(c);
              },
              child: Text(s.save),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showLinkGoalDialog(BuildContext context, Activity act, {required bool isTr}) async {
    final s = strings.value;
    final linkedIds = store.goalsForActivity(act.id).map((g) => g.$1.id).toSet();
    final available = store.goals.where((g) => !linkedIds.contains(g.id)).toList();

    if (available.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isTr
                  ? 'Bağlanabilecek başka hedef yok. Yeni hedef oluşturmak için Hedefler sayfasına gidin.'
                  : 'No available goals to link. Create one in Goals tab.',
            ),
          ),
        );
      }
      return;
    }

    final props = store.activityProperties(act.id);
    var selectedGoalId = available.first.id;
    int? selectedPropId;

    final firstGoal = available.first;
    if (firstGoal.isAmount && firstGoal.unitId != null) {
      final gu = store.unit(firstGoal.unitId!);
      selectedPropId = props.where((p) => store.unit(p.unitId).dim == gu.dim).firstOrNull?.id;
    }

    await showDialog<void>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setS) {
          final curGoal = available.where((g) => g.id == selectedGoalId).first;
          return AlertDialog(
            title: Text(isTr ? 'Hedefe Bağla' : 'Link to Goal'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isTr ? 'Hedef Seçin:' : 'Select Goal:',
                    style: TextStyle(
                      fontSize: AppFont.caption,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(c).colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<int>(
                    initialValue: selectedGoalId,
                    isExpanded: true,
                    decoration: InputDecoration(
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    items: available.map((g) {
                      return DropdownMenuItem(
                        value: g.id,
                        child: Text(
                          '${g.name} (${fmtNum(g.target)} ${store.goalUnitSymbol(g)})',
                          style: const TextStyle(fontSize: AppFont.small),
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                    }).toList(),
                    onChanged: (v) {
                      if (v != null) {
                        setS(() {
                          selectedGoalId = v;
                          final g = available.where((x) => x.id == v).first;
                          if (g.isAmount && g.unitId != null) {
                            final gu = store.unit(g.unitId!);
                            selectedPropId = props.where((p) => store.unit(p.unitId).dim == gu.dim).firstOrNull?.id;
                          } else {
                            selectedPropId = null;
                          }
                        });
                      }
                    },
                  ),
                  if (props.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(
                      isTr ? 'Ölçü Alınacak Özellik:' : 'Property to Measure:',
                      style: TextStyle(
                        fontSize: AppFont.caption,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(c).colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<int?>(
                      initialValue: selectedPropId,
                      isExpanded: true,
                      decoration: InputDecoration(
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      items: [
                        DropdownMenuItem<int?>(
                          value: null,
                          child: Text(
                            isTr
                                ? (curGoal.isAmount
                                    ? 'Doğrudan Aktivite Miktarı / Hacmi (${act.name})'
                                    : 'Otomatik / Doğrudan Değer')
                                : (curGoal.isAmount
                                    ? 'Direct Activity Amount / Volume (${act.name})'
                                    : 'Automatic / Direct Value'),
                            style: const TextStyle(fontSize: AppFont.small),
                          ),
                        ),
                        for (final p in props)
                          DropdownMenuItem<int?>(
                            value: p.id,
                            child: Text(
                              p.perUnitId != null && p.perUnitId != 'adet'
                                  ? '${p.name}: ${fmtNum(p.value)} ${store.unit(p.unitId).symbol} (her ${fmtNum(p.perQty)} ${store.unit(p.perUnitId!).symbol})'
                                  : '${p.name}: ${fmtNum(p.value)} ${store.unit(p.unitId).symbol} (her ${fmtNum(p.perQty)} adet)',
                              style: const TextStyle(fontSize: AppFont.small),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (v) => setS(() => selectedPropId = v),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c),
                child: Text(s.cancel),
              ),
              FilledButton(
                onPressed: () async {
                  await store.setActivityGoals(
                    act.id,
                    {selectedGoalId: 100},
                    goalProperties: {selectedGoalId: selectedPropId},
                  );
                  if (c.mounted) Navigator.pop(c);
                },
                child: Text(isTr ? 'Bağla' : 'Link'),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildEntriesSection(BuildContext context, List<Entry> entries, bool isTr) {
    final scheme = Theme.of(context).colorScheme;
    final sorted = entries.reversed.toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 16, 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                isTr ? 'Dönem Kayıtları' : 'Period Entries',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: AppFont.subtitle),
              ),
              Text(
                entriesText(entries.length),
                style: TextStyle(fontSize: AppFont.caption, color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
        if (entries.isEmpty)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: Text(
                isTr ? 'Bu dönemde henüz kayıt yok.' : 'No entries in this period yet.',
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: AppFont.body),
              ),
            ),
          )
        else
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.3)),
            ),
            child: ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: min(15, sorted.length),
              separatorBuilder: (context, index) => Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: 0.25)),
              itemBuilder: (context, i) {
                final e = sorted[i];
                final detail = store.entryDetail(e);
                final timeStr = fmtTime(e.time);
                final dateStr = fmtDateShort(e.time, isTr: isTr);

                return ListTile(
                  onTap: () => TodayTimeline.showEntryEditSheet(context, e),
                  leading: CircleAvatar(
                    radius: 18,
                    backgroundColor: scheme.surfaceContainerHighest,
                    child: Text(
                      widget.activity.emoji ?? '📌',
                      style: const TextStyle(fontSize: 16),
                    ),
                  ),
                  title: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        detail.isNotEmpty ? detail : widget.activity.name,
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: AppFont.body),
                      ),
                      Text(
                        '$dateStr $timeStr',
                        style: TextStyle(fontSize: AppFont.caption, color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                  subtitle: e.note != null && e.note!.isNotEmpty
                      ? Text(
                          e.note!,
                          style: TextStyle(fontSize: AppFont.caption, color: scheme.onSurfaceVariant),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        )
                      : null,
                  trailing: const Icon(Icons.chevron_right, size: 18),
                );
              },
            ),
          ),
      ],
    );
  }

  Future<void> _showQuickAddDialog(BuildContext context, Activity act, bool isTr) async {
    final noteCtrl = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: Row(
          children: [
            ActivityAvatar(act.id, size: 32),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                isTr ? '${act.name} Kaydet' : 'Log ${act.name}',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: TextField(
          controller: noteCtrl,
          autofocus: true,
          decoration: InputDecoration(
            labelText: isTr ? 'Not (isteğe bağlı, örn. 7/10)' : 'Note (optional, e.g. 7/10)',
            hintText: isTr ? 'Not veya detay' : 'Note or detail',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: Text(isTr ? 'İptal' : 'Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(c);
              await store.addEntry(
                act.id,
                note: noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim(),
              );
              if (mounted) {
                showSnack(this.context, isTr ? '${act.name} kaydedildi' : '${act.name} logged');
              }
            },
            child: Text(isTr ? 'Kaydet' : 'Save'),
          ),
        ],
      ),
    );
  }
}
