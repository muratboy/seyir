import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../../logic/l10n.dart';
import '../app_font.dart';

/// İstatistikler ve gidişat ekranında tespit edilen korelasyonları ve tetikleyicileri gösteren kart
class StatsCorrelationsCard extends StatelessWidget {
  final List<CorrelationInsight> insights;
  final void Function(int activityId)? onSelectActivity;

  const StatsCorrelationsCard({
    super.key,
    required this.insights,
    this.onSelectActivity,
  });

  @override
  Widget build(BuildContext context) {
    if (insights.isEmpty) return const SizedBox.shrink();

    final s = strings.value;
    final isTr = s.isTr;
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
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.hub_outlined, size: 18, color: scheme.primary),
                ),
                const SizedBox(width: 8),
                Text(
                  isTr ? 'İlişkiler & Korelasyon Analizi' : 'Correlations & Pattern Insights',
                  style: const TextStyle(fontSize: AppFont.subtitle, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          const SizedBox(height: 12),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: insights.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final insight = insights[i];
              final isWarning = insight.type == CorrelationType.warning;

              final Color bgColor = isWarning
                  ? Colors.orange.withValues(alpha: 0.1)
                  : Colors.teal.withValues(alpha: 0.1);
              final Color borderColor = isWarning
                  ? Colors.orange.withValues(alpha: 0.35)
                  : Colors.teal.withValues(alpha: 0.35);
              final Color iconColor = isWarning ? Colors.deepOrange : Colors.teal;
              final IconData icon = isWarning ? Icons.warning_amber_rounded : Icons.health_and_safety_outlined;

              final badgeText = isWarning
                  ? (isTr ? 'TETİKLEYİCİ' : 'TRIGGER')
                  : (isTr ? 'KORUYUCU / UYUM' : 'RELIEF / SYNERGY');

              return InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: onSelectActivity != null
                    ? () => onSelectActivity!(insight.relatedActivityId)
                    : null,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: bgColor,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: borderColor),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Icon(icon, color: iconColor, size: 20),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    insight.title,
                                    style: TextStyle(
                                      fontSize: AppFont.small,
                                      fontWeight: FontWeight.bold,
                                      color: scheme.onSurface,
                                    ),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: iconColor.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    badgeText,
                                    style: TextStyle(
                                      fontSize: AppFont.micro,
                                      fontWeight: FontWeight.bold,
                                      color: iconColor,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              insight.description,
                              style: TextStyle(
                                fontSize: AppFont.micro,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
      ),
    );
  }
}
