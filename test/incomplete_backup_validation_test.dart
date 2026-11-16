import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:takip/data/models.dart';
import 'package:takip/data/store.dart';
import 'package:takip/logic/l10n.dart';

import 'support/real_db.dart';

void main() {
  useRealDatabase();

  group('Eksik Yedek Doğrulaması', () {
    test('activities veya entries anahtarı olmayan yedek reddedilir ve veriler korunur', () async {
      await store.load();

      // Örnek başlangıç verileri oluştur
      final act = await store.addActivity('Yürüyüş', emoji: '🚶');
      await store.addEntry(act.id, qty: 30.0);
      await store.saveGoal(Goal(
        id: 0,
        name: 'Haftalık Yürüyüş',
        period: GoalPeriod.week,
        target: 120.0,
        type: 'target',
        mode: 'count',
        startDate: 1700000000000,
        createdAt: 1700000000000,
      ));
      await store.createTodo(Todo(
        id: 0,
        title: 'Yürüyüş ayakkabısı al',
        createdAt: DateTime.now().millisecondsSinceEpoch,
      ));

      final initialActCount = store.activities.length;
      final initialEntryCount = store.entries.length;
      final initialGoalCount = store.goals.length;
      final initialTodoCount = store.todos.length;

      expect(initialActCount, greaterThan(0));
      expect(initialEntryCount, greaterThan(0));
      expect(initialGoalCount, greaterThan(0));
      expect(initialTodoCount, greaterThan(0));

      // 1. activities anahtarı eksik yedek
      final missingActivitiesJson = jsonEncode({
        'app': 'takip',
        'version': 3,
        'entries': [
          {'id': 100, 'activity_id': 1, 'ts': 1700000000000, 'qty': 1.0}
        ],
      });

      await expectLater(
        store.importJson(missingActivitiesJson),
        throwsA(isA<FormatException>().having(
          (e) => e.message,
          'message',
          strings.value.isTr
              ? 'Yedek dosyası eksik: aktiviteler ya da kayıtlar yok.'
              : 'Backup file is incomplete: activities or entries are missing.',
        )),
      );

      // Veritabanındaki veriler hiç bozulmamalı
      expect(store.activities.length, initialActCount);
      expect(store.entries.length, initialEntryCount);
      expect(store.goals.length, initialGoalCount);
      expect(store.todos.length, initialTodoCount);

      // 2. entries anahtarı eksik yedek
      final missingEntriesJson = jsonEncode({
        'app': 'takip',
        'version': 3,
        'activities': [
          {'id': 1, 'name': 'Koşu', 'emoji': '🏃', 'created_at': 1700000000000}
        ],
      });

      await expectLater(
        store.importJson(missingEntriesJson),
        throwsA(isA<FormatException>().having(
          (e) => e.message,
          'message',
          strings.value.isTr
              ? 'Yedek dosyası eksik: aktiviteler ya da kayıtlar yok.'
              : 'Backup file is incomplete: activities or entries are missing.',
        )),
      );

      expect(store.activities.length, initialActCount);
      expect(store.entries.length, initialEntryCount);
      expect(store.goals.length, initialGoalCount);
      expect(store.todos.length, initialTodoCount);

      // 3. activities veya entries liste olmayan yedek (bozuk tip)
      final invalidTypeJson = jsonEncode({
        'app': 'seyir',
        'version': 3,
        'activities': 'geçersiz_tip',
        'entries': [],
      });

      await expectLater(
        store.importJson(invalidTypeJson),
        throwsA(isA<FormatException>().having(
          (e) => e.message,
          'message',
          strings.value.isTr
              ? 'Yedek dosyası eksik: aktiviteler ya da kayıtlar yok.'
              : 'Backup file is incomplete: activities or entries are missing.',
        )),
      );

      // 4. İngilizce yerel ayarda hata iletisi
      store.setLanguage(AppLanguage.en);
      try {
        await expectLater(
          store.importJson(missingActivitiesJson),
          throwsA(isA<FormatException>().having(
            (e) => e.message,
            'message',
            'Backup file is incomplete: activities or entries are missing.',
          )),
        );
      } finally {
        store.setLanguage(AppLanguage.tr);
      }

      // 5. Tam ve eksiksiz yedek sorunsuz yüklenir
      final validBackupJson = await store.exportJson();
      await store.importJson(validBackupJson);

      expect(store.activities.length, initialActCount);
      expect(store.entries.length, initialEntryCount);
      expect(store.goals.length, initialGoalCount);
      expect(store.todos.length, initialTodoCount);
    });
  });
}
