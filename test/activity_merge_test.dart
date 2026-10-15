import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:takip/data/models.dart';
import 'package:takip/data/store.dart';
import 'package:takip/logic/activity_merge.dart';
import 'package:takip/ui/activity_merge_page.dart';

void seed(List<Activity> activities, List<Entry> entries) {
  store.activities
    ..clear()
    ..addEntries([for (final a in activities) MapEntry(a.id, a)]);
  store.entries = [...entries]..sort((a, b) => a.ts.compareTo(b.ts));
  store.clearHabitStreakCache();
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('tr_TR');
  });

  group('findMergeCandidates logic', () {
    test('detects exact normalized match, typos and substrings', () {
      final act1 = Activity(id: 1, name: 'Çay', createdAt: 1000);
      final act2 = Activity(id: 2, name: 'cay', createdAt: 2000);
      final act3 = Activity(id: 3, name: 'Kitap Okuma', createdAt: 1500);
      final act4 = Activity(id: 4, name: 'Kitap Okumak', createdAt: 2500);
      final act5 = Activity(id: 5, name: 'Koşu', createdAt: 1000);

      final candidates = findMergeCandidates(
        [act1, act2, act3, act4, act5],
        entryCountOf: (id) => id == 1 ? 20 : (id == 3 ? 15 : 2),
        goalCountOf: (id) => 0,
      );

      expect(candidates.isNotEmpty, isTrue);

      // Çay and cay exact match should be at the top with score 100
      final exact = candidates.firstWhere((c) => (c.from.id == 2 && c.into.id == 1) || (c.from.id == 1 && c.into.id == 2));
      expect(exact.score, 100);
      // act1 has 20 entries, act2 has 2 entries -> into should be act1, from should be act2
      expect(exact.into.id, 1);
      expect(exact.from.id, 2);

      // Kitap Okuma vs Kitap Okumak (1 char typo)
      final typo = candidates.firstWhere((c) => (c.from.id == 3 && c.into.id == 4) || (c.from.id == 4 && c.into.id == 3));
      expect(typo.into.id, 3); // act3 has 15 entries
      expect(typo.from.id, 4);
    });
  });

  group('ActivityMergePage widget tests', () {
    testWidgets('renders candidates and allows selecting and swapping', (tester) async {
      final actA = Activity(id: 1, name: 'Kahve', emoji: '☕', createdAt: 1000);
      final actB = Activity(id: 2, name: 'Kahveler', emoji: '☕', createdAt: 2000);
      seed(
        [actA, actB],
        [
          Entry(id: 1, activityId: 1, ts: DateTime.now().millisecondsSinceEpoch),
          Entry(id: 2, activityId: 1, ts: DateTime.now().millisecondsSinceEpoch),
          Entry(id: 3, activityId: 2, ts: DateTime.now().millisecondsSinceEpoch),
        ],
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: ActivityMergePage(),
        ),
      );
      await tester.pumpAndSettle();

      // Title
      expect(find.text('Aktivite Birleştir'), findsOneWidget);

      // Suggested merge card exists
      expect(find.text('Önerilen Birleştirmeler'), findsOneWidget);
      expect(find.text('Bunu Seç'), findsOneWidget);

      // Tap "Bunu Seç"
      await tester.tap(find.text('Bunu Seç'));
      await tester.pumpAndSettle();

      // Check impact summary appears
      await tester.scrollUntilVisible(find.text('Birleştirme Özeti'), 200);
      expect(find.text('Birleştirme Özeti'), findsOneWidget);
      expect(find.text('Aktarılacak Kayıt Sayısı'), findsOneWidget);
      expect(find.text('Birleşim Sonrası Toplam'), findsOneWidget);

      // Swap button
      final swapBtn = find.byTooltip('Yönü Değiştir');
      await tester.scrollUntilVisible(swapBtn, 100);
      expect(swapBtn, findsOneWidget);
      await tester.tap(swapBtn);
      await tester.pumpAndSettle();

      // Confirm button is enabled
      final mergeBtn = find.byKey(const Key('merge-confirm-button'));
      await tester.scrollUntilVisible(mergeBtn, 100);
      expect(mergeBtn, findsOneWidget);
      expect(tester.widget<FilledButton>(mergeBtn).enabled, isTrue);
    });

    testWidgets('renders prefilled activities and opens confirmation dialog', (tester) async {
      final actA = Activity(id: 1, name: 'Kahve', emoji: '☕', createdAt: 1000);
      final actB = Activity(id: 2, name: 'Kahveler', emoji: '☕', createdAt: 2000);
      seed(
        [actA, actB],
        [
          Entry(id: 1, activityId: 1, ts: DateTime.now().millisecondsSinceEpoch),
          Entry(id: 2, activityId: 2, ts: DateTime.now().millisecondsSinceEpoch),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ActivityMergePage(
            initialFromActivity: actB,
            initialIntoActivity: actA,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final mergeBtn = find.byKey(const Key('merge-confirm-button'));
      await tester.scrollUntilVisible(mergeBtn, 200);
      expect(tester.widget<FilledButton>(mergeBtn).enabled, isTrue);

      await tester.tap(mergeBtn);
      await tester.pumpAndSettle();

      // Dialog opens
      expect(find.text('Evet, Birleştir'), findsOneWidget);
    });
  });
}
