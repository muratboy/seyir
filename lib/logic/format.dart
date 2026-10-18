import 'package:intl/intl.dart';

import '../data/models.dart';
import 'l10n.dart';

final _numTr = NumberFormat('#,##0.##', 'tr_TR');
final _num1Tr = NumberFormat('#,##0.#', 'tr_TR');
final _numEn = NumberFormat('#,##0.##', 'en_US');
final _num1En = NumberFormat('#,##0.#', 'en_US');

// Sayılar, yüzdeler ve birim kısaltmaları arayüz diline göre yazılır.
bool get _isTr => strings.value.isTr;

String fmtNum(double v) => (_isTr ? _numTr : _numEn).format(v);
String fmtNum1(double v) => (_isTr ? _num1Tr : _num1En).format(v);

/// Yüzde: Türkçede "%62", İngilizcede "62%".
String fmtPercent(Object pct) => _isTr ? '%$pct' : '$pct%';

/// Kaç kez yapıldığını söyleyen sayının birimi ("5 kez" / "5 times").
String get timesWord => _isTr ? 'kez' : 'times';

/// [n] sayısıyla birlikte yazılan hâli: İngilizcede tekil ve çoğul ayrılır ("1 time", "3 times").
String timesUnit(num n) => _isTr ? 'kez' : (n == 1 ? 'time' : 'times');

/// Kayıt sayısı, adıyla: "5 kayıt" / "1 entry", "5 entries".
String entriesText(int n) =>
    _isTr ? '${fmtNum(n.toDouble())} kayıt' : '${fmtNum(n.toDouble())} ${n == 1 ? 'entry' : 'entries'}';

/// Saat ve dakika kısaltmaları ("sa"/"h", "dk"/"min").
String get hourWord => _isTr ? 'sa' : 'h';
String get minuteWord => _isTr ? 'dk' : 'min';

DateTime dayStart(DateTime d) => DateTime(d.year, d.month, d.day);
DateTime dayEnd(DateTime d) => DateTime(d.year, d.month, d.day, 23, 59, 59, 999);
DateTime addDays(DateTime d, int days) => DateTime(d.year, d.month, d.day + days);
DateTime subDays(DateTime d, int days) => DateTime(d.year, d.month, d.day - days);
DateTime weekStart(DateTime d) => DateTime(d.year, d.month, d.day - (d.weekday - 1));
DateTime monthStart(DateTime d) => DateTime(d.year, d.month);
DateTime yearStart(DateTime d) => DateTime(d.year);

bool sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

String dayKey(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

/// İki tarih arasındaki takvim günü sayısı (yaz saati geçişlerinden etkilenmez).
int calendarDaysBetween(DateTime a, DateTime b) =>
    DateTime.utc(b.year, b.month, b.day).difference(DateTime.utc(a.year, a.month, a.day)).inDays;

String fmtTime(DateTime d) => DateFormat.Hm('tr_TR').format(d);
String fmtDate(DateTime d, {bool isTr = true}) =>
    DateFormat('d MMMM yyyy', isTr ? 'tr_TR' : 'en_US').format(d);
String fmtDateShort(DateTime d, {bool isTr = true}) =>
    DateFormat('d MMM', isTr ? 'tr_TR' : 'en_US').format(d);

/// "Bugün", "Dün", "Yarın" ya da "8 Ekim Perşembe"
String fmtDayTitle(DateTime d, {bool isTr = true}) {
  final today = dayStart(DateTime.now());
  final diff = dayStart(d).difference(today).inDays;
  if (diff == 0) return isTr ? 'Bugün' : 'Today';
  if (diff == -1) return isTr ? 'Dün' : 'Yesterday';
  if (diff == 1) return isTr ? 'Yarın' : 'Tomorrow';
  return DateFormat('d MMMM EEEE', isTr ? 'tr_TR' : 'en_US').format(d);
}

/// Temel birimdeki (L, g, dk, m, adet...) miktarı okunaklı biçimde yazar.
String fmtAmount(double base, String dim, {Unit? customUnit}) {
  switch (dim) {
    case 'volume':
      if (base.abs() < 1) return '${fmtNum1(base * 1000)} ml';
      return '${fmtNum(base)} L';
    case 'mass':
      if (base.abs() >= 1000) return '${fmtNum(base / 1000)} kg';
      return '${fmtNum1(base)} g';
    case 'time':
      final (sec, min, hour) = _isTr ? ('sn', 'dk', 'sa') : ('s', 'min', 'h');
      if (base.abs() < 1) return '${(base * 60).round()} $sec';
      if (base.abs() < 60) return '${fmtNum1(base)} $min';
      final h = base ~/ 60;
      final m = (base - h * 60).round();
      return m == 0 ? '$h $hour' : '$h $hour $m $min';
    case 'distance':
      if (base.abs() >= 1000) return '${fmtNum(base / 1000)} km';
      return '${fmtNum1(base)} m';
    case 'count':
      return '${fmtNum(base)} ${_isTr ? 'adet' : 'pcs'}';
    case 'energy':
      return '${fmtNum1(base)} kcal';
    default:
      return '${fmtNum(base)} ${customUnit?.symbol ?? ''}'.trim();
  }
}

String fmtDaysLeft(int days, {bool isTr = true}) {
  if (days < 0) return isTr ? 'Süre doldu' : 'Expired';
  if (days == 0) return isTr ? 'Bugün son gün' : 'Last day today';
  if (days == 1) return isTr ? 'Yarın son gün' : 'Last day tomorrow';
  return isTr ? '$days gün kaldı' : '$days days left';
}

/// Verilen metnin gün birimi (gün, gun, day, days, gunluk, d) olup olmadığını kontrol eder.
bool isDayUnit(String? unit) {
  if (unit == null) return false;
  final u = unit.trim().toLowerCase();
  return u == 'gün' ||
      u == 'gun' ||
      u == 'day' ||
      u == 'days' ||
      u == 'd' ||
      u == 'günlük' ||
      u == 'gunluk';
}

