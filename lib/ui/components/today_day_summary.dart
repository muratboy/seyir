import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../../data/store.dart';
import '../../logic/format.dart';
import '../../logic/l10n.dart';
import '../app_font.dart';

class TodayDaySummary extends StatelessWidget {
  final DateTime currentDay;

  const TodayDaySummary({super.key, required this.currentDay});

  @override
  Widget build(BuildContext context) {
    final s = strings.value;
    final scheme = Theme.of(context).colorScheme;
    final summary = store.getDaySummary(currentDay);
    final dailyGoals = store.goals.where((g) => g.period == GoalPeriod.day).toList();

    if (summary.count == 0 && dailyGoals.isEmpty) {
      return const SizedBox.shrink();
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          // Süre özeti
          if (summary.totalTimeMinutes > 0) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.3)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.schedule_rounded, size: 15, color: scheme.primary),
                  const SizedBox(width: 5),
                  Text(
                    fmtAmount(summary.totalTimeMinutes, 'time'),
                    style: TextStyle(fontSize: AppFont.caption, fontWeight: FontWeight.bold, color: scheme.onSurface),
                  ),
                ],
              ),
            ),
          ],

          // Sıvı / Hacim özeti
          if (summary.totalVolumeLiters > 0) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                color: Colors.blue.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue.withValues(alpha: 0.25)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.water_drop_rounded, size: 15, color: Colors.blue),
                  const SizedBox(width: 5),
                  Text(
                    fmtAmount(summary.totalVolumeLiters, 'volume'),
                    style: const TextStyle(fontSize: AppFont.caption, fontWeight: FontWeight.bold, color: Colors.blue),
                  ),
                ],
              ),
            ),
          ],

          // Kayıt sayısı
          if (summary.count > 0) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.3)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.list_alt_rounded, size: 15, color: scheme.secondary),
                  const SizedBox(width: 5),
                  Text(
                    '${summary.count} ${s.entriesCountSuffix}',
                    style: TextStyle(fontSize: AppFont.caption, fontWeight: FontWeight.bold, color: scheme.onSurface),
                  ),
                ],
              ),
            ),
          ],

          // Günlük hedefler için canlı mini ilerleme halkaları
          for (final g in dailyGoals) ...[
            Builder(builder: (context) {
              final st = store.goalStatus(g, at: currentDay);
              final isDone = st.done;
              final isLimit = g.isLimit;
              final isExceeded = st.isExceeded;

              final Color badgeColor = isLimit
                  ? (isExceeded ? Colors.red : Colors.teal)
                  : (isDone ? Colors.green : scheme.primary);

              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                  color: badgeColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: badgeColor.withValues(alpha: 0.35)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        value: isLimit ? (isExceeded ? 1.0 : (st.ratio.clamp(0.0, 1.0))) : (st.ratio.clamp(0.0, 1.0)),
                        strokeWidth: 2.5,
                        valueColor: AlwaysStoppedAnimation<Color>(badgeColor),
                        backgroundColor: badgeColor.withValues(alpha: 0.2),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      g.name,
                      style: TextStyle(fontSize: AppFont.caption, fontWeight: FontWeight.w600, color: badgeColor),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      isLimit
                          ? (isExceeded ? '⚠️' : '✓')
                          : (isDone ? '✓' : fmtPercent((st.ratio * 100).floor())),
                      style: TextStyle(fontSize: AppFont.micro, fontWeight: FontWeight.bold, color: badgeColor),
                    ),
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }
}
