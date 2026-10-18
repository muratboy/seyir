import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:takip/services/ai_service.dart';

void main() {
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
  });

  group('AiService HTTP Mock Tests', () {
    late HttpServer server;
    late Map<String, void Function(HttpRequest)> routes;

    setUp(() async {
      routes = {};
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) {
        final handler = routes[request.uri.path];
        if (handler != null) {
          handler(request);
        } else {
          request.response.statusCode = HttpStatus.notFound;
          request.response.close();
        }
      });
    });

    tearDown(() => server.close(force: true));

    test('validates OpenAI connection and generates roadmap with mock server', () async {
      final mockRoadmapJson = jsonEncode({
        'title': 'Test Yol Haritası',
        'description': 'Açıklama',
        'category': 'Test',
        'emoji': '🗺️',
        'steps': [
          {
            'order': 1,
            'title': 'Adım 1',
            'description': 'Görev',
            'type': 'task',
            'target': null,
            'unit': null,
          },
          {
            'order': 2,
            'title': 'Adım 2',
            'description': 'Hedef',
            'type': 'goal',
            'target': 500,
            'unit': 'dk',
          }
        ]
      });

      routes['/chat/completions'] = (req) async {
        final body = await utf8.decodeStream(req);
        final decoded = jsonDecode(body);
        final messages = decoded['messages'] as List;
        final userMsg = messages.last['content'] as String;

        if (userMsg.contains('Reply with OK')) {
          req.response.statusCode = HttpStatus.ok;
          req.response.write(jsonEncode({
            'choices': [
              {
                'message': {'role': 'assistant', 'content': 'OK'}
              }
            ]
          }));
          await req.response.close();
        } else {
          req.response.statusCode = HttpStatus.ok;
          req.response.write(jsonEncode({
            'choices': [
              {
                'message': {
                  'role': 'assistant',
                  'content': '```json\n$mockRoadmapJson\n```',
                }
              }
            ]
          }));
          await req.response.close();
        }
      };

      final customEndpoint = 'http://127.0.0.1:${server.port}/chat/completions';

      // 1. Test connection
      final ok = await AiService.testConnection(
        provider: 'custom',
        apiKey: 'test-key',
        customEndpoint: customEndpoint,
      );
      expect(ok, isTrue);

      // 2. Generate roadmap
      final roadmap = await AiService.generateRoadmap(
        topic: 'Flutter Öğrenme',
        provider: 'custom',
        apiKey: 'test-key',
        customEndpoint: customEndpoint,
        isTr: true,
      );

      expect(roadmap.title, 'Test Yol Haritası');
      expect(roadmap.steps.length, 2);
      expect(roadmap.steps[0].type, 'task');
      expect(roadmap.steps[1].type, 'goal');
      expect(roadmap.steps[1].target, 500);
      expect(roadmap.steps[1].unit, 'dk');
    });

    test('handles API errors properly (quota exceeded, invalid key)', () async {
      routes['/chat/completions'] = (req) async {
        req.response.statusCode = 429;
        req.response.write(jsonEncode({
          'error': {'message': 'Quota exceeded / Rate limit reached'}
        }));
        await req.response.close();
      };

      final customEndpoint = 'http://127.0.0.1:${server.port}/chat/completions';

      expect(
        () => AiService.testConnection(
          provider: 'custom',
          apiKey: 'test-key',
          customEndpoint: customEndpoint,
        ),
        throwsA(isA<AiException>().having((e) => e.problem, 'problem', AiProblem.rateLimitOrQuota)),
      );
    });

    test('throws AiException on empty topic or missing key', () async {
      expect(
        () => AiService.generateRoadmap(
          topic: '',
          provider: 'gemini',
          apiKey: 'key',
        ),
        throwsA(isA<AiException>().having((e) => e.problem, 'problem', AiProblem.parseError)),
      );

      expect(
        () => AiService.generateRoadmap(
          topic: 'Test',
          provider: 'gemini',
          apiKey: '',
        ),
        throwsA(isA<AiException>().having((e) => e.problem, 'problem', AiProblem.missingKey)),
      );
    });
  });
}
