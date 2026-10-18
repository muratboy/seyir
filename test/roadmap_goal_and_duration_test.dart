import 'package:flutter_test/flutter_test.dart';
import 'package:takip/data/models.dart';
import 'package:takip/data/store.dart';
import 'support/real_db.dart';

void main() {
  useRealDatabase();

  group('Roadmap Goal and Duration Challenges Tests', () {
    late Activity waterAct;
    late Roadmap roadmap;

    setUp(() async {
      await store.load();
      waterAct = await store.addActivity('Su', emoji: '💧');
      roadmap = await store.createRoadmap(Roadmap(
        title: '3 Ayda Sağlıklı Kilo Verme',
        steps: [
          RoadmapStep(
            title: 'Günlük su tüketimi hedefine ulaş',
            type: 'goal',
            target: 90,
            unit: 'gün',
          ),
          RoadmapStep(
            title: 'Su içme alışkanlığı kazan',
            type: 'goal',
            target: 30,
            unit: 'gün',
          ),
          RoadmapStep(
            title: '60 gün şekersiz beslenme meydan okuması',
            type: 'goal',
            target: 60,
            unit: 'gün',
          ),
        ],
      ));
      await store.setRoadmapStatus(roadmap.id, 'active');
    });

    test('Birimi gün olan adımda aynı gün 4 bardak su içilse bile ilerleme 4 gün değil 1 gün sayılır', () async {
      final step = roadmap.steps[1];
      // Adımı su aktivitesine bağlıyoruz
      await store.setRoadmapStepActivity(step.id, waterAct.id);

      // Aynı gün içinde 4 adet su kaydı giriyoruz
      final mlMeasure = store.measures.firstWhere((m) => m.unitId == 'ml');
      await store.addEntry(waterAct.id, measureId: mlMeasure.id, qty: 250);
      await store.addEntry(waterAct.id, measureId: mlMeasure.id, qty: 250);
      await store.addEntry(waterAct.id, measureId: mlMeasure.id, qty: 300);
      await store.addEntry(waterAct.id, measureId: mlMeasure.id, qty: 200);

      final p = store.stepProgress(roadmap, step);
      expect(p, isNotNull);
      // 4 kayıt girilmiş olsa bile hepsi aynı takvim gününe ait olduğundan ilerleme 1 gün olmalıdır!
      expect(p!.done, equals(1.0));
      expect(p.target, equals(30.0));
      expect(p.reached, isFalse);
    });

    test('Adıma Goal bağlandığında (Sıvı Alımı 2.5L), hedefe ulaşılan gün adım ilerlemesine 1 gün olarak yansır', () async {
      final step = roadmap.steps[0];

      // Günlük 2.5 Litre sıvı alımı hedefi oluşturuyoruz
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final liquidGoal = Goal(
        id: 0,
        name: 'Sıvı Alımı',
        target: 2.5,
        unitId: 'L',
        mode: 'amount',
        type: 'target',
        period: GoalPeriod.day,
        startDate: DateTime.now().subtract(const Duration(days: 2)).millisecondsSinceEpoch,
        createdAt: nowMs,
        links: [
          GoalLink(activityId: waterAct.id, pct: 100),
        ],
      );
      await store.saveGoal(liquidGoal);

      // Adımı bu hedefe bağlıyoruz
      await store.setRoadmapStepGoal(step.id, liquidGoal.id);
      expect(step.linkedGoalId, equals(liquidGoal.id));

      final mlMeasure = store.measures.firstWhere((m) => m.unitId == 'ml');

      // 1. Durum: Hedefin altına düşüldüğünde (1500 ml = 1.5L içildi, hedef 2.5L) adım ilerlemesi 0 gündür
      await store.addEntry(waterAct.id, measureId: mlMeasure.id, qty: 1500);
      var p = store.stepProgress(roadmap, step);
      expect(p, isNotNull);
      expect(p!.done, equals(0.0));

      // 2. Durum: 1000 ml (1.0L) daha içilerek hedefe ulaşıldığında (toplam 2.5L) adım ilerlemesi 1 gün olur
      await store.addEntry(waterAct.id, measureId: mlMeasure.id, qty: 1000);
      p = store.stepProgress(roadmap, step);
      expect(p, isNotNull);
      expect(p!.done, equals(1.0));

      // 3. Durum: Fazladan 500 ml daha içilse de o gün tekil bir gün olduğundan ilerleme 1 gün kalır
      await store.addEntry(waterAct.id, measureId: mlMeasure.id, qty: 500);
      p = store.stepProgress(roadmap, step);
      expect(p, isNotNull);
      expect(p!.done, equals(1.0));
    });

    test('Süreli hedef başlatıldığında geçen süre sayılır ve hedef süreye ulaşınca otomatik tamamlanır', () async {
      final step = roadmap.steps[2]; // 60 gün şekersiz beslenme

      // Süre henüz başlatılmadı
      var p = store.stepProgress(roadmap, step);
      expect(p, isNull);

      // 60 gün öncesinde başlatılmış gibi simüle ediyoruz
      final sixtyDaysAgo = DateTime.now().subtract(const Duration(days: 60)).millisecondsSinceEpoch;
      await store.startRoadmapStepDuration(step.id, startTs: sixtyDaysAgo);

      p = store.stepProgress(roadmap, step);
      expect(p, isNotNull);
      expect(p!.done, equals(60.0));
      expect(p.reached, isTrue);

      // Süre bittiğinde adım otomatik olarak tamamlanmış olmalı
      expect(step.isCompleted, isTrue);
      expect(step.autoCompleted, isTrue);

      // Süreyi baştan başlatma testi
      await store.resetRoadmapStepDuration(step.id);
      expect(step.isCompleted, isFalse);
      expect(step.autoCompleted, isFalse);
      p = store.stepProgress(roadmap, step);
      expect(p, isNotNull);
      expect(p!.done, equals(1.0)); // Bugün dahil 1. gün
    });

    test('Limit hedefine (Günde en fazla 0 sigara) bağlanan adım kural bozulmadığı günlerde ilerler', () async {
      final cigaretteAct = await store.addActivity('Sigara', emoji: '🚬');

      // Günde en fazla 0 sigara limit hedefi
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final noSmokingGoal = Goal(
        id: 0,
        name: 'Sigara Bırakma',
        target: 0.0,
        unitId: 'adet',
        type: 'limit',
        mode: 'count',
        period: GoalPeriod.day,
        startDate: DateTime.now().millisecondsSinceEpoch,
        createdAt: nowMs,
        links: [
          GoalLink(activityId: cigaretteAct.id, pct: 100),
        ],
      );
      await store.saveGoal(noSmokingGoal);

      final smokeStep = RoadmapStep(
        title: '60 gün sigara içmeme',
        type: 'goal',
        target: 60,
        unit: 'gün',
      );
      await store.addRoadmapStep(roadmap.id, smokeStep);
      await store.setRoadmapStepGoal(smokeStep.id, noSmokingGoal.id);

      // Bugün hiç sigara içilmediği için limit aşılmadı ve hedef başarılıdır (1 gün ilerleme)
      final p = store.stepProgress(roadmap, smokeStep);
      expect(p, isNotNull);
      expect(p!.done, equals(1.0));
    });

    test('Aktivite bağlanmamış bir hedefe doğrudan check-in yapıldığında hedefe ulaşılmış sayılır, seri artar ve bağlı adım ilerler', () async {
      // 1. Aktivite bağlanmamış bir hedef oluştur (örn: "Günde 8 saat kaliteli uyku")
      final now = DateTime.now();
      final sleepGoal = Goal(
        id: 0,
        name: 'Kaliteli Uyku',
        target: 1.0,
        unitId: 'adet',
        type: 'target',
        mode: 'count',
        period: GoalPeriod.day,
        startDate: now.subtract(const Duration(days: 3)).millisecondsSinceEpoch,
        createdAt: now.millisecondsSinceEpoch,
        links: [], // Aktivite bağı yok!
      );
      await store.saveGoal(sleepGoal);

      // Başlangıçta henüz check-in yapılmadı
      var st = store.goalStatus(sleepGoal);
      expect(st.done, isFalse);
      expect(st.isManual, isFalse);
      expect(store.isGoalCheckinDone(sleepGoal), isFalse);

      // 2. Bir yol haritası adımını bu aktivitesiz hedefe bağlayalım
      final sleepStep = RoadmapStep(
        title: '30 gün düzenli uyku',
        type: 'goal',
        target: 30,
        unit: 'gün',
      );
      await store.addRoadmapStep(roadmap.id, sleepStep);
      await store.setRoadmapStepGoal(sleepStep.id, sleepGoal.id);

      var p = store.stepProgress(roadmap, sleepStep);
      expect(p, isNotNull);
      expect(p!.done, equals(0.0));

      // 3. Doğrudan check-in (Ulaşıldı) işaretlemesi yapıyoruz
      final checkinResult = await store.toggleGoalCheckin(sleepGoal);
      expect(checkinResult, isTrue);
      expect(store.isGoalCheckinDone(sleepGoal), isTrue);

      st = store.goalStatus(sleepGoal);
      expect(st.done, isTrue);
      expect(st.isManual, isTrue);
      expect(st.ratio, equals(1.0));

      // Seri (streak) kontrolü: bugün tamamlandığı için en az 1 olmalıdır
      final streak = store.goalStreak(sleepGoal);
      expect(streak, equals(1));

      // Isı haritası ve streak info kontrolü
      final streakInfo = store.goalStreakInfo(sleepGoal);
      expect(streakInfo.isDoneToday, isTrue);

      // 4. Bağlı yol haritası adımının ilerlemesi kontrolü (1 gün ilerlemiş olmalı)
      p = store.stepProgress(roadmap, sleepStep);
      expect(p, isNotNull);
      expect(p!.done, equals(1.0));

      // 5. Check-in geri alındığında (toggle) durum eski haline dönmeli
      final uncheckResult = await store.toggleGoalCheckin(sleepGoal);
      expect(uncheckResult, isFalse);
      expect(store.isGoalCheckinDone(sleepGoal), isFalse);

      st = store.goalStatus(sleepGoal);
      expect(st.done, isFalse);
      expect(st.isManual, isFalse);

      p = store.stepProgress(roadmap, sleepStep);
      expect(p, isNotNull);
      expect(p!.done, equals(0.0));
    });
  });
}
