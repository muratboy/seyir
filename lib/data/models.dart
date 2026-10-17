import 'dart:convert';
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
  Unit(id: 'mg', name: 'Miligram', symbol: 'mg', dim: 'mass', factor: 0.001, builtin: true),
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

/// Hazır birimlerin İngilizce arayüzdeki adları ve kısaltmaları (kimlikler aynıdır).
const builtinUnitsEn = <Unit>[
  Unit(id: 'ml', name: 'Millilitre', symbol: 'ml', dim: 'volume', factor: 0.001, builtin: true),
  Unit(id: 'l', name: 'Litre', symbol: 'L', dim: 'volume', factor: 1, builtin: true),
  Unit(id: 'mg', name: 'Milligram', symbol: 'mg', dim: 'mass', factor: 0.001, builtin: true),
  Unit(id: 'g', name: 'Gram', symbol: 'g', dim: 'mass', factor: 1, builtin: true),
  Unit(id: 'kg', name: 'Kilogram', symbol: 'kg', dim: 'mass', factor: 1000, builtin: true),
  Unit(id: 'sn', name: 'Second', symbol: 's', dim: 'time', factor: 1 / 60, builtin: true),
  Unit(id: 'dk', name: 'Minute', symbol: 'min', dim: 'time', factor: 1, builtin: true),
  Unit(id: 'sa', name: 'Hour', symbol: 'h', dim: 'time', factor: 60, builtin: true),
  Unit(id: 'adet', name: 'Piece', symbol: 'pcs', dim: 'count', factor: 1, builtin: true),
  Unit(id: 'm', name: 'Metre', symbol: 'm', dim: 'distance', factor: 1, builtin: true),
  Unit(id: 'km', name: 'Kilometre', symbol: 'km', dim: 'distance', factor: 1000, builtin: true),
  Unit(id: 'kcal', name: 'Calorie', symbol: 'kcal', dim: 'energy', factor: 1, builtin: true),
];

const dimNames = <String, String>{
  'volume': 'Hacim',
  'mass': 'Ağırlık',
  'time': 'Süre',
  'count': 'Adet',
  'distance': 'Mesafe',
  'energy': 'Enerji',
};

const dimNamesEn = <String, String>{
  'volume': 'Volume',
  'mass': 'Weight',
  'time': 'Duration',
  'count': 'Count',
  'distance': 'Distance',
  'energy': 'Energy',
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
  bool isArchived;
  int createdAt;
  String _norm;

  Activity({
    required this.id,
    required this.name,
    this.emoji,
    this.category,
    this.color,
    this.isHabit = false,
    this.isArchived = false,
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
        'is_archived': isArchived ? 1 : 0,
        'created_at': createdAt,
      };

  factory Activity.fromMap(Map<String, Object?> m) => Activity(
        id: m['id'] as int,
        name: m['name'] as String,
        emoji: m['emoji'] as String?,
        category: m['category'] as String?,
        color: m['color'] as int?,
        isHabit: (m['is_habit'] as int? ?? 0) == 1,
        isArchived: (m['is_archived'] as int? ?? 0) == 1,
        createdAt: m['created_at'] as int,
      );
}

/// Aktiviteye ait ek özellik/metrik (örn: Ayran için 200 ml hacim, 76 kcal kalori, 4 g protein vb.)
class ActivityProperty {
  int id;
  int activityId;
  String name;
  double value;
  String unitId;
  double perQty; // Kaç adet/birim temel miktar için geçerli olduğu (varsayılan 1.0)
  String? perUnitId; // Temel miktarın birimi (örn: 'ml', 'g', 'adet', null ise 'adet' kabul edilir)

  ActivityProperty({
    this.id = 0,
    required this.activityId,
    required this.name,
    required this.value,
    required this.unitId,
    this.perQty = 1.0,
    this.perUnitId,
  });

  Map<String, Object?> toMap() => {
        if (id != 0) 'id': id,
        'activity_id': activityId,
        'name': name,
        'value': value,
        'unit_id': unitId,
        'per_qty': perQty,
        'per_unit_id': perUnitId,
      };

  factory ActivityProperty.fromMap(Map<String, Object?> m) => ActivityProperty(
        id: (m['id'] as int?) ?? 0,
        activityId: m['activity_id'] as int,
        name: m['name'] as String,
        value: (m['value'] as num).toDouble(),
        unitId: m['unit_id'] as String,
        perQty: ((m['per_qty'] as num?) ?? 1.0).toDouble(),
        perUnitId: m['per_unit_id'] as String?,
      );
}

/// Zaman damgalı tek bir kayıt. value/unitId, kayıt anındaki ölçünün
/// anlık görüntüsüdür (ölçü sonradan değişse de geçmiş bozulmaz).
class Entry {
  int id;
  int activityId;
  int ts;
  int? endTs;
  int? measureId;
  double qty;
  double? value;
  String? unitId;
  String? note;

  Entry({
    required this.id,
    required this.activityId,
    required this.ts,
    this.endTs,
    this.measureId,
    this.qty = 1,
    this.value,
    this.unitId,
    this.note,
  });

  DateTime get time => DateTime.fromMillisecondsSinceEpoch(ts);
  DateTime? get endTime => endTs != null ? DateTime.fromMillisecondsSinceEpoch(endTs!) : null;
  Duration? get duration => endTs != null ? Duration(milliseconds: (endTs! - ts).clamp(0, 86400000000)) : null;

  Map<String, Object?> toMap() => {
        'id': id,
        'activity_id': activityId,
        'ts': ts,
        'end_ts': endTs,
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
        endTs: m['end_ts'] as int?,
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

const periodNamesEn = <GoalPeriod, String>{
  GoalPeriod.day: 'Daily',
  GoalPeriod.week: 'Weekly',
  GoalPeriod.month: 'Monthly',
  GoalPeriod.total: 'Total',
};

String periodName(GoalPeriod period, {required bool isTr}) =>
    (isTr ? periodNames : periodNamesEn)[period] ?? period.name;

class GoalLink {
  int activityId;
  double pct; // 100 = tam katkı, 50 = yarısı
  int? propertyId; // Belirli bir aktivite özelliğine bağlanmışsa id'si (null ise otomatik / doğrudan)
  double? customRate; // İsteğe bağlı özel çarpan / oran

  GoalLink({
    required this.activityId,
    this.pct = 100,
    this.propertyId,
    this.customRate,
  });

  Map<String, Object?> toMap(int goalId) => {
        'goal_id': goalId,
        'activity_id': activityId,
        'pct': pct,
        'property_id': propertyId,
        'custom_rate': customRate,
      };

  factory GoalLink.fromMap(Map<String, Object?> m) => GoalLink(
        activityId: m['activity_id'] as int,
        pct: (m['pct'] as num).toDouble(),
        propertyId: m['property_id'] as int?,
        customRate: (m['custom_rate'] as num?)?.toDouble(),
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
  bool get isAmount => mode == 'amount';
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

class TimerSegment {
  final int startTs;
  final int endTs;

  const TimerSegment({required this.startTs, required this.endTs});

  int get durationMs => (endTs - startTs).clamp(0, 86400000000);

  Map<String, dynamic> toMap() => {'start': startTs, 'end': endTs};

  factory TimerSegment.fromMap(Map<String, dynamic> m) => TimerSegment(
        startTs: (m['start'] as num).toInt(),
        endTs: (m['end'] as num).toInt(),
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
  final List<TimerSegment> segments;

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
    this.segments = const [],
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

  bool get hasTarget => isCountdown && targetMs > 0;

  bool get isTargetReached => hasTarget && elapsedMs >= targetMs;

  double get progress {
    if (!isCountdown || targetMs <= 0) return 0.0;
    return (elapsedMs / targetMs).clamp(0.0, 1.0);
  }

  double get elapsedSeconds => elapsedMs / 1000.0;

  DateTime get startTime => DateTime.fromMillisecondsSinceEpoch(startTs);

  /// Başlangıç anı ile şu anki an farklı takvim günlerine mi ait?
  bool get spansMidnight {
    final start = startTime;
    final now = DateTime.now();
    return now.year != start.year || now.month != start.month || now.day != start.day;
  }

  DateTime get effectiveEndTime {
    if (isRunning && lastResumeTs != null) {
      return DateTime.now();
    }
    return startTime.add(Duration(milliseconds: elapsedMs));
  }

  List<TimerSegment> allSegments(int currentMs) {
    final list = List<TimerSegment>.from(segments);
    if (isRunning && lastResumeTs != null && currentMs > lastResumeTs!) {
      list.add(TimerSegment(startTs: lastResumeTs!, endTs: currentMs));
    }
    return list;
  }

  /// Gece yarısından (00:00:00) önceki kısım (ms)
  int get msBeforeMidnight {
    final start = startTime;
    final end = effectiveEndTime;
    final endMs = end.millisecondsSinceEpoch;
    final segs = allSegments(endMs);

    // Segmentler varsa kesintisiz kesin hesaplama
    if (segs.isNotEmpty) {
      final nextDayMidnight = DateTime(start.year, start.month, start.day + 1).millisecondsSinceEpoch;
      int exactBefore = 0;
      for (final s in segs) {
        if (s.startTs < nextDayMidnight) {
          final sEndBefore = s.endTs < nextDayMidnight ? s.endTs : nextDayMidnight;
          final duration = (sEndBefore - s.startTs).clamp(0, s.durationMs);
          exactBefore += duration;
        }
      }
      return exactBefore.clamp(0, elapsedMs);
    }

    // Segment yoksa oransal wall-clock formülü
    final wallClockTotal = end.difference(start).inMilliseconds;
    if (wallClockTotal <= 0 || elapsedMs <= 0) return elapsedMs;

    final nextDayMidnight = DateTime(start.year, start.month, start.day + 1);
    final wallClockBefore = nextDayMidnight.difference(start).inMilliseconds.clamp(0, wallClockTotal);

    final ratioBefore = wallClockBefore / wallClockTotal;
    final activeBefore = (elapsedMs * ratioBefore).round().clamp(0, elapsedMs);
    return activeBefore;
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
    bool clearNote = false,
    List<TimerSegment>? segments,
  }) {
    return ActiveTimer(
      id: id ?? this.id,
      activityId: activityId ?? this.activityId,
      startTs: startTs ?? this.startTs,
      accumulatedMs: accumulatedMs ?? this.accumulatedMs,
      lastResumeTs: clearLastResumeTs ? null : (lastResumeTs ?? this.lastResumeTs),
      isRunning: isRunning ?? this.isRunning,
      note: clearNote ? null : (note ?? this.note),
      mode: mode ?? this.mode,
      targetMs: targetMs ?? this.targetMs,
      isCollapsed: isCollapsed ?? this.isCollapsed,
      segments: segments ?? this.segments,
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
        'segments': jsonEncode(segments.map((s) => s.toMap()).toList()),
      };

  factory ActiveTimer.fromMap(Map<String, Object?> m) {
    List<TimerSegment> parsedSegments = const [];
    if (m['segments'] is String && (m['segments'] as String).isNotEmpty) {
      try {
        final list = jsonDecode(m['segments'] as String);
        if (list is List) {
          parsedSegments = list
              .map((item) => TimerSegment.fromMap(Map<String, dynamic>.from(item as Map)))
              .toList();
        }
      } catch (_) {}
    }

    return ActiveTimer(
      id: m['id'] as int,
      activityId: m['activity_id'] as int,
      startTs: m['start_ts'] as int,
      accumulatedMs: (m['accumulated_ms'] as int?) ?? 0,
      lastResumeTs: m['last_resume_ts'] as int?,
      isRunning: (m['is_running'] as int? ?? 1) == 1,
      note: m['note'] as String?,
      mode: (m['mode'] as String?) ?? 'stopwatch',
      targetMs: (m['target_ms'] as int?) ?? 0,
      segments: parsedSegments,
    );
  }
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

/// Belirli bir günün toplamlarını ve aktivite dökümünü içeren performans modeli.
class DaySummary {
  final DateTime date;
  final int count;
  final double totalTimeMinutes;
  final double totalVolumeLiters;
  final Map<int, int> activityCounts;
  final Map<int, double> activityTimeMinutes;
  final Map<int, double> activityVolumeLiters;

  const DaySummary({
    required this.date,
    required this.count,
    required this.totalTimeMinutes,
    required this.totalVolumeLiters,
    this.activityCounts = const {},
    this.activityTimeMinutes = const {},
    this.activityVolumeLiters = const {},
  });

  factory DaySummary.empty(DateTime date) => DaySummary(
        date: date,
        count: 0,
        totalTimeMinutes: 0,
        totalVolumeLiters: 0,
      );
}

/// Yol Haritası (Kişisel Gelişim, Beceri, Sınav veya Süreç Rotası)
class Roadmap {
  int id;
  String title;
  String description;
  String category;
  String emoji;
  String status; // 'not_started', 'active', 'completed', 'paused'
  int createdAt;
  int? startedAt;
  int? completedAt;
  List<RoadmapStep> steps;

  Roadmap({
    this.id = 0,
    required this.title,
    this.description = '',
    this.category = '',
    this.emoji = '🗺️',
    this.status = 'not_started',
    int? createdAt,
    this.startedAt,
    this.completedAt,
    List<RoadmapStep>? steps,
  })  : createdAt = createdAt ?? DateTime.now().millisecondsSinceEpoch,
        steps = steps ?? [];

  bool get isActive => status == 'active';
  bool get isCompleted => status == 'completed';
  bool get isNotStarted => status == 'not_started';

  int get totalSteps => steps.length;
  int get completedStepsCount => steps.where((s) => s.isCompleted).length;
  double get progressRatio => totalSteps == 0 ? 0.0 : completedStepsCount / totalSteps;
  int get progressPercent => (progressRatio * 100).round();

  RoadmapStep? get currentPendingStep {
    final pending = steps.where((s) => !s.isCompleted).toList();
    pending.sort((a, b) => a.order.compareTo(b.order));
    return pending.firstOrNull;
  }

  Map<String, Object?> toMap() => {
        if (id != 0) 'id': id,
        'title': title,
        'description': description,
        'category': category,
        'emoji': emoji,
        'status': status,
        'created_at': createdAt,
        'started_at': startedAt,
        'completed_at': completedAt,
      };

  factory Roadmap.fromMap(Map<String, Object?> m) => Roadmap(
        id: m['id'] as int,
        title: m['title'] as String,
        description: (m['description'] as String?) ?? '',
        category: (m['category'] as String?) ?? '',
        emoji: (m['emoji'] as String?) ?? '🗺️',
        status: (m['status'] as String?) ?? 'not_started',
        createdAt: m['created_at'] as int,
        startedAt: m['started_at'] as int?,
        completedAt: m['completed_at'] as int?,
      );
}

/// Yol Haritası Adımı (Ölçülü hedef veya ölçüsüz tek seferlik görev)
class RoadmapStep {
  int id;
  int roadmapId;
  int order;
  String title;
  String description;
  bool isCompleted;
  int? completedAt;
  String type; // 'task' (ölçüsüz görev) veya 'goal' (ölçülü hedef)
  double? target;
  String? unit;
  int? linkedActivityId;

  /// Adımı, bağlı aktivitenin kayıtları hedefe ulaştığı için uygulama tamamladıysa true; kullanıcı elle
  /// işaretlediyse false. Kayıt silinip hedefin altına düşülünce yalnızca böyle tamamlanmış adım yeniden
  /// açılır.
  bool autoCompleted;

  /// Kullanıcı, hedefi dolmuş adımın işaretini elle kaldırdıysa true: adım yeniden elle işaretlenene kadar
  /// uygulama onu kendiliğinden tamamlamaz. Yoksa kaldırılan işaret bir sonraki kayıtta geri gelirdi.
  bool keptOpen;

  RoadmapStep({
    this.id = 0,
    this.roadmapId = 0,
    this.order = 1,
    required this.title,
    this.description = '',
    this.isCompleted = false,
    this.completedAt,
    this.type = 'task',
    this.target,
    this.unit,
    this.linkedActivityId,
    this.autoCompleted = false,
    this.keptOpen = false,
  });

  bool get isTask => type == 'task';
  bool get isGoal => type == 'goal';

  Map<String, Object?> toMap() => {
        if (id != 0) 'id': id,
        'roadmap_id': roadmapId,
        'step_order': order,
        'title': title,
        'description': description,
        'is_completed': isCompleted ? 1 : 0,
        'completed_at': completedAt,
        'type': type,
        'target': target,
        'unit': unit,
        'linked_activity_id': linkedActivityId,
        'auto_completed': autoCompleted ? 1 : 0,
        'kept_open': keptOpen ? 1 : 0,
      };

  factory RoadmapStep.fromMap(Map<String, Object?> m) => RoadmapStep(
        id: m['id'] as int,
        roadmapId: m['roadmap_id'] as int,
        order: (m['step_order'] as int?) ?? 1,
        title: m['title'] as String,
        description: (m['description'] as String?) ?? '',
        isCompleted: ((m['is_completed'] as int?) ?? 0) == 1,
        completedAt: m['completed_at'] as int?,
        type: (m['type'] as String?) ?? 'task',
        target: (m['target'] as num?)?.toDouble(),
        unit: m['unit'] as String?,
        linkedActivityId: m['linked_activity_id'] as int?,
        autoCompleted: ((m['auto_completed'] as int?) ?? 0) == 1,
        keptOpen: ((m['kept_open'] as int?) ?? 0) == 1,
      );
}

/// Aktiviteye özel periyodik hatırlatıcı (Örn: "Her gün 09:00 Su" veya "Pzt, Çar, Cuma 18:00 Spor").
class ActivityReminder {
  int id;
  int activityId;
  String time; // 'HH:mm' örn: '09:00'
  String daysOfWeek; // '1,2,3,4,5,6,7' (1=Pazartesi .. 7=Pazar)
  bool isEnabled;
  String? customMessage;

  ActivityReminder({
    this.id = 0,
    required this.activityId,
    required this.time,
    this.daysOfWeek = '1,2,3,4,5,6,7',
    this.isEnabled = true,
    this.customMessage,
  });

  Set<int> get days => daysOfWeek.split(',').map(int.tryParse).whereType<int>().toSet();

  Map<String, Object?> toMap() => {
        if (id != 0) 'id': id,
        'activity_id': activityId,
        'time': time,
        'days_of_week': daysOfWeek,
        'is_enabled': isEnabled ? 1 : 0,
        'custom_message': customMessage,
      };

  factory ActivityReminder.fromMap(Map<String, Object?> m) => ActivityReminder(
        id: m['id'] as int,
        activityId: m['activity_id'] as int,
        time: m['time'] as String,
        daysOfWeek: (m['days_of_week'] as String?) ?? '1,2,3,4,5,6,7',
        isEnabled: ((m['is_enabled'] as int?) ?? 1) == 1,
        customMessage: m['custom_message'] as String?,
      );
}

/// Rutin / Aktivite Paketi (Örn: "Sabah Rutini": Su + Vitamin + Meditasyon).
class Routine {
  int id;
  String name;
  String emoji;
  int sort;
  List<RoutineItem> items;

  Routine({
    this.id = 0,
    required this.name,
    this.emoji = '⚡',
    this.sort = 0,
    List<RoutineItem>? items,
  }) : items = items ?? [];

  Map<String, Object?> toMap() => {
        if (id != 0) 'id': id,
        'name': name,
        'emoji': emoji,
        'sort': sort,
      };

  factory Routine.fromMap(Map<String, Object?> m) => Routine(
        id: m['id'] as int,
        name: m['name'] as String,
        emoji: (m['emoji'] as String?) ?? '⚡',
        sort: (m['sort'] as int?) ?? 0,
      );
}

/// Rutin içindeki tekil aktivite öğesi
class RoutineItem {
  int id;
  int routineId;
  int activityId;
  int? measureId;
  double qty;
  String? note;
  int sort;

  RoutineItem({
    this.id = 0,
    this.routineId = 0,
    required this.activityId,
    this.measureId,
    this.qty = 1.0,
    this.note,
    this.sort = 0,
  });

  Map<String, Object?> toMap() => {
        if (id != 0) 'id': id,
        'routine_id': routineId,
        'activity_id': activityId,
        'measure_id': measureId,
        'qty': qty,
        'note': note,
        'sort': sort,
      };

  factory RoutineItem.fromMap(Map<String, Object?> m) => RoutineItem(
        id: m['id'] as int,
        routineId: m['routine_id'] as int,
        activityId: m['activity_id'] as int,
        measureId: m['measure_id'] as int?,
        qty: (m['qty'] as num?)?.toDouble() ?? 1.0,
        note: m['note'] as String?,
        sort: (m['sort'] as int?) ?? 0,
      );
}

enum CorrelationType {
  positive, // Koruyucu veya pozitif etki (A yapılınca B belirtisi azalıyor veya alışkanlık artıyor)
  negative, // Birlikte yapılmayan / zıt durum
  warning,  // Tetikleyici (A yapılınca B belirtisi artıyor)
}

/// Belirti, alışkanlık ve metrikler arasındaki tespit edilen istatistiksel ilişki
class CorrelationInsight {
  final int primaryActivityId;
  final int relatedActivityId;
  final String title;
  final String description;
  final double changeRatio; // Örn: 0.45 (%45 azalma) veya 1.8 (1.8 kat artış)
  final CorrelationType type;
  final int coOccurrenceCount;
  final int totalPrimaryDays;

  const CorrelationInsight({
    required this.primaryActivityId,
    required this.relatedActivityId,
    required this.title,
    required this.description,
    required this.changeRatio,
    required this.type,
    required this.coOccurrenceCount,
    required this.totalPrimaryDays,
  });
}


