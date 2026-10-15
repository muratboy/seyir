import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:takip/data/models.dart';
import 'package:takip/data/store.dart';
import 'package:takip/services/roadmap_parser.dart';
import 'package:takip/ui/components/roadmap_step_progress.dart';
import 'package:takip/ui/goals_page.dart';
import 'package:takip/ui/roadmap_detail_page.dart';
import 'package:takip/ui/today_page.dart';

import 'support/real_db.dart';

/// Runs a store call and lets the widgets react to it. Database I/O is real: a write started by a tap only
/// finishes while real time passes, so real time and frames alternate for a moment.
Future<T> act<T>(WidgetTester tester, Future<T> Function() call) async {
  final result = await tester.runAsync(call);
  for (var i = 0; i < 8; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 50));
  }
  return result as T;
}

Roadmap roadmapNamed(String title) => RoadmapParser.parse('''{"title": "$title", "description": "", "category": "Test",
  "emoji": "🧭", "steps": [{"title": "İlk adım"}, {"title": "İkinci adım"}]}''')!;

void main() {
  useRealDatabase();

  setUpAll(() async {
    await initializeDateFormatting('tr_TR');
    Intl.defaultLocale = 'tr_TR';
  });

  // The pages embed these lists as constants, so a rebuild of the page does not rebuild them: each has to
  // follow the store on its own.
  testWidgets('the roadmap list follows roadmaps being added and deleted', (tester) async {
    await tester.runAsync(() => store.load());
    await tester.pumpWidget(const MaterialApp(home: GoalsPage()));
    await tester.pump();
    await tester.tap(find.text('Yol Haritası'));
    await tester.pump();
    expect(find.text('Henüz Bir Yol Haritası Yok'), findsOneWidget);

    final first = await act(tester, () => store.createRoadmap(roadmapNamed('Dağ yürüyüşü')));
    expect(find.text('Dağ yürüyüşü'), findsOneWidget, reason: 'a loaded roadmap appears without leaving the tab');
    expect(find.text('Henüz Bir Yol Haritası Yok'), findsNothing);

    await act(tester, () => store.createRoadmap(roadmapNamed('Bisiklet turu')));
    expect(find.text('Bisiklet turu'), findsOneWidget);

    await act(tester, () => store.deleteRoadmap(first.id));
    expect(find.text('Dağ yürüyüşü'), findsNothing, reason: 'a deleted roadmap disappears');
    expect(find.text('Bisiklet turu'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the habit list follows habits being added and removed', (tester) async {
    final yoga = await tester.runAsync(() async {
      await store.load();
      return store.addActivity('Yoga', emoji: '🧘');
    });
    await tester.pumpWidget(const MaterialApp(home: GoalsPage()));
    await tester.pump();
    await tester.tap(find.text('Zinciri Kırma'));
    await tester.pump();
    expect(find.text('Yoga'), findsNothing);

    await act(tester, () => store.setActivityHabit(yoga!.id, true));
    expect(find.text('Yoga'), findsWidgets, reason: 'a new habit appears without leaving the tab');

    await act(tester, () => store.setActivityHabit(yoga!.id, false));
    expect(find.text('Yoga'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the arrow of a Today section turns when the section is closed and opened', (tester) async {
    await tester.runAsync(() async {
      await store.load();
      final roadmap = await store.createRoadmap(roadmapNamed('Dağ yürüyüşü'));
      await store.setRoadmapStatus(roadmap.id, 'active');
    });
    await tester.pumpWidget(MaterialApp(home: TodayPage(focusRequest: ValueNotifier<int>(0))));
    await tester.pump();

    expect(find.byTooltip('Gizle'), findsOneWidget);
    expect(find.text('İlk adım'), findsOneWidget);

    await tester.tap(find.byTooltip('Gizle'));
    await act(tester, () async {});
    expect(find.text('İlk adım'), findsNothing, reason: 'the section is closed');
    expect(find.byTooltip('Göster'), findsOneWidget, reason: 'and its button now offers to open it');
    expect(find.byIcon(Icons.expand_more), findsOneWidget);

    await tester.tap(find.byTooltip('Göster'));
    await act(tester, () async {});
    expect(find.text('İlk adım'), findsOneWidget);
    expect(find.byTooltip('Gizle'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  group('Steps linked to an activity', () {
    late Activity kelime;
    late Roadmap roadmap;

    /// A started journey: a measured step linked to "Kelime", a plain task linked to it too, a free task.
    Future<void> seed() async {
      await store.load();
      kelime = await store.addActivity('Kelime', emoji: '🔤');
      roadmap = await store.createRoadmap(Roadmap(title: 'İngilizce', steps: [
        RoadmapStep(title: 'Kelime çalış', type: 'goal', target: 30, unit: 'dk'),
        RoadmapStep(title: 'İlk tekrar'),
        RoadmapStep(title: 'Kurs seç'),
      ]));
      await store.setRoadmapStepActivity(roadmap.steps[0].id, kelime.id);
      await store.setRoadmapStepActivity(roadmap.steps[1].id, kelime.id);
    }

    Future<void> study(double minutes) =>
        store.addEntry(kelime.id, measureId: store.measures.firstWhere((m) => m.name == 'Dakika').id, qty: minutes);

    testWidgets('the Today panel shows how far the next step has come and moves on when it is reached',
        (tester) async {
      await tester.runAsync(() async {
        await seed();
        await store.setRoadmapStatus(roadmap.id, 'active');
      });
      await tester.pumpWidget(MaterialApp(home: TodayPage(focusRequest: ValueNotifier<int>(0))));
      await tester.pump();
      expect(find.text('Kelime çalış'), findsOneWidget);
      expect(find.text('0 / 30 dk'), findsOneWidget);

      await act(tester, () => study(10));
      expect(find.text('10 / 30 dk'), findsOneWidget);

      // The entry that reaches the target ticks the step; the task linked to the same activity is done as
      // well, so the panel moves on to the first step that is still open.
      await act(tester, () => study(20));
      expect(find.text('Kelime çalış'), findsNothing);
      expect(find.text('Kurs seç'), findsOneWidget);
      expect(roadmap.steps.map((s) => s.isCompleted), [true, true, false]);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('the roadmap page shows the progress of every linked step', (tester) async {
      await tester.runAsync(seed);
      await tester.pumpWidget(MaterialApp(home: RoadmapDetailPage(roadmapId: roadmap.id)));
      await tester.pump();

      // Nothing counts before the journey starts, and the page says so.
      expect(find.text('Yolculuk başlayınca aktivitenin kayıtları sayılır'), findsNWidgets(2));

      await act(tester, () => store.setRoadmapStatus(roadmap.id, 'active'));
      expect(find.text('0 / 30 dk'), findsOneWidget);
      expect(find.text('Aktivite kaydedilince tamamlanır'), findsOneWidget);

      await act(tester, () => study(12));
      expect(find.text('12 / 30 dk'), findsOneWidget);
      expect(find.text('Aktivite kaydedildi'), findsOneWidget, reason: 'the task needed the activity once');
      expect(roadmap.steps[1].isCompleted, isTrue);
      expect(roadmap.steps[0].isCompleted, isFalse);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a step the user reopened says why it is still open, and the line fits a narrow column',
        (tester) async {
      await tester.runAsync(() async {
        await seed();
        await store.setRoadmapStatus(roadmap.id, 'active');
        await study(30);
        await store.toggleRoadmapStep(roadmap.steps[0].id, completed: false);
        await store.toggleRoadmapStep(roadmap.steps[1].id, completed: false);
      });
      const note = 'Adımı sen açık bıraktın; işaretleyince tamamlanır';

      for (final width in [72.0, 300.0]) {
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: width,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    StepProgressLine(roadmap: roadmap, step: roadmap.steps[0]),
                    StepProgressLine(roadmap: roadmap, step: roadmap.steps[1]),
                  ],
                ),
              ),
            ),
          ),
        ));
        expect(tester.takeException(), isNull, reason: 'at $width dp');
        expect(find.text('30 / 30 dk'), findsOneWidget);
        expect(find.text(note), findsNWidgets(2), reason: 'the measured step and the task');
      }
      await tester.pumpWidget(const SizedBox());
    });
  });
}
