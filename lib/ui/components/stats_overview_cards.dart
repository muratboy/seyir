import 'package:flutter/material.dart';

import '../../data/store.dart';
import '../../logic/format.dart';
import '../../logic/l10n.dart';
import '../../logic/period_stats.dart';
import '../app_font.dart';
import 'stats_common.dart';

/// Dönemin özeti: dört kutu ve altında boyutlara göre toplamlar.
///
/// Tüm aktiviteler birlikteyken kutular kayıt sayısı üzerinden konuşur; tek bir aktivite seçiliyken o
/// aktivitenin miktarını (süre, hacim, mesafe...) öne alır. Gün görünümünde "günlük ortalama" gibi bir güne
/// uymayan kutuların yerini günün ilk ve son kaydı alır.
class StatsOverviewCard extends StatelessWidget {
  final PeriodStats stats;
  final bool singleActivity;

  /// Grafikle ortak ölçüt (null = kayıt sayısı); "en yoğun" kutusu grafikteki en uzun çubuğu söyler.
  final String? metric;

  /// Dönemde kaydı olan farklı aktivite sayısı.
  final int activityCount;

  const StatsOverviewCard({
    super.key,
    required this.stats,
    required this.singleActivity,
    required this.metric,
    required this.activityCount,
  });

  bool get _isTr => strings.value.isTr;

  /// Neyle karşılaştırıldığı. Süren dönem, önceki dönemin aynı ana kadarki bölümüyle kıyaslanır.
  String get _comparedWith {
    final partial = stats.comparesPartial;
    return switch (stats.period.range) {
      StatRange.day => partial
          ? (_isTr ? 'dün bu saate kadar' : 'yesterday by now:')
          : (_isTr ? 'önceki gün' : 'previous day:'),
      StatRange.week => partial
          ? (_isTr ? 'geçen hafta bu vakte kadar' : 'last week by now:')
          : (_isTr ? 'önceki hafta' : 'previous week:'),
      StatRange.month => partial
          ? (_isTr ? 'geçen ay bu vakte kadar' : 'last month by now:')
          : (_isTr ? 'önceki ay' : 'previous month:'),
      StatRange.year => partial
          ? (_isTr ? 'geçen yıl bu vakte kadar' : 'last year by now:')
          : (_isTr ? 'önceki yıl' : 'previous year:'),
    };
  }

  /// "▲ 2 · geçen hafta bu vakte kadar 4"; kıyaslanacak veri yoksa null.
  String? _comparison(String? dim) {
    if (!stats.hasComparison) return null;
    String plain(double v) => dim == null ? fmtNum(v) : store.fmtBase(v, dim);
    final before = stats.previous.value(dim);
    final diff = stats.total.value(dim) - before;
    final change = diff.abs() < 1e-9
        ? (_isTr ? 'aynı' : 'same')
        : '${diff > 0 ? '▲' : '▼'} ${plain(diff.abs())}';
    return '$change · $_comparedWith ${plain(before)}';
  }

  @override
  Widget build(BuildContext context) {
    final s = strings.value;
    final scheme = Theme.of(context).colorScheme;
    final total = stats.total;
    final isDay = stats.period.range == StatRange.day;
    final mainDim = singleActivity ? total.mainDim : null;
    final activeDays = _isTr
        ? '${stats.activeDays} / ${stats.elapsedDays} gün'
        : '${stats.activeDays} of ${stats.elapsedDays} days';

    final countBox = KpiBox(
      title: s.metricCount,
      value: '${total.count}',
      subtitle: mainDim != null
          ? (isDay ? '' : (_isTr ? '$activeDays aktif' : '$activeDays active'))
          : (_comparison(null) ??
              (singleActivity ? '' : (_isTr ? '$activityCount aktivite' : '$activityCount activities'))),
      icon: metricIcon(null),
      color: mainDim != null ? Colors.amber.shade700 : scheme.primary,
    );

    final busiest = stats.busiestBucket(metric);
    final busiestBox = KpiBox(
      title: switch (stats.period.range) {
        StatRange.day => _isTr ? 'En Yoğun Saat' : 'Busiest Hour',
        StatRange.week || StatRange.month => _isTr ? 'En Yoğun Gün' : 'Busiest Day',
        StatRange.year => _isTr ? 'En Yoğun Ay' : 'Busiest Month',
      },
      value: busiest == null ? '–' : bucketName(stats.period, busiest),
      subtitle: busiest == null ? '' : fmtMetric(stats.buckets[busiest].value(metric), metric),
      icon: Icons.local_fire_department_rounded,
      color: Colors.deepOrange.shade600,
    );

    final first = stats.firstEntry;
    final last = stats.lastEntry;
    final firstLastBox = KpiBox(
      title: _isTr ? 'İlk – Son Kayıt' : 'First – Last Entry',
      value: first == null || last == null
          ? '–'
          : (fmtTime(first) == fmtTime(last) ? fmtTime(first) : '${fmtTime(first)} – ${fmtTime(last)}'),
      subtitle: '',
      icon: Icons.schedule_rounded,
      color: Colors.teal.shade600,
    );

    final boxes = <KpiBox>[
      if (mainDim != null)
        KpiBox(
          title: store.dimName(mainDim),
          value: store.fmtBase(total.value(mainDim), mainDim),
          subtitle: _comparison(mainDim) ?? (_isTr ? 'toplam' : 'in total'),
          icon: dimIcon(mainDim),
          color: scheme.primary,
        ),
      countBox,
      if (isDay) ...[
        if (!singleActivity)
          KpiBox(
            title: _isTr ? 'Aktivite' : 'Activities',
            value: '$activityCount',
            subtitle: _isTr ? 'farklı aktivite' : 'different activities',
            icon: Icons.category_outlined,
            color: Colors.amber.shade700,
          ),
        firstLastBox,
      ] else ...[
        if (mainDim == null)
          KpiBox(
            title: _isTr ? 'Aktif Gün' : 'Active Days',
            value: '${stats.activeDays} / ${stats.elapsedDays}',
            subtitle: _isTr ? 'kayıt olan gün' : 'days with entries',
            icon: Icons.event_available_rounded,
            color: Colors.amber.shade700,
          ),
        mainDim == null
            ? KpiBox(
                title: s.dailyAverage,
                value: fmtNum1(total.count / stats.elapsedDays),
                subtitle: s.entriesPerDay,
                icon: Icons.trending_up_rounded,
                color: Colors.teal.shade600,
              )
            : KpiBox(
                title: s.dailyAverage,
                value: store.fmtBase(total.value(mainDim) / stats.elapsedDays, mainDim),
                // Her gün yapılmayan bir işte "yaptığım günlerde ne kadar" sorusu ayrı bir bilgidir.
                subtitle: stats.activeDays > 0 && stats.activeDays < stats.elapsedDays
                    ? (_isTr
                        ? 'aktif günlerde ${store.fmtBase(total.value(mainDim) / stats.activeDays, mainDim)}'
                        : '${store.fmtBase(total.value(mainDim) / stats.activeDays, mainDim)} on active days')
                    : (_isTr ? 'gün başına' : 'per day'),
                icon: Icons.trending_up_rounded,
                color: Colors.teal.shade600,
              ),
      ],
      busiestBox,
    ];

    // Kutularda yer almayan boyutların toplamları.
    final otherDims =
        availableMetrics(total, singleActivity: singleActivity).whereType<String>().where((d) => d != mainDim);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.3)),
      ),
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.25),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Kutular ikişerli dizilir; tek kalan kutu satırı kaplar.
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
            if (otherDims.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  for (final dim in otherDims)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.25)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(dimIcon(dim), size: 14, color: scheme.primary),
                          const SizedBox(width: 6),
                          Text(
                            '${store.dimName(dim)}: ',
                            style: TextStyle(fontSize: AppFont.caption, color: scheme.onSurfaceVariant),
                          ),
                          Text(
                            store.fmtBase(total.value(dim), dim),
                            style: const TextStyle(fontSize: AppFont.caption, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class KpiBox extends StatelessWidget {
  final String title;
  final String value;

  /// Boşsa yazılmaz.
  final String subtitle;
  final IconData icon;
  final Color color;

  const KpiBox({
    super.key,
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 16, color: color),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: AppFont.caption,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurfaceVariant,
                  ),
                  // Dar ekranda "Günlük Ortalama" tek satıra sığmıyor; kesilmek yerine alt satıra geçer.
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Uzun değer ("12 Ekim, Pazartesi") kesilmek yerine küçülür.
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: TextStyle(
                fontSize: AppFont.title,
                fontWeight: FontWeight.bold,
                color: scheme.onSurface,
                letterSpacing: -0.5,
              ),
              maxLines: 1,
            ),
          ),
          if (subtitle.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: AppFont.micro,
                color: scheme.onSurfaceVariant.withValues(alpha: 0.8),
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }
}
