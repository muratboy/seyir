import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:takip/data/store.dart';
import 'package:takip/logic/l10n.dart';
import 'package:takip/services/backup_service.dart';
import 'package:takip/ui/settings_pages.dart';

import 'support/fonts.dart';
import 'support/real_db.dart';

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 15; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  useRealDatabase();

  setUpAll(() async {
    await loadRealFont();
    await initializeDateFormatting('tr_TR');
    Intl.defaultLocale = 'tr_TR';
  });

  tearDown(() {
    BackupService.saveFileOverrideForTest = null;
    strings.value = const AppStrings(AppLanguage.tr);
  });

  group('Yedek Dosya Adı Biçimlendirme (Birim Testleri)', () {
    test('Türkçe arayüzde seyir-yedek-YYYY-AA-GG-SSDD.json üretir', () {
      final dt = DateTime(2026, 11, 17, 14, 30);
      final fileName = BackupService.formatBackupFileName(dt, isTr: true);
      expect(fileName, equals('seyir-yedek-2026-11-17-1430.json'));
    });

    test('İngilizce arayüzde seyir-backup-YYYY-MM-DD-HHmm.json üretir', () {
      final dt = DateTime(2026, 11, 17, 14, 30);
      final fileName = BackupService.formatBackupFileName(dt, isTr: false);
      expect(fileName, equals('seyir-backup-2026-11-17-1430.json'));
    });

    test('Tek basamaklı ay, gün, saat ve dakikalar sıfır ile doldurulur', () {
      final dt = DateTime(2026, 3, 5, 8, 9);
      expect(
        BackupService.formatBackupFileName(dt, isTr: true),
        equals('seyir-yedek-2026-03-05-0809.json'),
      );
      expect(
        BackupService.formatBackupFileName(dt, isTr: false),
        equals('seyir-backup-2026-03-05-0809.json'),
      );
    });

    test('Dosya adı uzantısı her zaman .json ile biter', () {
      final dt = DateTime.now();
      expect(BackupService.formatBackupFileName(dt, isTr: true).endsWith('.json'), isTrue);
      expect(BackupService.formatBackupFileName(dt, isTr: false).endsWith('.json'), isTrue);
    });
  });

  group('Gidiş-Dönüş (Roundtrip) ve Geri Yükleme Uyumluluğu', () {
    test('kaydedilen baytlar yedek dosyasıyla aynıdır ve store.importJson ile eksiksiz geri yüklenir', () async {
      await store.load();

      // Test verisi oluştur
      final act = await store.addActivity('Roman Okuma', emoji: '📚');
      await store.addEntry(act.id, qty: 1.0, note: 'Bölüm 3');

      // Manuel yedek al
      final backup = await BackupService.createBackup(store, prefix: 'manual');
      final originalBytes = await backup.readAsBytes();

      Uint8List? capturedBytes;
      String? capturedName;
      BackupService.saveFileOverrideForTest = ({required fileName, required bytes}) async {
        capturedName = fileName;
        capturedBytes = bytes;
        return Uri.file('/storage/emulated/0/Download/$fileName');
      };

      final result = await BackupService.saveToDevice(backup, isTr: true);
      expect(result.isSaved, isTrue);
      expect(capturedBytes, isNotNull);
      expect(capturedBytes, equals(originalBytes));
      expect(capturedName, endsWith('.json'));

      // Veritabanını temizleyip kaydedilen baytları içe aktar
      final importedJson = utf8.decode(capturedBytes!);
      await store.importJson(importedJson);

      final restoredActs = store.activities.values.where((a) => a.name == 'Roman Okuma');
      expect(restoredActs.isNotEmpty, isTrue);
    });
  });

  group('Arayüz Testleri (Telefona Kaydet Eylemleri)', () {
    testWidgets('"Yedek Al" › "Telefona kaydet": yeni manual yedek oluşur, baytlar gider ve başarı iletisi gösterilir', (tester) async {
      tester.view.physicalSize = const Size(412, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.runAsync(store.load);

      Uint8List? capturedBytes;
      String? capturedName;
      BackupService.saveFileOverrideForTest = ({required fileName, required bytes}) async {
        capturedName = fileName;
        capturedBytes = bytes;
        return Uri.file('/storage/emulated/0/Download/$fileName');
      };

      await tester.pumpWidget(const MaterialApp(home: BackupSettingsPage()));
      await tester.pumpAndSettle();

      // "Yedek Al (JSON Dosyası)" satırına dokun
      await tester.tap(find.text('Yedek Al (JSON Dosyası)'));
      await tester.pumpAndSettle();

      // Seçim penceresi açıldı: "Telefona kaydet" ve "Paylaş" görünmeli
      expect(find.text('Telefona kaydet'), findsOneWidget);
      expect(find.text('Paylaş'), findsOneWidget);

      // "Telefona kaydet" seç
      await tester.tap(find.text('Telefona kaydet'));
      await _settle(tester);

      expect(capturedBytes, isNotNull);
      expect(capturedName, isNotNull);
      expect(capturedName, endsWith('.json'));
      expect(capturedName!.startsWith('seyir-yedek-'), isTrue);

      // Başarı iletisi gösterilmeli
      expect(find.text('Yedek telefona kaydedildi'), findsOneWidget);
    });

    testWidgets('"Yedek Al" › seçim penceresi kapatılırsa hiçbir yedek oluşturulmaz', (tester) async {
      tester.view.physicalSize = const Size(412, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      var initialCount = 0;
      await tester.runAsync(() async {
        await store.load();
        initialCount = (await BackupService.listBackups()).length;
      });

      await tester.pumpWidget(const MaterialApp(home: BackupSettingsPage()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Yedek Al (JSON Dosyası)'));
      await tester.pumpAndSettle();

      expect(find.text('Telefona kaydet'), findsOneWidget);

      // Pencereyi kapat
      Navigator.pop(tester.element(find.text('Telefona kaydet')));
      await tester.pumpAndSettle();

      var afterCount = 0;
      await tester.runAsync(() async {
        afterCount = (await BackupService.listBackups()).length;
      });
      expect(afterCount, equals(initialCount));
    });

    testWidgets('Yerel yedekler listesinde ⋮ menüsü › "Telefona kaydet": o yedeği kaydeder', (tester) async {
      tester.view.physicalSize = const Size(412, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.runAsync(() async {
        await store.load();
        await BackupService.createBackup(store, prefix: 'manual');
      });

      Uint8List? capturedBytes;
      String? capturedName;
      BackupService.saveFileOverrideForTest = ({required fileName, required bytes}) async {
        capturedName = fileName;
        capturedBytes = bytes;
        return Uri.file('/storage/emulated/0/Download/$fileName');
      };

      await tester.pumpWidget(const MaterialApp(home: BackupSettingsPage()));
      await tester.pumpAndSettle();

      // "Yerel Yedekler & Geçmiş" sayfasına dokun
      await tester.tap(find.text('Yerel Yedekler & Geçmiş'));
      await _settle(tester);

      // Menü düğmesine dokun
      final moreBtn = find.byIcon(Icons.more_vert).first;
      await tester.tap(moreBtn);
      await tester.pumpAndSettle();

      // "Telefona kaydet" seçeneğini gör ve dokun
      expect(find.text('Telefona kaydet'), findsOneWidget);
      await tester.tap(find.text('Telefona kaydet'));
      await _settle(tester);

      expect(capturedBytes, isNotNull);
      expect(capturedName, isNotNull);
      expect(capturedName, endsWith('.json'));
      expect(find.text('Yedek telefona kaydedildi'), findsOneWidget);
    });

    testWidgets('Kullanıcı sistem kaydetme penceresinden vazgeçtiğinde ileti gösterilmez', (tester) async {
      tester.view.physicalSize = const Size(412, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.runAsync(store.load);

      BackupService.saveFileOverrideForTest = ({required fileName, required bytes}) async {
        // Kullanıcı SAF penceresinden vazgeçti
        return null;
      };

      await tester.pumpWidget(const MaterialApp(home: BackupSettingsPage()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Yedek Al (JSON Dosyası)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Telefona kaydet'));
      await _settle(tester);

      // Vazgeçilince hiçbir bildirim görünmez
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('Kaydetme hatasında hata iletisi gösterilir', (tester) async {
      tester.view.physicalSize = const Size(412, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.runAsync(store.load);

      BackupService.saveFileOverrideForTest = ({required fileName, required bytes}) async {
        throw Exception('Depolama izni reddedildi');
      };

      await tester.pumpWidget(const MaterialApp(home: BackupSettingsPage()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Yedek Al (JSON Dosyası)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Telefona kaydet'));
      await _settle(tester);

      expect(find.textContaining('Yedek kaydedilemedi: Exception: Depolama izni reddedildi'), findsOneWidget);
    });

    testWidgets('Çift dokunuş koruması kaydetmenin iki kez başlatılmasını önler', (tester) async {
      tester.view.physicalSize = const Size(412, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.runAsync(store.load);

      var callCount = 0;
      final completer = Completer<Uri?>();
      BackupService.saveFileOverrideForTest = ({required fileName, required bytes}) {
        callCount++;
        return completer.future;
      };

      await tester.pumpWidget(const MaterialApp(home: BackupSettingsPage()));
      await tester.pumpAndSettle();

      // İlk dokunuş
      await tester.tap(find.text('Yedek Al (JSON Dosyası)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Telefona kaydet'));
      // Bottom sheet animasyonunun bitmesi ve saveFileOverrideForTest'e ulaşması için bekle
      await _settle(tester);

      expect(callCount, equals(1));

      // İşlem sürerken tekrar "Yedek Al"a basmayı dene
      await tester.tap(find.text('Yedek Al (JSON Dosyası)'));
      await tester.pump(const Duration(milliseconds: 50));

      // Hâlâ 1 kez çağrılmış olmalı (yeni seçim penceresi açılmaz)
      expect(callCount, equals(1));
      expect(find.text('Telefona kaydet'), findsNothing);

      // İşlemi tamamla
      completer.complete(Uri.file('/tmp/seyir.json'));
      await _settle(tester);

      expect(callCount, equals(1));
    });

    testWidgets('İngilizce arayüzde doğru metinler ve dosya adı biçimi kullanılır', (tester) async {
      tester.view.physicalSize = const Size(412, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.runAsync(() async {
        await store.load();
        await store.setLanguage(AppLanguage.en);
      });

      String? capturedName;
      BackupService.saveFileOverrideForTest = ({required fileName, required bytes}) async {
        capturedName = fileName;
        return Uri.file('/tmp/$fileName');
      };

      await tester.pumpWidget(const MaterialApp(home: BackupSettingsPage()));
      await tester.pumpAndSettle();

      expect(
        find.text('Create a backup file to save on your phone or share'),
        findsOneWidget,
      );

      await tester.tap(find.text(strings.value.backupExport));
      await tester.pumpAndSettle();

      expect(find.text('Save to phone'), findsOneWidget);
      expect(find.text('Share'), findsOneWidget);

      await tester.tap(find.text('Save to phone'));
      await _settle(tester);

      expect(capturedName, isNotNull);
      expect(capturedName!.startsWith('seyir-backup-'), isTrue);
      expect(find.text('Backup saved to your phone'), findsOneWidget);
    });
  });

  group('Yerleşim Taraması (360 dp ve x1.3 Yazı Boyutu)', () {
    for (final lang in [AppLanguage.tr, AppLanguage.en]) {
      final isTr = lang == AppLanguage.tr;
      testWidgets('seçim penceresi ve ⋮ menüsü 360 dp ve x1.3 yazı boyutunda taşmaz (${isTr ? 'TR' : 'EN'})', (tester) async {
        tester.view.physicalSize = const Size(360, 640);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.runAsync(() async {
          await store.load();
          await store.setLanguage(lang);
          await BackupService.createBackup(store, prefix: 'manual');
        });

        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(useMaterial3: true),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: const TextScaler.linear(1.3),
                size: const Size(360, 640),
              ),
              child: child!,
            ),
            home: const BackupSettingsPage(),
          ),
        );
        await tester.pumpAndSettle();

        // 1. Seçim penceresini aç
        await tester.tap(find.text(strings.value.backupExport));
        await tester.pumpAndSettle();

        // Seçim penceresi açıkken görsel hata (taşma) olmamalı
        expect(tester.takeException(), isNull);
        expect(find.text(isTr ? 'Telefona kaydet' : 'Save to phone'), findsOneWidget);

        // Kapat
        Navigator.pop(tester.element(find.text(isTr ? 'Telefona kaydet' : 'Save to phone')));
        await tester.pumpAndSettle();

        // 2. Yerel yedekler listesini aç
        await tester.tap(find.text(isTr ? 'Yerel Yedekler & Geçmiş' : 'Local Backups & History'));
        await _settle(tester);
        expect(tester.takeException(), isNull);

        // ⋮ menüsünü aç
        final moreBtn = find.byIcon(Icons.more_vert).first;
        await tester.tap(moreBtn);
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.text(isTr ? 'Telefona kaydet' : 'Save to phone'), findsOneWidget);
      });
    }
  });
}
