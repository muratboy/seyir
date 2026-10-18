import 'package:flutter_test/flutter_test.dart';
import 'package:takip/data/models.dart';
import 'package:takip/data/store.dart';
import 'support/real_db.dart';

void main() {
  useRealDatabase();

  group('Routine Execution and Measure Fallback Tests', () {
    late Activity waterAct;
    late Activity coffeeAct;
    late Measure glassMeasure;
    late Measure cupMeasure;

    setUp(() async {
      await store.load();
      waterAct = await store.addActivity('Su', emoji: '💧');
      coffeeAct = await store.addActivity('Kahve', emoji: '☕');

      glassMeasure = await store.addMeasure('Su Bardağı', 'ml', 200);
      cupMeasure = await store.addMeasure('Fincan', 'ml', 80);

      // Daha önce su için bardak, kahve için fincan kullanılmış olsun
      await store.addEntry(waterAct.id, measureId: glassMeasure.id, qty: 1);
      await store.addEntry(coffeeAct.id, measureId: cupMeasure.id, qty: 1);
    });

    test('Rutin basıldığında öğenin measureIdsi null olsa bile aktivitenin ölçüsü otomatik atanır ve hedefe yansır', () async {
      // 1. Sıvı Alımı hedefi tanımla
      final liquidGoal = Goal(
        id: 0,
        name: 'Sıvı Alımı',
        target: 1.0, // 1 Litre = 1000 ml
        unitId: 'L',
        mode: 'amount',
        type: 'target',
        period: GoalPeriod.day,
        startDate: DateTime.now().millisecondsSinceEpoch,
        createdAt: DateTime.now().millisecondsSinceEpoch,
        links: [
          GoalLink(activityId: waterAct.id, pct: 100),
          GoalLink(activityId: coffeeAct.id, pct: 100),
        ],
      );
      await store.saveGoal(liquidGoal);

      final initialStatus = store.goalStatus(liquidGoal);
      final initialVal = initialStatus.value; // setUp'taki 200ml + 80ml = 0.28 L

      // 2. Sabah Rutini oluştur (öğelerde measureId null olarak bırakılsın, kullanıcının yaşadığı durum gibi)
      final routine = Routine(
        id: 0,
        name: 'Sabah Rutini',
        emoji: '🌅',
        items: [
          RoutineItem(activityId: waterAct.id, qty: 1.0), // measureId: null
          RoutineItem(activityId: coffeeAct.id, qty: 1.0), // measureId: null
        ],
      );
      await store.saveRoutine(routine);

      // 3. Rutini çalıştır
      final entries = await store.executeRoutine(routine.id);
      expect(entries.length, equals(2));

      // Kayıtlar boş değil, ölçüleriyle ve değerleriyle kaydedilmiş olmalı!
      final waterEntry = entries.firstWhere((e) => e.activityId == waterAct.id);
      final coffeeEntry = entries.firstWhere((e) => e.activityId == coffeeAct.id);

      expect(waterEntry.measureId, equals(glassMeasure.id));
      expect(waterEntry.value, equals(200.0));
      expect(waterEntry.unitId, equals('ml'));

      expect(coffeeEntry.measureId, equals(cupMeasure.id));
      expect(coffeeEntry.value, equals(80.0));
      expect(coffeeEntry.unitId, equals('ml'));

      // 4. Hedefteki sıvı alımı miktarı artmış olmalı! (0.28 L + 0.20 L + 0.08 L = 0.56 L)
      final afterStatus = store.goalStatus(liquidGoal);
      expect(afterStatus.value, closeTo(initialVal + 0.28, 0.001));

      // 5. Kayıtların zaman damgası gece 00:00 değil, şu anki saati taşımalı
      final now = DateTime.now();
      final entryDate = DateTime.fromMillisecondsSinceEpoch(waterEntry.ts);
      expect(entryDate.hour, equals(now.hour));
      expect(entryDate.minute, equals(now.minute));
    });
  });
}
