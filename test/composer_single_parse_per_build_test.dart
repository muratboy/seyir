import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:takip/data/store.dart';
import 'package:takip/services/nl_parser.dart';
import 'package:takip/ui/today_page.dart';

import 'support/real_db.dart';

void main() {
  useRealDatabase();

  setUpAll(() async {
    await initializeDateFormatting('tr_TR');
    Intl.defaultLocale = 'tr_TR';
  });

  testWidgets('Giriş kutusuna bir tuş vuruşu yapıldığında çizim başına yalnızca 1 kez ayrıştırma yapılır', (tester) async {
    await tester.runAsync(() => store.load());
    await tester.pumpWidget(MaterialApp(home: TodayPage(focusRequest: ValueNotifier<int>(0))));
    await tester.pump();

    NaturalLanguageParser.resetParseMultiCallCount();
    expect(NaturalLanguageParser.parseMultiCallCount, 0);

    final composerField = find.byType(TextField).last;

    // 1. Bir tuş vuruşu / metin girişi ve çizim
    await tester.enterText(composerField, '2 bardak su');
    await tester.pump();

    // Çizim (build) başına ayrıştırma sayısı tam 1 olmalı
    expect(NaturalLanguageParser.parseMultiCallCount, 1);

    // 2. Metin güncellendiğinde yeni çizim için yine tam 1 kez ayrıştırma yapılır
    await tester.enterText(composerField, '3 bardak su');
    await tester.pump();

    expect(NaturalLanguageParser.parseMultiCallCount, 2);

    // 3. Gönder düğmesine basıldığında olay işleyicisi güncel zaman ve durumla taze ayrıştırır
    final submitButton = find.byKey(const Key('composer-submit'));
    await tester.tap(submitButton);

    // Olay işleyicisi taze ayrıştırdığı için sayaç artar
    expect(NaturalLanguageParser.parseMultiCallCount, greaterThan(2));

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });
}
