import 'package:intl/intl.dart';

import '../data/models.dart';

final _num = NumberFormat('#,##0.##', 'tr_TR');
final _num1 = NumberFormat('#,##0.#', 'tr_TR');

String fmtNum(double v) => _num.format(v);
String fmtNum1(double v) => _num1.format(v);

DateTime dayStart(DateTime d) => DateTime(d.year, d.month, d.day);
DateTime weekStart(DateTime d) => dayStart(d).subtract(Duration(days: d.weekday - 1));
DateTime monthStart(DateTime d) => DateTime(d.year, d.month);
DateTime yearStart(DateTime d) => DateTime(d.year);

bool sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

String dayKey(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

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

String fmtRelative(int ts) {
  final d = DateTime.fromMillisecondsSinceEpoch(ts);
  final now = DateTime.now();
  final diff = now.difference(d);
  if (diff.inMinutes < 1) return 'az önce';
  if (diff.inMinutes < 60) return '${diff.inMinutes} dk önce';
  if (sameDay(d, now)) return 'bugün ${fmtTime(d)}';
  final days = dayStart(now).difference(dayStart(d)).inDays;
  if (days == 1) return 'dün';
  if (days < 7) return '$days gün önce';
  return fmtDateShort(d);
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
      if (base.abs() < 1) return '${(base * 60).round()} sn';
      if (base.abs() < 60) return '${fmtNum1(base)} dk';
      final h = base ~/ 60;
      final m = (base - h * 60).round();
      return m == 0 ? '$h sa' : '$h sa $m dk';
    case 'distance':
      if (base.abs() >= 1000) return '${fmtNum(base / 1000)} km';
      return '${fmtNum1(base)} m';
    case 'count':
      return '${fmtNum(base)} adet';
    case 'energy':
      return '${fmtNum1(base)} kcal';
    default:
      return '${fmtNum(base)} ${customUnit?.symbol ?? ''}'.trim();
  }
}

String fmtInUnit(double v, Unit u) => '${fmtNum(v)} ${u.symbol}';

String fmtDaysLeft(int days) {
  if (days < 0) return 'Süre doldu';
  if (days == 0) return 'Bugün son gün';
  if (days == 1) return 'Yarın son gün';
  return '$days gün kaldı';
}
