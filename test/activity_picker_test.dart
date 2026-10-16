import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:takip/data/models.dart';
import 'package:takip/data/store.dart';
import 'package:takip/logic/l10n.dart';
import 'package:takip/ui/common.dart';

import 'support/real_db.dart';

Future<void> settleStore(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  useRealDatabase();

  setUpAll(() async {
    await initializeDateFormatting('tr_TR');
    Intl.defaultLocale = 'tr_TR';
  });

  setUp(() {
    store.language = AppLanguage.tr;
    strings.value = const AppStrings(AppLanguage.tr);
  });

  testWidgets('showActivityPicker shows inline create button when query is new and creates it in one tap', (tester) async {
    await tester.runAsync(() async {
      await store.load();
      await store.addActivity('Su', emoji: '💧');
    });

    Activity? chosen;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () async {
                chosen = await showActivityPicker(ctx, title: 'Aktivite Seç');
              },
              child: const Text('Aç'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Tap button to open picker bottom sheet
    await tester.tap(find.text('Aç'));
    await tester.pumpAndSettle();

    expect(find.text('Aktivite Seç'), findsOneWidget);
    expect(find.text('Su'), findsOneWidget);

    // Enter a new activity name
    await tester.enterText(find.byType(TextField), 'Yoga');
    await tester.pumpAndSettle();

    // Inline create button should appear in the text field suffix
    final createBtn = find.byKey(const Key('picker-quick-create-btn'));
    expect(createBtn, findsOneWidget);

    // Also the styled card in the list should appear
    expect(find.text('"Yoga" oluştur'), findsOneWidget);

    // Tap the inline create button
    await tester.tap(createBtn);
    await settleStore(tester);

    // Picker should pop and return the newly created activity
    expect(chosen, isNotNull);
    expect(chosen!.name, 'Yoga');
    expect(store.activities.values.any((a) => a.name == 'Yoga'), isTrue);
  });

  testWidgets('showActivityPicker shows clear button instead of create when exact match exists', (tester) async {
    await tester.runAsync(() async {
      await store.load();
      await store.addActivity('Koşu', emoji: '🏃');
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () => showActivityPicker(ctx),
              child: const Text('Aç'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Aç'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Koşu');
    await tester.pumpAndSettle();

    // No create button since Koşu already exists
    expect(find.byKey(const Key('picker-quick-create-btn')), findsNothing);
    // Clear icon should appear
    expect(find.byIcon(Icons.clear), findsOneWidget);
  });
}
