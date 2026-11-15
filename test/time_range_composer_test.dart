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
String? previewOf(WidgetTester tester) => tester.widget<Text>(find.byKey(const Key('composer-preview'))).data;

void main() {
  useRealDatabase();

  setUpAll(() async {
    await initializeDateFormatting('tr_TR');
    Intl.defaultLocale = 'tr_TR';
  });

  group('Saat Aralığı ve Önizleme Eşitliği Arayüz Testleri', () {
    testWidgets('14:00-15:30 ders için önizleme miktarı ile kayıt miktarı, başlangıcı ve bitişi aynıdır', (tester) async {
      await tester.runAsync(() async {
        await store.load();
        await store.addActivity('Ders', emoji: '📚');
      });
      await pumpToday(tester);

      await tester.enterText(composerField, '14:00-15:30 ders');
      await tester.pump();

      final preview = previewOf(tester)!;
      expect(preview, contains('1 sa 30 dk'));

      final timeChipFinder = find.byKey(const Key('composer-time-chip'));
      expect(timeChipFinder, findsOneWidget);
      final chipText = tester.widget<Text>(find.descendant(of: timeChipFinder, matching: find.byType(Text))).data!;
      expect(chipText, contains('14:00–15:30'));

      // Tek dokunuşta doğrudan kaydeder, seçenekler paneli açılmaz
      await tester.tap(submitButton);
      await settleStore(tester);

      expect(store.entries, hasLength(1));
      final entry = store.entries.single;
      expect(entry.qty, 90.0);
      expect(entry.time.hour, 14);
      expect(entry.time.minute, 0);
      expect(entry.endTime, isNotNull);
      expect(entry.endTime!.hour, 15);
      expect(entry.endTime!.minute, 30);
      expect(store.entryDetail(entry), contains('1 sa 30 dk'));

      await finish(tester);
    });

    testWidgets('2 saat 15 dk ders için önizleme miktarı ile kayıt miktarı, başlangıcı ve bitişi aynıdır', (tester) async {
      await tester.runAsync(() async {
        await store.load();
        await store.addActivity('Ders', emoji: '📚');
      });
      await pumpToday(tester);

      await tester.enterText(composerField, '2 saat 15 dk ders');
      await tester.pump();

      final preview = previewOf(tester)!;
      expect(preview, contains('2 sa 15 dk'));

      await tester.tap(submitButton);
      await settleStore(tester);

      expect(store.entries, hasLength(1));
      final entry = store.entries.single;
      expect(entry.qty, 135.0);
      expect(entry.endTime, isNotNull);
      expect(entry.endTime!.difference(entry.time).inMinutes, 135);
      expect(store.entryDetail(entry), contains('2 sa 15 dk'));

      await finish(tester);
    });

    testWidgets('30 dk koşu için önizleme miktarı ile kayıt miktarı, başlangıcı ve bitişi aynıdır', (tester) async {
      await tester.runAsync(() async {
        await store.load();
        await store.addActivity('Koşu', emoji: '🏃');
      });
      await pumpToday(tester);

      await tester.enterText(composerField, '30 dk koşu');
      await tester.pump();

      final preview = previewOf(tester)!;
      expect(preview, contains('30 dk'));

      await tester.tap(submitButton);
      await settleStore(tester);

      expect(store.entries, hasLength(1));
      final entry = store.entries.single;
      expect(entry.qty, 30.0);
      expect(entry.endTime, isNotNull);
      expect(entry.endTime!.difference(entry.time).inMinutes, 30);
      expect(store.entryDetail(entry), contains('30 dk'));

      await finish(tester);
    });

    testWidgets('dün 14:00-15:30 ders için önizleme miktarı ile kayıt miktarı, başlangıcı ve bitişi aynıdır', (tester) async {
      await tester.runAsync(() async {
        await store.load();
        await store.addActivity('Ders', emoji: '📚');
      });
      await pumpToday(tester);

      await tester.enterText(composerField, 'dün 14:00-15:30 ders');
      await tester.pump();

      final preview = previewOf(tester)!;
      expect(preview, contains('1 sa 30 dk'));

      final timeChipFinder = find.byKey(const Key('composer-time-chip'));
      expect(timeChipFinder, findsOneWidget);
      final chipText = tester.widget<Text>(find.descendant(of: timeChipFinder, matching: find.byType(Text))).data!;
      expect(chipText, 'Dün 14:00–15:30');

      await tester.tap(submitButton);
      await settleStore(tester);

      expect(store.entries, hasLength(1));
      final entry = store.entries.single;
      expect(entry.qty, 90.0);
      final now = DateTime.now();
      final yesterday = now.subtract(const Duration(days: 1));
      expect(entry.time.year, yesterday.year);
      expect(entry.time.month, yesterday.month);
      expect(entry.time.day, yesterday.day);
      expect(entry.time.hour, 14);
      expect(entry.time.minute, 0);
      expect(entry.endTime, isNotNull);
      expect(entry.endTime!.hour, 15);
      expect(entry.endTime!.minute, 30);
      expect(store.entryDetail(entry), contains('1 sa 30 dk'));

      await finish(tester);
    });

    testWidgets('2 bardak su için önizleme miktarı ile kayıt miktarı aynıdır', (tester) async {
      await tester.runAsync(() async {
        await store.load();
        await store.addActivity('Su', emoji: '💧');
      });
      await pumpToday(tester);

      await tester.enterText(composerField, '2 bardak su');
      await tester.pump();

      final preview = previewOf(tester)!;
      expect(preview, contains('2 Su bardağı · 400 ml'));

      await tester.tap(submitButton);
      await settleStore(tester);

      expect(store.entries, hasLength(1));
      final entry = store.entries.single;
      expect(entry.qty, 2.0);
      expect(store.entryDetail(entry), contains('2 Su bardağı · 400 ml'));

      await finish(tester);
    });

    testWidgets('1.000 adım için önizleme miktarı ile kayıt miktarı aynıdır', (tester) async {
      await tester.runAsync(() async {
        await store.load();
        await store.addActivity('Adım', emoji: '🚶');
      });
      await pumpToday(tester);

      await tester.enterText(composerField, '1.000 adım');
      await tester.pump();

      final preview = previewOf(tester)!;
      expect(preview, contains('1.000'));

      await tester.tap(submitButton);
      await settleStore(tester);

      expect(store.entries, hasLength(1));
      final entry = store.entries.single;
      expect(entry.qty, 1000.0);
      expect(preview, contains(store.entryDetail(entry)));

      await finish(tester);
    });

    testWidgets('Aralıkta gönder düğmesi seçenek panelini açmadan tek dokunuşta kaydeder', (tester) async {
      await tester.runAsync(() async {
        await store.load();
        await store.addActivity('Ders', emoji: '📚');
      });
      await pumpToday(tester);

      await tester.enterText(composerField, '14:00-15:30 ders');
      await tester.pump();

      // Seçenekler paneli kapalıdır
      expect(find.byType(TextField), findsOneWidget); // yalnızca kompozisyon alanı var, not alanı yok

      // Göndere bas
      await tester.tap(submitButton);
      await settleStore(tester);

      // Doğrudan kaydoldu
      expect(store.entries, hasLength(1));
      expect(store.entries.single.qty, 90.0);

      await finish(tester);
    });

    testWidgets('Zaman çipinden tarih değişince saat aralığının süresi korunur', (tester) async {
      await tester.runAsync(() async {
        await store.load();
        await store.addActivity('Ders', emoji: '📚');
      });
      await pumpToday(tester);

      await tester.enterText(composerField, '14:00-15:30 ders');
      await tester.pump();

      // Zaman çipine bas
      await tester.tap(find.byKey(const Key('composer-time-chip')));
      await tester.pumpAndSettle();

      final now = DateTime.now();
      // Geçmiş bir gün seç (örneğin ayın ilk günü ya da bugünden 2 gün önce)
      final targetDate = now.day > 2
          ? DateTime(now.year, now.month, now.day - 2)
          : DateTime(now.year, now.month, 1);
      await tester.tap(find.text(targetDate.day.toString()).first);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(TextButton).last); // Tarihi onayla
      await tester.pumpAndSettle();

      // Saati onayla
      await tester.tap(find.byType(TextButton).last);
      await tester.pumpAndSettle();

      // Önizleme süreyi korur
      expect(previewOf(tester), contains('1 sa 30 dk'));

      // Kaydet
      await tester.tap(submitButton);
      await settleStore(tester);

      expect(store.entries, hasLength(1));
      final entry = store.entries.single;
      expect(entry.qty, 90.0);
      expect(entry.endTime, isNotNull);
      expect(entry.endTime!.difference(entry.time).inMinutes, 90);

      await finish(tester);
    });

    testWidgets('Çok öğeli önizlemede aralıklı öğe süresini ve aralığını gösterir', (tester) async {
      await tester.runAsync(() async {
        await store.load();
        await store.addActivity('Ders', emoji: '📚');
        await store.addActivity('Kahve', emoji: '☕');
      });
      await pumpToday(tester);

      await tester.enterText(composerField, '14:00-15:30 ders ve 2 kahve');
      await tester.pump();

      // Çoklu listede süre ve saat aralığı birlikte görünür
      expect(find.text('1 sa 30 dk'), findsOneWidget);
      expect(find.textContaining('14:00–15:30'), findsWidgets);
      expect(find.textContaining('Kahve'), findsOneWidget);

      await finish(tester);
    });
  });
}
