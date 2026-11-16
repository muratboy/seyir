import 'package:flutter_test/flutter_test.dart';
import 'package:takip/data/models.dart';
import 'package:takip/logic/l10n.dart';
import 'package:takip/services/nl_parser.dart';

void main() {
  setUp(() {
    strings.value = const AppStrings(AppLanguage.tr);
  });

  group('Başında sıfır olan saat yazımları', () {
    final kahve = Activity(id: 1, name: 'Kahve', emoji: '☕', createdAt: 0);
    final ilac = Activity(id: 2, name: 'İlaç', emoji: '💊', createdAt: 0);
    final acts = [kahve, ilac];

    test('now = 2026-11-11 23:30 referansında saat ve gün çözümlemeleri', () {
      final now = DateTime(2026, 11, 11, 23, 30);

      // 07:00 kahve -> 2026-11-11 07:00
      final r1 = NaturalLanguageParser.parseMulti(
        '07:00 kahve',
        activities: acts,
        measures: const [],
        openTodos: const [],
        now: now,
        fallbackDay: now,
      );
      expect((r1.items.first as EntryParsedItem).at, DateTime(2026, 11, 11, 7, 0));

      // 08:15 ilaç -> 2026-11-11 08:15
      final r2 = NaturalLanguageParser.parseMulti(
        '08:15 ilaç',
        activities: acts,
        measures: const [],
        openTodos: const [],
        now: now,
        fallbackDay: now,
      );
      expect((r2.items.first as EntryParsedItem).at, DateTime(2026, 11, 11, 8, 15));

      // sabah 07:00 kahve -> 2026-11-11 07:00
      final r3 = NaturalLanguageParser.parseMulti(
        'sabah 07:00 kahve',
        activities: acts,
        measures: const [],
        openTodos: const [],
        now: now,
        fallbackDay: now,
      );
      expect((r3.items.first as EntryParsedItem).at, DateTime(2026, 11, 11, 7, 0));

      // dün 07:00 kahve -> 2026-11-10 07:00
      final r4 = NaturalLanguageParser.parseMulti(
        'dün 07:00 kahve',
        activities: acts,
        measures: const [],
        openTodos: const [],
        now: now,
        fallbackDay: now,
      );
      expect((r4.items.first as EntryParsedItem).at, DateTime(2026, 11, 10, 7, 0));

      // akşam 07:00 kahve -> 2026-11-11 19:00 (günün bölümü yazılmışsa o geçerli)
      final r5 = NaturalLanguageParser.parseMulti(
        'akşam 07:00 kahve',
        activities: acts,
        measures: const [],
        openTodos: const [],
        now: now,
        fallbackDay: now,
      );
      expect((r5.items.first as EntryParsedItem).at, DateTime(2026, 11, 11, 19, 0));
    });

    test('now = 2026-11-11 06:00 referansında henüz gelmemiş saat düne yazılır', () {
      final now = DateTime(2026, 11, 11, 6, 0);

      // 07:00 kahve -> 2026-11-10 07:00 (bugün 07:00 henüz gelmedi; kayıt düne yazılır)
      final r1 = NaturalLanguageParser.parseMulti(
        '07:00 kahve',
        activities: acts,
        measures: const [],
        openTodos: const [],
        now: now,
        fallbackDay: now,
      );
      expect((r1.items.first as EntryParsedItem).at, DateTime(2026, 11, 10, 7, 0));

      // dün 07:00 kahve -> 2026-11-10 07:00
      final r2 = NaturalLanguageParser.parseMulti(
        'dün 07:00 kahve',
        activities: acts,
        measures: const [],
        openTodos: const [],
        now: now,
        fallbackDay: now,
      );
      expect((r2.items.first as EntryParsedItem).at, DateTime(2026, 11, 10, 7, 0));
    });

    test('now = 2026-11-11 15:00 referansında saat biçimleri çözümlenir', () {
      final now = DateTime(2026, 11, 11, 15, 0);

      // 07:00 kahve -> 2026-11-11 07:00
      final r1 = NaturalLanguageParser.parseMulti(
        '07:00 kahve',
        activities: acts,
        measures: const [],
        openTodos: const [],
        now: now,
        fallbackDay: now,
      );
      expect((r1.items.first as EntryParsedItem).at, DateTime(2026, 11, 11, 7, 0));

      // 01:15 kahve -> 2026-11-11 01:15
      final r2 = NaturalLanguageParser.parseMulti(
        '01:15 kahve',
        activities: acts,
        measures: const [],
        openTodos: const [],
        now: now,
        fallbackDay: now,
      );
      expect((r2.items.first as EntryParsedItem).at, DateTime(2026, 11, 11, 1, 15));

      // 7:00 kahve -> 2026-11-11 07:00
      final r3 = NaturalLanguageParser.parseMulti(
        '7:00 kahve',
        activities: acts,
        measures: const [],
        openTodos: const [],
        now: now,
        fallbackDay: now,
      );
      expect((r3.items.first as EntryParsedItem).at, DateTime(2026, 11, 11, 7, 0));
    });
  });
}
