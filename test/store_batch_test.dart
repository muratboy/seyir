import 'package:flutter_test/flutter_test.dart';
import 'package:takip/data/models.dart';

import 'support/real_db.dart';

void main() {
  useRealDatabase();

  group('Store Batch Save & Undo Tests', () {
    test('saveBatch saves multiple entries and todos in a single transaction with correct times', () async {
      final s = await openStore();
      final su = await s.addActivity('Su', emoji: '💧');
      final kosu = await s.addActivity('Koşu', emoji: '🏃');

      final now = DateTime.now();
      final yesterday = DateTime(now.year, now.month, now.day - 1, 10, 0);

      final batchRes = await s.saveBatch(
        entries: [
          BatchEntryInput(activityId: su.id, qty: 2.0, at: yesterday),
          BatchEntryInput(activityId: kosu.id, qty: 30.0, at: now),
        ],
        todos: [
          BatchTodoInput(
            title: 'Dişçiyi ara',
            dueDate: DateTime(now.year, now.month, now.day + 1),
          ),
        ],
      );

      expect(batchRes.entries.length, 2);
      expect(batchRes.todos.length, 1);

      // Verify in-memory state
      expect(s.entries.any((e) => e.activityId == su.id && e.time.day == yesterday.day), true);
      expect(s.entries.any((e) => e.activityId == kosu.id && e.time.day == now.day), true);
      expect(s.todos.any((t) => t.title == 'Dişçiyi ara'), true);

      // Verify database state
      final db = await s.db;
      final entryRows = await db.query('entries');
      final todoRows = await db.query('todos');
      expect(entryRows.length, 2);
      expect(todoRows.length, 1);
    });

    test('undo deletes all created batch entries and todos atomically', () async {
      final s = await openStore();
      final su = await s.addActivity('Su', emoji: '💧');

      final now = DateTime.now();
      final batchRes = await s.saveBatch(
        entries: [
          BatchEntryInput(activityId: su.id, qty: 1.0, at: now),
        ],
        todos: [
          BatchTodoInput(title: 'Fatura öde'),
        ],
      );

      expect(s.entries.length, 1);
      expect(s.todos.length, 1);

      // Call undo
      await batchRes.undo();

      // State is cleanly restored
      expect(s.entries.isEmpty, true);
      expect(s.todos.isEmpty, true);

      final db = await s.db;
      final entryRows = await db.query('entries');
      final todoRows = await db.query('todos');
      expect(entryRows.isEmpty, true);
      expect(todoRows.isEmpty, true);
    });

    test('entry to past day contributes to that day\'s goal and does not affect today', () async {
      final s = await openStore();
      final su = await s.addActivity('Su', emoji: '💧');

      final now = DateTime.now();
      final yesterday = DateTime(now.year, now.month, now.day - 1, 12, 0);

      // Create a daily goal for Su (target 1 count)
      final goal = Goal(
        id: 0,
        name: 'Günde 1 Su',
        type: 'target',
        mode: 'count',
        target: 1.0,
        period: GoalPeriod.day,
        startDate: DateTime(now.year, now.month, now.day - 5).millisecondsSinceEpoch,
        createdAt: DateTime.now().millisecondsSinceEpoch,
        links: [GoalLink(activityId: su.id, pct: 100)],
      );
      await s.saveGoal(goal);

      // Before logging: both yesterday and today have 0
      final statusYesterdayBefore = s.goalStatus(s.goals.first, at: yesterday);
      final statusTodayBefore = s.goalStatus(s.goals.first, at: now);
      expect(statusYesterdayBefore.value, 0.0);
      expect(statusTodayBefore.value, 0.0);

      // Batch save entry to yesterday
      await s.saveBatch(
        entries: [
          BatchEntryInput(activityId: su.id, qty: 1.0, at: yesterday),
        ],
      );

      // After logging: yesterday is done (1.0), today is still 0.0!
      final statusYesterdayAfter = s.goalStatus(s.goals.first, at: yesterday);
      final statusTodayAfter = s.goalStatus(s.goals.first, at: now);
      expect(statusYesterdayAfter.value, 1.0);
      expect(statusYesterdayAfter.done, true);
      expect(statusTodayAfter.value, 0.0);
      expect(statusTodayAfter.done, false);
    });

    test('todo batch creates todos and no entries are created', () async {
      final s = await openStore();
      final batchRes = await s.saveBatch(
        todos: [
          BatchTodoInput(title: 'Raporu hazırla'),
          BatchTodoInput(title: 'Kitap oku'),
        ],
      );

      expect(batchRes.entries.isEmpty, true);
      expect(batchRes.todos.length, 2);
      expect(s.entries.isEmpty, true);
      expect(s.todos.length, 2);

      final db = await s.db;
      final entryRows = await db.query('entries');
      expect(entryRows.isEmpty, true);
    });
  });
}
