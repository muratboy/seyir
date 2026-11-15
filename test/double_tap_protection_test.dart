import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:takip/data/store.dart';
import 'package:takip/ui/components/goal_edit_dialog.dart';
import 'package:takip/ui/components/todo_quick_add_sheet.dart';
import 'package:takip/ui/today_page.dart';

import 'support/real_db.dart';

Future<void> settleStore(WidgetTester tester) async {
  for (var i = 0; i < 15; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  useRealDatabase();
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initializeDateFormatting('tr_TR', null);
  });

  group('Çift Dokunuş Çift Kayıt Engelleme Testleri', () {
    testWidgets('Kutu: araya çizim girmeden iki dokunuş tek kayıt açar', (tester) async {
      await tester.runAsync(() => store.load());
      await tester.pumpWidget(MaterialApp(home: TodayPage(focusRequest: ValueNotifier<int>(0))));
      await tester.pump();

      final composerField = find.byType(TextField).last;
      final submitButton = find.byKey(const Key('composer-submit'));

      await tester.enterText(composerField, '1 kahve');
      await tester.pump();

      // Araya çizim (pump) girmeden art arda iki dokunuş
      await tester.tap(submitButton);
      await tester.tap(submitButton);
      await settleStore(tester);

      expect(store.entries.length, 1);
    });

    testWidgets('Hızlı yapılacak ekleme: araya çizim girmeden iki dokunuş tek yapılacak açar', (tester) async {
      await tester.runAsync(() => store.load());
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () => TodoQuickAddSheet.show(ctx),
              child: const Text('Aç'),
            ),
          ),
        ),
      ));
      await tester.pump();

      await tester.tap(find.text('Aç'));
      await tester.pumpAndSettle();

      final textField = find.byType(TextField);
      await tester.enterText(textField, 'Rapor hazırla');
      await tester.pump();

      final addButton = find.widgetWithText(FilledButton, 'Ekle');

      // Araya çizim girmeden iki dokunuş
      await tester.tap(addButton);
      await tester.tap(addButton);
      await settleStore(tester);

      expect(store.todos.length, 1);
      expect(store.todos.first.title, 'Rapor hazırla');
    });

    testWidgets('Hedef oluşturma: araya çizim girmeden iki dokunuş tek hedef açar', (tester) async {
      await tester.runAsync(() => store.load());
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () => GoalEditDialog.show(ctx),
              child: const Text('Aç'),
            ),
          ),
        ),
      ));
      await tester.pump();

      await tester.tap(find.text('Aç'));
      await tester.pumpAndSettle();

      final textFields = find.byType(TextField);
      await tester.enterText(textFields.first, 'Su Hedefi');
      await tester.enterText(textFields.last, '2');
      await tester.pump();

      final saveButton = find.widgetWithText(FilledButton, 'Kaydet');

      // Araya çizim girmeden iki dokunuş
      await tester.tap(saveButton);
      await tester.tap(saveButton);
      await settleStore(tester);

      expect(store.goals.length, 1);
      expect(store.goals.first.name, 'Su Hedefi');
    });
  });
}
