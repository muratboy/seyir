import 'package:flutter/material.dart';

import '../../logic/l10n.dart';
import '../../logic/trend_insights.dart';
import '../app_font.dart';

/// Haftalık "Neler Değişti?" içgörü kartı.
///
/// Artanlar, azalanlar, ritmi bozulanlar ve tamamlanan hedefleri özetler.
class StatsInsightsCard extends StatelessWidget {
  final List<TrendInsight> insights;
  final ValueChanged<int?> onSelectActivity;

  const StatsInsightsCard({
    super.key,
    required this.insights,
    required this.onSelectActivity,
  });

  @override
  Widget build(BuildContext context) {
    if (insights.isEmpty) return const SizedBox.shrink();

    final s = strings.value;
    final scheme = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.3)),
      ),
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.25),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.auto_awesome_rounded, size: 20, color: Colors.amber.shade700),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    s.isTr ? 'Neler Değişti?' : 'What Changed?',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: AppFont.subtitle),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    s.isTr ? 'Haftalık Gidişat' : 'Weekly Trend',
                    style: TextStyle(
                      fontSize: AppFont.micro,
                      fontWeight: FontWeight.w600,
                      color: scheme.primary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            for (var i = 0; i < insights.length; i++) ...[
              if (i > 0) const SizedBox(height: 8),
              InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: insights[i].activityId != null
                    ? () => onSelectActivity(insights[i].activityId)
                    : null,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Icon(insights[i].icon, size: 16, color: insights[i].color),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          insights[i].text,
                          style: const TextStyle(
                            fontSize: AppFont.body,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      if (insights[i].activityId != null)
                        Icon(
                          Icons.chevron_right_rounded,
                          size: 16,
                          color: scheme.onSurfaceVariant.withValues(alpha: 0.5),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
