import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:takip/data/store.dart';
import 'package:takip/services/nl_parser.dart';

import 'support/real_db.dart';

class _TestCase {
  final String input;
  final String expectedType; // 'entry', 'todo', 'timer', 'empty'
  final String? expectedActivity;
  final double? expectedQty;
  final String? expectedUnit;
  final DateTime? expectedStart;
  final DateTime? expectedEnd;

  const _TestCase({
    required this.input,
    required this.expectedType,
    this.expectedActivity,
    this.expectedQty,
    this.expectedUnit,
    this.expectedStart,
    this.expectedEnd,
  });
}

void main() {
  useRealDatabase();
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initializeDateFormatting('tr_TR', null);
  });

  test('Serbest metin örnekleri beklenen kayda çevrilir', () async {
    await store.load();

    // Birimler
    final existingSymbols = store.allUnits.map((u) => u.symbol).toSet();
    if (!existingSymbols.contains('sayfa')) {
      await store.addUnit('Sayfa', 'sayfa');
      await Future.delayed(const Duration(milliseconds: 5));
    }
    if (!existingSymbols.contains('adim')) {
      await store.addUnit('Adım', 'adim');
      await Future.delayed(const Duration(milliseconds: 5));
    }

    // Ölçüler
    final existingMeasureNames = store.measures.map((m) => m.name.toLowerCase()).toSet();
    if (!existingMeasureNames.contains('bardak')) {
      await store.addMeasure('Bardak', 'l', 0.2);
    }
    if (!existingMeasureNames.contains('sayfa')) {
      await store.addMeasure('Sayfa', 'sayfa', 1.0);
    }
    if (!existingMeasureNames.contains('adım') && !existingMeasureNames.contains('adim')) {
      await store.addMeasure('Adım', 'adim', 1.0);
    }

    // Aktiviteler
    final actNames = [
      'Koşu', 'Yürüyüş', 'Su', 'Kahve', 'Kitap okuma', 'Ders çalışma',
      'Adım', 'İlaç', 'Işık', 'Film', 'Plank', 'Yüzme',
      'Running', 'Walking', 'Water', 'Coffee', 'Reading', 'Study', 'Steps', 'Run'
    ];
    for (final name in actNames) {
      if (store.exactMatch(name) == null) {
        await store.addActivity(name);
      }
    }

    final fixedNow = DateTime(2026, 11, 11, 15, 0); // 2026-11-11 Çarşamba 15:00

    final testCases = <_TestCase>[
      // --- 1. ve 2. İşler: Binlik ayraç ve Bileşik süre ---
      _TestCase(input: '1.000 adım', expectedType: 'entry', expectedActivity: 'Adım', expectedQty: 1000.0),
      _TestCase(input: '10.000 adım', expectedType: 'entry', expectedActivity: 'Adım', expectedQty: 10000.0),
      _TestCase(input: '5.000 adım attım', expectedType: 'entry', expectedActivity: 'Adım', expectedQty: 5000.0),
      _TestCase(input: '1.500 ml su', expectedType: 'entry', expectedActivity: 'Su', expectedQty: 1500.0, expectedUnit: 'ml'),
      _TestCase(input: '2 saat 15 dk ders', expectedType: 'entry', expectedActivity: 'Ders çalışma', expectedQty: 135.0, expectedUnit: 'dk',
          expectedStart: DateTime(2026, 11, 11, 12, 45), expectedEnd: DateTime(2026, 11, 11, 15, 0)),
      _TestCase(input: '2sa 15dk ders', expectedType: 'entry', expectedActivity: 'Ders çalışma', expectedQty: 135.0, expectedUnit: 'dk',
          expectedStart: DateTime(2026, 11, 11, 12, 45), expectedEnd: DateTime(2026, 11, 11, 15, 0)),
      _TestCase(input: '1 saat 30 dakika yürüyüş', expectedType: 'entry', expectedActivity: 'Yürüyüş', expectedQty: 90.0, expectedUnit: 'dk',
          expectedStart: DateTime(2026, 11, 11, 13, 30), expectedEnd: DateTime(2026, 11, 11, 15, 0)),
      _TestCase(input: '1h 30m study', expectedType: 'entry', expectedActivity: 'Study', expectedQty: 90.0, expectedUnit: 'dk',
          expectedStart: DateTime(2026, 11, 11, 13, 30), expectedEnd: DateTime(2026, 11, 11, 15, 0)),
      _TestCase(input: '1 hr 30 min', expectedType: 'entry', expectedQty: 90.0, expectedUnit: 'dk',
          expectedStart: DateTime(2026, 11, 11, 13, 30), expectedEnd: DateTime(2026, 11, 11, 15, 0)),
      _TestCase(input: '1 dk 30 sn', expectedType: 'entry', expectedQty: 90.0, expectedUnit: 'sn',
          expectedStart: DateTime(2026, 11, 11, 14, 58, 30), expectedEnd: DateTime(2026, 11, 11, 15, 0)),
      _TestCase(input: '1 saat 100 m yüzme', expectedType: 'entry', expectedActivity: 'Yüzme', expectedQty: 1.0, expectedUnit: 'sa',
          expectedStart: DateTime(2026, 11, 11, 14, 0), expectedEnd: DateTime(2026, 11, 11, 15, 0)),
      _TestCase(input: '2 saat 500 m yürüyüş', expectedType: 'entry', expectedActivity: 'Yürüyüş', expectedQty: 2.0, expectedUnit: 'sa',
          expectedStart: DateTime(2026, 11, 11, 13, 0), expectedEnd: DateTime(2026, 11, 11, 15, 0)),

      // --- 3. İş: Saat aralıkları ---
      _TestCase(input: '14:00-15:30 ders', expectedType: 'entry', expectedActivity: 'Ders çalışma', expectedQty: 90.0, expectedUnit: 'dk',
          expectedStart: DateTime(2026, 11, 11, 14, 0), expectedEnd: DateTime(2026, 11, 11, 15, 30)),
      _TestCase(input: '14.00-15.30 ders', expectedType: 'entry', expectedActivity: 'Ders çalışma', expectedQty: 90.0, expectedUnit: 'dk',
          expectedStart: DateTime(2026, 11, 11, 14, 0), expectedEnd: DateTime(2026, 11, 11, 15, 30)),
      _TestCase(input: '23:30-00:30 film', expectedType: 'entry', expectedActivity: 'Film', expectedQty: 60.0, expectedUnit: 'dk',
          expectedStart: DateTime(2026, 11, 10, 23, 30), expectedEnd: DateTime(2026, 11, 11, 0, 30)),

      // --- Temel Sayı & Süre Girişleri ---
      _TestCase(input: '1,5 km koşu', expectedType: 'entry', expectedActivity: 'Koşu', expectedQty: 1.5, expectedUnit: 'km'),
      _TestCase(input: '1.5 km koşu', expectedType: 'entry', expectedActivity: 'Koşu', expectedQty: 1.5, expectedUnit: 'km'),
      _TestCase(input: '0,5 l su', expectedType: 'entry', expectedActivity: 'Su', expectedQty: 0.5, expectedUnit: 'l'),
      _TestCase(input: '2 bardak su', expectedType: 'entry', expectedActivity: 'Su', expectedQty: 2.0),
      _TestCase(input: 'su 2 bardak', expectedType: 'entry', expectedActivity: 'Su', expectedQty: 2.0),
      _TestCase(input: 'iki bardak su', expectedType: 'entry', expectedActivity: 'Su', expectedQty: 2.0),
      _TestCase(input: '3 kahve', expectedType: 'entry', expectedActivity: 'Kahve', expectedQty: 3.0),
      _TestCase(input: 'kahve', expectedType: 'entry', expectedActivity: 'Kahve', expectedQty: 1.0),
      _TestCase(input: 'yarım saat koşu', expectedType: 'entry', expectedActivity: 'Koşu', expectedQty: 0.5, expectedUnit: 'sa',
          expectedStart: DateTime(2026, 11, 11, 14, 30), expectedEnd: DateTime(2026, 11, 11, 15, 0)),
      _TestCase(input: '1 buçuk saat yürüyüş', expectedType: 'entry', expectedActivity: 'Yürüyüş', expectedQty: 1.5, expectedUnit: 'sa',
          expectedStart: DateTime(2026, 11, 11, 13, 30), expectedEnd: DateTime(2026, 11, 11, 15, 0)),
      _TestCase(input: '1,5 saat ders', expectedType: 'entry', expectedActivity: 'Ders çalışma', expectedQty: 1.5, expectedUnit: 'sa',
          expectedStart: DateTime(2026, 11, 11, 13, 30), expectedEnd: DateTime(2026, 11, 11, 15, 0)),
      _TestCase(input: '90dk koşu', expectedType: 'entry', expectedActivity: 'Koşu', expectedQty: 90.0, expectedUnit: 'dk',
          expectedStart: DateTime(2026, 11, 11, 13, 30), expectedEnd: DateTime(2026, 11, 11, 15, 0)),
      _TestCase(input: '45 dakika kitap', expectedType: 'entry', expectedActivity: 'Kitap okuma', expectedQty: 45.0, expectedUnit: 'dk',
          expectedStart: DateTime(2026, 11, 11, 14, 15), expectedEnd: DateTime(2026, 11, 11, 15, 0)),
      _TestCase(input: '20 sayfa kitap', expectedType: 'entry', expectedActivity: 'Kitap okuma', expectedQty: 20.0, expectedUnit: 'sayfa'),
      _TestCase(input: '30 sn plank', expectedType: 'entry', expectedActivity: 'Plank', expectedQty: 30.0, expectedUnit: 'sn',
          expectedStart: DateTime(2026, 11, 11, 14, 59, 30), expectedEnd: DateTime(2026, 11, 11, 15, 0)),

      // --- Zaman İfadeleri ---
      _TestCase(input: 'dün 30 dk koşu', expectedType: 'entry', expectedActivity: 'Koşu', expectedQty: 30.0, expectedUnit: 'dk',
          expectedStart: DateTime(2026, 11, 10, 12, 0), expectedEnd: DateTime(2026, 11, 10, 12, 30)),
      _TestCase(input: 'dün akşam 8\'de 30 dk koşu', expectedType: 'entry', expectedActivity: 'Koşu', expectedQty: 30.0, expectedUnit: 'dk',
          expectedStart: DateTime(2026, 11, 10, 20, 0), expectedEnd: DateTime(2026, 11, 10, 20, 30)),
      _TestCase(input: 'sabah 7\'de koşu', expectedType: 'entry', expectedActivity: 'Koşu', expectedStart: DateTime(2026, 11, 11, 7, 0)),
      _TestCase(input: '7.30\'da kahve', expectedType: 'entry', expectedActivity: 'Kahve', expectedStart: DateTime(2026, 11, 11, 7, 30)),
      _TestCase(input: 'saat 9\'da ilaç', expectedType: 'entry', expectedActivity: 'İlaç', expectedStart: DateTime(2026, 11, 11, 9, 0)),
      _TestCase(input: '2 saat önce kahve', expectedType: 'entry', expectedActivity: 'Kahve', expectedStart: DateTime(2026, 11, 11, 13, 0)),
      _TestCase(input: 'yarın 30 dk koşu', expectedType: 'entry', expectedActivity: 'Koşu', expectedQty: 30.0, expectedUnit: 'dk',
          expectedStart: DateTime(2026, 11, 12, 12, 0), expectedEnd: DateTime(2026, 11, 12, 12, 30)),
      _TestCase(input: 'geçen cuma 5 km koşu', expectedType: 'entry', expectedActivity: 'Koşu', expectedQty: 5.0, expectedUnit: 'km',
          expectedStart: DateTime(2026, 11, 6, 12, 0)),
      _TestCase(input: 'pazartesi 30 dk koşu', expectedType: 'entry', expectedActivity: 'Koşu', expectedQty: 30.0, expectedUnit: 'dk',
          expectedStart: DateTime(2026, 11, 9, 12, 0), expectedEnd: DateTime(2026, 11, 9, 12, 30)),
      _TestCase(input: 'bu sabah 2 bardak su', expectedType: 'entry', expectedActivity: 'Su', expectedQty: 2.0, expectedStart: DateTime(2026, 11, 11, 8, 0)),
      _TestCase(input: 'öğlen 1 kahve', expectedType: 'entry', expectedActivity: 'Kahve', expectedQty: 1.0, expectedStart: DateTime(2026, 11, 11, 13, 0)),

      // --- Türkçe Ek / Karakter Varyasyonları ---
      _TestCase(input: 'IŞIK', expectedType: 'entry', expectedActivity: 'Işık'),
      _TestCase(input: 'ışık', expectedType: 'entry', expectedActivity: 'Işık'),
      _TestCase(input: 'ilaç', expectedType: 'entry', expectedActivity: 'İlaç'),
      _TestCase(input: 'İLAÇ', expectedType: 'entry', expectedActivity: 'İlaç'),
      _TestCase(input: 'ilac', expectedType: 'entry', expectedActivity: 'İlaç'),
      _TestCase(input: 'kosu 30 dk', expectedType: 'entry', expectedActivity: 'Koşu', expectedQty: 30.0, expectedUnit: 'dk'),
      _TestCase(input: 'koşuya çıktım 30 dk', expectedType: 'entry', expectedActivity: 'Koşu', expectedQty: 30.0, expectedUnit: 'dk'),
      _TestCase(input: 'kitap okudum 20 sayfa', expectedType: 'entry', expectedActivity: 'Kitap okuma', expectedQty: 20.0, expectedUnit: 'sayfa'),

      // --- Yapılacaklar ve Sayaçlar ---
      _TestCase(input: 'yapılacak: doktora git', expectedType: 'todo', expectedActivity: 'doktora git'),
      _TestCase(input: 'yarın: dişçiyi ara', expectedType: 'todo', expectedActivity: 'dişçiyi ara', expectedStart: DateTime(2026, 11, 12, 12, 0)),
      _TestCase(input: 'todo fatura öde', expectedType: 'todo', expectedActivity: 'fatura öde'),
      _TestCase(input: 'koşu başlat', expectedType: 'timer', expectedActivity: 'Koşu'),
      _TestCase(input: '25 dk pomodoro', expectedType: 'timer', expectedActivity: 'Pomodoro', expectedQty: 25.0),

      // --- İngilizce Girdiler ---
      _TestCase(input: '30 min run', expectedType: 'entry', expectedActivity: 'Run', expectedQty: 30.0, expectedUnit: 'dk'),
      _TestCase(input: '1.5 h study', expectedType: 'entry', expectedActivity: 'Study', expectedQty: 1.5, expectedUnit: 'sa'),
      _TestCase(input: '2 glasses of water', expectedType: 'entry', expectedActivity: 'Water', expectedQty: 2.0),
      _TestCase(input: '1,000 steps', expectedType: 'entry', expectedActivity: 'Steps', expectedQty: 1.0),
      _TestCase(input: '10k steps', expectedType: 'entry', expectedActivity: 'Steps', expectedQty: 10.0),
      _TestCase(input: 'yesterday 30 min run', expectedType: 'entry', expectedActivity: 'Run', expectedQty: 30.0, expectedUnit: 'dk',
          expectedStart: DateTime(2026, 11, 10, 12, 0), expectedEnd: DateTime(2026, 11, 10, 12, 30)),
      _TestCase(input: 'tomorrow: call dentist', expectedType: 'todo', expectedActivity: 'call dentist', expectedStart: DateTime(2026, 11, 12, 12, 0)),
      _TestCase(input: 'half an hour reading', expectedType: 'entry', expectedActivity: 'Reading', expectedQty: 0.5, expectedUnit: 'sa'),

      // --- Çoklu Giriş Örnekleri ---
      _TestCase(input: 'kahve su', expectedType: 'entry', expectedActivity: 'Kahve', expectedQty: 1.0),
      _TestCase(input: '1 kahve ve 2 bardak su', expectedType: 'entry', expectedActivity: 'Kahve', expectedQty: 1.0),
      _TestCase(input: '1 kahve, 2 su, 30 dk yürüyüş', expectedType: 'entry', expectedActivity: 'Kahve', expectedQty: 1.0),
      _TestCase(input: '30 dk koşu ve 20 sayfa kitap', expectedType: 'entry', expectedActivity: 'Koşu', expectedQty: 30.0),

      // --- Uç Durumlar ---
      _TestCase(input: '', expectedType: 'empty'),
      _TestCase(input: '   ', expectedType: 'empty'),
      _TestCase(input: '🏃‍♂️☕', expectedType: 'entry', expectedActivity: '🏃‍♂️☕', expectedQty: 1.0),
      _TestCase(input: 'a' * 2000, expectedType: 'entry', expectedActivity: 'a' * 2000, expectedQty: 1.0),
      _TestCase(input: '30', expectedType: 'entry', expectedQty: 30.0),
      _TestCase(input: 'dk', expectedType: 'entry', expectedActivity: 'Dk', expectedQty: 1.0, expectedUnit: 'dk'),
      _TestCase(input: '0 kahve', expectedType: 'entry', expectedActivity: 'Kahve', expectedQty: 0.0),
      _TestCase(input: '999999999 adım', expectedType: 'entry', expectedActivity: 'Adım', expectedQty: 999999999.0),
    ];

    for (final tc in testCases) {
      final multi = NaturalLanguageParser.parseMulti(
        tc.input,
        activities: store.activities.values.toList(),
        measures: store.measures,
        openTodos: store.todos,
        now: fixedNow,
        fallbackDay: fixedNow,
        defaultMeasureFor: store.defaultMeasureFor,
        predictCompletedTodos: store.predictCompletedTodos,
      );

      final items = multi.items;
      if (tc.expectedType == 'empty') {
        expect(items, isEmpty, reason: 'Girdi boş olmalıydı: "${tc.input}"');
        continue;
      }

      expect(items, isNotEmpty, reason: 'Girdi ayrıştırılamadı: "${tc.input}"');
      final first = items.first;

      if (tc.expectedType == 'todo') {
        expect(first, isA<TodoParsedItem>(), reason: 'Tür TodoParsedItem olmalı: "${tc.input}"');
        final todoItem = first as TodoParsedItem;
        if (tc.expectedActivity != null) {
          expect(todoItem.title.toLowerCase(), contains(tc.expectedActivity!.toLowerCase()),
              reason: 'Yapılacak başlığı eşleşmedi: "${tc.input}"');
        }
        if (tc.expectedStart != null) {
          expect(todoItem.dueDate, isNotNull);
          expect(todoItem.dueDate, tc.expectedStart);
        }
      } else if (tc.expectedType == 'timer') {
        expect(first, isA<EntryParsedItem>(), reason: 'Tür EntryParsedItem olmalı: "${tc.input}"');
        final entryItem = first as EntryParsedItem;
        expect(entryItem.timerCommand, isNotNull, reason: 'Sayaç komutu olmalıydı: "${tc.input}"');
      } else if (tc.expectedType == 'entry') {
        expect(first, isA<EntryParsedItem>(), reason: 'Tür EntryParsedItem olmalı: "${tc.input}"');
        final entryItem = first as EntryParsedItem;

        if (tc.expectedActivity != null) {
          final actName = entryItem.activity?.name ?? entryItem.activityName;
          expect(actName.toLowerCase(), tc.expectedActivity!.toLowerCase(),
              reason: 'Aktivite adı eşleşmedi: "${tc.input}"');
        }

        if (tc.expectedQty != null) {
          expect(entryItem.quantity, closeTo(tc.expectedQty!, 0.001),
              reason: 'Miktar eşleşmedi: "${tc.input}"');
        }

        if (tc.expectedUnit != null) {
          final u = entryItem.measure?.unitId ?? entryItem.parseResult.matchedMeasure?.unitId;
          expect(u, tc.expectedUnit, reason: 'Birim eşleşmedi: "${tc.input}"');
        }

        if (tc.expectedStart != null) {
          expect(entryItem.at, tc.expectedStart,
              reason: 'Başlangıç saati eşleşmedi: "${tc.input}"');
        }

        if (tc.expectedEnd != null) {
          expect(entryItem.endAt, tc.expectedEnd,
              reason: 'Bitiş saati eşleşmedi: "${tc.input}"');
        }
      }
    }
  });

  test('Çoklu Giriş Ayrıştırma Doğrulama Testi', () async {
    await store.load();
    final fixedNow = DateTime(2026, 11, 11, 15, 0);

    final multi1 = NaturalLanguageParser.parseMulti(
      '1 kahve ve 2 bardak su',
      activities: store.activities.values.toList(),
      measures: store.measures,
      openTodos: store.todos,
      now: fixedNow,
    );
    expect(multi1.items.length, 2);

    final multi2 = NaturalLanguageParser.parseMulti(
      '1 kahve, 2 su, 30 dk yürüyüş',
      activities: store.activities.values.toList(),
      measures: store.measures,
      openTodos: store.todos,
      now: fixedNow,
    );
    expect(multi2.items.length, 3);

    final multi3 = NaturalLanguageParser.parseMulti(
      '30 dk koşu ve 20 sayfa kitap',
      activities: store.activities.values.toList(),
      measures: store.measures,
      openTodos: store.todos,
      now: fixedNow,
    );
    expect(multi3.items.length, 2);
  });
}
