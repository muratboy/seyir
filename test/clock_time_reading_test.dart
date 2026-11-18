import 'package:flutter_test/flutter_test.dart';
import 'package:takip/data/models.dart';
import 'package:takip/logic/l10n.dart';
import 'package:takip/services/nl_parser.dart';

void main() {
  setUp(() {
    strings.value = const AppStrings(AppLanguage.tr);
  });

  group('Saat yazımı ve çözümlemeleri', () {
    final kahve = Activity(id: 1, name: 'Kahve', emoji: '☕', createdAt: 0);
    final ilac = Activity(id: 2, name: 'İlaç', emoji: '💊', createdAt: 0);
    final kahvalti = Activity(id: 3, name: 'Kahvaltı', emoji: '🍳', createdAt: 0);
    final toplanti = Activity(id: 4, name: 'Toplantı', emoji: '📅', createdAt: 0);
    final kosu = Activity(id: 5, name: 'Koşu', emoji: '🏃', createdAt: 0);
    final coffee = Activity(id: 6, name: 'Coffee', emoji: '☕', createdAt: 0);
    final acts = [kahve, ilac, kahvalti, toplanti, kosu, coffee];

    test('now = 2026-11-11 23:30 referansında Türkçe saat çözümlemeleri', () {
      final now = DateTime(2026, 11, 11, 23, 30);

      // 7:30 kahvaltı -> 2026-11-11 07:30
      final r1 = NaturalLanguageParser.parseMulti(
        '7:30 kahvaltı',
        activities: acts,
        measures: const [],
        openTodos: const [],
        now: now,
        fallbackDay: now,
      );
      expect((r1.items.first as EntryParsedItem).at, DateTime(2026, 11, 11, 7, 30));

      // 8:15 ilaç -> 2026-11-11 08:15
      final r2 = NaturalLanguageParser.parseMulti(
        '8:15 ilaç',
        activities: acts,
        measures: const [],
        openTodos: const [],
        now: now,
        fallbackDay: now,
      );
      expect((r2.items.first as EntryParsedItem).at, DateTime(2026, 11, 11, 8, 15));

      // 12:30 kahve -> 2026-11-11 12:30
      final r3 = NaturalLanguageParser.parseMulti(
        '12:30 kahve',
        activities: acts,
        measures: const [],
        openTodos: const [],
        now: now,
        fallbackDay: now,
      );
      expect((r3.items.first as EntryParsedItem).at, DateTime(2026, 11, 11, 12, 30));

      // 9:00 toplantı -> 2026-11-11 09:00
      final r4 = NaturalLanguageParser.parseMulti(
        '9:00 toplantı',
        activities: acts,
        measures: const [],
        openTodos: const [],
        now: now,
        fallbackDay: now,
      );
      expect((r4.items.first as EntryParsedItem).at, DateTime(2026, 11, 11, 9, 0));

      // 5:00 koşu -> 2026-11-11 05:00
      final r5 = NaturalLanguageParser.parseMulti(
        '5:00 koşu',
        activities: acts,
        measures: const [],
        openTodos: const [],
        now: now,
        fallbackDay: now,
      );
      expect((r5.items.first as EntryParsedItem).at, DateTime(2026, 11, 11, 5, 0));

      // 1:15 kahve -> 2026-11-11 01:15
      final r6 = NaturalLanguageParser.parseMulti(
        '1:15 kahve',
        activities: acts,
        measures: const [],
        openTodos: const [],
        now: now,
        fallbackDay: now,
      );
      expect((r6.items.first as EntryParsedItem).at, DateTime(2026, 11, 11, 1, 15));

      // 7.30 kahve -> 2026-11-11 07:30
      final r7 = NaturalLanguageParser.parseMulti(
        '7.30 kahve',
        activities: acts,
        measures: const [],
        openTodos: const [],
        now: now,
        fallbackDay: now,
      );
      expect((r7.items.first as EntryParsedItem).at, DateTime(2026, 11, 11, 7, 30));

      // saat 7:30 kahve -> 2026-11-11 07:30
      final r8 = NaturalLanguageParser.parseMulti(
        'saat 7:30 kahve',
        activities: acts,
        measures: const [],
        openTodos: const [],
        now: now,
        fallbackDay: now,
      );
      expect((r8.items.first as EntryParsedItem).at, DateTime(2026, 11, 11, 7, 30));

      // dün 7:00 kahve -> 2026-11-10 07:00
      final r9 = NaturalLanguageParser.parseMulti(
        'dün 7:00 kahve',
        activities: acts,
        measures: const [],
        openTodos: const [],
        now: now,
        fallbackDay: now,
      );
      expect((r9.items.first as EntryParsedItem).at, DateTime(2026, 11, 10, 7, 0));

      // akşam 7:30 kahve -> 2026-11-11 19:30
      final r10 = NaturalLanguageParser.parseMulti(
        'akşam 7:30 kahve',
        activities: acts,
        measures: const [],
        openTodos: const [],
        now: now,
        fallbackDay: now,
      );
      expect((r10.items.first as EntryParsedItem).at, DateTime(2026, 11, 11, 19, 30));

      // saat 7 kahve -> 2026-11-11 19:00 (dakikası yazılmamış; en yakın geçmiş saat tahminiyle akşam)
      final r11 = NaturalLanguageParser.parseMulti(
        'saat 7 kahve',
        activities: acts,
        measures: const [],
        openTodos: const [],
        now: now,
        fallbackDay: now,
      );
      expect((r11.items.first as EntryParsedItem).at, DateTime(2026, 11, 11, 19, 0));

      // Başında sıfır olan saatler:
      // 07:00 kahve -> 2026-11-11 07:00
      final r12 = NaturalLanguageParser.parseMulti(
        '07:00 kahve',
        activities: acts,
        measures: const [],
        openTodos: const [],
        now: now,
        fallbackDay: now,
      );
      expect((r12.items.first as EntryParsedItem).at, DateTime(2026, 11, 11, 7, 0));

      // 08:15 ilaç -> 2026-11-11 08:15
      final r13 = NaturalLanguageParser.parseMulti(
        '08:15 ilaç',
        activities: acts,
        measures: const [],
        openTodos: const [],
        now: now,
        fallbackDay: now,
      );
      expect((r13.items.first as EntryParsedItem).at, DateTime(2026, 11, 11, 8, 15));

      // sabah 07:00 kahve -> 2026-11-11 07:00
      final r14 = NaturalLanguageParser.parseMulti(
        'sabah 07:00 kahve',
        activities: acts,
        measures: const [],
        openTodos: const [],
        now: now,
        fallbackDay: now,
      );
      expect((r14.items.first as EntryParsedItem).at, DateTime(2026, 11, 11, 7, 0));

      // dün 07:00 kahve -> 2026-11-10 07:00
      final r15 = NaturalLanguageParser.parseMulti(
        'dün 07:00 kahve',
        activities: acts,
        measures: const [],
        openTodos: const [],
        now: now,
        fallbackDay: now,
      );
      expect((r15.items.first as EntryParsedItem).at, DateTime(2026, 11, 10, 7, 0));

      // akşam 07:00 kahve -> 2026-11-11 19:00 (günün bölümü yazılmışsa o geçerli)
      final r16 = NaturalLanguageParser.parseMulti(
        'akşam 07:00 kahve',
        activities: acts,
        measures: const [],
        openTodos: const [],
        now: now,
        fallbackDay: now,
      );
      expect((r16.items.first as EntryParsedItem).at, DateTime(2026, 11, 11, 19, 0));
    });

    test('now = 2026-11-11 06:00 referansında henüz gelmemiş saat düne yazılır', () {
      final now = DateTime(2026, 11, 11, 6, 0);

      // 7:30 kahve -> 2026-11-10 07:30
      final r1 = NaturalLanguageParser.parseMulti(
        '7:30 kahve',
        activities: acts,
        measures: const [],
        openTodos: const [],
        now: now,
        fallbackDay: now,
      );
      expect((r1.items.first as EntryParsedItem).at, DateTime(2026, 11, 10, 7, 30));

      // 12:30 kahve -> 2026-11-10 12:30
      final r2 = NaturalLanguageParser.parseMulti(
        '12:30 kahve',
        activities: acts,
        measures: const [],
        openTodos: const [],
        now: now,
        fallbackDay: now,
      );
      expect((r2.items.first as EntryParsedItem).at, DateTime(2026, 11, 10, 12, 30));

      // 5:00 koşu -> 2026-11-11 05:00 (06:00'dan önce olduğu için bugün)
      final r3 = NaturalLanguageParser.parseMulti(
        '5:00 koşu',
        activities: acts,
        measures: const [],
        openTodos: const [],
        now: now,
        fallbackDay: now,
      );
      expect((r3.items.first as EntryParsedItem).at, DateTime(2026, 11, 11, 5, 0));

      // saat 7 kahve -> 2026-11-10 19:00 (tahmin, değişmedi)
      final r4 = NaturalLanguageParser.parseMulti(
        'saat 7 kahve',
        activities: acts,
        measures: const [],
        openTodos: const [],
        now: now,
        fallbackDay: now,
      );
      expect((r4.items.first as EntryParsedItem).at, DateTime(2026, 11, 10, 19, 0));

      // 07:00 kahve -> 2026-11-10 07:00 (başında sıfır olan saat; henüz gelmediği için dün)
      final r5 = NaturalLanguageParser.parseMulti(
        '07:00 kahve',
        activities: acts,
        measures: const [],
        openTodos: const [],
        now: now,
        fallbackDay: now,
      );
      expect((r5.items.first as EntryParsedItem).at, DateTime(2026, 11, 10, 7, 0));

      // dün 07:00 kahve -> 2026-11-10 07:00
      final r6 = NaturalLanguageParser.parseMulti(
        'dün 07:00 kahve',
        activities: acts,
        measures: const [],
        openTodos: const [],
        now: now,
        fallbackDay: now,
      );
      expect((r6.items.first as EntryParsedItem).at, DateTime(2026, 11, 10, 7, 0));
    });

    test('now = 2026-11-11 15:00 referansında saat biçimleri çözümlenir', () {
      final now = DateTime(2026, 11, 11, 15, 0);

      // 7:30 kahve -> 2026-11-11 07:30
      final r1 = NaturalLanguageParser.parseMulti(
        '7:30 kahve',
        activities: acts,
        measures: const [],
        openTodos: const [],
        now: now,
        fallbackDay: now,
      );
      expect((r1.items.first as EntryParsedItem).at, DateTime(2026, 11, 11, 7, 30));

      // 1:15 kahve -> 2026-11-11 01:15
      final r2 = NaturalLanguageParser.parseMulti(
        '1:15 kahve',
        activities: acts,
        measures: const [],
        openTodos: const [],
        now: now,
        fallbackDay: now,
      );
      expect((r2.items.first as EntryParsedItem).at, DateTime(2026, 11, 11, 1, 15));

      // 12:30 kahve -> 2026-11-11 12:30
      final r3 = NaturalLanguageParser.parseMulti(
        '12:30 kahve',
        activities: acts,
        measures: const [],
        openTodos: const [],
        now: now,
        fallbackDay: now,
      );
      expect((r3.items.first as EntryParsedItem).at, DateTime(2026, 11, 11, 12, 30));

      // 19:30 kahve -> 2026-11-10 19:30 (15:00'ten sonra olduğu için dünün 19:30'u)
      final r4 = NaturalLanguageParser.parseMulti(
        '19:30 kahve',
        activities: acts,
        measures: const [],
        openTodos: const [],
        now: now,
        fallbackDay: now,
      );
      expect((r4.items.first as EntryParsedItem).at, DateTime(2026, 11, 10, 19, 30));

      // yarın 7:00 toplantı -> 2026-11-12 07:00 ve gelecek zamanlı
      final r5 = NaturalLanguageParser.parseMulti(
        'yarın 7:00 toplantı',
        activities: acts,
        measures: const [],
        openTodos: const [],
        now: now,
        fallbackDay: now,
      );
      final r5Entry = r5.items.first as EntryParsedItem;
      expect(r5Entry.at, DateTime(2026, 11, 12, 7, 0));
      expect(r5Entry.isExplicitFuture, isTrue);

      final converted = NaturalLanguageParser.convertFutureEntriesToTodos(
        r5.items,
        activities: acts,
        now: now,
      );
      expect(converted.first, isA<TodoParsedItem>());
      final todoItem = converted.first as TodoParsedItem;
      expect(todoItem.dueDate, DateTime(2026, 11, 12, 7, 0));

      // 07:00 kahve -> 2026-11-11 07:00
      final r6 = NaturalLanguageParser.parseMulti(
        '07:00 kahve',
        activities: acts,
        measures: const [],
        openTodos: const [],
        now: now,
        fallbackDay: now,
      );
      expect((r6.items.first as EntryParsedItem).at, DateTime(2026, 11, 11, 7, 0));

      // 01:15 kahve -> 2026-11-11 01:15
      final r7 = NaturalLanguageParser.parseMulti(
        '01:15 kahve',
        activities: acts,
        measures: const [],
        openTodos: const [],
        now: now,
        fallbackDay: now,
      );
      expect((r7.items.first as EntryParsedItem).at, DateTime(2026, 11, 11, 1, 15));

      // 7:00 kahve -> 2026-11-11 07:00
      final r8 = NaturalLanguageParser.parseMulti(
        '7:00 kahve',
        activities: acts,
        measures: const [],
        openTodos: const [],
        now: now,
        fallbackDay: now,
      );
      expect((r8.items.first as EntryParsedItem).at, DateTime(2026, 11, 11, 7, 0));
    });

    test('İngilizce arayüzde 12 saatlik tahmin korunur', () {
      strings.value = const AppStrings(AppLanguage.en);
      final now = DateTime(2026, 11, 11, 23, 30);

      // now = 23:30 iken "7:30 coffee" en yakın geçmiş saat olan 19:30'a çözülür
      final r1 = NaturalLanguageParser.parseMulti(
        '7:30 coffee',
        activities: acts,
        measures: const [],
        openTodos: const [],
        now: now,
        fallbackDay: now,
      );
      expect((r1.items.first as EntryParsedItem).at, DateTime(2026, 11, 11, 19, 30));

      // "07:30 coffee" başında sıfır olduğu için 07:30 olarak çözülür
      final r2 = NaturalLanguageParser.parseMulti(
        '07:30 coffee',
        activities: acts,
        measures: const [],
        openTodos: const [],
        now: now,
        fallbackDay: now,
      );
      expect((r2.items.first as EntryParsedItem).at, DateTime(2026, 11, 11, 7, 30));
    });
  });
}
