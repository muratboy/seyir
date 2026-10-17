import 'dart:math';

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
  final bool hasExplicitQuantity;
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
    if (extractedActivity.isEmpty) {
      extractedActivity = cleanInput;
    }

    // 5. Match with Existing Activities
    final (matchedActivity, confidence) = _matchActivity(extractedActivity, remainingWords, activities);
    // Yeni aktivite adı özgün yazımdan kurulur; normalize hâl "Çay"ı "Cay" olarak kaydederdi.
    final newActivityName = remainingRawWords.isEmpty ? cleanInput : remainingRawWords.join(' ');
    final finalActivityName = matchedActivity?.name ?? trCapitalize(newActivityName);

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
      hasExplicitQuantity: foundExplicitQty,
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
}
