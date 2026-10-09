import 'dart:ui' show Color;

import '../logic/text_match.dart';

/// Ölçü birimi. Aynı boyuttaki (dim) birimler birbirine çevrilebilir.
/// factor: boyutun temel birimine çarpan (hacim: L, ağırlık: g, süre: dk, mesafe: m).
class Unit {
  final String id;
  final String name;
  final String symbol;
  final String dim;
  final double factor;
  final bool builtin;

  const Unit({
    required this.id,
    required this.name,
    required this.symbol,
    required this.dim,
    required this.factor,
    this.builtin = false,
  });

  Map<String, Object?> toMap() =>
      {'id': id, 'name': name, 'symbol': symbol, 'dim': dim, 'factor': factor};

  factory Unit.fromMap(Map<String, Object?> m) => Unit(
        id: m['id'] as String,
        name: m['name'] as String,
        symbol: m['symbol'] as String,
        dim: m['dim'] as String,
        factor: (m['factor'] as num).toDouble(),
      );
}

const builtinUnits = <Unit>[
  Unit(id: 'ml', name: 'Mililitre', symbol: 'ml', dim: 'volume', factor: 0.001, builtin: true),
  Unit(id: 'l', name: 'Litre', symbol: 'L', dim: 'volume', factor: 1, builtin: true),
  Unit(id: 'g', name: 'Gram', symbol: 'g', dim: 'mass', factor: 1, builtin: true),
  Unit(id: 'kg', name: 'Kilogram', symbol: 'kg', dim: 'mass', factor: 1000, builtin: true),
  Unit(id: 'sn', name: 'Saniye', symbol: 'sn', dim: 'time', factor: 1 / 60, builtin: true),
  Unit(id: 'dk', name: 'Dakika', symbol: 'dk', dim: 'time', factor: 1, builtin: true),
  Unit(id: 'sa', name: 'Saat', symbol: 'sa', dim: 'time', factor: 60, builtin: true),
  Unit(id: 'adet', name: 'Adet', symbol: 'adet', dim: 'count', factor: 1, builtin: true),
  Unit(id: 'm', name: 'Metre', symbol: 'm', dim: 'distance', factor: 1, builtin: true),
  Unit(id: 'km', name: 'Kilometre', symbol: 'km', dim: 'distance', factor: 1000, builtin: true),
  Unit(id: 'kcal', name: 'Kalori', symbol: 'kcal', dim: 'energy', factor: 1, builtin: true),
];

const dimNames = <String, String>{
  'volume': 'Hacim',
  'mass': 'Ağırlık',
  'time': 'Süre',
  'count': 'Adet',
  'distance': 'Mesafe',
  'energy': 'Enerji',
};

/// Kullanıcının tanımladığı ölçü: "Demlik = 0,7 L", "Çay bardağı = 0,1 L".
/// qtyMode: 'stepper' (sayı/stepper), 'choices' (çoktan seçmeli 1,2,3...), 'grid' (parmakla boyanan kare ızgara)
class Measure {
  int id;
  String name;
  String unitId;
  double amount;
  int sort;
  String qtyMode; // 'stepper', 'choices', 'grid'
  String choices; // örn: "1,2,3,4,5"
  int gridRows;
  int gridCols;

  Measure({
    required this.id,
    required this.name,
    required this.unitId,
    required this.amount,
    this.sort = 0,
    this.qtyMode = 'stepper',
    this.choices = '1,2,3,4,5',
    this.gridRows = 2,
    this.gridCols = 5,
  });

  List<double> get choiceList {
    return choices
        .split(',')
        .map((s) => parseNum(s.trim()))
        .whereType<double>()
        .where((d) => d > 0)
        .toList();
  }

  int get gridTotal => gridRows * gridCols;

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'unit_id': unitId,
        'amount': amount,
        'sort': sort,
        'qty_mode': qtyMode,
        'choices': choices,
        'grid_rows': gridRows,
        'grid_cols': gridCols,
      };

  factory Measure.fromMap(Map<String, Object?> m) => Measure(
        id: m['id'] as int,
        name: m['name'] as String,
        unitId: m['unit_id'] as String,
        amount: (m['amount'] as num).toDouble(),
        sort: (m['sort'] as int?) ?? 0,
        qtyMode: (m['qty_mode'] as String?) ?? 'stepper',
        choices: (m['choices'] as String?) ?? '1,2,3,4,5',
        gridRows: (m['grid_rows'] as int?) ?? 2,
        gridCols: (m['grid_cols'] as int?) ?? 5,
      );
}

class CategoryDef {
  final String id;
  final String nameTr;
  final String nameEn;
  final String emoji;
  final int colorValue;

  const CategoryDef({
    required this.id,
    required this.nameTr,
    required this.nameEn,
    required this.emoji,
    required this.colorValue,
  });

  String name(bool isTr) => isTr ? nameTr : nameEn;
}

const defaultCategories = <CategoryDef>[
  CategoryDef(id: 'nutrition', nameTr: 'Beslenme & İçecek', nameEn: 'Food & Drink', emoji: '🍎', colorValue: 0xFFE65100),
  CategoryDef(id: 'sport', nameTr: 'Spor & Sağlık', nameEn: 'Fitness & Health', emoji: '🏃', colorValue: 0xFF2E7D32),
  CategoryDef(id: 'study', nameTr: 'Eğitim & Çalışma', nameEn: 'Study & Work', emoji: '📚', colorValue: 0xFF1565C0),
  CategoryDef(id: 'transport', nameTr: 'Ulaşım', nameEn: 'Transport', emoji: '🚌', colorValue: 0xFF6A1B9A),
  CategoryDef(id: 'routine', nameTr: 'Günlük Rutinler', nameEn: 'Routines', emoji: '⏱️', colorValue: 0xFF00838F),
  CategoryDef(id: 'hobby', nameTr: 'Eğlence & Hobi', nameEn: 'Leisure & Hobby', emoji: '🎮', colorValue: 0xFFC2185B),
  CategoryDef(id: 'other', nameTr: 'Genel', nameEn: 'General', emoji: '📌', colorValue: 0xFF455A64),
];

CategoryDef getCategoryDef(String? categoryId) {
  if (categoryId == null) return defaultCategories.last;
  return defaultCategories.firstWhere(
    (c) => c.id == categoryId,
    orElse: () => defaultCategories.last,
  );
}

/// Yapılan şey / olay türü: "Çay", "Deneme çözdüm", "Elektrik kesildi".
class Activity {
  int id;
  String name;
  String? emoji;
  String? category;
  int? color;
  bool isHabit;
  int createdAt;
  String _norm;

  Activity({
    required this.id,
    required this.name,
    this.emoji,
    this.category,
    this.color,
    this.isHabit = false,
    required this.createdAt,
  }) : _norm = normalizeTr(name);

  String get norm => _norm;

  CategoryDef get categoryDef => getCategoryDef(category);

  Color get displayColor => color != null ? Color(color!) : Color(categoryDef.colorValue);

  void rename(String n) {
    name = n;
    _norm = normalizeTr(n);
  }

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'emoji': emoji,
        'category': category,
        'color': color,
        'is_habit': isHabit ? 1 : 0,
        'created_at': createdAt,
      };

  factory Activity.fromMap(Map<String, Object?> m) => Activity(
        id: m['id'] as int,
        name: m['name'] as String,
        emoji: m['emoji'] as String?,
        category: m['category'] as String?,
        color: m['color'] as int?,
        isHabit: (m['is_habit'] as int? ?? 0) == 1,
        createdAt: m['created_at'] as int,
      );
}

/// Zaman damgalı tek bir kayıt. value/unitId, kayıt anındaki ölçünün
/// anlık görüntüsüdür (ölçü sonradan değişse de geçmiş bozulmaz).
class Entry {
  int id;
  int activityId;
  int ts;
  int? measureId;
  double qty;
  double? value;
  String? unitId;
  String? note;

  Entry({
    required this.id,
    required this.activityId,
    required this.ts,
    this.measureId,
    this.qty = 1,
    this.value,
    this.unitId,
    this.note,
  });

  DateTime get time => DateTime.fromMillisecondsSinceEpoch(ts);

  Map<String, Object?> toMap() => {
        'id': id,
        'activity_id': activityId,
        'ts': ts,
        'measure_id': measureId,
        'qty': qty,
        'value': value,
        'unit_id': unitId,
        'note': note,
      };

  factory Entry.fromMap(Map<String, Object?> m) => Entry(
        id: m['id'] as int,
        activityId: m['activity_id'] as int,
        ts: m['ts'] as int,
        measureId: m['measure_id'] as int?,
        qty: ((m['qty'] as num?) ?? 1).toDouble(),
        value: (m['value'] as num?)?.toDouble(),
        unitId: m['unit_id'] as String?,
        note: m['note'] as String?,
      );
}

enum GoalPeriod { day, week, month, total }

const periodNames = <GoalPeriod, String>{
  GoalPeriod.day: 'Günlük',
  GoalPeriod.week: 'Haftalık',
  GoalPeriod.month: 'Aylık',
  GoalPeriod.total: 'Toplam',
};

class GoalLink {
  int activityId;
  double pct; // 100 = tam katkı, 50 = yarısı

  GoalLink({required this.activityId, this.pct = 100});

  Map<String, Object?> toMap(int goalId) =>
      {'goal_id': goalId, 'activity_id': activityId, 'pct': pct};

  factory GoalLink.fromMap(Map<String, Object?> m) => GoalLink(
        activityId: m['activity_id'] as int,
        pct: (m['pct'] as num).toDouble(),
      );
}

class Goal {
  int id;
  String name;

  /// 'target' = ulaşılması gereken hedef (min), 'limit' = aşılmaması gereken sınır (maks)
  String type;

  /// 'amount' = toplam miktar (birimle), 'count' = kaç kez yapıldığı
  String mode;
  String? unitId;
  double target;
  GoalPeriod period;
  int startDate;
  int? endDate;
  int createdAt;
  int sort;
  List<GoalLink> links;

  Goal({
    required this.id,
    required this.name,
    this.type = 'target',
    required this.mode,
    this.unitId,
    required this.target,
    required this.period,
    required this.startDate,
    this.endDate,
    required this.createdAt,
    this.sort = 0,
    List<GoalLink>? links,
  }) : links = links ?? [];

  bool get isCount => mode == 'count';
  bool get isLimit => type == 'limit';
  bool get isTarget => type != 'limit';

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'type': type,
        'mode': mode,
        'unit_id': unitId,
        'target': target,
        'period': period.name,
        'start_date': startDate,
        'end_date': endDate,
        'created_at': createdAt,
        'sort': sort,
      };

  factory Goal.fromMap(Map<String, Object?> m) => Goal(
        id: m['id'] as int,
        name: m['name'] as String,
        type: (m['type'] as String?) ?? 'target',
        mode: m['mode'] as String,
        unitId: m['unit_id'] as String?,
        target: (m['target'] as num).toDouble(),
        period: GoalPeriod.values.byName(m['period'] as String),
        startDate: m['start_date'] as int,
        endDate: m['end_date'] as int?,
        createdAt: m['created_at'] as int,
        sort: (m['sort'] as int?) ?? 0,
      );
}

/// Hızlı listedeki öğe.
/// kind: 'shortcut' = her dokunuşta yeni kayıt, 'todo' = yapılacak (tiklenir).
/// daily: todo için her gün yenilenir mi (false = bir kerelik).
class QuickItem {
  int id;
  int activityId;
  String kind;
  bool daily;
  int? measureId;
  double qty;
  int sort;
  int createdAt;

  QuickItem({
    required this.id,
    required this.activityId,
    required this.kind,
    this.daily = true,
    this.measureId,
    this.qty = 1,
    this.sort = 0,
    required this.createdAt,
  });

  bool get isTodo => kind == 'todo';

  Map<String, Object?> toMap() => {
        'id': id,
        'activity_id': activityId,
        'kind': kind,
        'daily': daily ? 1 : 0,
        'measure_id': measureId,
        'qty': qty,
        'sort': sort,
        'created_at': createdAt,
      };

  factory QuickItem.fromMap(Map<String, Object?> m) => QuickItem(
        id: m['id'] as int,
        activityId: m['activity_id'] as int,
        kind: m['kind'] as String,
        daily: (m['daily'] as int? ?? 1) == 1,
        measureId: m['measure_id'] as int?,
        qty: ((m['qty'] as num?) ?? 1).toDouble(),
        sort: (m['sort'] as int?) ?? 0,
        createdAt: m['created_at'] as int,
      );
}

/// Devam eden veya duraklatılmış kronometre kaydı.
class ActiveTimer {
  final int id;
  final int activityId;
  final int startTs;
  final int accumulatedMs;
  final int? lastResumeTs;
  final bool isRunning;
  final String? note;
  final String mode; // 'stopwatch', 'pomodoro', 'countdown'
  final int targetMs;
  final bool isCollapsed;

  ActiveTimer({
    required this.id,
    required this.activityId,
    required this.startTs,
    this.accumulatedMs = 0,
    this.lastResumeTs,
    this.isRunning = true,
    this.note,
    this.mode = 'stopwatch',
    this.targetMs = 0,
    this.isCollapsed = false,
  });

  bool get isCountdown => mode == 'pomodoro' || mode == 'countdown';
  bool get isPomodoro => mode == 'pomodoro';

  int get elapsedMs {
    if (!isRunning || lastResumeTs == null) {
      return accumulatedMs;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final diff = now - lastResumeTs!;
    return accumulatedMs + (diff > 0 ? diff : 0);
  }

  int get remainingMs {
    if (!isCountdown || targetMs <= 0) return 0;
    final rem = targetMs - elapsedMs;
    return rem < 0 ? 0 : rem;
  }

  bool get isTargetReached => isCountdown && targetMs > 0 && elapsedMs >= targetMs;

  double get progress {
    if (!isCountdown || targetMs <= 0) return 0.0;
    return (elapsedMs / targetMs).clamp(0.0, 1.0);
  }

  double get elapsedSeconds => elapsedMs / 1000.0;
  double get elapsedMinutes => elapsedMs / 60000.0;

  DateTime get startTime => DateTime.fromMillisecondsSinceEpoch(startTs);

  /// Başlangıç anı ile şu anki an farklı takvim günlerine mi ait?
  bool get spansMidnight {
    final start = startTime;
    final now = DateTime.now();
    return now.year != start.year || now.month != start.month || now.day != start.day;
  }

  /// Gece yarısından (00:00:00) önceki kısım (ms)
  int get msBeforeMidnight {
    final start = startTime;
    final nextDayMidnight = DateTime(start.year, start.month, start.day + 1);
    final diff = nextDayMidnight.difference(start).inMilliseconds;
    return diff.clamp(0, elapsedMs);
  }

  /// Gece yarısından sonraki kısım (ms)
  int get msAfterMidnight {
    final remaining = elapsedMs - msBeforeMidnight;
    return remaining > 0 ? remaining : 0;
  }

  String get formattedDuration => formatTimerDuration(elapsedMs);
  String get formattedRemaining => formatTimerDuration(remainingMs);
  String get displayDuration => isCountdown ? formattedRemaining : formattedDuration;

  ActiveTimer copyWith({
    int? id,
    int? activityId,
    int? startTs,
    int? accumulatedMs,
    int? lastResumeTs,
    bool? isRunning,
    String? note,
    String? mode,
    int? targetMs,
    bool? isCollapsed,
    bool clearLastResumeTs = false,
  }) {
    return ActiveTimer(
      id: id ?? this.id,
      activityId: activityId ?? this.activityId,
      startTs: startTs ?? this.startTs,
      accumulatedMs: accumulatedMs ?? this.accumulatedMs,
      lastResumeTs: clearLastResumeTs ? null : (lastResumeTs ?? this.lastResumeTs),
      isRunning: isRunning ?? this.isRunning,
      note: note ?? this.note,
      mode: mode ?? this.mode,
      targetMs: targetMs ?? this.targetMs,
      isCollapsed: isCollapsed ?? this.isCollapsed,
    );
  }

  Map<String, Object?> toMap() => {
        'id': id,
        'activity_id': activityId,
        'start_ts': startTs,
        'accumulated_ms': accumulatedMs,
        'last_resume_ts': lastResumeTs,
        'is_running': isRunning ? 1 : 0,
        'note': note,
        'mode': mode,
        'target_ms': targetMs,
      };

  factory ActiveTimer.fromMap(Map<String, Object?> m) => ActiveTimer(
        id: m['id'] as int,
        activityId: m['activity_id'] as int,
        startTs: m['start_ts'] as int,
        accumulatedMs: (m['accumulated_ms'] as int?) ?? 0,
        lastResumeTs: m['last_resume_ts'] as int?,
        isRunning: (m['is_running'] as int? ?? 1) == 1,
        note: m['note'] as String?,
        mode: (m['mode'] as String?) ?? 'stopwatch',
        targetMs: (m['target_ms'] as int?) ?? 0,
      );
}

String formatTimerDuration(int ms) {
  final totalSeconds = (ms / 1000).floor();
  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  final seconds = totalSeconds % 60;

  final mm = minutes.toString().padLeft(2, '0');
  final ss = seconds.toString().padLeft(2, '0');
  if (hours > 0) {
    final hh = hours.toString().padLeft(2, '0');
    return '$hh:$mm:$ss';
  }
  return '$mm:$ss';
}

/// Gece yarısını aşan oturumlar için kullanıcı kayıt seçeneği.
enum MidnightSplitChoice {
  split,    // Gece yarısında böl (Dün x dk, Bugün y dk)
  startDay, // Tamamını başlangıç gününe (düne) yaz
  endDay,   // Tamamını bitiş gününe (bugüne) yaz
}

String formatDurationHuman(int ms, bool isTr) {
  final totalSec = (ms / 1000).round();
  if (totalSec < 60) return '$totalSec ${isTr ? "sn" : "s"}';
  final mins = (totalSec / 60).round();
  if (mins < 60) return '$mins ${isTr ? "dk" : "min"}';
  final hours = mins ~/ 60;
  final remMins = mins % 60;
  if (remMins == 0) return '$hours ${isTr ? "sa" : "h"}';
  return '$hours ${isTr ? "sa" : "h"} $remMins ${isTr ? "dk" : "min"}';
}


