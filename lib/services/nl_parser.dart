import 'dart:math';

import '../data/models.dart';
import '../logic/text_match.dart';
import '../logic/time_parser.dart';
import '../logic/todo_parser.dart';

enum NlActionType {
  addEntry,
  startStopwatch,
  startPomodoro,
  startCountdown,
}

sealed class ParsedItem {
  String get rawText;
}

class EntryParsedItem extends ParsedItem {
  @override
  final String rawText;
  final NlParseResult parseResult;
  final Activity? activity;
  final String activityName;
  final Measure? measure;
  final double quantity;
  final DateTime at;
  final DateTime? endAt;
  final bool hasExplicitTime;
  final bool hasExplicitDate;
  final bool isExplicitFuture;
  final bool isRelative;
  final String? timeKeyword;
  final bool isNewActivity;
  final ({String mode, int targetMs})? timerCommand;
  final List<Todo> willCompleteTodos;

  Todo? get willCompleteTodo => willCompleteTodos.firstOrNull;

  EntryParsedItem({
    required this.rawText,
    required this.parseResult,
    this.activity,
    required this.activityName,
    this.measure,
    required this.quantity,
    required this.at,
    this.endAt,
    this.hasExplicitTime = false,
    this.hasExplicitDate = false,
    this.isExplicitFuture = false,
    this.isRelative = false,
    this.timeKeyword,
    this.isNewActivity = false,
    this.timerCommand,
    Todo? willCompleteTodo,
    List<Todo>? willCompleteTodos,
  }) : willCompleteTodos = willCompleteTodos ?? (willCompleteTodo != null ? [willCompleteTodo] : const []);

  TodoParsedItem toTodoItem() {
    return TodoParsedItem(
      rawText: rawText,
      title: activity?.name ?? activityName,
      dueDate: at,
      dateKeyword: timeKeyword,
      suggestedActivity: activity,
      suggestedAmount: quantity > 0 ? quantity : null,
      suggestedUnit: measure?.unitId ?? measure?.name ?? activity?.name,
    );
  }

  EntryParsedItem copyWith({
    Activity? activity,
    String? activityName,
    Measure? measure,
    double? quantity,
    DateTime? at,
    DateTime? endAt,
    bool? hasExplicitTime,
    bool? hasExplicitDate,
    bool? isExplicitFuture,
    bool? isRelative,
    String? timeKeyword,
    bool? isNewActivity,
    Todo? willCompleteTodo,
    List<Todo>? willCompleteTodos,
  }) =>
      EntryParsedItem(
        rawText: rawText,
        parseResult: parseResult,
        activity: activity ?? this.activity,
        activityName: activityName ?? this.activityName,
        measure: measure ?? this.measure,
        quantity: quantity ?? this.quantity,
        at: at ?? this.at,
        endAt: endAt ?? this.endAt,
        hasExplicitTime: hasExplicitTime ?? this.hasExplicitTime,
        hasExplicitDate: hasExplicitDate ?? this.hasExplicitDate,
        isExplicitFuture: isExplicitFuture ?? this.isExplicitFuture,
        isRelative: isRelative ?? this.isRelative,
        timeKeyword: timeKeyword ?? this.timeKeyword,
        isNewActivity: isNewActivity ?? this.isNewActivity,
        timerCommand: timerCommand,
        willCompleteTodos: willCompleteTodos ?? (willCompleteTodo != null ? [willCompleteTodo] : this.willCompleteTodos),
      );
}

class TodoParsedItem extends ParsedItem {
  @override
  final String rawText;
  final String title;
  final DateTime? dueDate;
  final String? dateKeyword;
  final Activity? suggestedActivity;
  final double? suggestedAmount;
  final String? suggestedUnit;

  TodoParsedItem({
    required this.rawText,
    required this.title,
    this.dueDate,
    this.dateKeyword,
    this.suggestedActivity,
    this.suggestedAmount,
    this.suggestedUnit,
  });

  TodoParsedItem copyWith({
    String? title,
    DateTime? dueDate,
    String? dateKeyword,
    Activity? suggestedActivity,
    double? suggestedAmount,
    String? suggestedUnit,
  }) =>
      TodoParsedItem(
        rawText: rawText,
        title: title ?? this.title,
        dueDate: dueDate ?? this.dueDate,
        dateKeyword: dateKeyword ?? this.dateKeyword,
        suggestedActivity: suggestedActivity ?? this.suggestedActivity,
        suggestedAmount: suggestedAmount ?? this.suggestedAmount,
        suggestedUnit: suggestedUnit ?? this.suggestedUnit,
      );
}

class MultiParseResult {
  final String rawText;
  final bool isTodoMode;
  final List<ParsedItem> items;

  const MultiParseResult({
    required this.rawText,
    this.isTodoMode = false,
    required this.items,
  });

  List<EntryParsedItem> get entryItems => items.whereType<EntryParsedItem>().toList();
  List<TodoParsedItem> get todoItems => items.whereType<TodoParsedItem>().toList();
}

class NlParseResult {
  final String rawText;
  final String activityName;
  final Activity? matchedActivity;
  final Measure? matchedMeasure;
  final double quantity;
  final bool hasExplicitQuantity;
  final bool hasExplicitMeasure;
  final NlActionType actionType;
  final int? targetMinutes;
  final double confidence; // 0.0 - 1.0

  const NlParseResult({
    required this.rawText,
    required this.activityName,
    this.matchedActivity,
    this.matchedMeasure,
    required this.quantity,
    this.hasExplicitQuantity = false,
    this.hasExplicitMeasure = false,
    required this.actionType,
    this.targetMinutes,
    required this.confidence,
  });

  /// Sayaç komutuysa başlatılacak sayacın modu ve hedef süresi; kayıt ekleme ise null.
  /// Süresi söylenmeyen pomodoro 25 dakikadır, geri sayım ise miktarı dakika sayar.
  ({String mode, int targetMs})? get timerCommand => switch (actionType) {
        NlActionType.addEntry => null,
        NlActionType.startStopwatch => (mode: 'stopwatch', targetMs: 0),
        NlActionType.startPomodoro => (mode: 'pomodoro', targetMs: (targetMinutes ?? 25) * 60000),
        NlActionType.startCountdown => (
            mode: 'countdown',
            targetMs: max(1, targetMinutes ?? quantity.round()) * 60000,
          ),
      };

  String get summary => summaryIn(isTr: true);

  /// Ayrıştırmanın ne yapacağını anlatan kısa cümle.
  String summaryIn({required bool isTr}) {
    final act = matchedActivity?.name ?? activityName;
    final command = timerCommand;
    if (command != null) {
      final mins = command.targetMs ~/ 60000;
      return switch (command.mode) {
        'pomodoro' => isTr ? '$act için $mins Dk Pomodoro başlat' : 'Start a $mins min pomodoro for $act',
        'countdown' => isTr ? '$act için $mins Dk Geri Sayım başlat' : 'Start a $mins min countdown for $act',
        _ => isTr ? '$act için Kronometre başlat' : 'Start a stopwatch for $act',
      };
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
    'onaltı': 16,
    'onalti': 16,
    'onyedi': 17,
    'onsekiz': 18,
    'ondokuz': 19,
    'yirmi': 20,
    'yirmibir': 21,
    'yirmiiki': 22,
    'yirmibeş': 25,
    'yirmibes': 25,
    'otuz': 30,
    'otuzbeş': 35,
    'otuzbes': 35,
    'kırk': 40,
    'kirk': 40,
    'kırkbeş': 45,
    'kirkbes': 45,
    'elli': 50,
    'ellibeş': 55,
    'ellibes': 55,
    'altmış': 60,
    'altmis': 60,
    'yetmiş': 70,
    'yetmis': 70,
    'seksen': 80,
    'doksan': 90,
    'yüz': 100,
    'yuz': 100,
    'zero': 0,
    'half': 0.5,
    'quarter': 0.25,
    'one': 1,
    'two': 2,
    'three': 3,
    'four': 4,
    'five': 5,
    'six': 6,
    'seven': 7,
    'eight': 8,
    'nine': 9,
    'ten': 10,
    'eleven': 11,
    'twelve': 12,
    'thirteen': 13,
    'fourteen': 14,
    'fifteen': 15,
    'sixteen': 16,
    'seventeen': 17,
    'eighteen': 18,
    'nineteen': 19,
    'twenty': 20,
    'thirty': 30,
    'forty': 40,
    'fifty': 50,
    'sixty': 60,
    'seventy': 70,
    'eighty': 80,
    'ninety': 90,
    'hundred': 100,
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
    'stopwatch',
    'timer',
    'zamanlayıcı',
  ];

  /// Çekimli hâliyle yazılan komut fiilleri. Kök değil sözcüğün kendisi oldukları için ek almış hâlleri
  /// aranmaz: "açın" komuttur, "açınca" değildir. "tutar" bir tutarı da bildirdiğinden ("fatura tutar 500")
  /// yalnızca soru kalıbıyla komut sayılır.
  static const List<String> _timerVerbForms = [
    'açar',
    'açın',
    'açsana',
    'tutar mısın',
    'tutar mısınız',
  ];

  /// Yalnızca komut cümlelerinde atılan dolgu sözcükleri ("ders için kronometre açar mısın lütfen").
  /// Kayıt cümlesinde adın parçası olabilirler ("Sınav için çalışma").
  static const List<String> _commandFillers = ['icin', 'misin', 'misiniz', 'musun', 'musunuz', 'lutfen', 'please'];

  static const List<String> _pomodoroKeywords = [
    'pomodoro',
    'pomodoroyu',
    'odaklanma',
    'odak',
    'focus',
  ];

  static const List<String> _countdownKeywords = [
    'geri sayim',
    'geri sayım',
    'geri sayimi',
    'geri sayımı',
    'alarm',
    'sure tut',
    'süre tut',
    'countdown',
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
    'uyudum',
    'uyuduk',
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
    'sayfa',
    'page',
    'pages',
    'of',
    'for',
  ];

  /// Birim sözcükleri ve kimlikleri: "45 dk koşu", "2 saat ders", "30 min run".
  static const Map<String, String> _unitWords = {
    'sn': 'sn', 'saniye': 'sn', 'second': 'sn', 'seconds': 'sn',
    'dk': 'dk', 'dakika': 'dk', 'min': 'dk', 'mins': 'dk', 'minute': 'dk', 'minutes': 'dk',
    'sa': 'sa', 'saat': 'sa', 'h': 'sa', 'hr': 'sa', 'hrs': 'sa', 'hour': 'sa', 'hours': 'sa',
    'ml': 'ml', 'l': 'l', 'lt': 'l', 'litre': 'l', 'liter': 'l',
    'mg': 'mg', 'miligram': 'mg', 'milligram': 'mg',
    'g': 'g', 'gr': 'g', 'gram': 'g', 'kg': 'kg', 'kilo': 'kg',
    'km': 'km', 'kilometre': 'km', 'metre': 'm', 'kcal': 'kcal',
  };

  /// Yazıyla verilmiş bir birimin kimliği ("dakika", "min" -> "dk"); tanınmıyorsa null.
  static String? unitIdForWord(String word) => _unitWords[normalizeTr(word)];

  /// Sayıya yapışık yazılmış birimi ayırır ("45dk" -> "dk").
  static String _unitToken(String word) => word.replaceFirst(RegExp(r'^\d+([.,]\d+)?'), '');

  static const Map<String, String> _verbToActivityRoot = {
    'yurudum': 'yuru',
    'yuruduk': 'yuru',
    'yurumek': 'yuru',
    'yurume': 'yuru',
    'yürüdüm': 'yuru',
    'yürüdük': 'yuru',
    'yürümek': 'yuru',
    'yürüme': 'yuru',
    'kostum': 'kos',
    'kostuk': 'kos',
    'kosmak': 'kos',
    'kosma': 'kos',
    'koştum': 'kos',
    'koştuk': 'kos',
    'koşmak': 'kos',
    'koşma': 'kos',
    'uyudum': 'uyu',
    'uyuduk': 'uyu',
    'uyumak': 'uyu',
    'uyuma': 'uyu',
    'okudum': 'oku',
    'okuduk': 'oku',
    'okumak': 'oku',
    'okuma': 'oku',
    'ictim': 'ic',
    'içtim': 'ic',
    'yaptim': 'yap',
    'yaptım': 'yap',
  };

  /// Parses natural Turkish input like:
  /// - "2 kupa filtre kahve"
  /// - "bir buçuk litre su"
  /// - "30 dakika ders çalışma kronometre"
  /// - "pomodoro kitap okuma"
  /// - "45 dk koşu"
  /// - "yarım saat yürüyüş"
  ///
  /// [allowCommands] false ise metin yalnızca kayıt olarak okunur: "oruç tut" bir sayaç komutu değil,
  /// adında "tut" geçen bir kayıttır. Giriş kutusu, kullanıcı "kayıt olarak ekle" dediğinde bunu kullanır.
  static NlParseResult parse(
    String input, {
    required List<Activity> activities,
    required List<Measure> measures,
    bool allowCommands = true,
    Measure? Function(int activityId)? defaultMeasureFor,
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
    // Sözcükler hem özgün yazımıyla hem normalize edilmiş hâliyle tutulur; iki liste aynı sıradadır.
    // Eşleştirme normalize hâlle yapılır, yeni aktivitenin adı ise özgün yazımdan kurulur.
    final rawWords = cleanInput.split(RegExp(r'\s+'));
    final words = [
      for (final raw in rawWords) normalizeTr(raw).replaceAll(RegExp(r'[^\wçğıöşüÇĞİÖŞÜ]'), ''),
    ];

    // 1. Detect Action Type
    NlActionType actionType = NlActionType.addEntry;
    int? targetMinutes;

    final pomodoroWords = allowCommands ? _keywordHits(words, _pomodoroKeywords) : <int>{};
    final countdownWords = allowCommands ? _keywordHits(words, _countdownKeywords) : <int>{};
    final timerWords = allowCommands
        ? {..._keywordHits(words, _timerKeywords), ..._keywordHits(words, _timerVerbForms, exact: true)}
        : <int>{};
    final inNames = _wordsInsideActivityNames(words, {...pomodoroWords, ...countdownWords, ...timerWords}, activities);
    pomodoroWords.removeAll(inNames);
    countdownWords.removeAll(inNames);
    timerWords.removeAll(inNames);
    final commandWords = {...pomodoroWords, ...countdownWords, ...timerWords};

    if (pomodoroWords.isNotEmpty) {
      actionType = NlActionType.startPomodoro;
      targetMinutes = 25;
    } else if (countdownWords.isNotEmpty) {
      actionType = NlActionType.startCountdown;
    } else if (timerWords.isNotEmpty) {
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
      // Check for compound numbers: "yirmi iki", "on bir", "twenty five" etc.
      final compoundMatch = RegExp(
        r'\b(on|yirmi|otuz|kırk|kirk|elli|altmış|altmis|yetmiş|yetmis|seksen|doksan|twenty|thirty|forty|fifty)\s+(bir|iki|üç|uc|dört|dort|beş|bes|altı|alti|yedi|sekiz|dokuz|one|two|three|four|five|six|seven|eight|nine)\b',
      ).firstMatch(lower);
      if (compoundMatch != null) {
        final tens = _turkishWordNumbers[compoundMatch.group(1)!] ?? 0.0;
        final ones = _turkishWordNumbers[compoundMatch.group(2)!] ?? 0.0;
        quantity = tens + ones;
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
    }

    // Check if time-based (e.g. 30 dakika / 45 dk / yarım saat). Birim sayıya yapışık ya da ekli de
    // yazılabilir ("45dakika", "45 dk'lık", "1saat"); yalnızca "sa" kısaltması tam sözcük olmalıdır,
    // yoksa "sabah" gibi sözcükler saat sanılır.
    final isMinute =
        words.any((w) => w.contains('dakika') || w.startsWith('dk') || _unitWords[_unitToken(w)] == 'dk');
    final isHour = words.any((w) => w.contains('saat') || _unitWords[_unitToken(w)] == 'sa');
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
    final (matchedMeasure, measureWords) = _findMeasure(words, lower, measures);

    // 4. Extract Activity Name by filtering out numbers, measures, timer triggers and fillers
    final remainingWords = <String>[];
    final remainingRawWords = <String>[];
    for (var i = 0; i < words.length; i++) {
      final w = words[i];
      if (w.isEmpty) continue;

      // Ignore digits
      if (double.tryParse(w.replaceAll(',', '.')) != null) continue;
      // Ignore Turkish number words
      if (_turkishWordNumbers.containsKey(w)) continue;
      // Ignore timer/action keywords
      if (commandWords.contains(i)) continue;
      // Ignore fillers
      if (_fillerWords.contains(w)) continue;
      if (commandWords.isNotEmpty && _commandFillers.contains(w)) continue;
      // Ignore measure name words
      if (measureWords.contains(i)) continue;
      // Ignore unit words ("dk", "45dk", "min")
      if (_unitWords.containsKey(_unitToken(w))) continue;
      if (w == 'buçuk' || w == 'bucuk' || w == 'kadeh' || w == 'şişe' || w == 'kutu' || w == 'bardak' || w == 'kupa' || w == 'litre' || w == 'ml') continue;

      remainingWords.add(w);
      final raw = rawWords[i].replaceAll(_edgePunctuation, '');
      remainingRawWords.add(raw.isEmpty ? rawWords[i] : raw);
    }

    String extractedActivity = remainingWords.join(' ').trim();

    // 5. Match with Existing Activities
    var (matchedActivity, confidence) = _matchActivity(extractedActivity, remainingWords, activities);

    // Fiil çekimleri ve kök eşleşmesi yalnızca geriye başka bir isim kalmadığında çalışır (örn: "30 dk yurudum" -> Yürüyüş)
    if (matchedActivity == null && (remainingWords.isEmpty || remainingWords.every((w) => _verbToActivityRoot.containsKey(w)))) {
      for (final w in words) {
        final root = _verbToActivityRoot[w];
        if (root != null) {
          final found = activities.where((a) {
            final an = normalizeTr(a.name).toLowerCase();
            return an.startsWith(root) ||
                   (root == 'yuru' && an.contains('yuru')) ||
                   (root == 'kos' && an.contains('kos')) ||
                   (root == 'uyu' && an.contains('uyku')) ||
                   (root == 'oku' && (an.contains('kitap') || an.contains('oku')));
          }).firstOrNull;
          if (found != null) {
            matchedActivity = found;
            confidence = 0.9;
            break;
          }
        }
      }
    }

    // Yeni aktivite adı özgün yazımdan kurulur; normalize hâl "Çay"ı "Cay" olarak kaydederdi.
    String finalActivityName;
    if (matchedActivity != null) {
      finalActivityName = matchedActivity.name;
    } else {
      final newActivityName = remainingRawWords.isNotEmpty
          ? remainingRawWords.join(' ')
          : cleanInput;
      finalActivityName = trCapitalize(newActivityName);
    }

    // Ölçü belirtilmemişse ve aktivite biliniyorsa varsayılan ölçü kullanılır
    var effectiveMeasure = matchedMeasure;
    if (effectiveMeasure == null && matchedActivity != null && defaultMeasureFor != null) {
      effectiveMeasure = defaultMeasureFor(matchedActivity.id);
    }

    return NlParseResult(
      rawText: cleanInput,
      activityName: finalActivityName,
      matchedActivity: matchedActivity,
      matchedMeasure: effectiveMeasure,
      quantity: foundExplicitQty ? quantity : 1.0,
      hasExplicitQuantity: foundExplicitQty,
      hasExplicitMeasure: matchedMeasure != null,
      actionType: actionType,
      targetMinutes: targetMinutes,
      confidence: confidence,
    );
  }

  static final _edgePunctuation = RegExp(r'^[^\p{L}\p{N}]+|[^\p{L}\p{N}]+$', unicode: true);

  /// [words] içinde komut anahtar kelimelerine denk gelen sözcüklerin indeksleri.
  /// Metnin tamamında alt dizgi aramak "ilaç" içindeki "aç"ı ya da "tütün" içindeki "tut"u komut sanıyordu;
  /// bu yüzden anahtar kelimeler sözcük sözcük (çok kelimeliler ardışık sözcüklerle) karşılaştırılır.
  /// [exact] ise anahtar kelimeler ek almış hâlleriyle aranmaz.
  static Set<int> _keywordHits(List<String> words, List<String> keywords, {bool exact = false}) {
    final hits = <int>{};
    for (final keyword in keywords) {
      final parts = normalizeTr(keyword).split(' ');
      // Tek başına duran kısa kökler ("aç", "tut") ek alınca "açık", "tutku" gibi ilgisiz sözcüklerle
      // karışır. Kök yeterince uzunsa ("odak") ya da önünde başka bir sözcük varsa ("süre tut") karışmaz.
      final suffixAllowed = !exact && (parts.length > 1 || parts.last.length >= 4);
      for (var i = 0; i + parts.length <= words.length; i++) {
        var matches = true;
        for (var j = 0; j < parts.length && matches; j++) {
          matches = _isKeyword(words[i + j], parts[j], allowSuffix: suffixAllowed && j == parts.length - 1);
        }
        if (matches) {
          for (var j = 0; j < parts.length; j++) {
            hits.add(i + j);
          }
        }
      }
    }
    return hits;
  }

  /// Komut sözcüklerinden ([commandWords]) kayıtlı bir aktivitenin adının parçası olanların indeksleri.
  /// "Sayaç okuma" ya da "Not tut" adlı bir aktivite varken adını yazmak sayaç başlatmamalıdır: ad metinde
  /// bütünüyle geçiyorsa içindeki sözcükler komut değil addır. Adı yalnızca komut sözcüğünden oluşan
  /// aktivite ("Pomodoro") bunun dışındadır; yoksa "pomodoro" yazmak bir daha sayaç başlatamazdı.
  static Set<int> _wordsInsideActivityNames(List<String> words, Set<int> commandWords, List<Activity> activities) {
    final inside = <int>{};
    if (commandWords.isEmpty) return inside;
    for (final a in activities) {
      final nameWords = a.norm.split(' ');
      final at = _phraseIndex(words, nameWords);
      if (at == -1) continue;
      final covered = {for (var i = 0; i < nameWords.length; i++) at + i};
      if (covered.any(commandWords.contains) && !covered.every(commandWords.contains)) inside.addAll(covered);
    }
    return inside;
  }

  /// [allowSuffix] ise sözcük çekim eki almış olabilir ("kronometreyi", "odaklan", "süre tutar mısın").
  static bool _isKeyword(String word, String keyword, {required bool allowSuffix}) =>
      word == keyword || (allowSuffix && word.startsWith(keyword));

  /// Metindeki ölçüyü ve onu ifade eden sözcüklerin indekslerini bulur. Ölçü adları sözcük olarak aranır:
  /// alt dizgi aramak "program"daki "gram"ı, "kaset"teki "kase"yi ölçü sanıyordu.
  static (Measure?, Set<int>) _findMeasure(List<String> words, String lower, List<Measure> measures) {
    if (measures.isEmpty) return (null, const {});
    Set<int> indicesWhere(bool Function(String word) test) => {
          for (var i = 0; i < words.length; i++)
            if (test(words[i])) i,
        };

    // 1. Ölçünün adı metinde geçiyor ("2 su bardağı su"); en uzun ad kazanır.
    Measure? named;
    var namedAt = const <int>{};
    var namedLength = 0;
    for (final m in measures) {
      final name = normalizeTr(m.name);
      final nameWords = name.split(' ');
      final at = _phraseIndex(words, nameWords);
      if (at != -1 && name.length > namedLength) {
        named = m;
        namedLength = name.length;
        namedAt = {for (var i = 0; i < nameWords.length; i++) at + i};
      }
    }
    if (named != null) return (named, namedAt);

    // 2. Yaygın anahtar kelimeler ve eş anlamlılar üzerinden güvenli arama (firstOrNull)
    Measure? byName(String part) => measures.where((m) => normalizeTr(m.name).contains(part)).firstOrNull;
    if (lower.contains('cay bardagi')) {
      return (byName('cay'), indicesWhere((w) => w == 'cay' || w.startsWith('bardag')));
    } else if (lower.contains('su bardagi') || words.any((w) => w.startsWith('bardak') || w.startsWith('bardag'))) {
      // Yalın "bardak": çay içiliyorsa çay bardağı, değilse su bardağı. Ölçü adlarında sözcük yumuşamış
      // hâliyle geçer ("Su bardağı"); "bardak" diye aramak onları bulmuyordu.
      final glass = (words.contains('cay') ? byName('cay bardag') : null) ??
          byName('su bardag') ??
          byName('bardak') ??
          byName('bardag');
      return (glass, indicesWhere((w) => w.startsWith('bardak') || w.startsWith('bardag')));
    } else if (words.any((w) => w.startsWith('kupa'))) {
      return (byName('kupa'), indicesWhere((w) => w.startsWith('kupa')));
    } else if (words.any((w) => w.startsWith('demlik'))) {
      return (byName('demlik'), indicesWhere((w) => w.startsWith('demlik')));
    }

    // 3. Birim sözcüğü ("45 dk", "30 min", "5 km"): o birimin 1'lik ölçüsü. Başka miktarlı bir ölçü
    // ("Ders saati = 40 dk") seçilirse sayı onunla çarpılırdı.
    for (var i = 0; i < words.length; i++) {
      final unitId = _unitWords[_unitToken(words[i])];
      if (unitId == null) continue;
      final measure = measures.where((m) => m.unitId == unitId && m.amount == 1).firstOrNull;
      if (measure != null) return (measure, {i});
    }

    return (null, const {});
  }

  /// Ayıklanan aktivite adını mevcut aktiviteler ile eşleştirir (tam, alt dize veya kelime çakışması).
  /// Çıkarılan metni kayıtlı bir aktiviteye bağlar. Karşılaştırma sözcük sözcük yapılır: alt dizgi aramak
  /// "sucuk"u "Su"ya bağlayıp kaydı sessizce yanlış aktiviteye yazıyordu.
  static (Activity?, double) _matchActivity(
    String extractedActivity,
    List<String> remainingWords,
    List<Activity> activities,
  ) {
    if (activities.isEmpty || extractedActivity.isEmpty) {
      return (null, 0.5);
    }

    final eNorm = normalizeTr(extractedActivity);
    final textWords = eNorm.split(' ');

    // 1. Tam ad eşleşmesi
    final exact = activities.where((a) => normalizeTr(a.name) == eNorm).firstOrNull;
    if (exact != null) {
      return (exact, 1.0);
    }

    // 2. Aktivitenin adı metinde sözcük olarak geçiyor ("kahvemi içtim" -> "Kahve"); en uzun ad kazanır.
    Activity? contained;
    var containedLength = 0;
    for (final a in activities) {
      final name = normalizeTr(a.name);
      if (name.length > containedLength && _containsPhrase(textWords, name.split(' '))) {
        contained = a;
        containedLength = name.length;
      }
    }
    if (contained != null) {
      return (contained, 0.85);
    }

    // 3. Yazılan, daha uzun bir adın ilk sözcükleri ("kitap" -> "Kitap okuma")
    final prefixed =
        activities.where((a) => _startsWithWords(normalizeTr(a.name).split(' '), textWords)).firstOrNull;
    if (prefixed != null) {
      return (prefixed, 0.85);
    }

    // 4. Yazılan sözcüklerin hepsi adın içinde ("çalışma" -> "Ders çalışma"). Fazladan bir sözcük
    // ("matematik çalışma") başka bir aktivite demektir.
    if (remainingWords.isNotEmpty) {
      for (final act in activities) {
        final actWords = normalizeTr(act.name).split(' ');
        if (remainingWords.every(actWords.contains)) {
          return (act, 0.75);
        }
      }
    }

    return (null, 0.5);
  }

  static bool _startsWithWords(List<String> nameWords, List<String> textWords) {
    if (textWords.length >= nameWords.length) return false;
    for (var i = 0; i < textWords.length; i++) {
      if (nameWords[i] != textWords[i]) return false;
    }
    return true;
  }

  static bool _containsPhrase(List<String> textWords, List<String> nameWords) =>
      _phraseIndex(textWords, nameWords) != -1;

  /// Bir adın sonuna gelebilen yaygın çekim ekleri (Türkçe harfler sadeleştirilmiş hâliyle).
  static const Set<String> _caseSuffixes = {
    'a', 'e', 'i', 'u', 'm', 'n',
    'yi', 'yu', 'ya', 'ye', 'da', 'de', 'ta', 'te', 'in', 'un', 'im', 'um', 'si', 'su', 'li', 'lu', 'ni', 'nu',
    'mi', 'mu', 'dan', 'den', 'tan', 'ten', 'lar', 'ler', 'nin', 'nun', 'yla', 'yle', 'lik', 'luk', 'ini',
    'unu', 'ina', 'una', 'imi', 'umu',
  };

  /// [nameWords] metnin içinde art arda geçiyorsa başladığı indeks, yoksa -1. Son sözcük bir çekim eki
  /// almış olabilir ("su" -> "suyu", "kahve" -> "kahvemi"); ek olmayan bir devam ise başka bir sözcüktür
  /// ("su" -> "sucuk", "kase" -> "kaset").
  static int _phraseIndex(List<String> textWords, List<String> nameWords) {
    final n = nameWords.length;
    for (var i = 0; i + n <= textWords.length; i++) {
      var matches = true;
      for (var j = 0; j < n && matches; j++) {
        final word = textWords[i + j];
        final name = nameWords[j];
        if (j < n - 1) {
          matches = word == name;
        } else {
          matches = word == name || (word.startsWith(name) && _caseSuffixes.contains(word.substring(name.length)));
        }
      }
      if (matches) return i;
    }
    return -1;
  }

  /// Girdiyi güçlü ve zayıf ayırıcılarla parçalara böler.
  /// - Güçlü: "ve", ",", ";", "ayrıca", " + ", "and".
  /// - Zayıf: "sonra", "daha sonra", "then" (yalnızca iki taraf da kayıtlı aktiviteye uyuyorsa).
  /// - Bölünmeyen yerler: Aktivite adlarının içi, rakam arası virgül ("1,5 l").
  static List<String> splitSentence(
    String input, {
    required List<Activity> activities,
    required List<Measure> measures,
  }) {
    final cleanInput = input.trim();
    if (cleanInput.isEmpty) return const [];

    // 1. Bölünmesi yasak olan aralıkları belirle [start, end)
    final protectedRanges = <(int, int)>[];

    // Rakam arası virgül ("1,5 l", "0,5 kg")
    for (final m in RegExp(r'\d+,\d+').allMatches(cleanInput)) {
      protectedRanges.add((m.start, m.end));
    }

    // Bilinen aktivite adları (en uzun olanlar önce)
    final sortedActs = List.of(activities)..sort((a, b) => b.name.length.compareTo(a.name.length));
    final lowerNorm = normalizeTr(cleanInput).toLowerCase();

    for (final act in sortedActs) {
      if (act.name.trim().isEmpty) continue;
      final actNorm = normalizeTr(act.name).toLowerCase();
      // Yalnızca ayırıcı sözcük içeren adlar aralık korur ("Yoga ve meditasyon" gibi)
      if (!actNorm.contains('ve') &&
          !actNorm.contains(',') &&
          !actNorm.contains(';') &&
          !actNorm.contains('and') &&
          !actNorm.contains('+') &&
          !actNorm.contains('sonra') &&
          !actNorm.contains('then')) {
        continue;
      }

      int startIdx = 0;
      while (startIdx < lowerNorm.length) {
        final at = lowerNorm.indexOf(actNorm, startIdx);
        if (at == -1) break;
        protectedRanges.add((at, at + actNorm.length));
        startIdx = at + actNorm.length;
      }
    }

    bool isProtected(int index) {
      for (final (start, end) in protectedRanges) {
        if (index >= start && index < end) return true;
      }
      return false;
    }

    // 2. Güçlü ayırıcılar
    final strongSeparatorRegex = RegExp(
      r'(?<sep>,|;|\s*\+\s+|\b(ve|ayrıca|ayrica|and)\b)',
      caseSensitive: false,
    );

    final splitPoints = <(int, int)>[];
    for (final m in strongSeparatorRegex.allMatches(cleanInput)) {
      if (!isProtected(m.start)) {
        splitPoints.add((m.start, m.end));
      }
    }

    final strongChunks = <String>[];
    int lastEnd = 0;
    for (final (start, end) in splitPoints) {
      final chunk = cleanInput.substring(lastEnd, start).trim();
      if (chunk.isNotEmpty) {
        strongChunks.add(chunk);
      }
      lastEnd = end;
    }
    final finalChunk = cleanInput.substring(lastEnd).trim();
    if (finalChunk.isNotEmpty) {
      strongChunks.add(finalChunk);
    }

    if (strongChunks.isEmpty) {
      strongChunks.add(cleanInput);
    }

    // 3. Zayıf ayırıcılar ("sonra", "daha sonra", "then")
    final weakSeparatorRegex = RegExp(
      r'\b(daha\s+sonra|sonra|then)\b',
      caseSensitive: false,
    );

    final finalPieces = <String>[];
    for (final chunk in strongChunks) {
      final weakMatches = weakSeparatorRegex.allMatches(chunk).toList();
      if (weakMatches.isEmpty) {
        finalPieces.add(chunk);
        continue;
      }

      bool didSplit = false;
      for (final wm in weakMatches) {
        if (isProtected(wm.start)) continue;
        final left = chunk.substring(0, wm.start).trim();
        final right = chunk.substring(wm.end).trim();
        if (left.isEmpty || right.isEmpty) continue;

        final leftParse = parse(left, activities: activities, measures: measures, allowCommands: false);
        final rightParse = parse(right, activities: activities, measures: measures, allowCommands: false);

        if (leftParse.matchedActivity != null && rightParse.matchedActivity != null) {
          finalPieces.add(left);
          finalPieces.add(right);
          didSplit = true;
          break;
        }
      }

      if (!didSplit) {
        finalPieces.add(chunk);
      }
    }

    return finalPieces;
  }

  /// Yapılacak kipini ve olası baştaki tarih kelimesini tespit eder.
  static (bool isTodo, String? prefixDateKeyword, String content) _detectTodoMode(
    String input, {
    DateTime? now,
  }) {
    final trimmed = input.trim();

    // 1. "yapılacak", "yapilacak", "todo", "to-do" (iki noktalı veya iki noktasız)
    final todoPrefixRegex = RegExp(
      r'^(yapılacak|yapilacak|todo|to-do)(\s*:|\s+)',
      caseSensitive: false,
    );
    final match = todoPrefixRegex.firstMatch(trimmed);
    if (match != null) {
      final content = trimmed.substring(match.end).trim();
      return (true, null, content);
    }

    // 2. Bir tarih kelimesi ve iki nokta: "yarın: dişçiyi ara", "cuma: fatura"
    final dateColonRegex = RegExp(
      r'^(?<date>bugün|bugun|dün|dun|yarın|yarin|öbür\s+gün|obur\s+gun|haftaya|hafta\s*sonu|haftasonu|pazartesi|salı|sali|çarşamba|carsamba|perşembe|persembe|cuma|cumartesi|pazar|today|yesterday|tomorrow|next\s+week|weekend|monday|tuesday|wednesday|thursday|friday|saturday|sunday)\s*:\s*(?<content>.+)',
      caseSensitive: false,
    );
    final dcMatch = dateColonRegex.firstMatch(trimmed);
    if (dcMatch != null) {
      final dateWord = dcMatch.namedGroup('date')!.trim();
      final content = dcMatch.namedGroup('content')!.trim();
      return (true, dateWord, content);
    }

    return (false, null, trimmed);
  }

  /// Birden fazla kayıt veya yapılacak içeren serbest metni ayrıştırır.
  /// Zaman paylaşımı, geçmiş yönlü çözümleme ve kutudan yapılacak modunu destekler.
  static MultiParseResult parseMulti(
    String input, {
    required List<Activity> activities,
    required List<Measure> measures,
    List<Todo> openTodos = const [],
    DateTime? now,
    DateTime? fallbackDay,
    Measure? Function(int activityId)? defaultMeasureFor,
    List<Todo> Function(Iterable<dynamic> items)? predictCompletedTodos,
  }) {
    final cleanInput = input.trim();
    if (cleanInput.isEmpty) {
      return const MultiParseResult(rawText: '', items: []);
    }

    final (isTodo, prefixDateWord, content) = _detectTodoMode(cleanInput, now: now);
    if (isTodo) {
      DateTime? sharedDueDate;
      String? sharedDateKeyword = prefixDateWord;

      if (prefixDateWord != null) {
        final parsedDate = TimeParser.parse(
          prefixDateWord,
          direction: TemporalDirection.future,
          now: now,
        );
        if (parsedDate.hasExplicitDate) {
          sharedDueDate = parsedDate.dateTime;
        }
      }

      String workingContent = content;
      if (sharedDueDate == null) {
        final leadTime = TimeParser.parse(
          workingContent,
          direction: TemporalDirection.future,
          now: now,
        );
        final normWork = normalizeTr(workingContent).toLowerCase();
        final normLead = normalizeTr(leadTime.rawMatchedText).toLowerCase();
        if (leadTime.hasExplicitDate && normLead.isNotEmpty && normWork.startsWith(normLead)) {
          sharedDueDate = leadTime.dateTime;
          sharedDateKeyword = leadTime.dateKeyword;
          workingContent = leadTime.cleanedText;
        }
      }

      final pieces = splitSentence(workingContent, activities: activities, measures: measures);
      final todoItems = <TodoParsedItem>[];

      for (final piece in pieces) {
        if (piece.trim().isEmpty) continue;
        final todoParsed = TodoInputParser.parse(
          piece,
          activities: activities,
          measures: measures,
          now: now,
        );

        final dueDate = todoParsed.date ?? sharedDueDate;
        final dateKeyword = todoParsed.dateKeyword ?? sharedDateKeyword;

        todoItems.add(
          TodoParsedItem(
            rawText: piece,
            title: todoParsed.cleanTitle.isNotEmpty ? todoParsed.cleanTitle : piece,
            dueDate: dueDate,
            dateKeyword: dateKeyword,
            suggestedActivity: todoParsed.suggestedActivity,
            suggestedAmount: todoParsed.suggestedAmount,
            suggestedUnit: todoParsed.suggestedUnit,
          ),
        );
      }

      return MultiParseResult(
        rawText: cleanInput,
        isTodoMode: true,
        items: todoItems,
      );
    }

    // Kayıt modu (Record mode)
    TimeParseResult? sharedTime;
    String workingInput = cleanInput;

    final leadTime = TimeParser.parse(
      workingInput,
      direction: TemporalDirection.past,
      now: now,
      fallbackDay: fallbackDay,
    );

    final normInput = normalizeTr(workingInput).toLowerCase();
    final normLead = normalizeTr(leadTime.rawMatchedText).toLowerCase();
    if (normLead.isNotEmpty && (normInput.startsWith(normLead) || normInput.startsWith('$normLead '))) {
      sharedTime = leadTime;
      workingInput = leadTime.cleanedText;
    }

    final pieces = splitSentence(workingInput, activities: activities, measures: measures);
    final items = <ParsedItem>[];

    for (final piece in pieces) {
      if (piece.trim().isEmpty) continue;

      final pieceTime = TimeParser.parse(
        piece,
        direction: TemporalDirection.past,
        now: now,
        fallbackDay: fallbackDay,
      );

      final hasOwnTime = pieceTime.hasExplicitDate || pieceTime.hasExplicitTime || pieceTime.isRelative;
      final effectiveTime = hasOwnTime ? pieceTime : (sharedTime ?? pieceTime);
      final textToParse = hasOwnTime ? pieceTime.cleanedText : piece;

      final singleParse = parse(
        textToParse,
        activities: activities,
        measures: measures,
        allowCommands: pieces.length == 1,
        defaultMeasureFor: defaultMeasureFor,
      );

      final act = singleParse.matchedActivity;
      final effectiveM = singleParse.matchedMeasure ?? (act != null && defaultMeasureFor != null ? defaultMeasureFor(act.id) : null);
      final unitId = effectiveM?.unitId;
      final isDuration = unitId == 'dk' || unitId == 'sa' || unitId == 'sn';

      DateTime itemStartAt = effectiveTime.dateTime;
      DateTime? itemEndAt;

      if (isDuration) {
        final totalVal = effectiveM != null ? effectiveM.amount * singleParse.quantity : singleParse.quantity;
        final durSecs = (totalVal * (unitId == 'sa' ? 3600 : (unitId == 'dk' ? 60 : 1))).round();

        final hasExplicitClockOrPod = effectiveTime.hasExplicitTime && !effectiveTime.isRelative;
        final isRelativeAgo = effectiveTime.isRelative && effectiveTime.dateKeyword == 'önce';
        final isRelativeJustNow = effectiveTime.isRelative && effectiveTime.dateKeyword != 'önce';
        final hasNoTimeSpec = !effectiveTime.hasExplicitTime && !effectiveTime.hasExplicitDate && !effectiveTime.isRelative;

        if (hasNoTimeSpec || isRelativeJustNow) {
          // Zaman ifadesi yoksa ya da "az önce", "demin", "şimdi" varsa kayıt şimdi biter: başlangıç = şimdi - süre
          itemEndAt = effectiveTime.dateTime;
          itemStartAt = itemEndAt.subtract(Duration(seconds: durSecs));
        } else if (isRelativeAgo) {
          // "X önce" verilmişse kayıt X önce biter: bitiş = şimdi - X, başlangıç = bitiş - süre
          itemEndAt = effectiveTime.dateTime;
          itemStartAt = itemEndAt.subtract(Duration(seconds: durSecs));
        } else if (hasExplicitClockOrPod || effectiveTime.hasExplicitDate) {
          // Saat ya da gün bölümü verilmişse o an başlangıçtır: bitiş = başlangıç + süre
          itemStartAt = effectiveTime.dateTime;
          itemEndAt = itemStartAt.add(Duration(seconds: durSecs));
        } else {
          itemEndAt = effectiveTime.dateTime;
          itemStartAt = itemEndAt.subtract(Duration(seconds: durSecs));
        }
      }

      final matchedWillCompleteList = <Todo>[];
      if (act != null && openTodos.isNotEmpty) {
        final openLinked = openTodos.where(
          (t) => t.isLinked && !t.isCompleted && t.linkedActivityIds.contains(act.id),
        );
        for (final t in openLinked) {
          // Yapılacağın oluşturulmasından önceki kayıtlar sayılmaz
          if (itemStartAt.millisecondsSinceEpoch < t.createdAt) continue;

          // Birim ve boyut kontrolü
          final tUnit = t.targetUnit;
          if (t.targetAmount != null) {
            // Birim boyut uyumu: süre kaydı (dk, sa, sn) mesafe (km, m) veya hacim (l) hedefini tamamlayamaz
            final isTDuration = tUnit == 'dk' || tUnit == 'sa' || tUnit == 'sn';
            final isTDistance = tUnit == 'km' || tUnit == 'm';
            final isTVolume = tUnit == 'l' || tUnit == 'ml';
            final isTMass = tUnit == 'kg' || tUnit == 'g' || tUnit == 'mg';

            if (isDuration && !isTDuration) continue;
            if (!isDuration && isTDuration) continue;
            if (isTDistance && unitId != 'km' && unitId != 'm') continue;
            if (isTVolume && unitId != 'l' && unitId != 'ml') continue;
            if (isTMass && unitId != 'kg' && unitId != 'g' && unitId != 'mg') continue;

            final m = singleParse.matchedMeasure ?? effectiveM;
            final val = (m != null) ? (singleParse.quantity * m.amount) : singleParse.quantity;
            if (val >= t.targetAmount!) {
              matchedWillCompleteList.add(t);
            }
          } else {
            matchedWillCompleteList.add(t);
          }
        }
      }

      items.add(
        EntryParsedItem(
          rawText: piece,
          parseResult: singleParse,
          activity: singleParse.matchedActivity,
          activityName: singleParse.activityName,
          measure: singleParse.matchedMeasure,
          quantity: singleParse.quantity,
          at: itemStartAt,
          endAt: itemEndAt,
          hasExplicitTime: effectiveTime.hasExplicitTime,
          hasExplicitDate: effectiveTime.hasExplicitDate,
          isExplicitFuture: effectiveTime.isExplicitFuture,
          isRelative: effectiveTime.isRelative,
          timeKeyword: effectiveTime.dateKeyword,
          isNewActivity: singleParse.matchedActivity == null,
          timerCommand: singleParse.timerCommand,
          willCompleteTodos: matchedWillCompleteList,
        ),
      );
    }

    if (predictCompletedTodos != null) {
      final entryItems = items.whereType<EntryParsedItem>().toList();
      if (entryItems.isNotEmpty) {
        final predicted = predictCompletedTodos(entryItems);
        for (var i = 0; i < items.length; i++) {
          final it = items[i];
          if (it is EntryParsedItem && it.activity != null) {
            final forThis = predicted.where((t) => t.linkedActivityIds.contains(it.activity!.id)).toList();
            items[i] = it.copyWith(willCompleteTodos: forThis);
          }
        }
      }
    }

    return MultiParseResult(
      rawText: cleanInput,
      isTodoMode: false,
      items: items,
    );
  }
}
