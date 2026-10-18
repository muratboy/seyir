import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:takip/data/store.dart';
import 'package:takip/services/ai_service.dart';
import 'package:takip/ui/components/roadmap_ai_dialog.dart';
import 'package:takip/ui/settings_pages.dart';

import 'support/real_db.dart';

void main() {
  useRealDatabase();

  setUp(() async {
    await store.load();
  });

  group('AiService Models & Provider Defaults', () {
    test('returns correct default models and provider display names', () {
      expect(AiService.defaultModelFor('gemini'), 'gemini-flash-latest');
      expect(AiService.defaultModelFor('openai'), 'gpt-4o-mini');
      expect(AiService.defaultModelFor('openrouter'), 'google/gemini-2.0-flash-exp:free');
      expect(AiService.defaultModelFor('custom'), 'default');

      expect(AiService.providerDisplayName('gemini'), 'Google Gemini');
      expect(AiService.providerDisplayName('openai'), 'OpenAI');
      expect(AiService.providerDisplayName('openrouter'), 'OpenRouter');
      expect(AiService.providerDisplayName('custom'), contains('Özel'));
    });

    test('normalizes missing, prefixed or colloquial model names accurately', () {
      // Gemini
      expect(AiService.normalizeModelName('gemini', 'gemini'), 'gemini-flash-latest');
      expect(AiService.normalizeModelName('gemini', 'models/gemini-1.5-flash'), 'gemini-flash-latest');
      expect(AiService.normalizeModelName('gemini', 'flash'), 'gemini-flash-latest');
      expect(AiService.normalizeModelName('gemini', 'pro'), 'gemini-pro-latest');
      expect(AiService.normalizeModelName('gemini', 'gemini-3.8-flash'), 'gemini-3.8-flash');
      expect(AiService.normalizeModelName('gemini', 'flash-lite'), 'gemini-flash-lite-latest');
      expect(AiService.normalizeModelName('gemini', ''), 'gemini-flash-latest');

      // OpenAI
      expect(AiService.normalizeModelName('openai', 'chatgpt'), 'gpt-4o-mini');
      expect(AiService.normalizeModelName('openai', 'gpt-4'), 'gpt-4o');
      expect(AiService.normalizeModelName('openai', 'gpt-4o-mini'), 'gpt-4o-mini');

      // OpenRouter
      expect(AiService.normalizeModelName('openrouter', 'gemini'), 'google/gemini-2.0-flash-exp:free');
      expect(AiService.normalizeModelName('openrouter', 'claude'), 'anthropic/claude-3.5-sonnet');
      expect(AiService.normalizeModelName('openrouter', 'deepseek'), 'deepseek/deepseek-chat');

      // Recommended models list
      final geminiModels = AiService.recommendedModelsFor('gemini');
      expect(geminiModels.any((m) => m.id == 'gemini-flash-latest'), isTrue);
      expect(geminiModels.firstWhere((m) => m.id == 'gemini-flash-latest').isRecommended, isTrue);
    });
  });

  group('AppStore BYOK LLM Configuration', () {
    test('configures, persists and clears LLM settings', () async {
      expect(store.hasLlmKey, isFalse);
      expect(store.llmProvider, 'gemini');
      expect(store.activeLlmModel, 'gemini-flash-latest');

      await store.setLlmConfig(
        provider: 'gemini',
        apiKey: 'AIzaSyTest123',
        model: 'gemini-3.8-flash',
      );

      expect(store.hasLlmKey, isTrue);
      expect(store.llmApiKey, 'AIzaSyTest123');
      expect(store.activeLlmModel, 'gemini-3.8-flash');

      // Veritabanından tekrar okunsa dahi ayarlar korunur
      await store.refresh();
      expect(store.hasLlmKey, isTrue);
      expect(store.llmApiKey, 'AIzaSyTest123');
      expect(store.activeLlmModel, 'gemini-3.8-flash');

      // Anahtarı temizleme
      await store.clearLlmConfig();
      expect(store.hasLlmKey, isFalse);
      expect(store.llmApiKey, isEmpty);

      await store.refresh();
      expect(store.hasLlmKey, isFalse);
    });

    test('activeLlmModel falls back to provider default when model is empty', () async {
      await store.setLlmConfig(
        provider: 'openai',
        apiKey: 'sk-test',
        model: '',
      );
      expect(store.activeLlmModel, 'gpt-4o-mini');

      await store.setLlmConfig(
        provider: 'openrouter',
        apiKey: 'sk-or-test',
        model: '   ',
      );
      expect(store.activeLlmModel, 'google/gemini-2.0-flash-exp:free');
    });
  });

  group('UI Widgets Tests', () {
    testWidgets('AiSettingsPage renders options, explanations and test connection button', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: AiSettingsPage(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Yapay Zekâ & API (BYOK)'), findsOneWidget);
      expect(find.text('Gizlilik & Çevrimdışı İlkeli'), findsOneWidget);
      expect(find.text('Sağlayıcı ve Model'), findsOneWidget);
      expect(find.text('Bağlantıyı Test Et'), findsOneWidget);
      expect(find.text('Kaydet'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text('Nasıl Ücretsiz Gemini Anahtarı Alınır?'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Nasıl Ücretsiz Gemini Anahtarı Alınır?'), findsOneWidget);
    });

    testWidgets('RoadmapAiDialog shows setup prompt when no key', (tester) async {
      await tester.runAsync(() async {
        await store.clearLlmConfig();
      });
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: RoadmapAiDialog(),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Kendi Anahtarını Getir (BYOK)'), findsOneWidget);
      expect(find.text('API Anahtarı Tanımla (Ayarlar)'), findsOneWidget);
    });

    testWidgets('RoadmapAiDialog shows generator form when key is set', (tester) async {
      await tester.runAsync(() async {
        await store.setLlmConfig(provider: 'gemini', apiKey: 'AIzaSyTest');
      });
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: RoadmapAiDialog(),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Hızlı Öneriler:'), findsOneWidget);
      expect(find.text('Yol Haritası Üret'), findsOneWidget);
      expect(find.textContaining('Google Gemini'), findsOneWidget);
    });
  });
}
