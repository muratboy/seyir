import 'dart:math';

import '../data/models.dart';
import 'format.dart';

/// Bir aktivitenin veya olayın geçmiş kayıtlarına göre ritmi (sıklığı),
/// son yapılma zamanı ve son 30 günün aktiflik dizisi.
class ActivityRhythm {
  /// Son 30 günün aktiflik dizisi: 0 indeksi 29 gün öncesi, 29 indeksi bugündür.
  final List<bool> last30Days;

  /// Bu aktivitenin son 30 gündeki aktif gün sayısı.
  final int activeDaysCount;

  /// Aktivitenin genel ritmi: "ortalama 5 günde bir", "günde ortalama 2 kez", vb.
  final String cadenceText;

  /// Son kaydın zamanı: "Son: Bugün 14:00", "Son: Dün", "Son: 3 gün önce", vb.
  final String? lastTimeText;

  const ActivityRhythm({
    required this.last30Days,
    required this.activeDaysCount,
    required this.cadenceText,
    required this.lastTimeText,
  });

  /// [entries] aktivitenin kayıtlarıdır.
  factory ActivityRhythm.compute({
    required Iterable<Entry> entries,
    required DateTime now,
    required bool isTr,
  }) {
    final entryList = entries.toList()..sort((a, b) => a.ts.compareTo(b.ts));
    final todayStart = dayStart(now);
    final day30Ago = subDays(todayStart, 29);

    final activeDays = <String>{};
    DateTime? lastEntryTime;

    for (final e in entryList) {
      final t = e.time;
      if (!t.isBefore(day30Ago) && !t.isAfter(dayEnd(now))) {
        activeDays.add(dayKey(t));
      }
      if (lastEntryTime == null || t.isAfter(lastEntryTime)) {
        lastEntryTime = t;
      }
    }

    final last30Days = <bool>[
      for (var i = 0; i < 30; i++) activeDays.contains(dayKey(addDays(day30Ago, i))),
    ];
    final activeDaysCount = activeDays.length;

    // 1. Son Zaman Cümlesi
    String? lastTimeText;
    if (lastEntryTime != null) {
      final diffDays = calendarDaysBetween(dayStart(lastEntryTime), todayStart);
      lastTimeText = switch (diffDays) {
        0 => isTr ? 'Son: Bugün ${fmtTime(lastEntryTime)}' : 'Last: Today ${fmtTime(lastEntryTime)}',
        1 => isTr ? 'Son: Dün ${fmtTime(lastEntryTime)}' : 'Last: Yesterday ${fmtTime(lastEntryTime)}',
        < 7 => isTr ? 'Son: $diffDays gün önce' : 'Last: $diffDays days ago',
        _ => isTr ? 'Son: ${fmtDateShort(lastEntryTime, isTr: true)}' : 'Last: ${fmtDateShort(lastEntryTime, isTr: false)}',
      };
    }

    // 2. Ritim / Sıklık Hesabı
    String cadenceText;
    if (entryList.isEmpty) {
      cadenceText = isTr ? 'Kayıt yok' : 'No entries';
    } else if (entryList.length == 1) {
      cadenceText = isTr ? '1 kayıt' : '1 entry';
    } else {
      // Son 60 günde en az 2 kayıt varsa güncel ritmi öne al, yoksa tüm kayıt aralığına bak
      final sixtyDaysAgo = subDays(todayStart, 60);
      final recent = entryList.where((e) => !e.time.isBefore(sixtyDaysAgo)).toList();
      final sample = recent.length >= 2 ? recent : entryList;

      final firstTime = sample.first.time;
      final spanDays = max(1, calendarDaysBetween(dayStart(firstTime), todayStart) + 1);
      final count = sample.length;
      final daysPerEntry = spanDays / count;

      if (daysPerEntry < 0.8) {
        final perDay = count / spanDays;
        cadenceText = isTr ? 'günde ortalama ${fmtNum1(perDay)} kez' : 'avg ${fmtNum1(perDay)}x / day';
      } else if (daysPerEntry < 1.3) {
        cadenceText = isTr ? 'neredeyse her gün' : 'almost daily';
      } else if (daysPerEntry < 6.5) {
        final d = daysPerEntry.round();
        cadenceText = isTr ? 'ortalama $d günde bir' : 'avg every $d days';
      } else if (daysPerEntry < 25) {
        final w = (daysPerEntry / 7).round();
        cadenceText = w <= 1
            ? (isTr ? 'ortalama haftada bir' : 'avg weekly')
            : (isTr ? 'ortalama $w haftada bir' : 'avg every $w weeks');
      } else {
        final m = (daysPerEntry / 30).round();
        cadenceText = m <= 1
            ? (isTr ? 'ortalama ayda bir' : 'avg monthly')
            : (isTr ? 'ortalama $m ayda bir' : 'avg every $m months');
      }
    }

    return ActivityRhythm(
      last30Days: last30Days,
      activeDaysCount: activeDaysCount,
      cadenceText: cadenceText,
      lastTimeText: lastTimeText,
    );
  }
}
