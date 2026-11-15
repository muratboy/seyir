import 'dart:math';

import 'l10n.dart';

/// Türkçe karakterleri sadeleştirir ve küçük harfe çevirir:
/// "Çay Bardağı" -> "cay bardagi". Böylece "cay" yazınca "Çay" bulunur.
String normalizeTr(String s) {
  final b = StringBuffer();
  for (final r in s.runes) {
    final c = String.fromCharCode(r);
    switch (c) {
      case 'İ' || 'I' || 'ı' || 'i' || 'Î' || 'î':
        b.write('i');
      case 'Ç' || 'ç':
        b.write('c');
      case 'Ğ' || 'ğ':
        b.write('g');
      case 'Ö' || 'ö':
        b.write('o');
      case 'Ş' || 'ş':
        b.write('s');
      case 'Ü' || 'ü' || 'Û' || 'û':
        b.write('u');
      case 'Â' || 'â':
        b.write('a');
      default:
        b.write(c.toLowerCase());
    }
  }
  return b.toString().trim().replaceAll(RegExp(r'\s+'), ' ');
}

String trUpper(String s) => s.replaceAll('i', 'İ').replaceAll('ı', 'I').toUpperCase();

/// İlk harfi Türkçe kurallarıyla büyütür: "çay" -> "Çay", "ilaç" -> "İlaç".
String trCapitalize(String s) {
  final t = s.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (t.isEmpty) return t;
  return trUpper(t.substring(0, 1)) + t.substring(1);
}

int levenshtein(String a, String b) {
  if (a == b) return 0;
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;
  final d = List.generate(a.length + 1, (_) => List.filled(b.length + 1, 0));
  for (var i = 0; i <= a.length; i++) {
    d[i][0] = i;
  }
  for (var j = 0; j <= b.length; j++) {
    d[0][j] = j;
  }

  for (var i = 1; i <= a.length; i++) {
    for (var j = 1; j <= b.length; j++) {
      final cost = a[i - 1] == b[j - 1] ? 0 : 1;
      d[i][j] = min(min(d[i - 1][j] + 1, d[i][j - 1] + 1), d[i - 1][j - 1] + cost);
      // Damerau adjacent character swap tolerance (e.g. cya <-> cay)
      if (i > 1 && j > 1 && a[i - 1] == b[j - 2] && a[i - 2] == b[j - 1]) {
        d[i][j] = min(d[i][j], d[i - 2][j - 2] + 1);
      }
    }
  }
  return d[a.length][b.length];
}

/// Normalize edilmiş sorgu [q] ile isim [n] arasındaki benzerlik puanı (0 = alakasız).
double matchScore(String q, String n) {
  if (q.isEmpty || n.isEmpty) return 0;
  if (n == q) return 100;
  if (n.startsWith(q)) return 80 + 10 * q.length / n.length;
  final words = n.split(' ');
  if (words.any((w) => w.startsWith(q))) return 65 + 10 * q.length / n.length;
  if (n.contains(q)) return 55;
  final qw = q.split(' ');
  if (qw.length > 1 && qw.every((x) => words.any((w) => w.startsWith(x)))) {
    return 50;
  }
  // Yazım hatası toleransı ("cya" -> "çay", "kahv" -> "kahve")
  if (q.length >= 2) {
    var best = 0.0;
    final cands = <String>{n, ...words};
    for (final w in [n, ...words]) {
      if (w.length > q.length) cands.add(w.substring(0, q.length));
    }
    for (final c in cands) {
      final dist = levenshtein(q, c);
      // Yazım hatası sayılması için aday aynı harfle başlamalıdır; yoksa "kitap" yazınca "gitar" da önerilir.
      if (q[0] != c[0]) continue;
      final sim = 1.0 - dist / max(q.length, c.length);
      if (sim > best) best = sim;
      if (dist <= 1 && best < 0.6) best = 0.6;
    }
    if (best >= 0.5) return 40 * best;
  }
  return 0;
}

/// Binlik ayraçları ve ondalık sayıları çözümler.
/// - Nokta: ilk basamağı sıfır olmayan 1–3 basamak ve ardından bir ya da daha çok ".ddd" grubu binlik yazımdır
///   ("1.000" -> 1000, "10.000" -> 10000, "1.234,5" -> 1234.5). Her iki dilde geçerlidir.
/// - Virgül: yalnızca arayüz dili İngilizce iken ("1,000" -> 1000, "1,234.5" -> 1234.5). Türkçe arayüzde ondalık kalır (1).
/// - Değişmeyenler: "1.5", "1,5", "0.5", "0,5", "12.5", "1.50", "0.500" (0.5).
double? parseNum(String s, {bool? isEn}) {
  final t = s.trim().replaceAll(' ', '');
  if (t.isEmpty) return null;

  final english = isEn ?? (strings.value.lang == AppLanguage.en);

  // 1. Binlik nokta: 1-3 basamak (ilk rakam 1-9), ardı ardına .ddd grupları, isteğe bağlı ondalık virgül (,d+)
  final dotThousandRegex = RegExp(r'^([1-9]\d{0,2}(?:\.\d{3})+)(?:,(\d+))?$');
  final dotMatch = dotThousandRegex.firstMatch(t);
  if (dotMatch != null) {
    final intPart = dotMatch.group(1)!.replaceAll('.', '');
    final decPart = dotMatch.group(2);
    return double.tryParse(decPart != null ? '$intPart.$decPart' : intPart);
  }

  // 2. Binlik virgül (yalnızca İngilizce): 1-3 basamak (ilk rakam 1-9), ardı ardına ,ddd grupları, isteğe bağlı ondalık nokta (.d+)
  if (english) {
    final commaThousandRegex = RegExp(r'^([1-9]\d{0,2}(?:,\d{3})+)(?:\.(\d+))?$');
    final commaMatch = commaThousandRegex.firstMatch(t);
    if (commaMatch != null) {
      final intPart = commaMatch.group(1)!.replaceAll(',', '');
      final decPart = commaMatch.group(2);
      return double.tryParse(decPart != null ? '$intPart.$decPart' : intPart);
    }
  }

  // 3. Standart ondalık sayı (hem nokta hem virgül kabul edilir)
  return double.tryParse(t.replaceAll(',', '.'));
}
