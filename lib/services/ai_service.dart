import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../data/models.dart';
import 'roadmap_parser.dart';

/// Yapay zekâ istekleri sırasında oluşabilecek sorun türleri.
enum AiProblem {
  missingKey,
  invalidKey,
  rateLimitOrQuota,
  modelNotFound,
  networkError,
  timeout,
  parseError,
  serverError,
}

class AiException implements Exception {
  final AiProblem problem;
  final String message;
  final int? statusCode;

  const AiException(this.problem, this.message, {this.statusCode});

  @override
  String toString() => 'AiException($problem: $message${statusCode != null ? ', status: $statusCode' : ''})';
}

/// Önerilen yapay zekâ model seçeneği bilgisi.
class AiModelOption {
  final String id;
  final String displayName;
  final String? badge;
  final bool isRecommended;

  const AiModelOption({
    required this.id,
    required this.displayName,
    this.badge,
    this.isRecommended = false,
  });
}

/// Kullanıcının kendi API anahtarıyla (BYOK - Bring Your Own Key) yapay zekâ modellerine
/// (Google Gemini, OpenAI, OpenRouter, Özel Yerel Uç Nokta) doğrudan ve güvenli istek atmasını sağlar.
///
/// Uygulama tamamen çevrimdışı çalışır; hiçbir veri veya kayıt dış sunuculara gitmez.
/// Yalnızca kullanıcı bir yol haritası üretmek istediğinde bu servis üzerinden
/// seçilen modele tek seferlik bir istek gönderilir.
class AiService {
  AiService._();

  static const Duration timeoutDuration = Duration(seconds: 45);

  /// Sağlayıcıya göre varsayılan model adını döner.
  static String defaultModelFor(String provider) {
    return switch (provider.toLowerCase()) {
      'openai' => 'gpt-4o-mini',
      'openrouter' => 'google/gemini-2.0-flash-exp:free',
      'custom' => 'default',
      _ => 'gemini-flash-latest',
    };
  }

  /// Sağlayıcıya göre önerilen hazır model listesini döner.
  static List<AiModelOption> recommendedModelsFor(String provider, {bool isTr = true}) {
    return switch (provider.toLowerCase()) {
      'gemini' => [
          AiModelOption(
            id: 'gemini-flash-latest',
            displayName: 'Gemini Flash (En Güncel)',
            badge: isTr ? '⚡ Önerilen (Hızlı & Ücretsiz)' : '⚡ Recommended (Fast & Free)',
            isRecommended: true,
          ),
          AiModelOption(
            id: 'gemini-3.8-flash',
            displayName: 'Gemini 3.8 Flash',
            badge: isTr ? '🚀 Yeni Nesil Hızlı' : '🚀 Next-Gen Fast',
          ),
          AiModelOption(
            id: 'gemini-pro-latest',
            displayName: 'Gemini Pro (En Güncel)',
            badge: isTr ? '🧠 Gelişmiş Akıl Yürütme' : '🧠 Advanced Reasoning',
          ),
        ],
      'openai' => [
          AiModelOption(
            id: 'gpt-4o-mini',
            displayName: 'GPT-4o mini',
            badge: isTr ? '⚡ Önerilen (Hızlı & Ekonomik)' : '⚡ Recommended (Fast & Cheap)',
            isRecommended: true,
          ),
          AiModelOption(
            id: 'gpt-4o',
            displayName: 'GPT-4o',
            badge: isTr ? '🌟 En Yetenekli' : '🌟 Most Capable',
          ),
        ],
      'openrouter' => [
          AiModelOption(
            id: 'google/gemini-2.0-flash-exp:free',
            displayName: 'Gemini 2.0 Flash (Free)',
            badge: isTr ? '🆓 Ücretsiz' : '🆓 Free',
            isRecommended: true,
          ),
          AiModelOption(
            id: 'deepseek/deepseek-chat',
            displayName: 'DeepSeek V3',
            badge: isTr ? 'Ekonomik' : 'Cost-effective',
          ),
          AiModelOption(
            id: 'anthropic/claude-3.5-sonnet',
            displayName: 'Claude 3.5 Sonnet',
            badge: isTr ? '🏆 Yüksek Kalite' : '🏆 High Quality',
          ),
        ],
      _ => const [],
    };
  }

  /// Model adını temizler, bilinen eksik/takma adları veya biçimlendirme hatalarını
  /// (örn. "models/" öneki veya sadece "gemini") doğru API model adına dönüştürür.
  static String normalizeModelName(String provider, String? rawModel) {
    var m = (rawModel ?? '').trim();
    final p = provider.toLowerCase();

    // Başındaki ve sonundaki tırnak işaretlerini temizle
    if ((m.startsWith('"') && m.endsWith('"')) || (m.startsWith("'") && m.endsWith("'"))) {
      m = m.substring(1, m.length - 1).trim();
    }

    if (m.isEmpty) {
      return defaultModelFor(p);
    }

    if (p == 'gemini') {
      // "models/gemini-1.5-flash" gibi girilmişse "models/" kaldırılır
      if (m.toLowerCase().startsWith('models/')) {
        m = m.substring(7).trim();
      }
      final lower = m.toLowerCase();
      if (lower == 'gemini' ||
          lower == 'google' ||
          lower == 'google gemini' ||
          lower == 'default' ||
          lower == 'flash' ||
          lower == 'gemini-flash' ||
          lower == '1.5-flash' ||
          lower == 'gemini-1.5-flash' ||
          lower == 'gemini-2.0-flash' ||
          lower == 'gemini-2.5-flash' ||
          lower == 'gemini-flash-latest') {
        return 'gemini-flash-latest';
      }
      if (lower == 'pro' ||
          lower == 'gemini-pro' ||
          lower == '1.5-pro' ||
          lower == 'gemini-1.5-pro' ||
          lower == 'gemini-2.5-pro' ||
          lower == 'gemini-pro-latest') {
        return 'gemini-pro-latest';
      }
      if (lower == '3.8-flash' || lower == 'gemini-3.8' || lower == 'gemini-3.8-flash') {
        return 'gemini-3.8-flash';
      }
      if (lower == 'lite' || lower == 'flash-lite' || lower == 'gemini-flash-lite') {
        return 'gemini-flash-lite-latest';
      }
      return m;
    }

    if (p == 'openai') {
      final lower = m.toLowerCase();
      if (lower == 'openai' || lower == 'chatgpt' || lower == 'gpt' || lower == 'default' || lower == 'gpt-4o-mini') {
        return 'gpt-4o-mini';
      }
      if (lower == 'gpt-4' || lower == 'gpt4' || lower == 'gpt-4o' || lower == 'gpt4o') {
        return 'gpt-4o';
      }
      if (lower == 'gpt-3.5' || lower == 'gpt-3.5-turbo') {
        return 'gpt-4o-mini';
      }
      return m;
    }

    if (p == 'openrouter') {
      final lower = m.toLowerCase();
      if (lower == 'gemini' || lower == 'free' || lower == 'default') {
        return 'google/gemini-2.0-flash-exp:free';
      }
      if (lower == 'claude' || lower == 'claude-3.5' || lower == 'sonnet') {
        return 'anthropic/claude-3.5-sonnet';
      }
      if (lower == 'deepseek' || lower == 'deepseek-v3' || lower == 'v3') {
        return 'deepseek/deepseek-chat';
      }
      return m;
    }

    return m;
  }

  /// Sağlayıcı adının kullanıcı dostu görünümü.
  static String providerDisplayName(String provider) {
    return switch (provider.toLowerCase()) {
      'openai' => 'OpenAI',
      'openrouter' => 'OpenRouter',
      'custom' => 'Özel Uç Nokta (Ollama/Yerel)',
      _ => 'Google Gemini',
    };
  }

  /// Girilen API anahtarının ve modelin geçerli olup olmadığını doğrulamak için hafif bir test isteği gönderir.
  static Future<bool> testConnection({
    required String provider,
    required String apiKey,
    String? model,
    String? customEndpoint,
    bool isTr = true,
    HttpClient? customClient,
  }) async {
    final key = apiKey.trim();
    if (key.isEmpty && provider.toLowerCase() != 'custom') {
      throw AiException(
        AiProblem.missingKey,
        isTr ? 'API anahtarı boş bırakılamaz.' : 'API key cannot be empty.',
      );
    }

    final activeModel = normalizeModelName(provider, model);
    final client = customClient ?? HttpClient()..connectionTimeout = const Duration(seconds: 15);

    try {
      final p = provider.toLowerCase();
      if (p == 'gemini') {
        final cleanModel = activeModel.startsWith('models/') ? activeModel.substring(7) : activeModel;
        final uri = Uri.parse(
          'https://generativelanguage.googleapis.com/v1beta/models/$cleanModel:generateContent?key=$key',
        );
        final payload = jsonEncode({
          'contents': [
            {
              'parts': [
                {'text': 'Reply with OK'}
              ]
            }
          ]
        });

        final req = await client.postUrl(uri).timeout(const Duration(seconds: 15));
        req.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
        req.add(utf8.encode(payload));
        final resp = await req.close().timeout(const Duration(seconds: 15));
        final body = await utf8.decodeStream(resp);

        if (resp.statusCode != HttpStatus.ok) {
          throw _parseErrorResponse(
            resp.statusCode,
            body,
            isTr: isTr,
            provider: provider,
            activeModel: activeModel,
          );
        }
        return true;
      } else {
        // OpenAI / OpenRouter / Custom
        final uri = _resolveEndpoint(p, customEndpoint);
        final payload = jsonEncode({
          'model': activeModel,
          'messages': [
            {'role': 'user', 'content': 'Reply with OK'}
          ],
          'max_tokens': 5,
        });

        final req = await client.postUrl(uri).timeout(const Duration(seconds: 15));
        req.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
        if (key.isNotEmpty) {
          req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $key');
        }
        if (p == 'openrouter') {
          req.headers.set('HTTP-Referer', 'https://github.com/muratboy/seyir');
          req.headers.set('X-Title', 'Seyir');
        }
        req.add(utf8.encode(payload));
        final resp = await req.close().timeout(const Duration(seconds: 15));
        final body = await utf8.decodeStream(resp);

        if (resp.statusCode != HttpStatus.ok) {
          throw _parseErrorResponse(
            resp.statusCode,
            body,
            isTr: isTr,
            provider: provider,
            activeModel: activeModel,
          );
        }
        return true;
      }
    } on AiException {
      rethrow;
    } on TimeoutException {
      throw AiException(
        AiProblem.timeout,
        isTr ? 'Bağlantı zaman aşımına uğradı.' : 'Connection timed out.',
      );
    } on IOException catch (e) {
      throw AiException(
        AiProblem.networkError,
        isTr ? 'Ağ hatası: Sunucuya ulaşılamadı (${e.toString()})' : 'Network error: Cannot reach server (${e.toString()})',
      );
    } finally {
      if (customClient == null) {
        client.close(force: true);
      }
    }
  }

  /// Kullanıcının verdiği [topic] konusu için yapay zekâ modelinden yol haritası üretir ve
  /// [Roadmap] nesnesi olarak döner.
  static Future<Roadmap> generateRoadmap({
    required String topic,
    required String provider,
    required String apiKey,
    String? model,
    String? customEndpoint,
    bool isTr = true,
    HttpClient? customClient,
  }) async {
    final cleanTopic = topic.trim();
    if (cleanTopic.isEmpty) {
      throw AiException(
        AiProblem.parseError,
        isTr ? 'Lütfen bir konu veya hedef belirtin.' : 'Please specify a topic or goal.',
      );
    }

    final key = apiKey.trim();
    final p = provider.toLowerCase();
    if (key.isEmpty && p != 'custom') {
      throw AiException(
        AiProblem.missingKey,
        isTr
            ? 'API anahtarı bulunamadı. Lütfen Ayarlar > Yapay Zekâ (BYOK) bölümünden anahtarınızı kaydedin.'
            : 'API key not found. Please set your key in Settings > AI & API Key (BYOK).',
      );
    }

    final activeModel = normalizeModelName(provider, model);
    final prompt = _buildPrompt(cleanTopic, isTr: isTr);
    final client = customClient ?? HttpClient()..connectionTimeout = timeoutDuration;

    try {
      String rawResponse;
      if (p == 'gemini') {
        final cleanModel = activeModel.startsWith('models/') ? activeModel.substring(7) : activeModel;
        final uri = Uri.parse(
          'https://generativelanguage.googleapis.com/v1beta/models/$cleanModel:generateContent?key=$key',
        );
        final payload = jsonEncode({
          'contents': [
            {
              'parts': [
                {'text': prompt}
              ]
            }
          ],
          'generationConfig': {
            'temperature': 0.7,
          }
        });

        final req = await client.postUrl(uri).timeout(timeoutDuration);
        req.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
        req.add(utf8.encode(payload));
        final resp = await req.close().timeout(timeoutDuration);
        final body = await utf8.decodeStream(resp);

        if (resp.statusCode != HttpStatus.ok) {
          throw _parseErrorResponse(
            resp.statusCode,
            body,
            isTr: isTr,
            provider: provider,
            activeModel: activeModel,
          );
        }

        final decoded = jsonDecode(body);
        if (decoded is! Map) {
          throw AiException(AiProblem.parseError, isTr ? 'Geçersiz sunucu yanıtı.' : 'Invalid server response.');
        }

        final candidates = decoded['candidates'] as List?;
        if (candidates == null || candidates.isEmpty) {
          throw AiException(AiProblem.parseError, isTr ? 'Yapay zekâdan yanıt alınamadı.' : 'No response from AI.');
        }

        final firstCandidate = candidates[0];
        final parts = firstCandidate['content']?['parts'] as List?;
        if (parts == null || parts.isEmpty) {
          throw AiException(AiProblem.parseError, isTr ? 'Yapay zekâ içeriği boş döndü.' : 'Empty content from AI.');
        }

        rawResponse = parts[0]['text'] as String? ?? '';
      } else {
        // OpenAI / OpenRouter / Custom
        final uri = _resolveEndpoint(p, customEndpoint);
        final systemMsg = isTr
            ? 'Sen kişisel gelişim ve hedef planlama konusunda uzman bir asistansın. Çıktıyı SADECE belirtilen JSON formatında ver.'
            : 'You are an expert personal planning assistant. Output ONLY the requested JSON format.';

        final payload = jsonEncode({
          'model': activeModel,
          'messages': [
            {'role': 'system', 'content': systemMsg},
            {'role': 'user', 'content': prompt}
          ],
          'temperature': 0.7,
        });

        final req = await client.postUrl(uri).timeout(timeoutDuration);
        req.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
        if (key.isNotEmpty) {
          req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $key');
        }
        if (p == 'openrouter') {
          req.headers.set('HTTP-Referer', 'https://github.com/muratboy/seyir');
          req.headers.set('X-Title', 'Seyir');
        }
        req.add(utf8.encode(payload));
        final resp = await req.close().timeout(timeoutDuration);
        final body = await utf8.decodeStream(resp);

        if (resp.statusCode != HttpStatus.ok) {
          throw _parseErrorResponse(
            resp.statusCode,
            body,
            isTr: isTr,
            provider: provider,
            activeModel: activeModel,
          );
        }

        final decoded = jsonDecode(body);
        if (decoded is! Map) {
          throw AiException(AiProblem.parseError, isTr ? 'Geçersiz sunucu yanıtı.' : 'Invalid server response.');
        }

        final choices = decoded['choices'] as List?;
        if (choices == null || choices.isEmpty) {
          throw AiException(AiProblem.parseError, isTr ? 'Yapay zekâdan yanıt alınamadı.' : 'No response from AI.');
        }

        final firstChoice = choices[0];
        rawResponse = firstChoice['message']?['content'] as String? ?? '';
      }

      final parsed = RoadmapParser.parse(rawResponse, isTr: isTr);
      if (parsed == null) {
        throw AiException(
          AiProblem.parseError,
          isTr
              ? 'Yapay zekâ yanıt verdi ancak yol haritası JSON formatı çözümlenemedi. Lütfen tekrar deneyin.'
              : 'AI responded but the roadmap JSON format could not be parsed. Please try again.',
        );
      }

      return parsed;
    } on AiException {
      rethrow;
    } on TimeoutException {
      throw AiException(
        AiProblem.timeout,
        isTr
            ? 'Yapay zekâ sunucusu zamanında yanıt vermedi (45 sn zaman aşımı). Lütfen tekrar deneyin.'
            : 'AI server timed out (45s limit). Please try again.',
      );
    } on IOException catch (e) {
      throw AiException(
        AiProblem.networkError,
        isTr
            ? 'İnternet bağlantısı kurulamadı. Lütfen ağınızı kontrol edin (${e.toString()})'
            : 'Network connection failed. Please check your network (${e.toString()})',
      );
    } finally {
      if (customClient == null) {
        client.close(force: true);
      }
    }
  }

  static Uri _resolveEndpoint(String provider, String? customEndpoint) {
    if (provider == 'openrouter') {
      return Uri.parse('https://openrouter.ai/api/v1/chat/completions');
    }
    if (provider == 'custom') {
      final endpoint = (customEndpoint != null && customEndpoint.trim().isNotEmpty)
          ? customEndpoint.trim()
          : 'http://localhost:11434/v1';
      final clean = endpoint.endsWith('/') ? endpoint.substring(0, endpoint.length - 1) : endpoint;
      if (clean.endsWith('/chat/completions')) {
        return Uri.parse(clean);
      }
      return Uri.parse('$clean/chat/completions');
    }
    return Uri.parse('https://api.openai.com/v1/chat/completions');
  }

  static String _buildPrompt(String topic, {required bool isTr}) {
    if (isTr) {
      return '''Lütfen benim için "[$topic]" konusunda adım adım uygulanabilir bir yol haritası hazırla.

Aşağıdaki JSON kalıbını BİREBİR kullanarak yanıt ver. Yanıtında SADECE markdown kod bloğu içindeki JSON çıktısını ver:

```json
{
  "title": "Yol Haritası Başlığı",
  "description": "Yol haritasının genel hedefi ve kısa özeti",
  "category": "Kişisel Gelişim",
  "emoji": "🗺️",
  "steps": [
    {
      "order": 1,
      "title": "Adım Başlığı (tek seferlik görev)",
      "description": "Bu adımda ne yapılması gerektiği ve püf noktaları",
      "type": "task",
      "target": null,
      "unit": null
    },
    {
      "order": 2,
      "title": "Toplam 600 dk pratik yap",
      "description": "Günde 30 dk, düzenli",
      "type": "goal",
      "target": 600,
      "unit": "dk"
    }
  ]
}
```

Önemli Kurallar:
- "type": "task" -> Ölçüsüz, tek seferlik tiklenebilir görevler için kullanılır.
- "type": "goal" -> Ölçüsü, miktarı veya süresi olan adımlar için kullanılır (örneğin: toplam 600 dk, 12 bölüm, 50 km). "target" ve "unit" alanlarını doldur.
- "target", adım boyunca TOPLAMDA ulaşılacak miktardır; günlük miktar değildir. Günlük bir alışkanlığı toplamına çevirerek yaz (günde 30 dk, 20 gün -> 600 dk).
- En az 4, en fazla 15 mantıklı adım oluştur.
''';
    } else {
      return '''Please prepare a step-by-step, actionable roadmap for me on "[$topic]".

Answer using EXACTLY the JSON template below. Give ONLY the JSON output, inside a markdown code block:

```json
{
  "title": "Roadmap title",
  "description": "The overall aim of the roadmap and a short summary",
  "category": "Personal Growth",
  "emoji": "🗺️",
  "steps": [
    {
      "order": 1,
      "title": "Step title (one-off task)",
      "description": "What to do in this step and what to watch out for",
      "type": "task",
      "target": null,
      "unit": null
    },
    {
      "order": 2,
      "title": "Practice for 600 minutes in total",
      "description": "30 mins a day regularly",
      "type": "goal",
      "target": 600,
      "unit": "min"
    }
  ]
}
```

Important rules:
- "type": "task" -> for one-off tasks without a measure that are simply ticked off.
- "type": "goal" -> for steps with an amount, a quantity or a duration. Fill in "target" and "unit".
- "target" is the TOTAL to reach over the whole step, not a daily amount.
- Create between 4 and 15 meaningful steps.
''';
    }
  }

  static AiException _parseErrorResponse(
    int status,
    String body, {
    required bool isTr,
    String? provider,
    String? activeModel,
  }) {
    String detail = '';
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        if (decoded.containsKey('error')) {
          final err = decoded['error'];
          if (err is Map) {
            detail = err['message']?.toString() ?? err.toString();
          } else {
            detail = err.toString();
          }
        }
      }
    } catch (_) {}

    final lower = (detail + body).toLowerCase();
    if (status == 401 || status == 403 || lower.contains('api_key') || lower.contains('invalid api key')) {
      return AiException(
        AiProblem.invalidKey,
        isTr
            ? 'API anahtarı geçersiz veya yetkisiz. Lütfen anahtarınızı kontrol edin.'
            : 'API key is invalid or unauthorized. Please verify your key.',
        statusCode: status,
      );
    }

    if (status == 429 || lower.contains('quota') || lower.contains('rate_limit') || lower.contains('resource_exhausted')) {
      return AiException(
        AiProblem.rateLimitOrQuota,
        isTr
            ? 'API istek kotası doldu veya hız sınırı aşıldı. Lütfen biraz sonra tekrar deneyin.'
            : 'API rate limit or quota exceeded. Please try again later.',
        statusCode: status,
      );
    }

    if (status == 404 || lower.contains('not found') || lower.contains('model')) {
      final rec = provider != null ? defaultModelFor(provider) : 'gemini-1.5-flash';
      final modelStr = activeModel != null ? ' ($activeModel)' : '';
      return AiException(
        AiProblem.modelNotFound,
        isTr
            ? 'Seçilen yapay zekâ modeli bulunamadı$modelStr. Önerilen model: "$rec". Hata: $detail'
            : 'Selected AI model not found$modelStr. Recommended model: "$rec". Error: $detail',
        statusCode: status,
      );
    }

    return AiException(
      AiProblem.serverError,
      isTr
          ? 'Sunucu hatası ($status): ${detail.isNotEmpty ? detail : body}'
          : 'Server error ($status): ${detail.isNotEmpty ? detail : body}',
      statusCode: status,
    );
  }
}
