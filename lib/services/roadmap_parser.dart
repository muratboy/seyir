import 'dart:convert';
import '../data/models.dart';

class RoadmapParser {
  /// Kullanıcının LLM'e göndermek için panoya kopyalayacağı standart prompt şablonu
  static const String promptTemplate = '''Lütfen benim için "[BURAYA KONUYU YAZIN: örn: 3 Ayda Sağlıklı Kilo Verme / KPSS Sınavına Hazırlık / Radyo Tamiri Öğrenme / İngilizce B2 Seviyesi]" konusunda adım adım uygulanabilir bir yol haritası hazırla.

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
      "title": "Adım Başlığı (örn: Radyoyu sök ve lehimleri kontrol et)",
      "description": "Bu adımda ne yapılması gerektiği ve püf noktaları",
      "type": "task",
      "target": null,
      "unit": null
    },
    {
      "order": 2,
      "title": "Günde 30 dk tempolu yürüyüş yap",
      "description": "Hafif tempo yürüyüş",
      "type": "goal",
      "target": 30,
      "unit": "dk"
    }
  ]
}
```

Önemli Kurallar:
- "type": "task" -> Ölçüsüz, tek seferlik tiklenebilir görevler için kullanılır (örneğin: radyoyu tamir etmek, kursa kayıt olmak, kitap satın almak).
- "type": "goal" -> Ölçüsü, miktarı veya süresi olan adımlar için kullanılır (örneğin: 30 dk yürüyüş, 2 L su). "target" ve "unit" alanlarını doldur.
''';

  /// LLM'den gelen serbest metin veya doğrudan JSON metnini parse ederek Roadmap nesnesine dönüştürür.
  static Roadmap? parse(String raw) {
    if (raw.trim().isEmpty) return null;

    String jsonString = raw.trim();

    // 1. Markdown kod bloğu varsa içini ayıkla (```json ... ``` veya ``` ... ```)
    final codeBlockMatch = RegExp(r'```(?:json)?\s*([\s\S]*?)\s*```', caseSensitive: false).firstMatch(jsonString);
    if (codeBlockMatch != null && codeBlockMatch.group(1) != null) {
      jsonString = codeBlockMatch.group(1)!.trim();
    } else {
      // 2. Kod bloğu yoksa ilk { ile son } arasındaki JSON nesnesini bul
      final start = jsonString.indexOf('{');
      final end = jsonString.lastIndexOf('}');
      if (start != -1 && end != -1 && end > start) {
        jsonString = jsonString.substring(start, end + 1).trim();
      }
    }

    try {
      final decoded = jsonDecode(jsonString);
      if (decoded is! Map) return null;

      final map = (decoded['roadmap'] is Map)
          ? Map<String, dynamic>.from(decoded['roadmap'] as Map)
          : Map<String, dynamic>.from(decoded);

      final title = (map['title'] as String?)?.trim() ?? '';
      final rawSteps = map['steps'];

      // En azından başlık veya en az 1 adım olmalı, yoksa geçerli bir harita değildir
      if (title.isEmpty && (rawSteps is! List || rawSteps.isEmpty)) {
        return null;
      }

      final description = (map['description'] as String?)?.trim() ?? '';
      final category = (map['category'] as String?)?.trim() ?? 'Genel';
      final emoji = (map['emoji'] as String?)?.trim() ?? '🗺️';

      final steps = <RoadmapStep>[];

      if (rawSteps is List) {
        for (var i = 0; i < rawSteps.length; i++) {
          final item = rawSteps[i];
          if (item is Map) {
            final stepMap = Map<String, dynamic>.from(item);
            final stepTitle = (stepMap['title'] as String?)?.trim() ?? 'Adım ${i + 1}';
            final stepDesc = (stepMap['description'] as String?)?.trim() ?? '';
            final typeStr = ((stepMap['type'] as String?)?.toLowerCase().trim() == 'goal') ? 'goal' : 'task';
            final targetNum = (stepMap['target'] as num?)?.toDouble();
            final unitStr = (stepMap['unit'] as String?)?.trim();

            steps.add(
              RoadmapStep(
                id: 0,
                roadmapId: 0,
                order: (stepMap['order'] as int?) ?? (i + 1),
                title: stepTitle,
                description: stepDesc,
                type: typeStr,
                target: targetNum,
                unit: unitStr,
                isCompleted: false,
              ),
            );
          }
        }
      }

      // Sıraya göre diz
      steps.sort((a, b) => a.order.compareTo(b.order));
      for (var i = 0; i < steps.length; i++) {
        steps[i].order = i + 1;
      }

      return Roadmap(
        id: 0,
        title: title.isEmpty ? 'Yeni Yol Haritası' : title,
        description: description,
        category: category,
        emoji: emoji.isEmpty ? '🗺️' : emoji,
        status: 'not_started',
        createdAt: DateTime.now().millisecondsSinceEpoch,
        steps: steps,
      );
    } catch (_) {
      return null;
    }
  }
}
