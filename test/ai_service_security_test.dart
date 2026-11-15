import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:takip/services/ai_service.dart';

class _FakeHttpHeaders implements HttpHeaders {
  final Map<String, String> values = {};

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {
    values[name.toLowerCase()] = value.toString();
  }

  @override
  String? value(String name) => values[name.toLowerCase()];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeHttpClientResponse extends Stream<List<int>> implements HttpClientResponse {
  @override
  final int statusCode;
  final String body;

  _FakeHttpClientResponse(this.statusCode, this.body);

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return Stream.value(utf8.encode(body)).listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeHttpClientRequest implements HttpClientRequest {
  final _FakeHttpClient client;
  final _FakeHttpHeaders _headers = _FakeHttpHeaders();

  _FakeHttpClientRequest(this.client);

  @override
  HttpHeaders get headers => _headers;

  @override
  void add(List<int> data) {}

  @override
  Future<HttpClientResponse> close() async {
    client.capturedHeaders.addAll(_headers.values);
    return _FakeHttpClientResponse(client.statusCode, client.responseBody);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeHttpClient implements HttpClient {
  Uri? lastUri;
  final Map<String, String> capturedHeaders = {};
  int statusCode = 200;
  String responseBody = jsonEncode({
    'candidates': [
      {
        'content': {
          'parts': [
            {
              'text': '''```json
{
  "title": "Güvenlik Test Haritası",
  "description": "Test açıklaması",
  "category": "Test",
  "emoji": "🛡️",
  "steps": [
    {
      "order": 1,
      "title": "Adım 1",
      "description": "Detay",
      "type": "task",
      "target": null,
      "unit": null
    }
  ]
}
```'''
            }
          ]
        }
      }
    ],
    'choices': [
      {
        'message': {
          'content': '''```json
{
  "title": "Güvenlik Test Haritası",
  "description": "Test açıklaması",
  "category": "Test",
  "emoji": "🛡️",
  "steps": [
    {
      "order": 1,
      "title": "Adım 1",
      "description": "Detay",
      "type": "task",
      "target": null,
      "unit": null
    }
  ]
}
```'''
        }
      }
    ]
  });
  IOException? throwOnPost;

  @override
  Duration? connectionTimeout;

  @override
  Future<HttpClientRequest> postUrl(Uri url) async {
    lastUri = url;
    if (throwOnPost != null) {
      throw throwOnPost!;
    }
    return _FakeHttpClientRequest(this);
  }

  @override
  void close({bool force = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('AiService API Anahtarı ve Ağ Güvenliği', () {
    const geminiSecretKey = 'AIzaSyFakeSecretGeminiKey12345';
    const openaiSecretKey = 'sk-proj-FakeOpenAiSecretKey67890';
    const openrouterSecretKey = 'sk-or-v1-FakeOpenRouterKeyabcde';

    test('Gemini bağlantı testinde anahtar URL sorgusunda yer almaz, x-goog-api-key başlığında gider', () async {
      final fakeClient = _FakeHttpClient();

      final ok = await AiService.testConnection(
        provider: 'gemini',
        apiKey: geminiSecretKey,
        customClient: fakeClient,
      );

      expect(ok, isTrue);
      expect(fakeClient.lastUri, isNotNull);
      expect(
        fakeClient.lastUri!.queryParameters.containsKey('key'),
        isFalse,
        reason: 'API anahtarı URL sorgu parametrelerinde bulunmamalıdır',
      );
      expect(
        fakeClient.lastUri.toString().contains(geminiSecretKey),
        isFalse,
        reason: 'URL string içinde anahtar geçmemelidir',
      );
      expect(
        fakeClient.capturedHeaders['x-goog-api-key'],
        equals(geminiSecretKey),
        reason: 'Anahtar x-goog-api-key başlığında taşınmalıdır',
      );
    });

    test('Gemini yol haritası isteğinde anahtar URL sorgusunda yer almaz, x-goog-api-key başlığında gider', () async {
      final fakeClient = _FakeHttpClient();

      final roadmap = await AiService.generateRoadmap(
        topic: 'Test Konusu',
        provider: 'gemini',
        apiKey: geminiSecretKey,
        customClient: fakeClient,
      );

      expect(roadmap.title, 'Güvenlik Test Haritası');
      expect(
        fakeClient.lastUri!.queryParameters.containsKey('key'),
        isFalse,
        reason: 'API anahtarı URL sorgu parametrelerinde bulunmamalıdır',
      );
      expect(
        fakeClient.lastUri.toString().contains(geminiSecretKey),
        isFalse,
        reason: 'URL string içinde anahtar geçmemelidir',
      );
      expect(
        fakeClient.capturedHeaders['x-goog-api-key'],
        equals(geminiSecretKey),
        reason: 'Anahtar x-goog-api-key başlığında taşınmalıdır',
      );
    });

    test('Ağ hatası oluştuğunda hata iletisinde API anahtarı hiçbir koşulda görünmez', () async {
      final fakeClient = _FakeHttpClient()
        ..throwOnPost = HttpException(
          'Connection refused to https://generativelanguage.googleapis.com?key=$geminiSecretKey',
          uri: Uri.parse('https://generativelanguage.googleapis.com?key=$geminiSecretKey'),
        );

      // 1. testConnection hata mesajı denetimi
      try {
        await AiService.testConnection(
          provider: 'gemini',
          apiKey: geminiSecretKey,
          customClient: fakeClient,
        );
        fail('AiException fırlatılmalıydı');
      } on AiException catch (e) {
        expect(e.problem, equals(AiProblem.networkError));
        expect(
          e.message.contains(geminiSecretKey),
          isFalse,
          reason: 'Hata mesajında API anahtarı bulunmamalıdır',
        );
        expect(
          e.toString().contains(geminiSecretKey),
          isFalse,
          reason: 'Exception toString() çıktısında API anahtarı bulunmamalıdır',
        );
      }

      // 2. generateRoadmap hata mesajı denetimi
      try {
        await AiService.generateRoadmap(
          topic: 'Test',
          provider: 'gemini',
          apiKey: geminiSecretKey,
          customClient: fakeClient,
        );
        fail('AiException fırlatılmalıydı');
      } on AiException catch (e) {
        expect(e.problem, equals(AiProblem.networkError));
        expect(
          e.message.contains(geminiSecretKey),
          isFalse,
          reason: 'Hata mesajında API anahtarı bulunmamalıdır',
        );
        expect(
          e.toString().contains(geminiSecretKey),
          isFalse,
          reason: 'Exception toString() çıktısında API anahtarı bulunmamalıdır',
        );
      }
    });

    test('OpenAI ve OpenRouter isteklerinde yetkilendirme başlığı ve davranışı değişmez', () async {
      // OpenAI kontrolü
      final openAiClient = _FakeHttpClient();
      final openAiOk = await AiService.testConnection(
        provider: 'openai',
        apiKey: openaiSecretKey,
        customClient: openAiClient,
      );
      expect(openAiOk, isTrue);
      expect(
        openAiClient.capturedHeaders['authorization'],
        equals('Bearer $openaiSecretKey'),
        reason: 'OpenAI için Authorization Bearer başlığı korunmalıdır',
      );
      expect(
        openAiClient.capturedHeaders.containsKey('x-goog-api-key'),
        isFalse,
        reason: 'OpenAI isteğinde x-goog-api-key bulunmamalıdır',
      );

      // OpenRouter kontrolü
      final openRouterClient = _FakeHttpClient();
      final openRouterOk = await AiService.testConnection(
        provider: 'openrouter',
        apiKey: openrouterSecretKey,
        customClient: openRouterClient,
      );
      expect(openRouterOk, isTrue);
      expect(
        openRouterClient.capturedHeaders['authorization'],
        equals('Bearer $openrouterSecretKey'),
        reason: 'OpenRouter için Authorization Bearer başlığı korunmalıdır',
      );
      expect(
        openRouterClient.capturedHeaders['http-referer'],
        equals('https://github.com/muratboy/seyir'),
      );
      expect(
        openRouterClient.capturedHeaders['x-title'],
        equals('Seyir'),
      );
      expect(
        openRouterClient.capturedHeaders.containsKey('x-goog-api-key'),
        isFalse,
        reason: 'OpenRouter isteğinde x-goog-api-key bulunmamalıdır',
      );
    });
  });
}
