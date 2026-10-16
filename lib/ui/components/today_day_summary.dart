import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../../data/store.dart';
import '../../logic/format.dart';
import '../app_font.dart';

class TodayDaySummary extends StatelessWidget {
  final DateTime currentDay;

  const TodayDaySummary({super.key, required this.currentDay});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dailyGoals = store.goals.where((g) => g.period == GoalPeriod.day).toList();
    // Bugünün Özeti açıkken günlük hedefler zaten orada detaylı gösterildiği için
    // üstte aynı hedefleri ikinci kez sıralamayız; yalnızca özet kartı kapalıysa mini halkalar görünür.
    final summaryCollapsed = store.isSectionCollapsed('summary');
    if (!summaryCollapsed || dailyGoals.isEmpty) {
      return const SizedBox.shrink();
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.only(top: 6, right: 4),
      child: Row(
        children: [
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
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
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
