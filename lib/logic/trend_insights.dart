import 'dart:math';

import 'package:flutter/material.dart';

import '../data/store.dart';
import 'activity_rhythm.dart';
import 'format.dart';

enum TrendType {
  increased,
  decreased,
  dormant,
  goalMet,
  streak,
}

class TrendInsight {
  final TrendType type;
  final String text;
  final IconData icon;
  final Color color;
  final int? activityId;

  const TrendInsight({
    required this.type,
    required this.text,
    required this.icon,
    required this.color,
    this.activityId,
  });
}

/// Haftalık "Neler Değişti?" içgörülerini hesaplar.
List<TrendInsight> computeWeeklyInsights({
  required AppStore store,
  required DateTime now,
  required bool isTr,
}) {
  final insights = <TrendInsight>[];

  final thisWeekStart = weekStart(now);
  final thisWeekEnd = addDays(thisWeekStart, 7);
  final prevWeekStart = subDays(thisWeekStart, 7);

  // Bu hafta şu ana kadar
  final thisWeekEntries = store.entriesIn(thisWeekStart, thisWeekEnd).where((e) => !e.time.isAfter(now)).toList();
  // Geçen hafta aynı ana kadar olan karşılaştırma anı
  final daysPassed = calendarDaysBetween(thisWeekStart, now);
  final sameMomentInPrevWeek = DateTime(
    prevWeekStart.year,
    prevWeekStart.month,
    prevWeekStart.day + daysPassed,
    now.hour,
    now.minute,
    now.second,
    now.millisecond,
    now.microsecond,
  );
  final prevWeekEntries = store.entriesIn(prevWeekStart, sameMomentInPrevWeek).toList();

  final thisCounts = <int, int>{};
  for (final e in thisWeekEntries) {
    thisCounts[e.activityId] = (thisCounts[e.activityId] ?? 0) + 1;
  }
  final prevCounts = <int, int>{};
  for (final e in prevWeekEntries) {
    prevCounts[e.activityId] = (prevCounts[e.activityId] ?? 0) + 1;
  }

  // 1. Tutulan Hedefler (Goal Met)
  for (final g in store.goals) {
    final status = store.goalStatus(g, at: now);
    if (status.done && status.value > 0) {
      final actId = g.links.firstOrNull?.activityId;
      insights.add(
        TrendInsight(
          type: TrendType.goalMet,
          text: isTr ? '🎯 ${g.name}: Hedefe ulaşıldı!' : '🎯 ${g.name}: Goal reached!',
          icon: Icons.check_circle_rounded,
          color: Colors.green.shade600,
          activityId: actId,
        ),
      );
    }
  }

  // 2. Alışkanlık Serileri (Streak >= 3)
  for (final a in store.activities.values) {
    if (a.isArchived) continue;
    final info = store.habitStreakInfo(a.id);
    if (info.currentStreak >= 3) {
      insights.add(
        TrendInsight(
          type: TrendType.streak,
          text: isTr
              ? '🔥 ${a.name}: ${info.currentStreak} günlük seri devam ediyor!'
              : '🔥 ${a.name}: ${info.currentStreak} day streak ongoing!',
          icon: Icons.local_fire_department_rounded,
          color: Colors.deepOrange.shade600,
          activityId: a.id,
        ),
      );
    }
  }

  // 3. Uzun Süredir Yapılmayanlar / Ritmi Bozulanlar (Dormant)
  final todayStart = dayStart(now);
  for (final a in store.activities.values) {
    if (a.isArchived) continue;
    final entries = store.entries.where((e) => e.activityId == a.id).toList();
    if (entries.length < 3) continue;

    final rhythm = ActivityRhythm.compute(entries: entries, now: now, isTr: isTr);
    final lastTime = entries.last.time;
    final daysSince = calendarDaysBetween(dayStart(lastTime), todayStart);

    // İlk ve son kayıt aralığından ortalama gün
    final spanDays = max(1, calendarDaysBetween(dayStart(entries.first.time), todayStart) + 1);
    final avgIntervalDays = spanDays / entries.length;

    // Normal ritmin 2 katından fazla gecikmiş ve en az 7 gündür yapılmamışsa
    if (avgIntervalDays <= 14 && daysSince >= max(7, (avgIntervalDays * 2.0).round())) {
      insights.add(
        TrendInsight(
          type: TrendType.dormant,
          text: isTr
              ? '⏳ ${a.name}: $daysSince gündür yapılmadı (${rhythm.cadenceText})'
              : '⏳ ${a.name}: Not logged for $daysSince days (${rhythm.cadenceText})',
          icon: Icons.hourglass_empty_rounded,
          color: Colors.amber.shade800,
          activityId: a.id,
        ),
      );
    }
  }

  // 4. Artan Aktiviteler (Increased this week)
  for (final entry in thisCounts.entries) {
    final actId = entry.key;
    final act = store.activity(actId);
    final thisC = entry.value;
    final prevC = prevCounts[actId] ?? 0;

    if (thisC >= 2) {
      if (prevC == 0 && thisC >= 3) {
        insights.add(
          TrendInsight(
            type: TrendType.increased,
            text: isTr
                ? '📈 ${act.name}: Bu hafta yeni tempo ($thisC kez)'
                : '📈 ${act.name}: New momentum this week ($thisC times)',
            icon: Icons.trending_up_rounded,
            color: Colors.teal.shade600,
            activityId: actId,
          ),
        );
      } else if (thisC >= prevC + 2 || (prevC > 0 && thisC >= (prevC * 1.5).round() && thisC - prevC >= 1)) {
        insights.add(
          TrendInsight(
            type: TrendType.increased,
            text: isTr
                ? '📈 ${act.name}: Geçen haftaya göre artışta ($thisC vs $prevC kez)'
                : '📈 ${act.name}: Increased vs last week ($thisC vs $prevC times)',
            icon: Icons.trending_up_rounded,
            color: Colors.teal.shade600,
            activityId: actId,
          ),
        );
      }
    }
  }

  // 5. Azalan Aktiviteler (Decreased this week)
  for (final entry in prevCounts.entries) {
    final actId = entry.key;
    final act = store.activity(actId);
    final prevC = entry.value;
    final thisC = thisCounts[actId] ?? 0;

    if (prevC >= 3 && thisC < prevC && (prevC - thisC >= 2 || (thisC == 0 && prevC >= 2))) {
      insights.add(
        TrendInsight(
          type: TrendType.decreased,
          text: isTr
              ? '📉 ${act.name}: Bu hafta azaldı ($thisC vs $prevC kez)'
              : '📉 ${act.name}: Decreased this week ($thisC vs $prevC times)',
          icon: Icons.trending_down_rounded,
          color: Colors.blueGrey.shade600,
          activityId: actId,
        ),
      );
    }
  }

  return insights;
}
