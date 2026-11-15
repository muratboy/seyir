import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:takip/data/store.dart';
import 'package:takip/services/backup_service.dart';

import 'support/real_db.dart';

void main() {
  useRealDatabase();

  setUp(() async {
    await store.load();
  });

  group('Yedekleme ve Geri Yükleme Gizlilik / Güvenlik Kuralları', () {
    const deviceApiKey = 'device-secret-api-key-12345';
    const backupApiKey = 'backup-secret-api-key-99999';

    test('dışa aktarılan JSON çıktısında ve güvenlik yedeğinde llm_api_key bulunmaz', () async {
      await store.setLlmConfig(
        provider: 'gemini',
        apiKey: deviceApiKey,
        model: 'gemini-flash-latest',
      );
      expect(store.llmApiKey, equals(deviceApiKey));

      // 1. Manuel exportJson çıktısını kontrol et
      final exportedJson = await store.exportJson();
      expect(
        exportedJson.contains(deviceApiKey),
        isFalse,
        reason: 'Dışa aktarılan JSON içeriğinde API anahtarı düz metin olarak geçmemelidir',
      );

      final decoded = jsonDecode(exportedJson) as Map<String, dynamic>;
      final settings = (decoded['settings'] as List).cast<Map<String, dynamic>>();
      expect(
        settings.any((r) => r['key'] == 'llm_api_key'),
        isFalse,
        reason: 'settings tablosu içinde llm_api_key satırı bulunmamalıdır',
      );

      // 2. Geri yükleme öncesi güvenlik yedeğini kontrol et
      final snapshot = await BackupService.createPreRestoreSnapshot(store);
      try {
        final snapshotText = await snapshot.readAsString();
        expect(
          snapshotText.contains(deviceApiKey),
          isFalse,
          reason: 'Güvenlik yedeği dosyasında API anahtarı bulunmamalıdır',
        );
        final snapshotDecoded = jsonDecode(snapshotText) as Map<String, dynamic>;
        final snapshotSettings = (snapshotDecoded['settings'] as List).cast<Map<String, dynamic>>();
        expect(
          snapshotSettings.any((r) => r['key'] == 'llm_api_key'),
          isFalse,
          reason: 'Güvenlik yedeğindeki settings tablosunda llm_api_key satırı bulunmamalıdır',
        );
      } finally {
        if (await snapshot.exists()) {
          await snapshot.delete();
        }
      }
    });

    test('cihazda API anahtarı varken geri yükleme cihazdaki dört ayarı korur, yedektekileri ezer', () async {
      // Cihazdaki yapay zeka ayarlarını hazırla
      await store.setLlmConfig(
        provider: 'gemini',
        apiKey: deviceApiKey,
        model: 'gemini-flash-latest',
        customEndpoint: 'https://gemini.local/endpoint',
      );

      // Başka ayarları olan (eski biçimli veya farklı yapay zeka ayarlı) yedek oluştur
      final baseExport = await store.exportJson();
      final backupMap = jsonDecode(baseExport) as Map<String, dynamic>;
      final backupSettings = (backupMap['settings'] as List).cast<Map<String, dynamic>>();

      // Yedek içine farklı yapay zeka ayarları ekle
      backupSettings.removeWhere((r) => r['key'] == 'llm_provider' || r['key'] == 'llm_model');
      backupSettings.add({'key': 'llm_provider', 'value': 'openai'});
      backupSettings.add({'key': 'llm_api_key', 'value': backupApiKey});
      backupSettings.add({'key': 'llm_model', 'value': 'gpt-4o'});
      backupSettings.add({'key': 'llm_custom_endpoint', 'value': 'https://api.openai.com'});

      final backupJson = jsonEncode(backupMap);

      // İçe aktarma yap
      await store.importJson(backupJson);

      // Cihazdaki ayarların aynen korunduğunu doğrula
      expect(store.llmApiKey, equals(deviceApiKey), reason: 'Cihazdaki API anahtarı korunmalıdır');
      expect(store.llmProvider, equals('gemini'), reason: 'Cihazdaki sağlayıcı korunmalıdır');
      expect(store.llmModel, equals('gemini-flash-latest'), reason: 'Cihazdaki model korunmalıdır');
      expect(store.llmCustomEndpoint, equals('https://gemini.local/endpoint'), reason: 'Cihazdaki uç nokta korunmalıdır');

      // Bellek ile veritabanının birebir aynı olduğunu doğrudan SQL ile doğrula
      final db = await store.db;
      final dbRows = await db.query('settings');
      final dbSettings = {for (final r in dbRows) r['key'] as String: r['value'] as String};
      expect(dbSettings['llm_api_key'], equals(deviceApiKey));
      expect(dbSettings['llm_provider'], equals('gemini'));
      expect(dbSettings['llm_model'], equals('gemini-flash-latest'));
      expect(dbSettings['llm_custom_endpoint'], equals('https://gemini.local/endpoint'));
    });

    test('cihazda API anahtarı yokken eski biçimli yedekten gelen anahtar ve ayarlar alınır', () async {
      // Cihazdaki yapay zeka yapılandırmasını temizle
      await store.clearLlmConfig();
      expect(store.hasLlmKey, isFalse);
      expect(store.llmApiKey, isEmpty);

      // Eski biçimli yedek: içinde llm_api_key bulunan bir yedek simüle et
      final baseExport = await store.exportJson();
      final backupMap = jsonDecode(baseExport) as Map<String, dynamic>;
      final backupSettings = (backupMap['settings'] as List).cast<Map<String, dynamic>>();

      backupSettings.removeWhere((r) => r['key'] == 'llm_provider' || r['key'] == 'llm_model');
      backupSettings.add({'key': 'llm_provider', 'value': 'openrouter'});
      backupSettings.add({'key': 'llm_api_key', 'value': 'restored-old-key-8888'});
      backupSettings.add({'key': 'llm_model', 'value': 'deepseek/deepseek-chat'});
      backupSettings.add({'key': 'llm_custom_endpoint', 'value': 'https://openrouter.ai/api'});

      final backupJson = jsonEncode(backupMap);

      // İçe aktarma yap
      await store.importJson(backupJson);

      // Cihazda anahtar olmadığı için yedekten başarıyla yüklendiğini doğrula
      expect(store.llmApiKey, equals('restored-old-key-8888'));
      expect(store.llmProvider, equals('openrouter'));
      expect(store.llmModel, equals('deepseek/deepseek-chat'));
      expect(store.llmCustomEndpoint, equals('https://openrouter.ai/api'));

      // Bellek ile veritabanının birebir aynı olduğunu doğrula
      final db = await store.db;
      final dbRows = await db.query('settings');
      final dbSettings = {for (final r in dbRows) r['key'] as String: r['value'] as String};
      expect(dbSettings['llm_api_key'], equals('restored-old-key-8888'));
      expect(dbSettings['llm_provider'], equals('openrouter'));
      expect(dbSettings['llm_model'], equals('deepseek/deepseek-chat'));
      expect(dbSettings['llm_custom_endpoint'], equals('https://openrouter.ai/api'));
    });
  });
}
