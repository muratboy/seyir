import 'package:flutter_test/flutter_test.dart';
import 'package:takip/data/models.dart';
import 'package:takip/services/roadmap_parser.dart';

void main() {
  group('RoadmapParser Tests', () {
    test('promptTemplate contains JSON schema instructions and markdown guide', () {
      final template = RoadmapParser.promptTemplate;
      expect(template, contains('JSON kalıbını'));
      expect(template, contains('"title"'));
      expect(template, contains('"steps"'));
      expect(template, contains('"type": "task"'));
      expect(template, contains('"type": "goal"'));
    });

    test('parses clean valid JSON correctly', () {
      const jsonStr = '''
      {
        "roadmap": {
          "title": "Kilo Verme ve Sağlıklı Yaşam",
          "description": "3 aylık dengeli kilo verme ve spor yolculuğu",
          "emoji": "🏃",
          "category": "Sağlık",
          "steps": [
            {
              "order": 1,
              "title": "Günde 2.5 litre su iç",
              "description": "Metabolizmayı hızlandırmak için düzenli su tüketimi",
              "type": "goal",
              "target": 2.5,
              "unit": "L"
            },
            {
              "order": 2,
              "title": "Sağlıklı beslenme rehberini oku",
              "description": "Makro besin dengelerini öğren",
              "type": "task"
            },
            {
              "order": 3,
              "title": "Haftada 3 gün 5 km koş",
              "description": "Kardiyo egzersizi",
              "type": "goal",
              "target": 5.0,
              "unit": "km"
            }
          ]
        }
      }
      ''';

      final roadmap = RoadmapParser.parse(jsonStr);
      expect(roadmap, isNotNull);
      expect(roadmap!.title, equals('Kilo Verme ve Sağlıklı Yaşam'));
      expect(roadmap.description, equals('3 aylık dengeli kilo verme ve spor yolculuğu'));
      expect(roadmap.emoji, equals('🏃'));
      expect(roadmap.category, equals('Sağlık'));
      expect(roadmap.steps.length, equals(3));

      // Step 1: Measured goal
      final s1 = roadmap.steps[0];
      expect(s1.order, equals(1));
      expect(s1.title, equals('Günde 2.5 litre su iç'));
      expect(s1.type, equals('goal'));
      expect(s1.target, equals(2.5));
      expect(s1.unit, equals('L'));
      expect(s1.isCompleted, isFalse);

      // Step 2: Unmeasured task (e.g. check-off task like repairing a radio)
      final s2 = roadmap.steps[1];
      expect(s2.order, equals(2));
      expect(s2.title, equals('Sağlıklı beslenme rehberini oku'));
      expect(s2.type, equals('task'));
      expect(s2.target, isNull);
      expect(s2.isCompleted, isFalse);

      // Step 3: Measured goal
      final s3 = roadmap.steps[2];
      expect(s3.order, equals(3));
      expect(s3.type, equals('goal'));
      expect(s3.target, equals(5.0));
      expect(s3.unit, equals('km'));
    });

    test('extracts JSON from LLM markdown code blocks with surrounding commentary', () {
      const llmOutput = '''
      Elbette! İşte senin için hazırladığım detaylı yol haritası:

      ```json
      {
        "roadmap": {
          "title": "Elektronik ve Radyo Tamiri Öğrenme",
          "description": "Temel elektronikten eski radyoları onarmaya uzanan yolculuk",
          "emoji": "🛠️",
          "steps": [
            {
              "order": 1,
              "title": "Havya ve lehim takımı temin et",
              "type": "task"
            },
            {
              "order": 2,
              "title": "Kondansatör ve direnç ölçümlerini öğren",
              "type": "task"
            },
            {
              "order": 3,
              "title": "Bozuk radyoyu tamir et",
              "description": "Güç katındaki arızalı parçayı değiştirip çalıştır",
              "type": "task"
            }
          ]
        }
      }
      ```

      Umarım bu plan hedeflerine ulaşmanda sana yardımcı olur! Başarılar dilerim.
      ''';

      final roadmap = RoadmapParser.parse(llmOutput);
      expect(roadmap, isNotNull);
      expect(roadmap!.title, equals('Elektronik ve Radyo Tamiri Öğrenme'));
      expect(roadmap.emoji, equals('🛠️'));
      expect(roadmap.steps.length, equals(3));
      expect(roadmap.steps[2].title, equals('Bozuk radyoyu tamir et'));
      expect(roadmap.steps[2].type, equals('task'));
    });

    test('handles invalid text by returning null without exceptions', () {
      expect(RoadmapParser.parse(''), isNull);
      expect(RoadmapParser.parse('Merhaba dünya, bu bir yol haritası değil.'), isNull);
      expect(RoadmapParser.parse('{ "yanlis": "format" }'), isNull);
    });
  });

  group('Roadmap Model & Progress Calculation Tests', () {
    test('calculates step counts and percentages correctly', () {
      final step1 = RoadmapStep(id: 1, roadmapId: 10, order: 1, title: 'Adım 1', isCompleted: true);
      final step2 = RoadmapStep(id: 2, roadmapId: 10, order: 2, title: 'Adım 2', isCompleted: false);
      final step3 = RoadmapStep(id: 3, roadmapId: 10, order: 3, title: 'Adım 3', isCompleted: false);
      final step4 = RoadmapStep(id: 4, roadmapId: 10, order: 4, title: 'Adım 4', isCompleted: true);

      final roadmap = Roadmap(
        id: 10,
        title: 'Test Haritası',
        status: 'active',
        steps: [step1, step2, step3, step4],
      );

      expect(roadmap.totalSteps, equals(4));
      expect(roadmap.completedStepsCount, equals(2));
      expect(roadmap.progressRatio, equals(0.5));
      expect(roadmap.progressPercent, equals(50));
      expect(roadmap.isActive, isTrue);
      expect(roadmap.isCompleted, isFalse);
    });

    test('currentPendingStep finds lowest order incomplete step', () {
      final step1 = RoadmapStep(id: 1, roadmapId: 1, order: 1, title: 'Bitmiş Adım', isCompleted: true);
      final step2 = RoadmapStep(id: 2, roadmapId: 1, order: 2, title: 'Sıradaki Adım', isCompleted: false);
      final step3 = RoadmapStep(id: 3, roadmapId: 1, order: 3, title: 'Gelecek Adım', isCompleted: false);

      final roadmap = Roadmap(
        id: 1,
        title: 'Rota',
        steps: [step3, step1, step2], // karışık sıra
      );

      final next = roadmap.currentPendingStep;
      expect(next, isNotNull);
      expect(next!.id, equals(2));
      expect(next.title, equals('Sıradaki Adım'));
    });

    test('currentPendingStep returns null when all steps are completed', () {
      final step1 = RoadmapStep(id: 1, roadmapId: 1, order: 1, title: 'Adım 1', isCompleted: true);
      final step2 = RoadmapStep(id: 2, roadmapId: 1, order: 2, title: 'Adım 2', isCompleted: true);

      final roadmap = Roadmap(
        id: 1,
        title: 'Tamamlanan Rota',
        steps: [step1, step2],
      );

      expect(roadmap.currentPendingStep, isNull);
      expect(roadmap.progressRatio, equals(1.0));
      expect(roadmap.progressPercent, equals(100));
    });

    test('serialization toMap and fromMap works symmetrically', () {
      final original = Roadmap(
        id: 5,
        title: 'Yazılım Geliştirici Olma',
        description: 'Flutter ve Dart öğrenme yolu',
        category: 'Kariyer',
        emoji: '💻',
        status: 'active',
        createdAt: 1700000000000,
        startedAt: 1700000050000,
        completedAt: null,
      );

      final map = original.toMap();
      final revived = Roadmap.fromMap(map);

      expect(revived.id, equals(original.id));
      expect(revived.title, equals(original.title));
      expect(revived.description, equals(original.description));
      expect(revived.category, equals(original.category));
      expect(revived.emoji, equals(original.emoji));
      expect(revived.status, equals(original.status));
      expect(revived.createdAt, equals(original.createdAt));
      expect(revived.startedAt, equals(original.startedAt));
    });

    test('step serialization toMap and fromMap handles task and goal', () {
      final taskStep = RoadmapStep(
        id: 101,
        roadmapId: 5,
        order: 1,
        title: 'Radyoyu tamir et',
        description: 'Parçayı değiştir',
        type: 'task',
        isCompleted: true,
        completedAt: 1700000010000,
      );

      final taskMap = taskStep.toMap();
      final revivedTask = RoadmapStep.fromMap(taskMap);
      expect(revivedTask.id, equals(101));
      expect(revivedTask.title, equals('Radyoyu tamir et'));
      expect(revivedTask.isTask, isTrue);
      expect(revivedTask.isCompleted, isTrue);

      final goalStep = RoadmapStep(
        id: 102,
        roadmapId: 5,
        order: 2,
        title: '10 saat kod yaz',
        type: 'goal',
        target: 10.0,
        unit: 'sa',
        isCompleted: false,
      );

      final goalMap = goalStep.toMap();
      final revivedGoal = RoadmapStep.fromMap(goalMap);
      expect(revivedGoal.id, equals(102));
      expect(revivedGoal.isGoal, isTrue);
      expect(revivedGoal.target, equals(10.0));
      expect(revivedGoal.unit, equals('sa'));
    });
  });
}
