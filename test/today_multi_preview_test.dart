import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:takip/data/store.dart';
import 'package:takip/ui/today_page.dart';

import 'support/real_db.dart';

Future<void> settleStore(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> pumpToday(WidgetTester tester) async {
  await tester.runAsync(() => store.load());
  await tester.pumpWidget(MaterialApp(home: TodayPage(focusRequest: ValueNotifier<int>(0))));
  await tester.pump();
}

Future<void> finish(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.runAsync(() async {
    for (final t in List.of(store.activeTimers)) {
      await store.cancelTimer(t.id);
    }
  });
  await tester.pump(const Duration(seconds: 6));
}

Finder get composerField => find.byType(TextField).last;
Finder get submitButton => find.byKey(const Key('composer-submit'));

void main() {
  useRealDatabase();

  setUpAll(() async {
    await initializeDateFormatting('tr_TR');
    Intl.defaultLocale = 'tr_TR';
  });

  testWidgets('multi-item preview shows items and allows removing an item with ×', (tester) async {
    await pumpToday(tester);

    await tester.enterText(composerField, '2 kahve ve 30 dk kosu');
    await tester.pump();

    // Çoklu önizleme satırları görünür
    expect(find.textContaining('Kahve'), findsOneWidget);
    expect(find.textContaining('Kosu'), findsOneWidget);

    // İki adet kaldırma (×) butonu olmalı
    final removeButtons = find.byIcon(Icons.close);
    expect(removeButtons, findsNWidgets(2));

    // İlk öğeyi (Kahve) kaldır
    await tester.tap(removeButtons.first);
    await tester.pump();

    // Artık yalnızca Kosu kalmalı
    expect(find.textContaining('Kahve'), findsNothing);
    expect(find.textContaining('Kosu'), findsOneWidget);

    // Kaydet düğmesine bas
    await tester.tap(submitButton);
    await settleStore(tester);

    // Yalnızca Kosu kaydedildi
    expect(store.entries.any((e) => e.qty == 30), isTrue);
    expect(store.entries.any((e) => e.qty == 2), isFalse);

    await finish(tester);
  });

  testWidgets('future entry shows warning and can be converted to todo with chip', (tester) async {
    await pumpToday(tester);

    await tester.enterText(composerField, 'yarin 2 kahve');
    await tester.pump();

    // Gelecek zaman uyarısı ve dönüştürme çipi görünür
    expect(find.text('Gelecek zaman'), findsOneWidget);
    expect(find.text('Yapılacak olarak ekle'), findsOneWidget);

    // Dönüştürme çipine dokun
    await tester.tap(find.text('Yapılacak olarak ekle'));
    await tester.pump();

    // Artık to-do öğesine dönüştü, "Gelecek zaman" uyarısı kalktı
    expect(find.text('Gelecek zaman'), findsNothing);
    expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);

    // Kaydet düğmesine bas
    await tester.tap(submitButton);
    await settleStore(tester);

    // Yapılacak oluştu, kayıt oluşmadı
    expect(store.todos.any((t) => t.title.toLowerCase().contains('kahve')), isTrue);

    await finish(tester);
  });

  testWidgets('time chip is visible for past time and tapping opens date picker', (tester) async {
    await pumpToday(tester);

    await tester.enterText(composerField, 'dun gece 500 ml su ve 30 dk kosu');
    await tester.pump();

    // Zaman çipi görünür (Dün 22:00)
    final timeTexts = find.textContaining('22:00');
    expect(timeTexts, findsWidgets);

    // Zaman çipine dokununca tarih seçici açılır
    await tester.tap(timeTexts.first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // DatePicker dialog görünür (kapat)
    expect(find.byType(DatePickerDialog), findsOneWidget);
    Navigator.of(tester.element(find.byType(DatePickerDialog))).pop();
    await tester.pump();

    await finish(tester);
  });
}
