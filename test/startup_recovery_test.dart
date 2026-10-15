import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:takip/data/store.dart';
import 'package:takip/logic/l10n.dart';
import 'package:takip/main.dart';
import 'package:takip/ui/startup_recovery_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await initializeDateFormatting('tr_TR');
    await initializeDateFormatting('en_US');

    // Neither a documents directory nor a database exists in this test. Unanswered platform calls never
    // complete under the fake clock of widget tests, so both channels are made to fail right away.
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => null,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('com.tekartik.sqflite'),
      (call) async => throw PlatformException(code: 'unavailable', message: 'no database in this test'),
    );
  });

  testWidgets('a failed startup opens the recovery page instead of leaving the app closed', (tester) async {
    const s = AppStrings(AppLanguage.tr);
    expect(store.loaded, isFalse);

    await tester.pumpWidget(const TakipApp(startupError: FormatException('unreadable row')));
    await tester.pumpAndSettle();

    expect(find.byType(StartupRecoveryPage), findsOneWidget);
    expect(find.text(s.startupErrorTitle), findsOneWidget);
    expect(find.textContaining('unreadable row'), findsOneWidget);
    expect(find.text(s.noLocalBackups), findsOneWidget);

    // Retrying fails again here: the page stays and shows the new error.
    await tester.tap(find.text(s.retry));
    await tester.pumpAndSettle();

    expect(find.byType(StartupRecoveryPage), findsOneWidget);
    expect(find.textContaining('unreadable row'), findsNothing);
  });
}
