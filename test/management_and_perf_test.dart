import 'package:flutter_test/flutter_test.dart';
import 'package:takip/data/models.dart';
import 'package:takip/data/store.dart';
import 'support/real_db.dart';

void main() {
  useRealDatabase();

  group('Entry Memory Indexing & Fast Lookups', () {
    test('entriesForActivity and lastEntryForActivity return correct results in O(1)', () async {
      final act1 = await store.addActivity('Su');
      final act2 = await store.addActivity('Kitap');

      final now = DateTime.now();
      final e1 = (await store.addEntry(act1.id, at: now.subtract(const Duration(hours: 2)))).entry;
      final e2 = (await store.addEntry(act2.id, at: now.subtract(const Duration(hours: 1)))).entry;
      final e3 = (await store.addEntry(act1.id, at: now)).entry;

      final act1Entries = store.entriesForActivity(act1.id);
      expect(act1Entries.length, equals(2));
      expect(act1Entries.map((e) => e.id), containsAllInOrder([e1.id, e3.id]));

      final act2Entries = store.entriesForActivity(act2.id);
      expect(act2Entries.length, equals(1));
      expect(act2Entries.first.id, equals(e2.id));

      expect(store.lastEntryForActivity(act1.id)?.id, equals(e3.id));
      expect(store.lastEntryForActivity(act2.id)?.id, equals(e2.id));
      expect(store.lastEntryForActivity(9999), isNull);
    });

    test('updating an entry activityId and date updates indexing and database', () async {
      final act1 = await store.addActivity('Aktivite A');
      final act2 = await store.addActivity('Aktivite B');

      final initialTime = DateTime(2026, 5, 10, 14, 0);
      final e = (await store.addEntry(act1.id, at: initialTime)).entry;

      expect(store.entriesForActivity(act1.id).length, equals(1));
      expect(store.entriesForActivity(act2.id).length, equals(0));

      final newTime = DateTime(2026, 5, 15, 16, 30);
      await store.updateEntry(
        e,
        activityId: act2.id,
        time: newTime,
        note: 'Değiştirildi',
      );

      expect(store.entriesForActivity(act1.id).length, equals(0));
      final act2Entries = store.entriesForActivity(act2.id);
      expect(act2Entries.length, equals(1));
      expect(act2Entries.first.activityId, equals(act2.id));
      expect(act2Entries.first.time, equals(newTime));
      expect(act2Entries.first.note, equals('Değiştirildi'));
    });
  });

  group('Reordering & Updating: QuickItems, Goals, Roadmaps', () {
    test('reorderQuickItems updates items sort order and persists', () async {
      final a1 = await store.addActivity('Kahve');
      final a2 = await store.addActivity('Yürüyüş');
      final a3 = await store.addActivity('Meditasyon');

      final now = DateTime.now().millisecondsSinceEpoch;
      final q1 = QuickItem(id: 0, activityId: a1.id, kind: 'button', sort: 0, createdAt: now);
      final q2 = QuickItem(id: 0, activityId: a2.id, kind: 'button', sort: 1, createdAt: now);
      final q3 = QuickItem(id: 0, activityId: a3.id, kind: 'button', sort: 2, createdAt: now);

      await store.saveQuickItem(q1);
      await store.saveQuickItem(q2);
      await store.saveQuickItem(q3);

      expect(store.quickItems.map((q) => q.activityId).toList(), equals([a1.id, a2.id, a3.id]));

      // Move a3 from index 2 to index 0
      await store.reorderQuickItems(2, 0);
      expect(store.quickItems.map((q) => q.activityId).toList(), equals([a3.id, a1.id, a2.id]));

      // Verify persistence by reloading from DB
      final otherStore = await openStore();
      expect(otherStore.quickItems.map((q) => q.activityId).toList(), equals([a3.id, a1.id, a2.id]));
    });

    test('reorderGoals updates goal order and persists', () async {
      final a = await store.addActivity('Egzersiz');
      final g1 = Goal(
        id: 0,
        name: 'Hedef 1',
        mode: 'count',
        period: GoalPeriod.day,
        target: 1,
        sort: 0,
        startDate: 0,
        createdAt: 0,
        links: [GoalLink(activityId: a.id)],
      );
      final g2 = Goal(
        id: 0,
        name: 'Hedef 2',
        mode: 'count',
        period: GoalPeriod.day,
        target: 2,
        sort: 1,
        startDate: 0,
        createdAt: 0,
        links: [GoalLink(activityId: a.id)],
      );
      final g3 = Goal(
        id: 0,
        name: 'Hedef 3',
        mode: 'count',
        period: GoalPeriod.day,
        target: 3,
        sort: 2,
        startDate: 0,
        createdAt: 0,
        links: [GoalLink(activityId: a.id)],
      );

      await store.saveGoal(g1);
      await store.saveGoal(g2);
      await store.saveGoal(g3);

      expect(store.goals.map((g) => g.name).toList(), equals(['Hedef 1', 'Hedef 2', 'Hedef 3']));

      // Move Hedef 1 to index 2
      await store.reorderGoals(0, 2);
      expect(store.goals.map((g) => g.name).toList(), equals(['Hedef 2', 'Hedef 3', 'Hedef 1']));

      // Verify persistence
      final otherStore = await openStore();
      expect(otherStore.goals.map((g) => g.name).toList(), equals(['Hedef 2', 'Hedef 3', 'Hedef 1']));
    });

    test('reorderRoadmapSteps and updateRoadmapStep work properly', () async {
      final r = Roadmap(
        id: 0,
        title: 'Yazılım Öğrenme',
        emoji: '💻',
        category: 'Kariyer',
        status: 'active',
        createdAt: DateTime.now().millisecondsSinceEpoch,
        steps: [
          RoadmapStep(id: 0, roadmapId: 0, order: 1, title: 'Adım 1', type: 'task'),
          RoadmapStep(id: 0, roadmapId: 0, order: 2, title: 'Adım 2', type: 'task'),
          RoadmapStep(id: 0, roadmapId: 0, order: 3, title: 'Adım 3', type: 'task'),
        ],
      );

      final created = await store.createRoadmap(r);
      expect(created.steps.map((s) => s.title).toList(), equals(['Adım 1', 'Adım 2', 'Adım 3']));

      // Reorder: Move Adım 3 to index 0
      await store.reorderRoadmapSteps(created.id, 2, 0);
      expect(created.steps.map((s) => s.title).toList(), equals(['Adım 3', 'Adım 1', 'Adım 2']));

      // Update step details
      final stepToEdit = created.steps.first;
      stepToEdit.title = 'Adım 3 Güncellendi';
      stepToEdit.description = 'Detaylı açıklama';
      stepToEdit.target = 50;
      stepToEdit.unit = 'sayfa';
      stepToEdit.type = 'goal';
      await store.updateRoadmapStep(stepToEdit);

      expect(created.steps.first.title, equals('Adım 3 Güncellendi'));
      expect(created.steps.first.target, equals(50));
      expect(created.steps.first.unit, equals('sayfa'));

      // Verify persistence
      final otherStore = await openStore();
      final reloadedRoadmap = otherStore.roadmaps.firstWhere((rm) => rm.id == created.id);
      expect(reloadedRoadmap.steps.map((s) => s.title).toList(),
          equals(['Adım 3 Güncellendi', 'Adım 1', 'Adım 2']));
    });
  });
}
