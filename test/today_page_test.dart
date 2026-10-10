import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:takip/data/store.dart';
import 'package:takip/ui/today_page.dart';

void main() {
  setUp(() async {
    await initializeDateFormatting('tr_TR');
    await initializeDateFormatting('en_US');
    Intl.defaultLocale = 'tr_TR';
    store.clearHabitStreakCache();
  });

  testWidgets('TodayPage renders without overflow when navigating to future dates like 12 Ekim Pazartesi', (tester) async {
    // Set a compact screen size (e.g., standard 360x640) to strictly verify overflow safety
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final focusNotifier = ValueNotifier<int>(0);

    await tester.pumpWidget(
      MaterialApp(
        home: TodayPage(focusRequest: focusNotifier),
      ),
    );
    await tester.pumpAndSettle();

    // Verify initial "Bugün" is rendered
    expect(find.text('Bugün'), findsOneWidget);

    // Tap next day button twice to reach 2 days in the future
    final nextBtn = find.byTooltip('Sonraki gün');
    expect(nextBtn, findsOneWidget);

    await tester.tap(nextBtn);
    await tester.pumpAndSettle();

    await tester.tap(nextBtn);
    await tester.pumpAndSettle();

    // No RenderFlex overflow exception should be thrown
    expect(tester.takeException(), isNull);

    // Verify "Bugüne dön" button appears
    final todayBtn = find.byTooltip('Bugüne dön');
    expect(todayBtn, findsOneWidget);

    // Tap "Bugüne dön"
    await tester.tap(todayBtn);
    await tester.pumpAndSettle();

    expect(find.text('Bugün'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
