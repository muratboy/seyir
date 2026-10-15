import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/store.dart';
import '../logic/activity_format_analysis.dart';
import '../logic/activity_rhythm.dart';
import '../logic/format.dart';
import '../logic/l10n.dart';
import '../logic/period_stats.dart';
import '../logic/trend_insights.dart';
import '../services/export_service.dart';
import 'activity_page.dart';
import 'app_font.dart';
import 'common.dart';
import 'components/activity_dot_strip.dart';
import 'components/activity_format_views.dart';
import 'components/stats_category_chart.dart';
import 'components/stats_common.dart';
import 'components/stats_insights_card.dart';
import 'components/stats_overview_cards.dart';
import 'components/stats_trend_chart.dart';
import 'contribution_heatmap.dart';

/// İstatistik sekmesi: seçilen dönemin özeti, dağılımı ve aktiviteleri.
///
/// Sayfa yalnızca gösterir; hesaplar [PeriodStats] içindedir. Bir aktivite seçilince aynı bölümler o
/// aktivitenin kendi miktarıyla (süre, hacim, mesafe...) konuşur.
class StatsPage extends StatefulWidget {
  final int? initialActivityId;

  const StatsPage({super.key, this.initialActivityId});

  @override
  State<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends State<StatsPage> {
  StatRange _range = StatRange.week;
  DateTime _anchor = DateTime.now();
  int? _activityId; // null = tüm aktiviteler
  final Map<int, ActivityFormat> _activityFormatOverrides = {};

  @override
  void initState() {
    super.initState();
    _activityId = widget.initialActivityId;
  }

  // Grafiğin ölçütü (null = kayıt sayısı). Kullanıcı seçene kadar veriye göre belirlenir: tek aktivitede o
  // aktivitenin asıl miktarı, hepsi birlikteyken kayıt sayısı.
  String? _metric;
  bool _metricChosen = false;

  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Aktiviteyi seçer (null = hepsi) ve sayfanın başına döner: özet ve grafik oradadır.
  void _selectActivity(int? id) {
    setState(() {
      _activityId = id;
      _metricChosen = false;
    });
    if (_scroll.hasClients) {
      _scroll.animateTo(0, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final s = strings.value;
        final now = DateTime.now();
        final period = StatPeriod.containing(_range, _anchor);
        // Seçili aktivite bu arada silinmiş olabilir.
        final activityId = store.activities.containsKey(_activityId) ? _activityId : null;
        bool wanted(Entry e) => activityId == null || e.activityId == activityId;

        final stats = PeriodStats.compute(
          period: period,
          entriesIn: (from, to) => store.entriesIn(from, to).where(wanted),
          unitOf: store.unit,
          now: now,
          trackingSince: store.entries.where(wanted).firstOrNull?.time,
        );
        final byActivity = store.totalsByActivity(period.from, period.to);
        final periodCount = byActivity.values.fold<int>(0, (sum, t) => sum + t.count);

        final metrics = availableMetrics(stats.total, singleActivity: activityId != null);
        final metric = _metricChosen && metrics.contains(_metric)
            ? _metric
            : (activityId != null ? stats.total.mainDim : null);

        return Scaffold(
          appBar: AppBar(
            title: Text(s.statsTitle, style: const TextStyle(fontWeight: FontWeight.bold)),
            actions: [_exportMenu()],
          ),
          body: SingleChildScrollView(
            controller: _scroll,
            padding: const EdgeInsets.only(bottom: 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: SegmentedButton<StatRange>(
                    showSelectedIcon: false,
                    style: ButtonStyle(
                      visualDensity: VisualDensity.compact,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      padding: WidgetStateProperty.all(const EdgeInsets.symmetric(horizontal: 4)),
                      // Temanın yazı tipiyle; yalın bir TextStyle düğmenin yazı ailesini düşürüyordu.
                      textStyle: WidgetStateProperty.all(
                        Theme.of(context).textTheme.labelLarge?.copyWith(fontSize: AppFont.small, fontWeight: FontWeight.w600),
                      ),
                    ),
                    segments: [
                      // Dar ekranda büyük yazıyla "Haftalık" bölünmek yerine küçülür.
                      for (final (range, label) in [
                        (StatRange.day, s.viewDay),
                        (StatRange.week, s.viewWeek),
                        (StatRange.month, s.viewMonth),
                        (StatRange.year, s.viewYear),
                      ])
                        ButtonSegment(
                          value: range,
                          label: FittedBox(fit: BoxFit.scaleDown, child: Text(label, maxLines: 1)),
                        ),
                    ],
                    selected: {_range},
                    onSelectionChanged: (set) => setState(() => _range = set.first),
                  ),
                ),
                _periodBar(period, now),
                _activityChips(byActivity, periodCount, activityId),
                const SizedBox(height: 6),
                if (stats.total.count == 0)
                  _emptyPeriod(activityId)
                else ...[
                  if (activityId != null) ...[
                    ActivityFormatView(
                      activity: store.activity(activityId),
                      analysis: ActivityFormatAnalysis.compute(
                        activity: store.activity(activityId),
                        entries: store.entriesIn(period.from, period.to).where(wanted),
                        unitOf: store.unit,
                        measureNameOf: (id) => store.measureById(id)?.name,
                        now: now,
                        elapsedDays: stats.elapsedDays,
                        isTr: s.isTr,
                        overrideFormat: _activityFormatOverrides[activityId],
                      ),
                      isTr: s.isTr,
                      onFormatChanged: (format) => setState(() => _activityFormatOverrides[activityId] = format),
                    ),
                  ] else ...[
                    StatsOverviewCard(
                      stats: stats,
                      singleActivity: false,
                      metric: metric,
                      activityCount: byActivity.length,
                    ),
                  ],
                  StatsTrendChart(
                    stats: stats,
                    metric: metric,
                    metrics: metrics,
                    now: now,
                    onMetricChanged: (m) => setState(() {
                      _metric = m;
                      _metricChosen = true;
                    }),
                  ),
                ],
                if (activityId != null) ...[
                  _calendarCard(store.activity(activityId)),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.open_in_new_rounded, size: 16),
                      label: Text(s.isTr ? 'Aktivite Sayfasını Aç' : 'Open Activity Page'),
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ActivityPage(
                            activity: store.activity(activityId),
                            initialRange: _range,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Center(
                    child: TextButton.icon(
                      icon: const Icon(Icons.arrow_back_rounded, size: 18),
                      label: Text(s.isTr ? 'Tüm aktivitelere dön' : 'Back to all activities'),
                      onPressed: () => _selectActivity(null),
                    ),
                  ),
                ] else if (stats.total.count > 0) ...[
                  StatsInsightsCard(
                    insights: computeWeeklyInsights(store: store, now: now, isTr: s.isTr),
                    onSelectActivity: _selectActivity,
                  ),
                  _activityList(byActivity, periodCount),
                  const SizedBox(height: 8),
                  StatsCategoryChart(entries: store.entriesIn(period.from, period.to).toList()),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  // ---------------------------------------------------------------- dışa aktarma

  /// Dışa aktarma seçilen döneme değil tüm kayıtlara bakar; menü bunu söyler.
  Widget _exportMenu() {
    final s = strings.value;
    return PopupMenuButton<String>(
      icon: const Icon(Icons.ios_share_rounded),
      tooltip: s.isTr ? 'Dışa aktar' : 'Export',
      onSelected: (kind) =>
          kind == 'pdf' ? ExportService.exportPdf(context, store) : ExportService.exportCsv(context, store),
      itemBuilder: (context) => [
        PopupMenuItem(
          enabled: false,
          height: 32,
          child: Text(
            s.isTr ? 'Tüm kayıtlar dışa aktarılır' : 'All entries are exported',
            style: const TextStyle(fontSize: AppFont.caption),
          ),
        ),
        PopupMenuItem(
          value: 'pdf',
          child: Row(
            children: [
              const Icon(Icons.picture_as_pdf_outlined, size: 20),
              const SizedBox(width: 12),
              Flexible(child: Text(s.isTr ? 'PDF raporu' : 'PDF report')),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'csv',
          child: Row(
            children: [
              const Icon(Icons.table_chart_outlined, size: 20),
              const SizedBox(width: 12),
              Flexible(child: Text(s.isTr ? 'Excel tablosu (CSV)' : 'Spreadsheet (CSV)')),
            ],
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------- dönem ve süzgeç

  /// "‹ 12 – 18 Eki ›": önceki ve sonraki döneme geçer; başlığa dokununca bugüne döner.
  Widget _periodBar(StatPeriod period, DateTime now) {
    final s = strings.value;
    final scheme = Theme.of(context).colorScheme;
    final isCurrent = period.contains(now);
    // Gelecekte kayıt olmaz: içinde bulunulan dönemden ileri gidilmez.
    final canGoForward = !now.isBefore(period.to);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
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

  /// Aktivite süzgeci. Seçili aktivite hep başta durur; dönemde en çok kaydı olanlar onu izler.
  Widget _activityChips(Map<int, PeriodTotal> byActivity, int periodCount, int? activityId) {
    final s = strings.value;
    int countOf(Activity a) => byActivity[a.id]?.count ?? 0;
    final activities = store.activities.values.toList()
      ..sort((a, b) {
        if ((a.id == activityId) != (b.id == activityId)) return a.id == activityId ? -1 : 1;
        final byCount = countOf(b).compareTo(countOf(a));
        return byCount != 0 ? byCount : a.norm.compareTo(b.norm);
      });

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          FilterChip(
            showCheckmark: false,
            label: Text('${s.isTr ? "Tümü" : "All"} ($periodCount)'),
            selected: activityId == null,
            onSelected: (_) => _selectActivity(null),
          ),
          for (final act in activities) ...[
            const SizedBox(width: 8),
            FilterChip(
              showCheckmark: false,
              avatar: act.emoji != null && act.emoji!.isNotEmpty
                  ? Text(act.emoji!, style: const TextStyle(fontSize: AppFont.body))
                  : ActivityAvatar(act.id, size: 20),
              label: Text(countOf(act) > 0 ? '${act.name} (${countOf(act)})' : act.name),
              selected: act.id == activityId,
              onSelected: (_) => _selectActivity(act.id == activityId ? null : act.id),
            ),
          ],
        ],
      ),
    );
  }

  Widget _emptyPeriod(int? activityId) {
    final s = strings.value;
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          children: [
            Icon(Icons.analytics_outlined, size: 40, color: scheme.outlineVariant),
            const SizedBox(height: 10),
            Text(
              activityId == null
                  ? (s.isTr ? 'Bu dönemde kayıt yok.' : 'No entries in this period.')
                  : (s.isTr
                      ? '${store.activity(activityId).name}: bu dönemde kayıt yok.'
                      : '${store.activity(activityId).name}: no entries in this period.'),
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- tüm aktiviteler

  /// Dönemin aktiviteleri, en çok kaydı olandan başlayarak. Her satır aktivitenin kendi miktarını (varsa)
  /// öne alır; dokununca o aktivitenin istatistiklerine geçilir.
  Widget _activityList(Map<int, PeriodTotal> byActivity, int periodCount) {
    final s = strings.value;
    final scheme = Theme.of(context).colorScheme;
    final rows = byActivity.entries.toList()
      ..sort((a, b) {
        final byCount = b.value.count.compareTo(a.value.count);
        return byCount != 0 ? byCount : store.activity(a.key).norm.compareTo(store.activity(b.key).norm);
      });
    final maxCount = rows.first.value.count;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle(
          s.isTr ? 'Aktiviteler' : 'Activities',
          trailing: Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Text(
              '${rows.length} ${s.isTr ? "aktivite" : (rows.length == 1 ? "activity" : "activities")}',
              style: TextStyle(fontSize: AppFont.caption, color: scheme.onSurfaceVariant),
            ),
          ),
        ),
        Card(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          elevation: 0,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.3)),
          ),
          child: Column(
            children: [
              for (var i = 0; i < rows.length; i++) ...[
                if (i > 0) Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: 0.25)),
                _activityRow(store.activity(rows[i].key), rows[i].value, maxCount, periodCount),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _activityRow(Activity act, PeriodTotal total, int maxCount, int periodCount) {
    final s = strings.value;
    final scheme = Theme.of(context).colorScheme;
    final dim = total.mainDim;
    final share = fmtPercent((total.count / periodCount * 100).round());

    final entries = store.entries.where((e) => e.activityId == act.id);
    final rhythm = ActivityRhythm.compute(
      entries: entries,
      now: DateTime.now(),
      isTr: s.isTr,
    );

    return InkWell(
      onTap: () => _selectActivity(act.id),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
        child: Row(
          children: [
            ActivityAvatar(act.id, size: 36),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    act.isHabit ? '${act.name} 🔥' : act.name,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: AppFont.body),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    rhythm.lastTimeText != null
                        ? '${rhythm.cadenceText} · ${rhythm.lastTimeText}'
                        : rhythm.cadenceText,
                    style: TextStyle(fontSize: AppFont.micro, color: scheme.onSurfaceVariant),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 5),
                  ActivityDotStrip(
                    dots: rhythm.last30Days,
                    color: act.displayColor,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  dim == null ? entriesText(total.count) : store.fmtBase(total.value(dim), dim),
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: AppFont.body),
                ),
                Text(
                  dim == null ? share : '${entriesText(total.count)} · $share',
                  style: TextStyle(fontSize: AppFont.micro, color: scheme.onSurfaceVariant),
                ),
              ],
            ),
            Icon(Icons.chevron_right_rounded, size: 18, color: scheme.onSurfaceVariant.withValues(alpha: 0.6)),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- tek aktivite

  /// Aktivitenin son haftaları ve serileri. Takvim seçilen dönemden bağımsızdır; başlığı bunu söyler.
  Widget _calendarCard(Activity act) => LayoutBuilder(
        builder: (context, box) {
          // Karta sığdığı kadar hafta gösterilir. Sabit 20 hafta dar ekranda yana kayıyor, ilk ayın adı da
          // kenarda yarım kalıyordu. (Kutu 16,5 px; kartın ve ızgaranın boşlukları ile gün adları 102 px.)
          final weeks = ((box.maxWidth - 102) / 16.5).floor().clamp(8, 26);
          return _calendarCardOf(act, weeks);
        },
      );

  Widget _calendarCardOf(Activity act, int weeks) {
    final s = strings.value;
    final scheme = Theme.of(context).colorScheme;
    final info = store.habitStreakInfo(act.id);
    final days = s.isTr ? 'gün' : 'days';

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
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.calendar_month_rounded, size: 20, color: scheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      text: s.isTr ? 'Takvim' : 'Calendar',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: AppFont.subtitle),
                      children: [
                        TextSpan(
                          text: s.isTr ? '  son $weeks hafta' : '  last $weeks weeks',
                          style: TextStyle(
                            fontWeight: FontWeight.normal,
                            fontSize: AppFont.caption,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  tooltip: act.isHabit
                      ? (s.isTr ? 'Alışkanlık olarak izleniyor' : 'Tracked as a habit')
                      : (s.isTr ? 'Alışkanlık olarak izle' : 'Track as a habit'),
                  icon: Icon(
                    act.isHabit ? Icons.local_fire_department_rounded : Icons.local_fire_department_outlined,
                    color: act.isHabit ? Colors.orange : scheme.onSurfaceVariant,
                  ),
                  onPressed: () => store.setActivityHabit(act.id, !act.isHabit),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
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
                    weekCount: weeks,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
