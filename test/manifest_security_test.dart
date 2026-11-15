import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Android Manifest Güvenlik ve Gizlilik Yapılandırması', () {
    late String manifestContent;

    setUpAll(() {
      final file = File('android/app/src/main/AndroidManifest.xml');
      expect(file.existsSync(), isTrue, reason: 'AndroidManifest.xml bulunamadı');
      manifestContent = file.readAsStringSync();
    });

    test('bulut yedeği kapalı olmalı (allowBackup="false")', () {
      // Veritabanı ve hassas kullanıcı verilerinin Google bulut yedeğine çıkmaması için
      // allowBackup özelliği açıkça false olarak tanımlanmalıdır.
      expect(manifestContent, contains('android:allowBackup="false"'));
    });

    test('takip şemalı intent filtresinde BROWSABLE kategorisi bulunmamalı', () {
      // Dış web sitelerinin veya tarayıcıların onay almadan takip:// bağlantılarını
      // tetiklemesini önlemek için BROWSABLE kategorisi kaldırılmalıdır.
      final mainActivityRegex = RegExp(
        r'<activity[^>]*android:name="\.MainActivity"[^>]*>([\s\S]*?)<\/activity>',
      );
      final match = mainActivityRegex.firstMatch(manifestContent);
      expect(match, isNotNull, reason: 'MainActivity manifest içinde bulunamadı');

      final activityBody = match!.group(1)!;
      final takipFilterRegex = RegExp(
        r'<intent-filter>([\s\S]*?<data[^>]*android:scheme="takip"[^>]*>[\s\S]*?)<\/intent-filter>',
      );
      final filterMatch = takipFilterRegex.firstMatch(activityBody);
      expect(filterMatch, isNotNull, reason: 'takip şemalı intent-filter bulunamadı');

      final filterBody = filterMatch!.group(1)!;
      expect(
        filterBody.contains('android.intent.category.BROWSABLE'),
        isFalse,
        reason: 'takip şemasında BROWSABLE kategorisi bulunmamalı',
      );
      expect(
        filterBody.contains('android.intent.category.DEFAULT'),
        isTrue,
        reason: 'DEFAULT kategorisi korunmalıdır',
      );
    });

    test('HomeWidgetBackgroundReceiver dışa kapalı olmalı (exported="false")', () {
      // Başka uygulamaların yetkisiz yayın göndererek arka planda kayıt tetiklemesini
      // engellemek için HomeWidgetBackgroundReceiver dışa kapalı olmalıdır.
      final receiverRegex = RegExp(
        r'<receiver[^>]*android:name="es\.antonborri\.home_widget\.HomeWidgetBackgroundReceiver"[^>]*android:exported="([^"]+)"',
      );
      final match = receiverRegex.firstMatch(manifestContent);
      expect(match, isNotNull, reason: 'HomeWidgetBackgroundReceiver manifest içinde bulunamadı');
      expect(match!.group(1), equals('false'));
    });
  });
}
