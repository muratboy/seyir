import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:takip/data/models.dart';
import 'package:takip/ui/components/active_timer_card.dart';

void main() {
  testWidgets('showTimerModeDialog supports keyboard input and preset chips for custom countdown', (tester) async {
    TimerConfig? selectedConfig;
    final testActivity = Activity(
      id: 1,
      name: 'Kitap Okuma',
      emoji: '📚',
      createdAt: 1000,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return ElevatedButton(
                onPressed: () async {
                  selectedConfig = await showTimerModeDialog(context, testActivity);
                },
                child: const Text('Open Dialog'),
              );
            },
          ),
        ),
      ),
    );

    // Open sheet
    await tester.tap(find.text('Open Dialog'));
    await tester.pumpAndSettle();

    // Verify sections
    expect(find.text('Kitap Okuma'), findsOneWidget);
    expect(find.text('⏱️ Kronometre'), findsOneWidget);
    expect(find.text('🍅 Pomodoro (25 Dk)'), findsOneWidget);
    expect(find.text('⏳ Özel Geri Sayım'), findsOneWidget);

    // Verify initial custom minutes is 15
    expect(find.text('15 Dk Başlat'), findsOneWidget);
    final minField = find.byType(TextField);
    expect(minField, findsOneWidget);
    expect(find.widgetWithText(TextField, '15'), findsOneWidget);

    // Tap preset chip 30 dk
    await tester.tap(find.widgetWithText(ChoiceChip, '30 dk'));
    await tester.pumpAndSettle();
    expect(find.text('30 Dk Başlat'), findsOneWidget);
    expect(find.widgetWithText(TextField, '30'), findsOneWidget);

    // Type 42 dk with keyboard
    await tester.enterText(minField, '42');
    await tester.pumpAndSettle();
    expect(find.text('42 Dk Başlat'), findsOneWidget);

    // Tap Start button
    await tester.tap(find.text('42 Dk Başlat'));
    await tester.pumpAndSettle();

    // Dialog should be closed and return 42 minutes countdown
    expect(selectedConfig, isNotNull);
    expect(selectedConfig!.mode, 'countdown');
    expect(selectedConfig!.targetMs, 42 * 60 * 1000);
  });

  testWidgets('showTimerModeDialog disables start button when input is 0 or empty', (tester) async {
    final testActivity = Activity(
      id: 2,
      name: 'Spor',
      emoji: '🏃',
      createdAt: 1000,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return ElevatedButton(
                onPressed: () => showTimerModeDialog(context, testActivity),
                child: const Text('Open Dialog'),
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open Dialog'));
    await tester.pumpAndSettle();

    final minField = find.byType(TextField);
    await tester.enterText(minField, '');
    await tester.pumpAndSettle();

    // Button should now show "Başlat" and be disabled
    final startBtn = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(startBtn.onPressed, isNull);
    expect(find.text('Başlat'), findsOneWidget);

    // Enter 0
    await tester.enterText(minField, '0');
    await tester.pumpAndSettle();
    final startBtnZero = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(startBtnZero.onPressed, isNull);

    // Enter valid 12
    await tester.enterText(minField, '12');
    await tester.pumpAndSettle();
    final startBtnValid = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(startBtnValid.onPressed, isNotNull);
    expect(find.text('12 Dk Başlat'), findsOneWidget);
  });
}
