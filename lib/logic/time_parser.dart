import 'package:intl/intl.dart';

import 'text_match.dart';

enum TemporalDirection {
  past,
  future,
}

class TimeParseResult {
  final DateTime dateTime;
  final bool hasExplicitDate;
  final bool hasExplicitTime;
  final bool isExplicitFuture;
  final bool isRelative;
  final String? dateKeyword;
  final String cleanedText;
  final String rawMatchedText;

  const TimeParseResult({
    required this.dateTime,
    this.hasExplicitDate = false,
    this.hasExplicitTime = false,
    this.isExplicitFuture = false,
    this.isRelative = false,
    this.dateKeyword,
    required this.cleanedText,
    this.rawMatchedText = '',
  });

  String? get dueDateString => hasExplicitDate ? DateFormat('yyyy-MM-dd').format(dateTime) : null;
}

class TimeParser {
  static const Map<String, int> _weekdays = {
    'pazartesi': 1,
    'monday': 1,
    'mon': 1,
    'salı': 2,
    'sali': 2,
    'tuesday': 2,
    'tue': 2,
    'çarşamba': 3,
    'carsamba': 3,
    'wednesday': 3,
    'wed': 3,
    'perşembe': 4,
    'persembe': 4,
    'thursday': 4,
    'thu': 4,
    'cuma': 5,
    'friday': 5,
    'fri': 5,
    'cumartesi': 6,
    'saturday': 6,
    'sat': 6,
    'pazar': 7,
    'sunday': 7,
    'sun': 7,
  };

  static const Map<String, double> _numberWords = {
    'yarım': 0.5,
    'yarim': 0.5,
    'buçuk': 0.5,
    'bucuk': 0.5,
    'çeyrek': 0.25,
    'ceyrek': 0.25,
    'bir': 1.0,
    'iki': 2.0,
    'üç': 3.0,
    'uc': 3.0,
    'dört': 4.0,
    'dort': 4.0,
    'beş': 5.0,
    'bes': 5.0,
    'altı': 6.0,
    'alti': 6.0,
    'yedi': 7.0,
    'sekiz': 8.0,
    'dokuz': 9.0,
    'on': 10.0,
    'onbir': 11.0,
    'oniki': 12.0,
    'on iki': 12.0,
    'yirmi': 20.0,
    'otuz': 30.0,
    'kırk': 40.0,
    'kirk': 40.0,
    'elli': 50.0,
    'altmış': 60.0,
    'altmis': 60.0,
    'half': 0.5,
    'quarter': 0.25,
    'one': 1.0,
    'two': 2.0,
    'three': 3.0,
    'four': 4.0,
    'five': 5.0,
    'six': 6.0,
    'seven': 7.0,
    'eight': 8.0,
    'nine': 9.0,
    'ten': 10.0,
    'twenty': 20.0,
    'thirty': 30.0,
  };

  /// Parses date and time from [input].
  /// [direction]: [TemporalDirection.past] for log entries, [TemporalDirection.future] for todos.
  /// [now]: Reference point in time.
  /// [fallbackDay]: Default calendar day if no date is mentioned (e.g. current open day in Günlük).
  static TimeParseResult parse(
    String input, {
    required TemporalDirection direction,
    DateTime? now,
    DateTime? fallbackDay,
  }) {
    final refNow = now ?? DateTime.now();
    final today = DateTime(refNow.year, refNow.month, refNow.day);
    final baseDay = fallbackDay != null
        ? DateTime(fallbackDay.year, fallbackDay.month, fallbackDay.day)
        : today;

    final trimmed = input.trim();
    if (trimmed.isEmpty) {
      return TimeParseResult(
        dateTime: refNow,
        cleanedText: '',
      );
    }

    String workingText = trimmed;
    final matchedTokens = <String>[];

    DateTime? detectedDate;
    String? matchedKeyword;
    bool hasExplicitDate = false;
    bool isExplicitFuture = false;
    bool isExplicitToday = false;

    // -------------------------------------------------------------
    // 1. Relative Time ("2 saat önce", "30 dk önce", "yarım saat önce", "az önce", "demin")
    // -------------------------------------------------------------
    final relRegex = RegExp(
      r'(^|\s)(?<val>\d+([.,]\d+)?|bir\s+buçuk|bir\s+bucuk|yarım|yarim|çeyrek|ceyrek|bir|iki|üç|uc|dört|dort|beş|bes|altı|alti|yedi|sekiz|dokuz|on|yirmi|otuz|half\s+an?|one|two|three)?\s*(?<unit>saat|sa|hour|hours|hr|hrs|dakika|dk|min|mins|minute|minutes)\s+(?<ago>önce|once|ago)($|\s)',
      caseSensitive: false,
    );

    final relMatch = relRegex.firstMatch(workingText);
    if (relMatch != null) {
      final valStr = relMatch.namedGroup('val')?.trim().toLowerCase();
      final unitStr = relMatch.namedGroup('unit')!.toLowerCase();
      final fullMatchStr = relMatch.group(0)!;

      double qty = 1.0;
      if (valStr != null && valStr.isNotEmpty) {
        if (valStr.contains('buçuk') || valStr.contains('bucuk')) {
          qty = 1.5;
        } else if (_numberWords.containsKey(valStr)) {
          qty = _numberWords[valStr]!;
        } else {
          qty = double.tryParse(valStr.replaceAll(',', '.')) ?? 1.0;
        }
      }

      int minutes = 0;
      if (unitStr.startsWith('sa') || unitStr.startsWith('h')) {
        minutes = (qty * 60).round();
      } else {
        minutes = qty.round();
      }

      final resolvedTime = refNow.subtract(Duration(minutes: minutes));
      workingText = _removeMatch(workingText, relMatch);
      matchedTokens.add(fullMatchStr.trim());

      return TimeParseResult(
        dateTime: resolvedTime,
        hasExplicitDate: false,
        hasExplicitTime: true,
        isRelative: true,
        dateKeyword: 'önce',
        cleanedText: _cleanText(workingText),
        rawMatchedText: matchedTokens.join(' '),
      );
    }

    // "az önce", "demin", "just now"
    final justNowRegex = RegExp(r'(^|\s)(az\s+önce|az\s+once|demin|just\s+now)($|\s)', caseSensitive: false);
    final jnMatch = justNowRegex.firstMatch(workingText);
    if (jnMatch != null) {
      final matchStr = jnMatch.group(2)!;
      workingText = _removeMatch(workingText, jnMatch);
      matchedTokens.add(matchStr);
      return TimeParseResult(
        dateTime: refNow,
        hasExplicitDate: false,
        hasExplicitTime: true,
        isRelative: true,
        dateKeyword: matchStr,
        cleanedText: _cleanText(workingText),
        rawMatchedText: matchedTokens.join(' '),
      );
    }

    // -------------------------------------------------------------
    // 2. Multi-word Date Expressions
    // -------------------------------------------------------------
    // "dünden önceki gün", "önceki gün", "evvelsi gün", "day before yesterday"
    final twoDaysAgoRegex = RegExp(
      r'(^|\s)(dünden\s+önceki\s+gün|dunden\s+onceki\s+gun|önceki\s+gün|onceki\s+gun|evvelsi\s+gün|evvelsi\s+gun|day\s+before\s+yesterday)($|\s)',
      caseSensitive: false,
    );
    final twoDaysAgoMatch = twoDaysAgoRegex.firstMatch(workingText);
    if (twoDaysAgoMatch != null) {
      detectedDate = today.subtract(const Duration(days: 2));
      matchedKeyword = twoDaysAgoMatch.group(2)!;
      hasExplicitDate = true;
      workingText = _removeMatch(workingText, twoDaysAgoMatch);
      matchedTokens.add(matchedKeyword);
    }

    // "öbür gün", "day after tomorrow"
    if (detectedDate == null) {
      final oburRegex = RegExp(r'(^|\s)(öbür\s+gün|obur\s+gun|oburgun|day\s+after\s+tomorrow)($|\s)', caseSensitive: false);
      final oburMatch = oburRegex.firstMatch(workingText);
      if (oburMatch != null) {
        detectedDate = today.add(const Duration(days: 2));
        matchedKeyword = oburMatch.group(2)!;
        hasExplicitDate = true;
        if (direction == TemporalDirection.past) {
          isExplicitFuture = true;
        }
        workingText = _removeMatch(workingText, oburMatch);
        matchedTokens.add(matchedKeyword);
      }
    }

    // "hafta sonu", "weekend"
    if (detectedDate == null) {
      final weekendRegex = RegExp(r'(^|\s)(hafta\s*sonu|haftasonu|weekend)($|\s)', caseSensitive: false);
      final weekendMatch = weekendRegex.firstMatch(workingText);
      if (weekendMatch != null) {
        final wd = today.weekday;
        if (direction == TemporalDirection.future) {
          final offset = (wd == 6 || wd == 7) ? 0 : (6 - wd);
          detectedDate = today.add(Duration(days: offset));
        } else {
          // past
          final offset = (wd == 6 || wd == 7) ? 0 : -(wd + 1); // last Saturday
          detectedDate = today.add(Duration(days: offset));
        }
        matchedKeyword = 'hafta sonu';
        hasExplicitDate = true;
        workingText = _removeMatch(workingText, weekendMatch);
        matchedTokens.add(matchedKeyword);
      }
    }

    // "haftaya", "next week"
    if (detectedDate == null) {
      final nextWeekRegex = RegExp(r'(^|\s)(haftaya|next\s+week)($|\s)', caseSensitive: false);
      final nwMatch = nextWeekRegex.firstMatch(workingText);
      if (nwMatch != null) {
        detectedDate = today.add(const Duration(days: 7));
        matchedKeyword = nwMatch.group(2)!;
        hasExplicitDate = true;
        if (direction == TemporalDirection.past) {
          isExplicitFuture = true;
        }
        workingText = _removeMatch(workingText, nwMatch);
        matchedTokens.add(matchedKeyword);
      }
    }

    // "geçen hafta", "last week"
    if (detectedDate == null) {
      final lastWeekRegex = RegExp(r'(^|\s)(geçen\s+hafta|gecen\s+hafta|last\s+week)($|\s)', caseSensitive: false);
      final lwMatch = lastWeekRegex.firstMatch(workingText);
      if (lwMatch != null) {
        detectedDate = today.subtract(const Duration(days: 7));
        matchedKeyword = lwMatch.group(2)!;
        hasExplicitDate = true;
        workingText = _removeMatch(workingText, lwMatch);
        matchedTokens.add(matchedKeyword);
      }
    }

    // "geçen [gün]", "last [day]" (e.g. "geçen cuma", "last friday")
    if (detectedDate == null) {
      final lastDayRegex = RegExp(
        r'(^|\s)(geçen|gecen|last)\s+(?<day>pazartesi|salı|sali|çarşamba|carsamba|perşembe|persembe|cuma|cumartesi|pazar|monday|tuesday|wednesday|thursday|friday|saturday|sunday)($|\s)',
        caseSensitive: false,
      );
      final ldMatch = lastDayRegex.firstMatch(workingText);
      if (ldMatch != null) {
        final dayStr = normalizeTr(ldMatch.namedGroup('day')!).toLowerCase();
        final targetWd = _weekdays[dayStr]!;
        final curWd = today.weekday;
        final pastDiff = curWd == targetWd
            ? 7
            : (curWd > targetWd ? curWd - targetWd : curWd + 7 - targetWd);
        detectedDate = today.subtract(Duration(days: pastDiff));
        matchedKeyword = ldMatch.group(0)!.trim();
        hasExplicitDate = true;
        workingText = _removeMatch(workingText, ldMatch);
        matchedTokens.add(matchedKeyword);
      }
    }

    // -------------------------------------------------------------
    // 3. Single-word Date Expressions
    // -------------------------------------------------------------
    if (detectedDate == null) {
      final words = workingText.split(RegExp(r'\s+'));
      final remainingWords = <String>[];

      for (var i = 0; i < words.length; i++) {
        final rawWord = words[i];
        final cleanWord = rawWord.replaceAll(RegExp(r'^[^\wçğıöşüÇĞİÖŞÜ]+|[^\wçğıöşüÇĞİÖŞÜ]+$'), '');
        final norm = normalizeTr(cleanWord).toLowerCase();

        if (detectedDate == null) {
          if (norm == 'dun' || norm == 'dün' || norm == 'yesterday') {
            detectedDate = today.subtract(const Duration(days: 1));
            matchedKeyword = 'dün';
            hasExplicitDate = true;
            matchedTokens.add(rawWord);
            continue;
          } else if (norm == 'bugun' || norm == 'bugün' || norm == 'today') {
            detectedDate = today;
            matchedKeyword = 'bugün';
            hasExplicitDate = true;
            isExplicitToday = true;
            matchedTokens.add(rawWord);
            continue;
          } else if (norm == 'yarin' || norm == 'yarın' || norm == 'tomorrow') {
            detectedDate = today.add(const Duration(days: 1));
            matchedKeyword = 'yarın';
            hasExplicitDate = true;
            if (direction == TemporalDirection.past) {
              isExplicitFuture = true;
            }
            matchedTokens.add(rawWord);
            continue;
          } else if (_weekdays.containsKey(norm)) {
            final targetWd = _weekdays[norm]!;
            final curWd = today.weekday;

            if (direction == TemporalDirection.future) {
              int offset;
              if (targetWd == curWd) {
                offset = 0;
              } else if (targetWd > curWd) {
                offset = targetWd - curWd;
              } else {
                offset = 7 - (curWd - targetWd);
              }
              detectedDate = today.add(Duration(days: offset));
            } else {
              // past: en yakın GEÇMİŞ gün. Bugünün adıysa bugün.
              int offset;
              if (targetWd == curWd) {
                offset = 0;
              } else if (targetWd < curWd) {
                offset = targetWd - curWd;
              } else {
                offset = (targetWd - curWd) - 7;
              }
              detectedDate = today.add(Duration(days: offset));
            }

            matchedKeyword = norm;
            hasExplicitDate = true;
            matchedTokens.add(rawWord);
            continue;
          }
        }
        remainingWords.add(rawWord);
      }
      workingText = remainingWords.join(' ');
    }

    // -------------------------------------------------------------
    // 4. Time of Day (Gün Bölümleri) & Specific Clock Hours
    // -------------------------------------------------------------
    int? resolvedHour;
    int? resolvedMinute;
    bool hasExplicitTime = false;
    bool hadNightMention = false;

    // Gün bölümleri:
    // sabah: 08:00, öğle/öğlen: 12:30, öğleden sonra: 15:00, akşam: 19:00, gece: 22:00
    // "gece" 1-5 arası saatle gelirse 01:00-05:00 olur.
    final partOfDayRegex = RegExp(
      r'(^|\s)(sabah|öğleden\s+sonra|ogleden\s+sonra|öğlen|oglen|öğle|ogle|akşam|aksam|gece|morning|afternoon|noon|midday|evening|night)(\s+(vakti|saatlerinde|zamanı|zamani))?($|\s)',
      caseSensitive: false,
    );

    final podMatch = partOfDayRegex.firstMatch(workingText);
    String? matchedPod;
    if (podMatch != null) {
      final podRaw = normalizeTr(podMatch.group(2)!).toLowerCase();
      matchedPod = podRaw;
      workingText = _removeMatch(workingText, podMatch);
      matchedTokens.add(podMatch.group(0)!.trim());

      if (podRaw.contains('gece') || podRaw.contains('night')) {
        hadNightMention = true;
        resolvedHour = 22;
        resolvedMinute = 0;
        hasExplicitTime = true;
      } else if (podRaw.contains('aksam') || podRaw.contains('evening')) {
        resolvedHour = 19;
        resolvedMinute = 0;
        hasExplicitTime = true;
      } else if (podRaw.contains('ogleden sonra') || podRaw.contains('afternoon')) {
        resolvedHour = 15;
        resolvedMinute = 0;
        hasExplicitTime = true;
      } else if (podRaw.contains('ogle') || podRaw.contains('noon') || podRaw.contains('midday')) {
        resolvedHour = 12;
        resolvedMinute = 30;
        hasExplicitTime = true;
      } else if (podRaw.contains('sabah') || podRaw.contains('morning')) {
        resolvedHour = 8;
        resolvedMinute = 0;
        hasExplicitTime = true;
      }
    }

    // Specific Clock Hours:
    // "saat 8'de", "saat 8", "saat 8:30", "14.30", "20:15'te", "saat sekizde", "saat iki buçukta"
    final clockRegex = RegExp(
      r"(^|\s)(saat\s+)?(?<h>\b\d{1,2}\b|bir|iki|üç|uc|dört|dort|beş|bes|altı|alti|yedi|sekiz|dokuz|on|onbir|oniki)(?<sep>[.:])?(?<m>\d{2}|buçuk|bucuk)?(\s*(bucuk|buçuk))?(\s*('?(de|da|te|ta|ye|ya|deki|daki|teki|taki)))?($|\s)",
      caseSensitive: false,
    );

    // Saat desenini ancak açıkça 'saat' geçiyorsa ya da ': .' ayırıcı veya 'de/da' eki varsa ara
    for (final m in clockRegex.allMatches(workingText)) {
      final hasSaatWord = m.group(2) != null;
      final sep = m.namedGroup('sep');
      final rawH = m.namedGroup('h')!;
      final rawM = m.namedGroup('m');
      final fullMatch = m.group(0)!;

      // Yanlışlıkla aktivite miktarını ("2 kahve") saat sanmamak için:
      // 'saat' sözcüğü yoksa, saat ayracı (':' ya da '.') veya belirgin ek (14'te, 20:15) olmalıdır.
      final hasColonOrDot = sep != null && (sep == ':' || sep == '.');
      final hasSuffix = RegExp(r"('?(de|da|te|ta|ye|ya))\b", caseSensitive: false).hasMatch(fullMatch);
      if (!hasSaatWord && !hasColonOrDot && !hasSuffix && matchedPod == null) {
        continue;
      }

      int? hVal;
      if (int.tryParse(rawH) != null) {
        hVal = int.parse(rawH);
      } else {
        final normH = normalizeTr(rawH).toLowerCase();
        hVal = _numberWords[normH]?.round();
      }

      if (hVal == null || hVal < 0 || hVal > 24) continue;

      int mVal = 0;
      if (rawM != null) {
        if (rawM == 'buçuk' || rawM == 'bucuk') {
          mVal = 30;
        } else {
          mVal = int.tryParse(rawM) ?? 0;
        }
      } else if (fullMatch.contains('buçuk') || fullMatch.contains('bucuk')) {
        mVal = 30;
      }

      // Gece kuralı: 1-5 arası saat gece ile gelirse 01:00-05:00
      if (hadNightMention && hVal >= 1 && hVal <= 5) {
        resolvedHour = hVal;
      } else if (hadNightMention && hVal >= 1 && hVal <= 11) {
        // "gece 10" -> 22
        resolvedHour = hVal + 12;
      } else if (matchedPod != null && matchedPod.contains('aksam') && hVal >= 1 && hVal <= 11) {
        // "akşam 7" -> 19
        resolvedHour = hVal + 12;
      } else if (matchedPod != null && matchedPod.contains('ogleden sonra') && hVal >= 1 && hVal <= 11) {
        // "öğleden sonra 3" -> 15
        resolvedHour = hVal + 12;
      } else if (hVal > 12) {
        resolvedHour = hVal;
      } else {
        // 12 saat belirsizliği (ambiguity):
        // Şimdiye en yakın GEÇMİŞ saat seçilir (past yönünde)
        if (direction == TemporalDirection.past) {
          final targetDay = detectedDate ?? baseDay;
          resolvedHour = _resolveClosestPastHour(hVal, mVal, targetDay, refNow);
        } else {
          resolvedHour = hVal;
        }
      }

      resolvedMinute = mVal;
      hasExplicitTime = true;
      workingText = _removeMatch(workingText, m);
      matchedTokens.add(fullMatch.trim());
      break;
    }

    // -------------------------------------------------------------
    // 5. Resolving Final DateTime & Future Rules
    // -------------------------------------------------------------
    final targetDate = detectedDate ?? baseDay;
    DateTime finalDateTime;

    if (hasExplicitTime) {
      final h = resolvedHour ?? 12;
      final m = resolvedMinute ?? 0;
      final candidate = DateTime(targetDate.year, targetDate.month, targetDate.day, h, m);

      // Gelecek zaman kontrolleri:
      if (detectedDate == null) {
        // Gün belirtilmemişse:
        // Eğer saat refNow'dan ilerideyse ve yön geçmişse:
        // Örtük gelecek bir önceki güne kayar: sabah 09:00'da "akşam" -> dün 19:00.
        if (direction == TemporalDirection.past && candidate.isAfter(refNow)) {
          final prevDay = targetDate.subtract(const Duration(days: 1));
          finalDateTime = DateTime(prevDay.year, prevDay.month, prevDay.day, h, m);
        } else {
          finalDateTime = candidate;
        }
      } else {
        // Açık gün belirtilmiş ("yarın", "bugün akşam" sabahken):
        if (direction == TemporalDirection.past) {
          if (isExplicitToday && candidate.isAfter(refNow)) {
            // Sabahken "bugün akşam" -> açık gelecek
            isExplicitFuture = true;
          }
        }
        finalDateTime = candidate;
      }
    } else if (hasExplicitDate) {
      // Saatsiz gün: "dün 2 kahve" -> o gün 12:00.
      finalDateTime = DateTime(targetDate.year, targetDate.month, targetDate.day, 12, 0);
    } else {
      // Hiçbir zaman ifadesi yoksa fallback (mevcut açık günün saati)
      finalDateTime = fallbackDay != null
          ? DateTime(fallbackDay.year, fallbackDay.month, fallbackDay.day, refNow.hour, refNow.minute)
          : refNow;
    }

    return TimeParseResult(
      dateTime: finalDateTime,
      hasExplicitDate: hasExplicitDate,
      hasExplicitTime: hasExplicitTime,
      isExplicitFuture: isExplicitFuture,
      dateKeyword: matchedKeyword,
      cleanedText: _cleanText(workingText),
      rawMatchedText: matchedTokens.join(' '),
    );
  }

  /// 12 saatlik belirsizlikte en yakın geçmiş saati seçer.
  /// Örn: 21:00'de "saat 8" -> 20:00 (1 saat önce, 08:00 ise 13 saat önce).
  /// Örn: 10:00'da "saat 8" -> 08:00 (2 saat önce, dün 20:00 ise 14 saat önce).
  static int _resolveClosestPastHour(int h, int m, DateTime targetDay, DateTime refNow) {
    if (h == 0 || h > 12) return h;

    final c1Hour = h == 12 ? 0 : h;
    final c2Hour = h == 12 ? 12 : h + 12;

    final dt1 = DateTime(targetDay.year, targetDay.month, targetDay.day, c1Hour, m);
    final dt2 = DateTime(targetDay.year, targetDay.month, targetDay.day, c2Hour, m);

    // İkisi de bugünün geçmişinde mi?
    final diff1 = refNow.difference(dt1).inMinutes;
    final diff2 = refNow.difference(dt2).inMinutes;

    if (diff1 >= 0 && diff2 >= 0) {
      // Hangisi daha yakın (farkı daha küçük)?
      return diff1 < diff2 ? c1Hour : c2Hour;
    } else if (diff1 >= 0) {
      return c1Hour;
    } else if (diff2 >= 0) {
      return c2Hour;
    } else {
      // İkisi de gelecekte (örn: saat 07:00 iken "saat 8" dendi)
      // Dünün adaylarına bak:
      final d1Yesterday = dt1.subtract(const Duration(days: 1));
      final d2Yesterday = dt2.subtract(const Duration(days: 1));
      final diffY1 = refNow.difference(d1Yesterday).inMinutes;
      final diffY2 = refNow.difference(d2Yesterday).inMinutes;
      return diffY1 < diffY2 ? c1Hour : c2Hour;
    }
  }

  static String _removeMatch(String text, Match m) {
    final start = m.start;
    final end = m.end;
    final before = text.substring(0, start);
    final after = text.substring(end);
    return '$before $after';
  }

  static String _cleanText(String text) => text
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll(RegExp(r'^[^\wçğıöşüÇĞİÖŞÜ]+|[^\wçğıöşüÇĞİÖŞÜ]+$'), '')
      .trim();
}
