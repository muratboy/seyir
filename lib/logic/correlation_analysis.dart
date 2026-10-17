import 'dart:math';

import '../data/models.dart';
import '../data/store.dart';
import 'format.dart';

/// Belirtiler ve alışkanlıklar arasındaki ilişkileri, tetikleyicileri ve birlikte yapılma örüntülerini analiz eder.
class CorrelationEngine {
  static bool isSymptom(Activity act) {
    final cat = act.categoryDef.name(true).toLowerCase();
    if (cat.contains('sağlık') || cat.contains('belirti') || cat.contains('hastalık')) {
      return true;
    }
    final name = act.name.toLowerCase();
    const symptomKeywords = [
      'ağrı',
      'baş ağrısı',
      'migren',
      'yorgunluk',
      'halsiz',
      'stres',
      'mide',
      'bulantı',
      'uykusuzluk',
      'kaygı',
      'belirti',
      'pain',
      'headache',
      'fatigue',
      'stress',
      'nausea',
      'symptom',
    ];
    return symptomKeywords.any((k) => name.contains(k));
  }

  /// Verilen mağazadaki tüm kayıtları veya seçili [activityId] için korelasyonları hesaplar.
  static List<CorrelationInsight> analyze(
    AppStore store, {
    int? activityId,
    DateTime? now,
    bool isTr = true,
    int daysBack = 60,
  }) {
    final insights = <CorrelationInsight>[];
    final referenceDate = now ?? DateTime.now();
    final startDate = subDays(dayStart(referenceDate), daysBack);

    // 1. Gün bazında aktiviteleri çıkar
    final dayActivityMap = <DateTime, Set<int>>{};
    final relevantEntries = store.entries.where((e) => !e.time.isBefore(startDate) && !e.time.isAfter(referenceDate));

    for (final e in relevantEntries) {
      final day = dayStart(e.time);
      (dayActivityMap[day] ??= {}).add(e.activityId);
    }

    final totalDays = dayActivityMap.length;
    if (totalDays < 4) return const []; // Yeterli gün verisi yok

    // Günlerdeki aktivite sayıları
    final activityDayCounts = <int, int>{};
    for (final acts in dayActivityMap.values) {
      for (final a in acts) {
        activityDayCounts[a] = (activityDayCounts[a] ?? 0) + 1;
      }
    }

    // Aday aktiviteler (en az 2 gün yapılmış olanlar)
    final candidateActIds = activityDayCounts.entries
        .where((e) => e.value >= 2 && store.activities.containsKey(e.key))
        .map((e) => e.key)
        .toList();

    if (candidateActIds.length < 2) return const [];

    final processedPairs = <String>{};

    for (final actAId in candidateActIds) {
      if (activityId != null && actAId != activityId) {
        // Tek bir aktiviteye odaklanıldıysa, A veya B o aktivite olmalı
        continue;
      }
      final actA = store.activities[actAId];
      if (actA == null || actA.isArchived) continue;
      final isASymptom = isSymptom(actA);

      for (final actBId in candidateActIds) {
        if (actAId == actBId) continue;
        final actB = store.activities[actBId];
        if (actB == null || actB.isArchived) continue;
        final isBSymptom = isSymptom(actB);

        final pairKey = '${min(actAId, actBId)}_${max(actAId, actBId)}';

        int nA = 0;
        int nNotA = 0;
        int nAandB = 0;
        int nNotAandB = 0;

        for (final acts in dayActivityMap.values) {
          final hasA = acts.contains(actAId);
          final hasB = acts.contains(actBId);

          if (hasA) {
            nA++;
            if (hasB) nAandB++;
          } else {
            nNotA++;
            if (hasB) nNotAandB++;
          }
        }

        // Minimum eşik: Karşılaştırma için her iki durum da en az 2 gün gözlemlenmiş olmalı
        if (nA < 2 || nNotA < 2) continue;

        final pBGivenA = nAandB / nA;
        final pBGivenNotA = nNotAandB / nNotA;

        if (isBSymptom) {
          // A durumunun B belirtisi üzerindeki etkisi (tetikleyici veya koruyucu)
          if (pBGivenNotA == 0) {
            // Belirti yalnızca A aktivitesi yapıldığında görülmüş
            if (pBGivenA >= 0.5 && nAandB >= 2) {
              final pct = (pBGivenA * 100).round();
              insights.add(
                CorrelationInsight(
                  primaryActivityId: actAId,
                  relatedActivityId: actBId,
                  title: isTr ? '${actA.name} ➔ ${actB.name} Tetikleyicisi' : '${actA.name} ➔ ${actB.name} Trigger',
                  description: isTr
                      ? '${actA.name} görülen günlerde %$pct olasılıkla ${actB.name} belirtisi ortaya çıktı (diğer günlerde hiç görülmedi).'
                      : '${actB.name} occurred on $pct% of days with ${actA.name} (never on other days).',
                  changeRatio: 99.0,
                  type: CorrelationType.warning,
                  coOccurrenceCount: nAandB,
                  totalPrimaryDays: nA,
                ),
              );
            }
          } else {
            final ratio = pBGivenA / pBGivenNotA;
            if (ratio >= 1.35 && nAandB >= 2) {
              final pctIncrease = ((ratio - 1.0) * 100).round();
              insights.add(
                CorrelationInsight(
                  primaryActivityId: actAId,
                  relatedActivityId: actBId,
                  title: isTr ? '${actA.name} ➔ ${actB.name} Tetikleyicisi' : '${actA.name} ➔ ${actB.name} Trigger',
                  description: isTr
                      ? '${actA.name} görülen günlerde ${actB.name} belirtisi %$pctIncrease daha sık görüldü.'
                      : '${actB.name} occurred $pctIncrease% more often on days with ${actA.name}.',
                  changeRatio: ratio,
                  type: CorrelationType.warning,
                  coOccurrenceCount: nAandB,
                  totalPrimaryDays: nA,
                ),
              );
            } else if (ratio <= 0.65 && nNotAandB >= 2) {
              final pctDecrease = ((1.0 - ratio) * 100).round();
              insights.add(
                CorrelationInsight(
                  primaryActivityId: actAId,
                  relatedActivityId: actBId,
                  title: isTr ? '${actA.name} ➔ ${actB.name} Azaltıcı' : '${actA.name} ➔ ${actB.name} Relief',
                  description: isTr
                      ? '${actA.name} yapılan günlerde ${actB.name} belirtisi %$pctDecrease daha az kaydedildi.'
                      : '${actB.name} was $pctDecrease% less frequent on days with ${actA.name}.',
                  changeRatio: ratio,
                  type: CorrelationType.positive,
                  coOccurrenceCount: nAandB,
                  totalPrimaryDays: nA,
                ),
              );
            }
          }
        } else if (!isASymptom && !isBSymptom) {
          // İki alışkanlık arasındaki rutin birlikteliği (Co-occurrence)
          if (!processedPairs.contains(pairKey)) {
            if (pBGivenA >= 0.65 && nAandB >= 2) {
              final pct = (pBGivenA * 100).round();
              insights.add(
                CorrelationInsight(
                  primaryActivityId: actAId,
                  relatedActivityId: actBId,
                  title: isTr ? '${actA.name} + ${actB.name} Uyumu' : '${actA.name} + ${actB.name} Synergy',
                  description: isTr
                      ? '${actA.name} yaptığın günlerin %$pct\'inde ${actB.name} da yaptın.'
                      : 'On $pct% of days with ${actA.name}, you also logged ${actB.name}.',
                  changeRatio: pBGivenA,
                  type: CorrelationType.positive,
                  coOccurrenceCount: nAandB,
                  totalPrimaryDays: nA,
                ),
              );
              processedPairs.add(pairKey);
            }
          }
        }
      }
    }

    // Önce uyarılar (tetikleyiciler), sonra koruyucular ve alışkanlık uyumları
    insights.sort((a, b) {
      if (a.type == CorrelationType.warning && b.type != CorrelationType.warning) return -1;
      if (b.type == CorrelationType.warning && a.type != CorrelationType.warning) return 1;
      return b.coOccurrenceCount.compareTo(a.coOccurrenceCount);
    });

    return insights.take(6).toList();
  }
}
