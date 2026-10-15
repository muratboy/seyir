import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:takip/logic/l10n.dart';
import 'package:takip/services/roadmap_parser.dart';
import 'package:takip/ui/components/roadmap_import_dialog.dart';

import 'support/fonts.dart';

/// Names of products, and the jargon for them, that the app must not show: the template works with any
/// assistant, and the texts say so in plain words.
final _specific = RegExp('ChatGPT|Claude|Gemini|LLM', caseSensitive: false);

void main() {
  // The test font is far wider than real text; with it the fixed parts of the dialog leave no room for
  // the preview.
  setUpAll(loadRealFont);
  tearDown(() => strings.value = const AppStrings(AppLanguage.tr));

  for (final lang in AppLanguage.values) {
    testWidgets('the roadmap import speaks of an AI assistant, not of products (${lang.name})', (tester) async {
      strings.value = AppStrings(lang);
      // The clipboard lives on the platform side.
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String?;
        return null;
      });
      addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));

      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: RoadmapImportDialog())));
      await tester.pump();
      final tr = lang == AppLanguage.tr;

      expect(find.textContaining(_specific), findsNothing);
      expect(find.textContaining(tr ? 'yapay zekâ asistanına' : 'AI assistant'), findsOneWidget);

      await tester.tap(find.text(tr ? 'Kalıbı Kopyala' : 'Copy Template'));
      await tester.pump();
      expect(find.textContaining(_specific), findsNothing, reason: 'the confirmation after copying');
      expect(find.byType(SnackBar), findsOneWidget);
      expect(copied, RoadmapParser.promptFor(isTr: tr));
      expect(copied, isNot(matches(_specific)), reason: 'the template itself names nobody either');

      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('the example is a roadmap the app can read, with tasks and measured goals (${lang.name})',
        (tester) async {
      strings.value = AppStrings(lang);
      tester.view.physicalSize = const Size(412, 892);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final tr = lang == AppLanguage.tr;

      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: RoadmapImportDialog())));
      await tester.pump();
      await tester.tap(find.text(tr ? 'Örnek' : 'Example'));
      await tester.pump();

      // The preview replaces the text box; nothing is saved until it is confirmed.
      expect(find.textContaining(tr ? 'Geçerli bir yol haritası' : 'Could not parse'), findsNothing);
      expect(find.text(tr ? '3 Ayda İngilizce Konuşma Pratiği' : 'Conversational Spanish in 3 Months'),
          findsOneWidget);
      expect(find.textContaining(tr ? '6 Adım' : '6 Steps'), findsOneWidget);
      expect(find.text(tr ? 'Görev' : 'Task'), findsWidgets);
      expect(find.text(tr ? '600 dk' : '600 min'), findsOneWidget, reason: 'amounts are written like elsewhere');
      expect(find.text(tr ? 'Yol Haritasını Yükle' : 'Save Roadmap'), findsOneWidget);
      expect(tester.takeException(), isNull);
      // On a phone of ordinary width the two buttons share a line, which leaves the preview more room.
      final edit = tester.getCenter(find.text(tr ? 'Metni Düzenle' : 'Edit Text'));
      final save = tester.getCenter(find.text(tr ? 'Yol Haritasını Yükle' : 'Save Roadmap'));
      expect(edit.dy, closeTo(save.dy, 1));
      expect(edit.dx, lessThan(save.dx));

      // The rest of the steps is reached by scrolling the preview.
      final preview = find.byType(Scrollable).last;
      await tester.scrollUntilVisible(find.text(tr ? '12 bölüm' : '12 episodes'), 120, scrollable: preview);
      await tester.scrollUntilVisible(find.text(tr ? '240 dk' : '240 min'), 120, scrollable: preview);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('the dialog fits a small phone, also while the keyboard is open and in the preview', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: RoadmapImportDialog())));
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);

    // The keyboard takes almost half of the screen; the answer box keeps a usable height and the part
    // above it scrolls.
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(TextField)).height, greaterThanOrEqualTo(150));

    tester.view.viewInsets = FakeViewPadding.zero;
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Örnek'));
    await tester.pump();
    expect(find.text('Yol Haritasını Yükle'), findsOneWidget);
    expect(tester.takeException(), isNull, reason: 'the two buttons do not fit side by side at this width');
  });
}
