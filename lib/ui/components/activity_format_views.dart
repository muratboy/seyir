import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../../data/store.dart';
import '../../logic/activity_format_analysis.dart';
import '../../logic/format.dart';
import '../app_font.dart';
import 'stats_common.dart';
import 'stats_overview_cards.dart';

/// Aktivitenin kayıt biçimine (Süre, Miktar, Olay) göre özelleşmiş özet görünümü.
class ActivityFormatView extends StatelessWidget {
  final Activity activity;
  final ActivityFormatAnalysis analysis;
  final bool isTr;
  final ValueChanged<ActivityFormat>? onFormatChanged;

  const ActivityFormatView({
    super.key,
    required this.activity,
    required this.analysis,
    required this.isTr,
    this.onFormatChanged,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Biçim Seçici (Süre / Miktar / Olay)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(
            children: [
              Expanded(
                child: SegmentedButton<ActivityFormat>(
                  showSelectedIcon: false,
                  style: ButtonStyle(
                    visualDensity: VisualDensity.compact,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    padding: WidgetStateProperty.all(const EdgeInsets.symmetric(horizontal: 2)),
                    textStyle: WidgetStateProperty.all(
                      Theme.of(context).textTheme.labelLarge?.copyWith(
                            fontSize: AppFont.small,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ),
                  segments: [
                    ButtonSegment(
                      value: ActivityFormat.duration,
                      icon: const Icon(Icons.timer_outlined, size: 16),
                      label: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(isTr ? 'Süre' : 'Duration'),
                      ),
                    ),
                    ButtonSegment(
                      value: ActivityFormat.quantity,
                      icon: const Icon(Icons.scale_rounded, size: 16),
                      label: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(isTr ? 'Miktar' : 'Quantity'),
                      ),
                    ),
                    ButtonSegment(
                      value: ActivityFormat.event,
                      icon: const Icon(Icons.event_note_rounded, size: 16),
                      label: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(isTr ? 'Olay' : 'Event'),
                      ),
                    ),
                  ],
                  selected: {analysis.format},
                  onSelectionChanged: onFormatChanged != null
                      ? (set) => onFormatChanged!(set.first)
                      : null,
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 4),

        // Biçime Özel KPI Kutuları
        Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
            side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.3)),
          ),
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.25),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: switch (analysis.format) {
              ActivityFormat.duration => _buildDurationBoxes(context, analysis.durationMetrics!),
              ActivityFormat.quantity => _buildQuantityBoxes(context, analysis.quantityMetrics!),
              ActivityFormat.event => _buildEventBoxes(context, analysis.eventMetrics!),
            },
          ),
        ),

        // Biçime Özel Ek Detaylar (Kırılım, Şiddet Analizi vb.)
        if (analysis.format == ActivityFormat.quantity &&
            analysis.quantityMetrics != null &&
            analysis.quantityMetrics!.measureBreakdown.isNotEmpty)
          _buildMeasureBreakdownCard(context, analysis.quantityMetrics!),

        if (analysis.format == ActivityFormat.event &&
            analysis.eventMetrics != null &&
            analysis.eventMetrics!.severity.hasData)
          _buildSeverityCard(context, analysis.eventMetrics!.severity),
      ],
    );
  }

  // ---------------------------------------------------------------- SÜRE GÖRÜNÜMÜ

  Widget _buildDurationBoxes(BuildContext context, DurationMetrics m) {
    final scheme = Theme.of(context).colorScheme;

    final longestText = m.longestSessionMinutes == null
        ? ''
        : (isTr
            ? 'En uzun: ${fmtAmount(m.longestSessionMinutes!, 'time')}'
            : 'Longest: ${fmtAmount(m.longestSessionMinutes!, 'time')}');

    final activeDaysText = isTr
        ? 'Aktif günlerde ${fmtAmount(m.activeDayAvgMinutes, 'time')}'
        : '${fmtAmount(m.activeDayAvgMinutes, 'time')} on active days';

    final lastSessionText = m.lastSessionMinutes == null
        ? ''
        : (m.lastSessionTime != null
            ? fmtDateShort(m.lastSessionTime!, isTr: isTr)
            : '');

    final boxes = <KpiBox>[
      KpiBox(
        title: isTr ? 'Toplam Süre' : 'Total Duration',
        value: fmtAmount(m.totalMinutes, 'time'),
        subtitle: isTr ? '${m.sessionCount} oturum' : '${m.sessionCount} sessions',
        icon: Icons.timer_rounded,
        color: scheme.primary,
      ),
      KpiBox(
        title: isTr ? 'Ortalama Oturum' : 'Avg Session',
        value: m.sessionCount == 0 ? '–' : fmtAmount(m.avgSessionMinutes, 'time'),
        subtitle: longestText,
        icon: Icons.hourglass_top_rounded,
        color: Colors.purple.shade600,
      ),
      KpiBox(
        title: isTr ? 'Günlük Ortalama' : 'Daily Average',
        value: fmtAmount(m.dailyAvgMinutes, 'time'),
        subtitle: m.sessionCount > 0 ? activeDaysText : '',
        icon: Icons.trending_up_rounded,
        color: Colors.teal.shade600,
      ),
      KpiBox(
        title: isTr ? 'Son Oturum' : 'Last Session',
        value: m.lastSessionMinutes == null ? '–' : fmtAmount(m.lastSessionMinutes!, 'time'),
        subtitle: lastSessionText,
        icon: Icons.history_rounded,
        color: Colors.indigo.shade600,
      ),
    ];

    return _renderBoxGrid(boxes);
  }

  // ---------------------------------------------------------------- MİKTAR GÖRÜNÜMÜ

  Widget _buildQuantityBoxes(BuildContext context, QuantityMetrics m) {
    final scheme = Theme.of(context).colorScheme;

    final activeDaysText = isTr
        ? 'Aktif günlerde ${store.fmtBase(m.activeDayAvgBase, m.dim)}'
        : '${store.fmtBase(m.activeDayAvgBase, m.dim)} on active days';

    final maxEntryText = m.maxEntryTime != null ? fmtDateShort(m.maxEntryTime!, isTr: isTr) : '';

    final boxes = <KpiBox>[
      KpiBox(
        title: isTr ? 'Toplam Miktar' : 'Total Quantity',
        value: store.fmtBase(m.totalBase, m.dim),
        subtitle: isTr ? '${m.entryCount} kayıt' : '${m.entryCount} entries',
        icon: dimIcon(m.dim),
        color: scheme.primary,
      ),
      KpiBox(
        title: isTr ? 'Günlük Ortalama' : 'Daily Average',
        value: store.fmtBase(m.dailyAvgBase, m.dim),
        subtitle: m.entryCount > 0 ? activeDaysText : '',
        icon: Icons.trending_up_rounded,
        color: Colors.teal.shade600,
      ),
      KpiBox(
        title: isTr ? 'Kayıt Başına' : 'Per Entry',
        value: m.entryCount == 0 ? '–' : store.fmtBase(m.avgPerEntry, m.dim),
        subtitle: isTr ? 'ortalama miktar' : 'average amount',
        icon: Icons.speed_rounded,
        color: Colors.indigo.shade600,
      ),
      KpiBox(
        title: isTr ? 'En Yüksek Kayıt' : 'Peak Entry',
        value: m.maxEntryBase == null ? '–' : store.fmtBase(m.maxEntryBase!, m.dim),
        subtitle: maxEntryText,
        icon: Icons.vertical_align_top_rounded,
        color: Colors.deepOrange.shade600,
      ),
    ];

    return _renderBoxGrid(boxes);
  }

  // ---------------------------------------------------------------- OLAY GÖRÜNÜMÜ

  Widget _buildEventBoxes(BuildContext context, EventMetrics m) {
    final scheme = Theme.of(context).colorScheme;

    final maxIntervalText = m.maxInterval == null
        ? ''
        : (isTr ? 'En uzun: ${fmtInterval(m.maxInterval!, isTr: true)}' : 'Longest: ${fmtInterval(m.maxInterval!, isTr: false)}');

    final lastEventText = m.lastTime != null ? fmtDateShort(m.lastTime!, isTr: isTr) : '';

    final boxes = <KpiBox>[
      KpiBox(
        title: isTr ? 'Toplam Olay' : 'Total Events',
        value: '${m.totalCount} ${timesUnit(m.totalCount)}',
        subtitle: m.cadenceText,
        icon: Icons.event_note_rounded,
        color: scheme.primary,
      ),
      KpiBox(
        title: isTr ? 'Ortalama Aralık' : 'Avg Interval',
        value: m.avgInterval == null ? '–' : fmtInterval(m.avgInterval!, isTr: isTr),
        subtitle: maxIntervalText,
        icon: Icons.sync_alt_rounded,
        color: Colors.purple.shade600,
      ),
      KpiBox(
        title: isTr ? 'Son Gerçekleşme' : 'Last Occurred',
        value: m.timeSinceLast == null ? '–' : (isTr ? '${fmtInterval(m.timeSinceLast!, isTr: true)} önce' : '${fmtInterval(m.timeSinceLast!, isTr: false)} ago'),
        subtitle: lastEventText,
        icon: Icons.schedule_rounded,
        color: Colors.teal.shade600,
      ),
      KpiBox(
        title: isTr ? 'Aktif Günler' : 'Active Days',
        value: '${m.activeDaysCount} ${isTr ? "gün" : "days"}',
        subtitle: isTr ? 'olay görülen gün' : 'days with event',
        icon: Icons.event_available_rounded,
        color: Colors.amber.shade800,
      ),
    ];

    return _renderBoxGrid(boxes);
  }

  Widget _renderBoxGrid(List<KpiBox> boxes) {
    return Column(
      children: [
        for (var i = 0; i < boxes.length; i += 2) ...[
          if (i > 0) const SizedBox(height: 8),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: boxes[i]),
                if (i + 1 < boxes.length) ...[
                  const SizedBox(width: 8),
                  Expanded(child: boxes[i + 1]),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }

  // ---------------------------------------------------------------- ÖLÇÜ KIRILIMI KARTI

  Widget _buildMeasureBreakdownCard(BuildContext context, QuantityMetrics m) {
    final scheme = Theme.of(context).colorScheme;
    final rows = m.measureBreakdown;
    final maxCount = rows.fold<int>(1, (maxVal, item) => item.$2 > maxVal ? item.$2 : maxVal);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 16, 6),
          child: Text(
            isTr ? 'Ölçülere Göre Dağılım' : 'Distribution by Measure',
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
              for (var i = 0; i < rows.length; i++) ...[
                if (i > 0) Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: 0.25)),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              rows[i].$1,
                              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: AppFont.body),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 6),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(3),
                              child: LinearProgressIndicator(
                                value: rows[i].$2 / maxCount,
                                minHeight: 4,
                                backgroundColor: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            store.fmtBase(rows[i].$3, m.dim),
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: AppFont.body),
                          ),
                          Text(
                            entriesText(rows[i].$2),
                            style: TextStyle(fontSize: AppFont.micro, color: scheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------- ŞİDDET ANALİZİ KARTI

  Widget _buildSeverityCard(BuildContext context, SeverityAnalysis s) {
    final scheme = Theme.of(context).colorScheme;

    final (trendText, trendColor, trendIcon) = switch (s.direction) {
      SeverityTrendDirection.decreasing => (
          isTr ? 'Şiddet Azalıyor' : 'Decreasing',
          Colors.green.shade700,
          Icons.trending_down_rounded
        ),
      SeverityTrendDirection.increasing => (
          isTr ? 'Şiddet Artıyor' : 'Increasing',
          Colors.red.shade700,
          Icons.trending_up_rounded
        ),
      SeverityTrendDirection.stable => (
          isTr ? 'Durağan Seyrediyor' : 'Stable',
          Colors.amber.shade800,
          Icons.trending_flat_rounded
        ),
      SeverityTrendDirection.unknown => (
          isTr ? 'Yeterli veri yok' : 'Not enough data',
          scheme.onSurfaceVariant,
          Icons.remove_rounded
        ),
    };

    final hafif = s.distribution['hafif'] ?? 0;
    final orta = s.distribution['orta'] ?? 0;
    final siddetli = s.distribution['şiddetli'] ?? 0;
    final total = s.count > 0 ? s.count : 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 16, 6),
          child: Row(
            children: [
              Icon(Icons.healing_rounded, size: 18, color: scheme.primary),
              const SizedBox(width: 8),
              Text(
                isTr ? 'Şiddet ve Belirti Eğilimi' : 'Severity & Trend',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: AppFont.subtitle),
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
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isTr ? 'Ortalama Şiddet' : 'Avg Severity',
                            style: TextStyle(
                              fontSize: AppFont.caption,
                              color: scheme.onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.baseline,
                            textBaseline: TextBaseline.alphabetic,
                            children: [
                              Text(
                                fmtNum1(s.avgScore ?? 0.0),
                                style: const TextStyle(
                                  fontSize: AppFont.headline,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                ' / 10',
                                style: TextStyle(
                                  fontSize: AppFont.body,
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: trendColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(trendIcon, size: 18, color: trendColor),
                          const SizedBox(width: 6),
                          Text(
                            trendText,
                            style: TextStyle(
                              fontSize: AppFont.caption,
                              fontWeight: FontWeight.bold,
                              color: trendColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // 3'lü Dağılım Çubuğu
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: SizedBox(
                    height: 8,
                    child: Row(
                      children: [
                        if (hafif > 0)
                          Expanded(
                            flex: hafif,
                            child: Container(color: Colors.green),
                          ),
                        if (orta > 0)
                          Expanded(
                            flex: orta,
                            child: Container(color: Colors.orange),
                          ),
                        if (siddetli > 0)
                          Expanded(
                            flex: siddetli,
                            child: Container(color: Colors.red),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),

                // Açıklama Etiketleri
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _legendItem(
                      color: Colors.green,
                      label: isTr ? 'Hafif' : 'Mild',
                      count: hafif,
                      pct: (hafif / total * 100).round(),
                    ),
                    _legendItem(
                      color: Colors.orange,
                      label: isTr ? 'Orta' : 'Moderate',
                      count: orta,
                      pct: (orta / total * 100).round(),
                    ),
                    _legendItem(
                      color: Colors.red,
                      label: isTr ? 'Şiddetli' : 'Severe',
                      count: siddetli,
                      pct: (siddetli / total * 100).round(),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _legendItem({
    required Color color,
    required String label,
    required int count,
    required int pct,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(
          isTr ? '$label: $count (%$pct)' : '$label: $count ($pct%)',
          style: const TextStyle(fontSize: AppFont.micro, fontWeight: FontWeight.w500),
        ),
      ],
    );
  }
}
