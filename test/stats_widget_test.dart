import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:takip/data/models.dart';
import 'package:takip/data/store.dart';
import 'package:takip/ui/stats_page.dart';

void main() {
  testWidgets('Pumps StatsPage without errors', (tester) async {
    await initializeDateFormatting('tr_TR');
    await initializeDateFormatting('en_US');
    Intl.defaultLocale = 'tr_TR';

    // Add dummy entries in store
    store.activities[1] = Activity(id: 1, name: 'Ders', createdAt: 0);
    final now = DateTime.now();
    store.entries.add(Entry(id: 1, activityId: 1, ts: now.millisecondsSinceEpoch, qty: 1, value: 30, unitId: 'dk'));

    await tester.pumpWidget(
      const MaterialApp(
        home: StatsPage(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('İstatistikler & Özet'), findsOneWidget);
  });
}
