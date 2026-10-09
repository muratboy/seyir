import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:takip/data/models.dart';
import 'package:takip/data/store.dart';
import 'package:takip/logic/format.dart';
import 'package:takip/ui/contribution_heatmap.dart';
import 'package:takip/ui/goals_page.dart';

void main() {
  setUp(() async {
    await initializeDateFormatting('tr_TR');
    await initializeDateFormatting('en_US');
    Intl.defaultLocale = 'tr_TR';
  });

  testWidgets('ContributionHeatmap renders cells and legend', (tester) async {
    final today = dayStart(DateTime.now());
    final dailyCounts = <DateTime, int>{
      today: 3,
      today.subtract(const Duration(days: 1)): 2,
      today.subtract(const Duration(days: 2)): 1,
    };

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ContributionHeatmap(
            dailyCounts: dailyCounts,
            weekCount: 16,
            baseColor: const Color(0xFF22C55E),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Verify day labels (Pzt, Çar, Cum)
    expect(find.text('Pzt'), findsOneWidget);
    expect(find.text('Çar'), findsOneWidget);
    expect(find.text('Cum'), findsOneWidget);

    // Verify legend texts
    expect(find.text('Daha az'), findsOneWidget);
    expect(find.text('Daha çok'), findsOneWidget);
  });

  testWidgets('GoalsPage switches between Goals and Habits tab', (tester) async {
    // Setup in-memory activity with habit
    final testHabit = Activity(
      id: 99,
      name: 'Kitap Okuma',
      emoji: '📚',
      isHabit: true,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
    store.activities[99] = testHabit;

    await tester.pumpWidget(
      const MaterialApp(
        home: GoalsPage(),
      ),
    );

    await tester.pumpAndSettle();

    // Verify both tab segments exist
    expect(find.byType(SegmentedButton<GoalsPageTab>), findsOneWidget);
    expect(find.textContaining('Zinciri Kırma'), findsOneWidget);

    // Tap on Zinciri Kırma tab
    await tester.tap(find.textContaining('Zinciri Kırma'));
    await tester.pumpAndSettle();

    // Verify habit card for Kitap Okuma is shown
    expect(find.text('Kitap Okuma'), findsOneWidget);
    expect(find.textContaining('Mevcut Seri'), findsWidgets);
    expect(find.textContaining('En Uzun Seri'), findsWidgets);
    expect(find.byType(ContributionHeatmap), findsOneWidget);
  });
}
