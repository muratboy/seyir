import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../../data/store.dart';
import '../../logic/l10n.dart';
import '../../logic/format.dart';
import '../app_font.dart';

class StatsCategoryChart extends StatelessWidget {
  final List<Entry> entries;

  const StatsCategoryChart({super.key, required this.entries});

  @override
  Widget build(BuildContext context) {
    final s = strings.value;
    final scheme = Theme.of(context).colorScheme;

    if (entries.isEmpty) return const SizedBox.shrink();

    final catCounts = <String, (CategoryDef def, int count)>{};
    for (final e in entries) {
      final act = store.activities[e.activityId];
      final def = act?.categoryDef ?? getCategoryDef(null);
      final prev = catCounts[def.id] ?? (def, 0);
      catCounts[def.id] = (def, prev.$2 + 1);
    }

    final total = entries.length;
    final sortedCats = catCounts.values.toList()
      ..sort((a, b) => b.$2.compareTo(a.$2));

    // Tek kategori varsa (genellikle %100 Genel) kullanıcıya katma değer sağlamadığı için gizle
    if (sortedCats.length < 2) return const SizedBox.shrink();

    final sections = sortedCats.map((item) {
      final pct = (item.$2 / total) * 100;
      return PieChartSectionData(
        value: item.$2.toDouble(),
        title: pct >= 12 ? fmtPercent(pct.round()) : '',
        color: Color(item.$1.colorValue),
        radius: 34,
        titleStyle: const TextStyle(
          color: Colors.white,
          fontSize: AppFont.micro,
          fontWeight: FontWeight.bold,
        ),
      );
    }).toList();

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.pie_chart_rounded, size: 18, color: scheme.primary),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    s.isTr ? 'Kategori Dağılımı' : 'Category Distribution',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: AppFont.subtitle),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${sortedCats.length} ${s.isTr ? "Kategori" : "Categories"}',
                  style: TextStyle(fontSize: AppFont.caption, color: scheme.onSurfaceVariant),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                // Donut Chart with centered total logs count
                SizedBox(
                  width: 124,
                  height: 124,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      PieChart(
                        PieChartData(
                          sections: sections,
                          centerSpaceRadius: 30,
                          sectionsSpace: 2.5,
                        ),
                      ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '$total',
                            style: TextStyle(
                              fontSize: AppFont.title,
                              fontWeight: FontWeight.bold,
                              color: scheme.onSurface,
                            ),
                          ),
                          Text(
                            s.metricCount,
                            style: TextStyle(
                              fontSize: AppFont.micro,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                // Categories breakdown list with proportional bars
                Expanded(
                  child: Column(
                    children: sortedCats.map((item) {
                      final ratio = item.$2 / total;
                      final pctStr = (ratio * 100).toStringAsFixed(0);
                      final catColor = Color(item.$1.colorValue);

                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Ad, grafiğin yanındaki sütunun bütün genişliğini kullanır; sayı çubuğun yanındadır.
                            // Sayı adın yanındayken dar ekranda "Beslenme" kelimesi bile sığmayıp bölünüyordu.
                            Row(
                              children: [
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: catColor,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    '${item.$1.emoji} ${item.$1.name(s.isTr)}',
                                    style: const TextStyle(
                                      fontSize: AppFont.caption,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 3),
                            Row(
                              children: [
                                Expanded(
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(3),
                                    child: LinearProgressIndicator(
                                      value: ratio,
                                      minHeight: 4,
                                      backgroundColor:
                                          scheme.surfaceContainerHighest.withValues(alpha: 0.4),
                                      valueColor: AlwaysStoppedAnimation<Color>(catColor),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  '${item.$2} (${fmtPercent(pctStr)})',
                                  style: TextStyle(
                                    fontSize: AppFont.caption,
                                    fontWeight: FontWeight.bold,
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
