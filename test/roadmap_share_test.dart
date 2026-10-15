import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:takip/data/models.dart';
import 'package:takip/data/store.dart';
import 'package:takip/services/roadmap_parser.dart';
import 'package:takip/ui/roadmap_detail_page.dart';

import 'support/real_db.dart';

/// A journey with progress of its own: ticked steps, a linked activity, a start date.
Roadmap _journey() => Roadmap(
      id: 7,
      title: '3 Ayda İngilizce',
      description: 'Günlük konuşma düzeyi',
      category: 'Dil',
      emoji: '🗣️',
      status: 'active',
      startedAt: 1700000000000,
      steps: [
        RoadmapStep(id: 2, order: 2, title: 'Kelime çalış', description: 'Cümle içinde', type: 'goal', target: 600, unit: 'dk',
            linkedActivityId: 14, isCompleted: true, autoCompleted: true, completedAt: 1700000500000),
        RoadmapStep(id: 1, order: 1, title: 'Seviyeni ölç', isCompleted: true),
        RoadmapStep(id: 3, order: 3, title: 'Dizi izle', type: 'goal', target: 12.5, unit: 'bölüm'),
      ],
    );

void main() {
  test('a shared roadmap reads back as the same plan, without anyone\'s progress', () {
    final text = RoadmapParser.shareText(_journey(), isTr: true);
    expect(text, startsWith('🗣️ 3 Ayda İngilizce\n'));
    expect(text, contains('Yapay Zekâ Kalıbıyla İçe Aktar'));
    for (final private in ['is_completed', 'linked', 'auto', 'completed_at', 'started', '14', '1700000']) {
      expect(text, isNot(contains(private)), reason: private);
    }
    expect(text, contains('"target": 600,'), reason: 'whole numbers are written without ".0"');

    final back = RoadmapParser.parse(text)!;
    expect(back.title, '3 Ayda İngilizce');
    expect(back.description, 'Günlük konuşma düzeyi');
    expect(back.category, 'Dil');
    expect(back.emoji, '🗣️');
    expect(back.status, 'not_started');
    expect([for (final s in back.steps) (s.order, s.title, s.type, s.target, s.unit)], [
      (1, 'Seviyeni ölç', 'task', null, null),
      (2, 'Kelime çalış', 'goal', 600.0, 'dk'),
      (3, 'Dizi izle', 'goal', 12.5, 'bölüm'),
    ]);
    expect(back.steps[1].description, 'Cümle içinde');
    expect(back.steps.any((s) => s.isCompleted || s.linkedActivityId != null), isFalse);
  });

  group('Sharing from the roadmap page', () {
    useRealDatabase();

    testWidgets('copies a text that the import reads back, or hands it to the share sheet', (tester) async {
      final roadmap = await tester.runAsync(() async {
        await store.load();
        return store.createRoadmap(_journey()..id = 0);
      });
      String? copied;
      String? shared;
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String?;
        return null;
      });
      messenger.setMockMethodCallHandler(const MethodChannel('dev.fluttercommunity.plus/share'), (call) async {
        shared = (call.arguments as Map)['text'] as String?;
        return 'dev.fluttercommunity.plus/share/unavailable';
      });
      addTearDown(() {
        messenger.setMockMethodCallHandler(SystemChannels.platform, null);
        messenger.setMockMethodCallHandler(const MethodChannel('dev.fluttercommunity.plus/share'), null);
      });

      await tester.pumpWidget(MaterialApp(home: RoadmapDetailPage(roadmapId: roadmap!.id)));
      await tester.pump();
      await tester.tap(find.byTooltip('Paylaş'));
      await tester.pumpAndSettle();
      expect(find.text('Yol Haritasını Paylaş'), findsOneWidget);
      expect(find.textContaining('İlerlemen ve adımlara bağladığın aktiviteler sende kalır'), findsOneWidget);
      expect(find.textContaining('Bağlantıdan Ekle ile ekler'), findsOneWidget);

      await tester.tap(find.text('Metni Kopyala'));
      await tester.pumpAndSettle();
      expect(find.text('Yol haritası metni kopyalandı'), findsOneWidget);
      // In the order the page shows them (saving numbered them as they were listed).
      final shown = [...roadmap.steps]..sort((a, b) => a.order.compareTo(b.order));
      expect(RoadmapParser.parse(copied!)!.steps.map((s) => s.title), shown.map((s) => s.title));

      await tester.tap(find.byTooltip('Paylaş'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Uygulamayla Paylaş'));
      await tester.pumpAndSettle();
      expect(shared, copied, reason: 'the same text either way');
      expect(find.text('Yol Haritasını Paylaş'), findsNothing);
    });
  });
}
