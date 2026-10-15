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
      "title": "Toplam 600 dk tempolu yürüyüş yap",
      "description": "Günde yarım saat, hafif tempoda",
      "type": "goal",
      "target": 600,
      "unit": "dk"
    }
  ]
}
```

Önemli Kurallar:
- "type": "task" -> Ölçüsüz, tek seferlik tiklenebilir görevler için kullanılır (örneğin: radyoyu tamir etmek, kursa kayıt olmak, kitap satın almak).
- "type": "goal" -> Ölçüsü, miktarı veya süresi olan adımlar için kullanılır (örneğin: toplam 600 dk yürüyüş, 12 bölüm, 50 km). "target" ve "unit" alanlarını doldur.
- "target", adım boyunca TOPLAMDA ulaşılacak miktardır; günlük miktar değildir. Günlük bir alışkanlığı toplamına çevirerek yaz (günde 30 dk, 20 gün -> 600 dk).
''';

  /// [promptTemplate] şablonunun İngilizce arayüzde kopyalanan karşılığı.
  static const String promptTemplateEn = '''Please prepare a step-by-step, actionable roadmap for me on "[WRITE THE TOPIC HERE: e.g. Losing Weight Healthily in 3 Months / Preparing for an Exam / Learning to Repair a Radio / English at B2 Level]".

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
      "title": "Step title (e.g. Open the radio and check the solder joints)",
      "description": "What to do in this step and what to watch out for",
      "type": "task",
      "target": null,
      "unit": null
    },
    {
      "order": 2,
      "title": "Walk briskly for 600 minutes in total",
      "description": "Half an hour a day at an easy pace",
      "type": "goal",
      "target": 600,
      "unit": "min"
    }
  ]
}
```

Important rules:
- "type": "task" -> for one-off tasks without a measure that are simply ticked off (e.g. repairing the radio, enrolling in a course, buying a book).
- "type": "goal" -> for steps with an amount, a quantity or a duration (e.g. 600 minutes of walking in total, 12 episodes, 50 km). Fill in "target" and "unit".
- "target" is the TOTAL to reach over the whole step, not a daily amount. Turn a daily habit into its total (30 minutes a day for 20 days -> 600 min).
''';

  static String promptFor({required bool isTr}) => isTr ? promptTemplate : promptTemplateEn;

  /// LLM'den gelen serbest metin veya doğrudan JSON metnini parse ederek Roadmap nesnesine dönüştürür.
  /// [isTr] yalnızca eksik başlıkların yerine konan adların dilini belirler.
  static Roadmap? parse(String raw, {bool isTr = true}) {
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

      final title = _text(map['title']) ?? '';
      final rawSteps = map['steps'];

      // En azından başlık veya en az 1 adım olmalı, yoksa geçerli bir harita değildir
      if (title.isEmpty && (rawSteps is! List || rawSteps.isEmpty)) {
        return null;
      }

      final description = _text(map['description']) ?? '';
      final category = _text(map['category']) ?? (isTr ? 'Genel' : 'General');
      final emoji = _text(map['emoji']) ?? '🗺️';

      final steps = <RoadmapStep>[];

      if (rawSteps is List) {
        for (var i = 0; i < rawSteps.length; i++) {
          final item = rawSteps[i];
          if (item is Map) {
            final stepMap = Map<String, dynamic>.from(item);
            // Alanlar hoşgörüyle okunur: LLM yanıtları sayıları sık sık tırnak içinde verir ("target": "30")
            // ve tek bir beklenmedik tür bütün haritanın reddedilmesine yol açmamalıdır.
            final stepTitle = _text(stepMap['title']) ?? (isTr ? 'Adım ${i + 1}' : 'Step ${i + 1}');
            final stepDesc = _text(stepMap['description']) ?? '';
            final typeStr = (_text(stepMap['type'])?.toLowerCase() == 'goal') ? 'goal' : 'task';
            final targetNum = _number(stepMap['target']);
            final unitStr = _text(stepMap['unit']);

            steps.add(
              RoadmapStep(
                id: 0,
                roadmapId: 0,
                order: _number(stepMap['order'])?.round() ?? (i + 1),
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
        title: title.isEmpty ? (isTr ? 'Yeni Yol Haritası' : 'New Roadmap') : title,
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

  /// Yol haritasının paylaşılacak hâli, [parse]'ın okuduğu biçimde: yalnızca plan (başlık, açıklama, kategori,
  /// simge ve adımlar). İlerleme, adımlara bağlanan aktiviteler ve tarihler kişiye özeldir; paylaşılmaz.
  static Map<String, Object?> toJson(Roadmap r) {
    final steps = [...r.steps]..sort((a, b) => a.order.compareTo(b.order));
    // 600.0 değil 600: metin, yapay zekâ kalıbındaki gibi okunaklı kalsın.
    Object? number(double? v) => v == null ? null : (v == v.roundToDouble() ? v.toInt() : v);
    return {
      'title': r.title,
      'description': r.description,
      'category': r.category,
      'emoji': r.emoji,
      'steps': [
        for (var i = 0; i < steps.length; i++)
          {
            'order': i + 1,
            'title': steps[i].title,
            'description': steps[i].description,
            'type': steps[i].type,
            'target': number(steps[i].target),
            'unit': steps[i].unit,
          },
      ],
    };
  }

  /// Bir mesaja ya da bir sitedeki sayfaya konacak paylaşım metni: başlık, nasıl ekleneceği ve kod bloğu
  /// içinde [toJson]. Hem "Yapay Zekâ Kalıbıyla İçe Aktar"a yapıştırıldığında hem de bir bağlantıdan
  /// indirildiğinde [parse] onu okur.
  static String shareText(Roadmap r, {required bool isTr}) {
    final json = const JsonEncoder.withIndent('  ').convert(toJson(r));
    final how = isTr
        ? "Takip'te eklemek için: Yol Haritası Ekle › Yapay Zekâ Kalıbıyla İçe Aktar › Yapıştır"
        : 'To add it in Takip: Add Roadmap › Import with AI Prompt › Paste';
    return '${r.emoji} ${r.title}\n$how\n\n```json\n$json\n```\n';
  }

  /// Bir JSON değerini metne çevirir; boşsa ya da yoksa null.
  static String? _text(Object? value) {
    if (value == null) return null;
    final text = '$value'.trim();
    return text.isEmpty ? null : text;
  }

  /// Bir JSON değerini sayıya çevirir ("30", "2,5" gibi metinler dahil); çevrilemiyorsa null.
  static double? _number(Object? value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value.trim().replaceAll(',', '.'));
    return null;
  }
}
