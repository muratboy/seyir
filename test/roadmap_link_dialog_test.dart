import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:takip/data/store.dart';
import 'package:takip/services/roadmap_link_service.dart';
import 'package:takip/ui/components/roadmap_link_dialog.dart';
import 'package:takip/ui/tabs/roadmaps_tab.dart';

import 'support/fonts.dart';
import 'support/real_db.dart';

const _shared = '''```json
{"title": "Paylaşılan Plan", "category": "Dil", "emoji": "🔗", "steps": [
  {"title": "Kaynak seç"},
  {"title": "Kelime çalış", "type": "goal", "target": 300, "unit": "dk"}]}
```''';

/// Opens the dialog the way the add-roadmap sheet does, with [fetcher] in place of the internet.
Future<void> _open(WidgetTester tester, RoadmapLinkFetcher fetcher) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => Center(
          child: TextButton(
            onPressed: () => RoadmapLinkDialog.show(context, fetcher: fetcher),
            child: const Text('aç'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('aç'));
  await tester.pumpAndSettle();
}

Future<void> _fetch(WidgetTester tester, String link) async {
  await tester.enterText(find.byKey(const Key('roadmap-link-field')), link);
  await tester.pump();
  await tester.tap(find.text('Getir'));
  await tester.pump();
  await tester.pump();
}

/// Lets real database work started by a tap finish.
Future<void> _settle(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 50 && !done(); i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  useRealDatabase();
  setUpAll(loadRealFont);

  testWidgets('a shared link is fetched and previewed, and saved only when confirmed', (tester) async {
    await tester.runAsync(() => store.load());
    final asked = <Uri>[];
    await _open(tester, (uri) async {
      asked.add(uri);
      return _shared;
    });

    final fetchButton = find.ancestor(of: find.text('Getir'), matching: find.byWidgetPredicate((w) => w is FilledButton));
    expect(tester.widget<FilledButton>(fetchButton).enabled, isFalse, reason: 'there is nothing to fetch yet');

    await _fetch(tester, 'Bak: github.com/ali/planlar/blob/main/plan.json');
    expect(asked.single.toString(), 'https://raw.githubusercontent.com/ali/planlar/main/plan.json');
    expect(find.text('Paylaşılan Plan'), findsOneWidget);
    expect(find.text('Dil • 2 Adım'), findsOneWidget);
    expect(find.text('300 dk'), findsOneWidget);
    expect(find.text('Kaynak: raw.githubusercontent.com'), findsOneWidget, reason: 'the user sees where it came from');
    expect(store.roadmaps, isEmpty, reason: 'nothing is saved before it is confirmed');

    // Going back keeps the link for another try.
    await tester.tap(find.text('Bağlantıyı Değiştir'));
    await tester.pump();
    expect(find.text('Bak: github.com/ali/planlar/blob/main/plan.json'), findsOneWidget);
    await tester.tap(find.text('Getir'));
    await tester.pump();
    await tester.pump();

    await tester.tap(find.text('Yol Haritasını Yükle'));
    await _settle(tester, () => store.roadmaps.isNotEmpty);
    await tester.pumpAndSettle();
    expect(store.roadmaps.single.title, 'Paylaşılan Plan');
    expect(store.roadmaps.single.steps.length, 2);
    expect(find.byType(RoadmapLinkDialog), findsNothing);
    expect(find.text('🎉 "Paylaşılan Plan" yol haritalarına eklendi!'), findsOneWidget);
  });

  testWidgets('problems are explained in the dialog, and a bad link is not even fetched', (tester) async {
    var calls = 0;
    var answer = '<!doctype html><html><body>Giriş yap</body></html>';
    Object? failure;
    await _open(tester, (uri) async {
      calls++;
      if (failure != null) throw failure;
      return answer;
    });
    String error() => tester.widget<Text>(find.byKey(const Key('roadmap-link-error'))).data!;

    await _fetch(tester, 'http://example.com/plan.json');
    expect(error(), contains('yalnızca https://'));
    await _fetch(tester, 'https://192.168.1.10/plan.json');
    expect(error(), contains('kendi cihazında ya da ağında'));
    await _fetch(tester, 'yol haritam');
    expect(error(), contains('internet adresine benzemiyor'));
    expect(calls, 0);

    await _fetch(tester, 'https://example.com/sayfa');
    expect(error(), contains('yol haritası biçiminde değil'), reason: 'a web page instead of the roadmap text');

    failure = const RoadmapLinkException(RoadmapLinkProblem.status, status: 404);
    await _fetch(tester, 'https://example.com/plan.json');
    expect(error(), contains('hata 404'));

    failure = const RoadmapLinkException(RoadmapLinkProblem.network);
    await _fetch(tester, 'https://example.com/plan.json');
    expect(error(), contains('İnternet bağlantını'));

    failure = null;
    answer = '{"title": "Uzun", "steps": [${List.filled(RoadmapLinkService.maxSteps + 1, '{"title": "Adım"}').join(',')}]}';
    await _fetch(tester, 'https://example.com/uzun.json');
    expect(error(), contains('çok uzun'));
    expect(calls, 4);
  });

  testWidgets('the add sheet offers the link and both fit a small phone with large text', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: TextButton(onPressed: () => RoadmapsTab.showCreateOptions(context), child: const Text('ekle')),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('ekle'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Bağlantıdan Ekle'), findsOneWidget);

    await tester.tap(find.text('Bağlantıdan Ekle'));
    await tester.pumpAndSettle();
    expect(find.byType(RoadmapLinkDialog), findsOneWidget);
    expect(tester.takeException(), isNull);

    // With the keyboard open the address field and its note scroll instead of overflowing.
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    tester.view.viewInsets = FakeViewPadding.zero;
    await tester.pumpAndSettle();
  });
}
