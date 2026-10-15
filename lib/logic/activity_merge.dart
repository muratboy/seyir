import 'dart:math';

import '../data/models.dart';
import 'text_match.dart';

/// İki benzer aktivitenin birleştirilmesi için otomatik öneri adayı.
class ActivityMergeCandidate {
  final Activity from;
  final Activity into;
  final String reason;
  final double score;

  const ActivityMergeCandidate({
    required this.from,
    required this.into,
    required this.reason,
    required this.score,
  });
}

/// Birleştirme işleminin etkisini özetleyen veri yapısı.
class ActivityMergeImpact {
  final int fromEntriesCount;
  final int intoEntriesCount;
  final int linkedGoalsCount;
  final int activeTimersCount;
  final int roadmapStepsCount;

  const ActivityMergeImpact({
    required this.fromEntriesCount,
    required this.intoEntriesCount,
    required this.linkedGoalsCount,
    required this.activeTimersCount,
    required this.roadmapStepsCount,
  });

  int get totalEntriesAfter => fromEntriesCount + intoEntriesCount;
}

/// Verilen aktiviteler arasından benzer isimli ve birleştirilebilecek adayları bulur.
List<ActivityMergeCandidate> findMergeCandidates(
  Iterable<Activity> activities, {
  required int Function(int id) entryCountOf,
  required int Function(int id) goalCountOf,
  bool isTr = true,
}) {
  final list = activities.toList();
  final candidates = <ActivityMergeCandidate>[];
  final seenPairs = <String>{};

  for (var i = 0; i < list.length; i++) {
    for (var j = i + 1; j < list.length; j++) {
      final a = list[i];
      final b = list[j];
      if (a.id == b.id) continue;

      final pairKey = a.id < b.id ? '${a.id}_${b.id}' : '${b.id}_${a.id}';
      if (seenPairs.contains(pairKey)) continue;

      final normA = a.norm;
      final normB = b.norm;
      if (normA.isEmpty || normB.isEmpty) continue;

      double score = 0;
      String? reason;

      if (normA == normB) {
        score = 100;
        reason = isTr ? 'Birebir aynı isim (büyük/küçük harf farkı)' : 'Exact same name (case difference)';
      } else {
        final dist = levenshtein(normA, normB);
        final minLen = min(normA.length, normB.length);
        final maxLen = max(normA.length, normB.length);

        if (dist <= 2 && minLen >= 4) {
          score = 80.0 - dist * 10;
          reason = isTr ? 'Yazım benzerliği ($dist harf farkı)' : 'Typo similarity ($dist char diff)';
        } else if (normA.contains(normB) || normB.contains(normA)) {
          if (minLen >= 3) {
            score = 65.0 + (minLen / maxLen) * 15;
            reason = isTr ? 'Biri diğerinin adını içeriyor' : 'One contains the other';
          }
        }
      }

      if (score >= 60 && reason != null) {
        seenPairs.add(pairKey);

        // Hangi aktivite hedef (into), hangisi kaynak (from) olmalı?
        // Daha çok kaydı veya hedefi olan kalıcı (into) olsun, az olan aktarılsın (from).
        final aScore = entryCountOf(a.id) * 10 + goalCountOf(a.id) * 20 - a.createdAt ~/ 100000000;
        final bScore = entryCountOf(b.id) * 10 + goalCountOf(b.id) * 20 - b.createdAt ~/ 100000000;

        final from = aScore <= bScore ? a : b;
        final into = aScore <= bScore ? b : a;

        candidates.add(
          ActivityMergeCandidate(
            from: from,
            into: into,
            reason: reason,
            score: score,
          ),
        );
      }
    }
  }

  candidates.sort((x, y) => y.score.compareTo(x.score));
  return candidates;
}
