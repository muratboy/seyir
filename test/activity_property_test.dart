import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:takip/data/models.dart';
import 'package:takip/data/store.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:takip/logic/l10n.dart';
import 'package:takip/ui/activity_page.dart';
import 'package:takip/ui/components/goal_edit_dialog.dart';

import 'support/real_db.dart';

void main() {
  useRealDatabase();

  setUpAll(() async {
    await initializeDateFormatting('tr_TR');
    await initializeDateFormatting('en_US');
    Intl.defaultLocale = 'tr_TR';
  });

  setUp(() async {
    store.language = AppLanguage.tr;
    strings.value = const AppStrings(AppLanguage.tr);
    await store.load();
    final d = await store.db;
    await d.delete('activity_properties');
    await d.delete('goal_links');
    await d.delete('goals');
    await d.delete('entries');
    await d.delete('activities');
    await store.load();
  });

  test('ActivityProperty CRUD and association to Activity', () async {
    final act = await store.addActivity('Ayran', emoji: '🥛', category: 'nutrition');

    // 1. Add Volume and Calorie properties
    final volProp = await store.saveActivityProperty(ActivityProperty(
      activityId: act.id,
      name: 'Hacim',
      value: 200,
      unitId: 'ml',
      perQty: 1.0,
    ));

    final calProp = await store.saveActivityProperty(ActivityProperty(
      activityId: act.id,
      name: 'Kalori',
      value: 76,
      unitId: 'kcal',
      perQty: 1.0,
    ));

    expect(volProp.id, isNonZero);
    expect(calProp.id, isNonZero);

    // 2. Query properties
    final props = store.activityProperties(act.id);
    expect(props.length, 2);
    expect(props.map((p) => p.name), containsAll(['Hacim', 'Kalori']));

    // 3. Find property by id
    final found = store.findActivityProperty(calProp.id);
    expect(found?.value, 76.0);

    // 4. Update property
    calProp.value = 80;
    await store.saveActivityProperty(calProp);
    final updated = store.findActivityProperty(calProp.id);
    expect(updated?.value, 80.0);

    // 5. Delete property
    await store.deleteActivityProperty(volProp.id);
    expect(store.activityProperties(act.id).length, 1);
    expect(store.findActivityProperty(volProp.id), isNull);
  });

  test('Multi-property goal contribution: Liquid intake (L) and Calorie goal (kcal)', () async {
    final act = await store.addActivity('Ayran', emoji: '🥛', category: 'nutrition');

    // Ayran has: 200 ml volume, 76 kcal calories per 1 glass (adet)
    final volProp = await store.saveActivityProperty(ActivityProperty(
      activityId: act.id,
      name: 'Hacim',
      value: 200,
      unitId: 'ml',
      perQty: 1.0,
    ));

    final calProp = await store.saveActivityProperty(ActivityProperty(
      activityId: act.id,
      name: 'Kalori',
      value: 76,
      unitId: 'kcal',
      perQty: 1.0,
    ));

    // Goal 1: Liquid Intake (target: 2.0 L, mode: amount, unit: l)
    final liquidGoal = Goal(
      id: 0,
      name: 'Sıvı Alımı',
      mode: 'amount',
      unitId: 'l',
      target: 2.0,
      period: GoalPeriod.day,
      startDate: DateTime.now().millisecondsSinceEpoch,
      createdAt: DateTime.now().millisecondsSinceEpoch,
      links: [GoalLink(activityId: act.id, pct: 100, propertyId: volProp.id)],
    );
    await store.saveGoal(liquidGoal);

    // Goal 2: Calorie Goal (target: 2000 kcal, mode: amount, unit: kcal)
    final calorieGoal = Goal(
      id: 0,
      name: 'Kalori Hedefi',
      mode: 'amount',
      unitId: 'kcal',
      target: 2000,
      period: GoalPeriod.day,
      startDate: DateTime.now().millisecondsSinceEpoch,
      createdAt: DateTime.now().millisecondsSinceEpoch,
      links: [GoalLink(activityId: act.id, pct: 100, propertyId: calProp.id)],
    );
    await store.saveGoal(calorieGoal);

    final now = DateTime.now();

    // Case 1: Log 1 adet Ayran (without explicit measure value)
    final entry1 = Entry(
      id: 1,
      activityId: act.id,
      ts: now.millisecondsSinceEpoch,
      qty: 1,
    );

    final liquidContrib1 = store.contribution(liquidGoal, entry1, 100, link: liquidGoal.links.first);
    final calContrib1 = store.contribution(calorieGoal, entry1, 100, link: calorieGoal.links.first);

    // 1 adet Ayran = 200 ml = 0.2 L
    expect(liquidContrib1, closeTo(0.2, 0.001));
    // 1 adet Ayran = 76 kcal
    expect(calContrib1, closeTo(76.0, 0.001));

    // Case 2: Log 2 adet Ayran
    final entry2 = Entry(
      id: 2,
      activityId: act.id,
      ts: now.millisecondsSinceEpoch,
      qty: 2,
    );

    final liquidContrib2 = store.contribution(liquidGoal, entry2, 100, link: liquidGoal.links.first);
    final calContrib2 = store.contribution(calorieGoal, entry2, 100, link: calorieGoal.links.first);

    expect(liquidContrib2, closeTo(0.4, 0.001));
    expect(calContrib2, closeTo(152.0, 0.001));

    // Case 3: Log with explicit volume: 500 ml Ayran (e.value = 500, e.unitId = 'ml')
    final entry3 = Entry(
      id: 3,
      activityId: act.id,
      ts: now.millisecondsSinceEpoch,
      qty: 1,
      value: 500,
      unitId: 'ml',
    );

    final liquidContrib3 = store.contribution(liquidGoal, entry3, 100, link: liquidGoal.links.first);
    final calContrib3 = store.contribution(calorieGoal, entry3, 100, link: calorieGoal.links.first);

    // 500 ml in Litres = 0.5 L
    expect(liquidContrib3, closeTo(0.5, 0.001));
    // Scaled calories: 500 ml / 200 ml = 2.5x -> 2.5 * 76 = 190 kcal
    expect(calContrib3, closeTo(190.0, 0.001));

    // Case 4: Log with explicit volume: 1 Litre Ayran (e.value = 1.0, e.unitId = 'l')
    final entry4 = Entry(
      id: 4,
      activityId: act.id,
      ts: now.millisecondsSinceEpoch,
      qty: 1,
      value: 1.0,
      unitId: 'l',
    );

    final liquidContrib4 = store.contribution(liquidGoal, entry4, 100, link: liquidGoal.links.first);
    final calContrib4 = store.contribution(calorieGoal, entry4, 100, link: calorieGoal.links.first);

    // 1 L in Litres = 1.0 L
    expect(liquidContrib4, closeTo(1.0, 0.001));
    // Scaled calories: 1000 ml / 200 ml = 5.0x -> 5.0 * 76 = 380 kcal
    expect(calContrib4, closeTo(380.0, 0.001));
  });

  test('Auto-matching dimension when propertyId is null in GoalLink', () async {
    final act = await store.addActivity('Ayran', emoji: '🥛', category: 'nutrition');

    await store.saveActivityProperty(ActivityProperty(
      activityId: act.id,
      name: 'Hacim',
      value: 200,
      unitId: 'ml',
      perQty: 1.0,
    ));

    await store.saveActivityProperty(ActivityProperty(
      activityId: act.id,
      name: 'Kalori',
      value: 76,
      unitId: 'kcal',
      perQty: 1.0,
    ));

    // Goal without explicit propertyId (propertyId: null)
    final calGoal = Goal(
      id: 0,
      name: 'Kalori',
      mode: 'amount',
      unitId: 'kcal',
      target: 2000,
      period: GoalPeriod.day,
      startDate: DateTime.now().millisecondsSinceEpoch,
      createdAt: DateTime.now().millisecondsSinceEpoch,
      links: [GoalLink(activityId: act.id, pct: 100, propertyId: null)],
    );

    final entry = Entry(
      id: 1,
      activityId: act.id,
      ts: DateTime.now().millisecondsSinceEpoch,
      qty: 2,
    );

    // Auto-matching finds energy property (76 kcal) -> 2 * 76 = 152 kcal
    final contrib = store.contribution(calGoal, entry, 100, link: calGoal.links.first);
    expect(contrib, closeTo(152.0, 0.001));
  });

  test('Activity deletion removes properties and cleans up goal_links propertyId', () async {
    final act = await store.addActivity('Ayran', emoji: '🥛');
    final p = await store.saveActivityProperty(ActivityProperty(
      activityId: act.id,
      name: 'Kalori',
      value: 76,
      unitId: 'kcal',
    ));

    final g = Goal(
      id: 0,
      name: 'Test Goal',
      mode: 'amount',
      unitId: 'kcal',
      target: 500,
      period: GoalPeriod.day,
      startDate: 0,
      createdAt: 0,
      links: [GoalLink(activityId: act.id, propertyId: p.id)],
    );
    await store.saveGoal(g);

    expect(store.activityProperties(act.id).length, 1);
    await store.deleteActivity(act.id);
    expect(store.activityProperties(act.id), isEmpty);
    expect(store.findActivityProperty(p.id), isNull);
  });

  test('JSON backup and restore validates and restores activity_properties', () async {
    final act = await store.addActivity('Ayran', emoji: '🥛');
    await store.saveActivityProperty(ActivityProperty(
      activityId: act.id,
      name: 'Kalori',
      value: 76,
      unitId: 'kcal',
    ));

    final jsonStr = await store.exportJson();
    final decoded = jsonDecode(jsonStr) as Map<String, dynamic>;
    expect(decoded.containsKey('activity_properties'), isTrue);
    final propList = decoded['activity_properties'] as List;
    expect(propList.length, 1);
    expect(propList.first['name'], 'Kalori');
    expect((propList.first['value'] as num).toDouble(), 76.0);

    // Clear and restore
    final d = await store.db;
    await d.delete('activity_properties');
    await store.load();
    expect(store.activityProperties(act.id), isEmpty);

    await store.importJson(jsonStr);
    expect(store.activityProperties(act.id).length, 1);
    expect(store.activityProperties(act.id).first.name, 'Kalori');
    expect(store.activityProperties(act.id).first.value, 76.0);
  });

  testWidgets('ActivityPage shows properties card and opens add property dialog', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    late Activity act;
    await tester.runAsync(() async {
      act = await store.addActivity('Ayran', emoji: '🥛');
      await store.saveActivityProperty(ActivityProperty(
        activityId: act.id,
        name: 'Kalori',
        value: 76,
        unitId: 'kcal',
      ));
    });

    await tester.pumpWidget(MaterialApp(
      home: ActivityPage(activity: act),
    ));
    await tester.pumpAndSettle();

    await tester.drag(find.byType(Scrollable).first, const Offset(0, -300));
    await tester.pumpAndSettle();

    expect(find.text('Özellikler & Metrikler'), findsOneWidget);
    expect(find.text('Kalori'), findsOneWidget);
    expect(find.textContaining('76 kcal'), findsOneWidget);

    // Tap "Özellik Ekle"
    await tester.tap(find.text('Özellik Ekle'));
    await tester.pumpAndSettle();

    expect(find.text('Yeni Özellik Ekle'), findsOneWidget);
    expect(find.text('Hızlı Şablonlar:'), findsOneWidget);
    expect(find.text('Sıvı / Hacim'), findsOneWidget);

    // Cancel dialog
    await tester.tap(find.text(strings.value.cancel));
    await tester.pumpAndSettle();
    expect(find.text('Yeni Özellik Ekle'), findsNothing);
  });

  testWidgets('GoalEditDialog shows property dropdown for activities with properties', (tester) async {
    late Activity act;
    late ActivityProperty volProp;
    await tester.runAsync(() async {
      act = await store.addActivity('Ayran', emoji: '🥛');
      volProp = await store.saveActivityProperty(ActivityProperty(
        activityId: act.id,
        name: 'Hacim',
        value: 200,
        unitId: 'ml',
      ));
    });

    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) {
        return Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () {
                final existing = Goal(
                  id: 1,
                  name: 'Sıvı Hedefi',
                  mode: 'amount',
                  unitId: 'l',
                  target: 2.0,
                  period: GoalPeriod.day,
                  startDate: 0,
                  createdAt: 0,
                  links: [GoalLink(activityId: act.id, pct: 100, propertyId: volProp.id)],
                );
                GoalEditDialog.show(context, existing: existing);
              },
              child: const Text('Open'),
            ),
          ),
        );
      }),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('Ölçü Alınacak Özellik:'), findsOneWidget);
    expect(find.textContaining('Hacim: 200 ml'), findsOneWidget);

    // Cancel
    await tester.tap(find.text(strings.value.cancel));
    await tester.pumpAndSettle();
  });
}
