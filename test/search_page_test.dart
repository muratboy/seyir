import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:takip/data/models.dart';
import 'package:takip/data/store.dart';
import 'package:takip/ui/search_page.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('tr_TR');
    await initializeDateFormatting('en_US');
    Intl.defaultLocale = 'tr_TR';
  });

  tearDown(() {
    store.activities.clear();
    store.entries = [];
    store.roadmaps = [];
  });

  testWidgets('TakipSearchDelegate finds matching activities, notes and roadmaps', (tester) async {
    final bookActivity = Activity(id: 1, name: 'Kitap Okuma', emoji: '📚', createdAt: 0);
    final runActivity = Activity(id: 2, name: 'Koşu', emoji: '🏃', createdAt: 0);
    store.activities[1] = bookActivity;
    store.activities[2] = runActivity;

    final entryWithNote = Entry(
      id: 101,
      activityId: 1,
      ts: DateTime(2026, 10, 15, 14, 30).millisecondsSinceEpoch,
      note: 'Dostoyevski Suç ve Ceza 50 sayfa bitti',
      qty: 1,
    );
    store.entries = [entryWithNote];

    final roadmap = Roadmap(
      id: 201,
      title: 'Flutter İleri Seviye Öğrenme',
      createdAt: DateTime.now().millisecondsSinceEpoch,
      steps: [
        RoadmapStep(id: 301, roadmapId: 201, title: 'State management mimarisi', order: 1),
      ],
    );
    store.roadmaps = [roadmap];

    final delegate = TakipSearchDelegate(store: store);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return ElevatedButton(
                onPressed: () {
                  showSearch(context: context, delegate: delegate);
                },
                child: const Text('Ara'),
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Open search
    await tester.tap(find.text('Ara'));
    await tester.pumpAndSettle();

    // Verify search input is present
    expect(find.byType(TextField), findsOneWidget);

    // Search for "Kitap" -> matches activity and entry
    delegate.query = 'Kitap';
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Kitap Okuma'), findsWidgets);

    // Search for "Dostoyevski" -> matches entry note
    delegate.query = 'Dostoyevski';
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.textContaining('Suç ve Ceza'), findsOneWidget);

    // Search for "Flutter" -> matches roadmap
    delegate.query = 'Flutter';
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.textContaining('Flutter İleri Seviye Öğrenme'), findsOneWidget);
  });
}
