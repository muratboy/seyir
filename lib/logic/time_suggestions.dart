import 'dart:math';

import '../data/models.dart';
import '../data/store.dart';
import 'format.dart';

/// Zamana ve güne göre akıllı aktivite önerisi hesabı.
///
/// Günün saati (±2 saatlik pencere), haftanın günü (hafta içi / hafta sonu)
/// ve son 60 günün kayıt sıklığına göre her aktiviteye bir zaman uyum puanı verir.
class TimeSuggestions {
  /// [now] anındaki zaman örüntüsüne göre en uygun aktiviteleri döndürür.
  static List<Activity> compute({
    required Map<int, Activity> activities,
    required List<Entry> entries,
    required Map<int, ActivityStats> stats,
    DateTime? now,
    int limit = 6,
  }) {
    final current = now ?? DateTime.now();
    final currentHour = current.hour;
    final currentWeekday = current.weekday;
    final isWeekend = currentWeekday == 6 || currentWeekday == 7;

    final nonArchived = activities.values.where((a) => !a.isArchived).toList();
    if (nonArchived.isEmpty) return const [];

    // Son 60 günün kayıtları (veya veri azsa tümü)
    final cutoff = subDays(current, 60);
    final recentEntries = entries.where((e) => !e.time.isBefore(cutoff)).toList();

    // Aktivite bazında saat ve gün uyumu puanlaması
    final scores = <int, double>{};

    for (final a in nonArchived) {
      final actEntries = recentEntries.where((e) => e.activityId == a.id).toList();
      final st = stats[a.id];
      if (st == null || st.count == 0 || actEntries.isEmpty) {
        continue;
      }

      double hourScore = 0.0;
      double weekdayScore = 0.0;
      DateTime? lastTime;

      for (final e in actEntries) {
        final t = e.time;
        if (lastTime == null || t.isAfter(lastTime)) {
          lastTime = t;
        }

        // 1. Saat Farkı (Döngüsel 24 saat farkı)
        int diff = (t.hour - currentHour).abs();
        if (diff > 12) diff = 24 - diff;

        if (diff == 0) {
          hourScore += 3.0;
        } else if (diff == 1) {
          hourScore += 2.0;
        } else if (diff == 2) {
          hourScore += 1.0;
        } else if (diff == 3) {
          hourScore += 0.3;
        }

        // 2. Gün Uyumu
        if (t.weekday == currentWeekday) {
          weekdayScore += 1.5;
        } else {
          final eIsWeekend = t.weekday == 6 || t.weekday == 7;
          if (eIsWeekend == isWeekend) {
            weekdayScore += 0.5;
          }
        }
      }

      // 3. Genel sıklık ve son 30 günün payı
      double totalScore = (hourScore * 1.5) + (weekdayScore * 1.0) + (st.recent * 0.4);

      // 4. Kısa süre önce yapıldıysa (son 20 dakika içinde) bir sonraki rutine yer aç
      if (lastTime != null && current.difference(lastTime).inMinutes < 20) {
        totalScore *= 0.5;
      }

      if (totalScore > 0) {
        scores[a.id] = totalScore;
      }
    }

    // Puanlananları sırala
    final sorted = nonArchived.where((a) => scores.containsKey(a.id)).toList()
      ..sort((a, b) => scores[b.id]!.compareTo(scores[a.id]!));

    final result = sorted.take(limit).toList();

    // Yeterli zaman örüntüsü yoksa genel sıklığa göre tamamla
    if (result.length < limit) {
      final remaining = nonArchived.where((a) => !result.contains(a)).toList()
        ..sort((a, b) {
          final sa = stats[a.id]?.recent ?? 0;
          final sb = stats[b.id]?.recent ?? 0;
          return sb.compareTo(sa);
        });
      result.addAll(remaining.take(limit - result.length));
    }

    return result;
  }

  /// Belirli bir aktivitenin şu anki saatle uyum katsayısı (0.0 - 5.0)
  static double timeAffinity(int activityId, List<Entry> entries, DateTime now) {
    final cutoff = subDays(now, 60);
    final actEntries = entries.where((e) => e.activityId == activityId && !e.time.isBefore(cutoff));
    if (actEntries.isEmpty) return 0.0;

    double score = 0.0;
    final nowHour = now.hour;
    for (final e in actEntries) {
      int diff = (e.time.hour - nowHour).abs();
      if (diff > 12) diff = 24 - diff;
      if (diff == 0) {
        score += 1.0;
      } else if (diff == 1) {
        score += 0.6;
      } else if (diff == 2) {
        score += 0.3;
      }
    }
    return min(5.0, score);
  }
}
