import 'dart:math';

import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/store.dart';
import '../logic/activity_format_analysis.dart';
import '../logic/activity_rhythm.dart';
import '../logic/format.dart';
import '../logic/l10n.dart';
import '../logic/period_stats.dart';
import 'app_font.dart';
import 'common.dart';
import 'components/activity_dot_strip.dart';
import 'components/activity_format_views.dart';
import 'components/stats_common.dart';
import 'components/today_timeline.dart';
import 'contribution_heatmap.dart';

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
        final allEntries = store.entries.where((e) => e.activityId == act.id).toList();
        final periodEntries = store.entriesIn(period.from, period.to).where((e) => e.activityId == act.id).toList();

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
                tooltip: isTr ? 'Aktiviteyi düzenle' : 'Edit activity',
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => showActivityEditDialog(context, act),
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

                // 6. Bağlı Hedefler ve Limitler (varsa)
                if (linkedGoals.isNotEmpty)
                  _buildLinkedGoalsCard(context, linkedGoals, isTr),

                // 7. Bu Dönemdeki Kayıtlar Listesi
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

  Widget _buildLinkedGoalsCard(BuildContext context, List<(Goal, GoalLink)> linkedGoals, bool isTr) {
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 16, 4),
          child: Text(
            isTr ? 'Bağlı Hedefler ve Limitler' : 'Linked Goals & Limits',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: AppFont.subtitle),
          ),
        ),
        Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.3)),
          ),
          child: Column(
            children: [
              for (var i = 0; i < linkedGoals.length; i++) ...[
                if (i > 0) Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: 0.25)),
                Builder(builder: (context) {
                  final (goal, link) = linkedGoals[i];
                  final isLimit = goal.isLimit;
                  return ListTile(
                    leading: Icon(
                      isLimit ? Icons.shield_outlined : Icons.track_changes,
                      color: isLimit ? Colors.amber.shade800 : Colors.blue.shade800,
                    ),
                    title: Text(goal.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(
                      isTr
                          ? '${periodNames[goal.period]} ${isLimit ? "Limit" : "Hedef"} · Katkı payı: %${link.pct}'
                          : '${periodNamesEn[goal.period]} ${isLimit ? "Limit" : "Goal"} · Contribution: %${link.pct}',
                      style: const TextStyle(fontSize: AppFont.caption),
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
