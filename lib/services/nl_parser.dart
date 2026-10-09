import '../data/models.dart';
import '../logic/text_match.dart';

enum NlActionType {
  addEntry,
  startStopwatch,
  startPomodoro,
  startCountdown,
}

class NlParseResult {
  final String rawText;
  final String activityName;
  final Activity? matchedActivity;
  final Measure? matchedMeasure;
  final double quantity;
  final NlActionType actionType;
  final int? targetMinutes;
  final double confidence; // 0.0 - 1.0

  const NlParseResult({
    required this.rawText,
    required this.activityName,
    this.matchedActivity,
    this.matchedMeasure,
    required this.quantity,
    required this.actionType,
    this.targetMinutes,
    required this.confidence,
  });

  String get summary {
    final act = matchedActivity?.name ?? activityName;
    if (actionType == NlActionType.startStopwatch) {
      return '$act için Kronometre başlat';
    }
    if (actionType == NlActionType.startPomodoro) {
      final mins = targetMinutes ?? 25;
      return '$act için $mins Dk Pomodoro başlat';
    }
    if (actionType == NlActionType.startCountdown) {
      final mins = targetMinutes ?? quantity.round();
      return '$act için $mins Dk Geri Sayım başlat';
    }
    final mName = matchedMeasure?.name ?? '';
    return '$quantity $mName $act'.trim();
  }
}

class NaturalLanguageParser {
  static const Map<String, double> _turkishWordNumbers = {
    'sıfır': 0,
    'sifir': 0,
    'yarım': 0.5,
    'yarim': 0.5,
    'buçuk': 0.5,
    'bucuk': 0.5,
    'çeyrek': 0.25,
    'ceyrek': 0.25,
    'bir': 1,
    'iki': 2,
    'üç': 3,
    'uc': 3,
    'dört': 4,
    'dort': 4,
    'beş': 5,
    'bes': 5,
    'altı': 6,
    'alti': 6,
    'yedi': 7,
    'sekiz': 8,
    'dokuz': 9,
    'on': 10,
    'onbir': 11,
    'oniki': 12,
    'onüç': 13,
    'onuc': 13,
    'ondört': 14,
    'ondort': 14,
    'onbeş': 15,
    'onbes': 15,
    'yirmi': 20,
    'yirmibeş': 25,
    'yirmibes': 25,
    'otuz': 30,
    'kırk': 40,
    'kirk': 40,
    'kırkbeş': 45,
    'kirkbes': 45,
    'elli': 50,
    'altmış': 60,
    'altmis': 60,
    'yetmiş': 70,
    'yetmis': 70,
    'seksen': 80,
    'doksan': 90,
    'yüz': 100,
    'yuz': 100,
  };

  static const List<String> _timerKeywords = [
    'kronometre',
    'kronometreyi',
    'sayac',
    'sayaç',
    'sayaci',
    'sayacı',
    'baslat',
    'başlat',
    'baslatir',
    'başlatır',
    'tut',
    'baslasin',
    'başlasın',
    'ac',
    'aç',
  ];

  static const List<String> _pomodoroKeywords = [
    'pomodoro',
    'pomodoroyu',
    'odaklanma',
    'odak',
  ];

  static const List<String> _countdownKeywords = [
    'geri sayim',
    'geri sayım',
    'geri sayimi',
    'geri sayımı',
    'alarm',
    'sure tut',
    'süre tut',
  ];

  static const List<String> _fillerWords = [
    'ictim',
    'içtim',
    'yedim',
    'yaptim',
    'yaptım',
    'okudum',
    'kostum',
    'koştum',
    'yurudum',
    'yürüdüm',
    'cozdum',
    'çözdüm',
    'ettim',
    'gittim',
    'aldim',
    'aldım',
    'tane',
    'defa',
    'kere',
    'adet',
  ];

  /// Parses natural Turkish input like:
  /// - "2 kupa filtre kahve"
  /// - "bir buçuk litre su"
  /// - "30 dakika ders çalışma kronometre"
  /// - "pomodoro kitap okuma"
  /// - "45 dk koşu"
  /// - "yarım saat yürüyüş"
  static NlParseResult parse(
    String input, {
    required List<Activity> activities,
    required List<Measure> measures,
  }) {
    final cleanInput = input.trim();
    if (cleanInput.isEmpty) {
      return const NlParseResult(
        rawText: '',
        activityName: '',
        quantity: 1,
        actionType: NlActionType.addEntry,
        confidence: 0,
      );
    }

    final lower = normalizeTr(cleanInput).toLowerCase();
    final words = lower.split(RegExp(r'\s+'));

    // 1. Detect Action Type
    NlActionType actionType = NlActionType.addEntry;
    int? targetMinutes;

    final isPomodoro = _pomodoroKeywords.any((k) => lower.contains(k));
    final isCountdown = _countdownKeywords.any((k) => lower.contains(k));
    final isTimer = _timerKeywords.any((k) => lower.contains(k));

    if (isPomodoro) {
      actionType = NlActionType.startPomodoro;
      targetMinutes = 25;
    } else if (isCountdown) {
      actionType = NlActionType.startCountdown;
    } else if (isTimer) {
      actionType = NlActionType.startStopwatch;
    }

    // 2. Parse Number / Quantity
    double quantity = 1.0;
    bool foundExplicitQty = false;

    // Check for "bir buçuk", "iki buçuk" etc.
    final bucukMatch = RegExp(r'(bir|iki|üç|uc|dört|dort|beş|bes|altı|alti|yedi|sekiz|dokuz|\d+)\s+(buçuk|bucuk)').firstMatch(lower);
    if (bucukMatch != null) {
      final baseStr = bucukMatch.group(1)!;
      final baseVal = double.tryParse(baseStr) ?? _turkishWordNumbers[baseStr] ?? 1.0;
      quantity = baseVal + 0.5;
      foundExplicitQty = true;
    } else {
      // Check for standalone numbers (digits)
      final digitMatch = RegExp(r'(\d+([.,]\d+)?)').firstMatch(lower);
      if (digitMatch != null) {
        final numStr = digitMatch.group(1)!.replaceAll(',', '.');
        final val = double.tryParse(numStr);
        if (val != null) {
          quantity = val;
          foundExplicitQty = true;
        }
      } else {
        // Check for words like "yarım", "çeyrek", "bir", "iki", "üç"
        for (final word in words) {
          if (_turkishWordNumbers.containsKey(word)) {
            quantity = _turkishWordNumbers[word]!;
            foundExplicitQty = true;
            break;
          }
        }
      }
    }

    // Check if time-based (e.g. 30 dakika / 45 dk / yarım saat)
    final isMinute = lower.contains('dakika') || lower.contains(' dk');
    final isHour = lower.contains('saat') || lower.contains(' sa');
    if (isMinute) {
      if (actionType == NlActionType.startCountdown || actionType == NlActionType.startPomodoro) {
        targetMinutes = quantity.round();
      }
    } else if (isHour) {
      if (actionType == NlActionType.startCountdown || actionType == NlActionType.startPomodoro) {
        targetMinutes = (quantity * 60).round();
      }
    }

    // 3. Find Measure
    Measure? matchedMeasure;
    for (final m in measures) {
      final mName = normalizeTr(m.name).toLowerCase();
      if (lower.contains(mName)) {
        matchedMeasure = m;
        break;
      }
    }

    // If measure not found by exact name, try common keywords
    if (matchedMeasure == null) {
      if (lower.contains('çay bardağı') || lower.contains('cay bardagi')) {
        matchedMeasure = measures.firstWhere((m) => m.name.toLowerCase().contains('çay'), orElse: () => measures.first);
      } else if (lower.contains('su bardağı') || lower.contains('su bardagi') || lower.contains('bardak')) {
        matchedMeasure = measures.firstWhere((m) => m.name.toLowerCase().contains('bardak'), orElse: () => measures.first);
      } else if (lower.contains('kupa')) {
        matchedMeasure = measures.firstWhere((m) => m.name.toLowerCase().contains('kupa'), orElse: () => measures.first);
      } else if (lower.contains('demlik')) {
        matchedMeasure = measures.firstWhere((m) => m.name.toLowerCase().contains('demlik'), orElse: () => measures.first);
      } else if (lower.contains('litre') || lower.contains(' lt')) {
        matchedMeasure = measures.firstWhere((m) => m.name.toLowerCase().contains('litre') || m.unitId == 'l', orElse: () => measures.first);
      }
    }

    // 4. Extract Activity Name by filtering out numbers, measures, timer triggers and fillers
    final remainingWords = <String>[];
    for (final rawW in words) {
      final w = rawW.replaceAll(RegExp(r'[^\wçğıöşüÇĞİÖŞÜ]'), '');
      if (w.isEmpty) continue;

      // Ignore digits
      if (double.tryParse(w.replaceAll(',', '.')) != null) continue;
      // Ignore Turkish number words
      if (_turkishWordNumbers.containsKey(w)) continue;
      // Ignore timer/action keywords
      if (_timerKeywords.contains(w) || _pomodoroKeywords.contains(w) || _countdownKeywords.contains(w)) continue;
      // Ignore fillers
      if (_fillerWords.contains(w)) continue;
      // Ignore measure name words
      if (matchedMeasure != null && normalizeTr(matchedMeasure.name).toLowerCase().contains(w)) continue;
      if (w == 'dakika' || w == 'dk' || w == 'saat' || w == 'sa' || w == 'saniye' || w == 'sn') continue;
      if (w == 'buçuk' || w == 'bucuk' || w == 'kadeh' || w == 'şişe' || w == 'kutu' || w == 'bardak' || w == 'kupa' || w == 'litre' || w == 'ml') continue;

      remainingWords.add(w);
    }

    String extractedActivity = remainingWords.join(' ').trim();
    if (extractedActivity.isEmpty) {
      extractedActivity = cleanInput;
    }

    // 5. Match with Existing Activities
    Activity? matchedActivity;
    double confidence = 0.5;

    // Exact match
    final exact = activities.where((a) => normalizeTr(a.name).toLowerCase() == normalizeTr(extractedActivity).toLowerCase()).firstOrNull;
    if (exact != null) {
      matchedActivity = exact;
      confidence = 1.0;
    } else {
      // Substring match
      final sub = activities.where((a) {
        final aNorm = normalizeTr(a.name).toLowerCase();
        final eNorm = normalizeTr(extractedActivity).toLowerCase();
        return aNorm.contains(eNorm) || eNorm.contains(aNorm);
      }).firstOrNull;

      if (sub != null) {
        matchedActivity = sub;
        confidence = 0.85;
      } else {
        // Word token overlap match
        for (final act in activities) {
          final actWords = normalizeTr(act.name).toLowerCase().split(' ');
          final hasOverlap = actWords.any((aw) => remainingWords.contains(aw));
          if (hasOverlap) {
            matchedActivity = act;
            confidence = 0.75;
            break;
          }
        }
      }
    }

    // Capitalize activity name if not matched
    final finalActivityName = matchedActivity?.name ?? trCapitalize(extractedActivity);

    // If still no measure, but activity has a default measure or only one measure
    if (matchedMeasure == null && matchedActivity != null) {
      // try default measure from store if available
    }

    return NlParseResult(
      rawText: cleanInput,
      activityName: finalActivityName,
      matchedActivity: matchedActivity,
      matchedMeasure: matchedMeasure,
      quantity: foundExplicitQty ? quantity : 1.0,
      actionType: actionType,
      targetMinutes: targetMinutes,
      confidence: confidence,
    );
  }
}
