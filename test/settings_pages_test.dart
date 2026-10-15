import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:takip/data/store.dart';
import 'package:takip/ui/manage_page.dart';

import 'support/fonts.dart';
import 'support/real_db.dart';

/// Lets the real database work started by a tap finish, then draws the result.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  useRealDatabase();

  setUpAll(() async {
    await loadRealFont();
    await initializeDateFormatting('tr_TR');
    Intl.defaultLocale = 'tr_TR';
  });

  testWidgets('notifications, health and backups have their own pages, each summed up in settings', (tester) async {
    // A tall phone: the whole settings page is built at once.
    tester.view.physicalSize = const Size(412, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.runAsync(() async {
      await store.load();
      await store.setTimerSoundEnabled(true);
      await store.setWaterReminder(enabled: false);
      await store.setDailySummaryReminder(enabled: true);
    });
    await tester.pumpWidget(const MaterialApp(home: ManagePage()));
    await tester.pump();

    // The settings page itself stays short: the details are one tap away.
    expect(find.text('Gün İçi Su Hatırlatıcısı'), findsNothing);
    expect(find.text('Uyku Takibi'), findsNothing);
    expect(find.text('Yerel Yedekler & Geçmiş'), findsNothing);
    expect(find.text('Sayaç alarmı açık · 1 hatırlatıcı açık'), findsOneWidget);
    expect(find.text('Adım sayar kapalı · uyku takibi kapalı'), findsOneWidget);

    // Health: what changes there shows in the summary on the way back.
    await tester.tap(find.text('Sağlık & Sensör Takibi'));
    await tester.pumpAndSettle();
    expect(find.text('Adım Sayar (Otomatik)'), findsOneWidget);
    await tester.tap(find.text('Uyku Takibi'));
    await _settle(tester);
    expect(store.sleepTrackerEnabled, isTrue);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Adım sayar kapalı · uyku takibi açık'), findsOneWidget);

    // Notifications: one "try" row instead of the two test buttons.
    await tester.tap(find.text('Akıllı Hatırlatıcılar & Bildirimler'));
    await tester.pumpAndSettle();
    expect(find.text('Gün İçi Su Hatırlatıcısı'), findsOneWidget);
    expect(find.text('Su Testi'), findsNothing);
    expect(find.text('Alarm Testi (3s)'), findsNothing);
    await tester.scrollUntilVisible(find.text('Bildirimi Dene'), 200, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Bildirimi Dene'));
    await _settle(tester);
    expect(find.text('3 saniye içinde bir deneme bildirimi gelecek.'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    // Backups and reports.
    await tester.tap(find.text('Yedekleme & Raporlama'));
    await tester.pumpAndSettle();
    for (final row in [
      'PDF Sağlık & Alışkanlık Raporu',
      'Excel (CSV) Tablosu',
      'Yedek Al (JSON Dosyası)',
      'Yedekten Geri Yükle',
      'Yerel Yedekler & Geçmiş',
    ]) {
      expect(find.text(row), findsOneWidget, reason: row);
    }
    await tester.pumpWidget(const SizedBox());
  });
}
