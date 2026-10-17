import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:takip/data/models.dart';
import 'package:takip/data/store.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:takip/logic/l10n.dart';
import 'package:takip/ui/manage_page.dart';

import 'support/real_db.dart';

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  useRealDatabase();

  setUpAll(() async {
    await initializeDateFormatting('tr_TR');
    await initializeDateFormatting('en_US');
    Intl.defaultLocale = 'tr_TR';
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final name in ['home_widget', 'home_widget/updates']) {
      messenger.setMockMethodCallHandler(MethodChannel(name), (call) async {
        if (call.method == 'isRequestPinWidgetSupported') return true;
        if (call.method == 'requestPinWidget') return null;
        return null;
      });
    }
  });

  setUp(() async {
    store.language = AppLanguage.tr;
    strings.value = const AppStrings(AppLanguage.tr);
    await store.load();
    final d = await store.db;
    await d.delete('entries');
    await d.delete('activities');
    await d.delete('settings');
    await store.load();
  });

  test('singleWidgetActivityId getter, setter and persistence', () async {
    expect(store.singleWidgetActivityId, isNull);
    expect(store.singleWidgetActivityLabel(strings.value), 'Akıllı / Otomatik Öneri');

    final act = await store.addActivity('Su', emoji: '💧');
    await store.setSingleWidgetActivityId(act.id);
    expect(store.singleWidgetActivityId, act.id);
    expect(store.singleWidgetActivityLabel(strings.value), '💧 Su');

    // Reload store to verify DB persistence
    await store.load();
    expect(store.singleWidgetActivityId, act.id);

    // Reset to auto (null/0)
    await store.setSingleWidgetActivityId(null);
    expect(store.singleWidgetActivityId, isNull);
    expect(store.singleWidgetActivityLabel(strings.value), 'Akıllı / Otomatik Öneri');

    await store.load();
    expect(store.singleWidgetActivityId, isNull);
  });

  test('widgetPayload reflects singleWidgetActivityId and contains activities list', () async {
    final act1 = await store.addActivity('Su', emoji: '💧');
    final act2 = await store.addActivity('Kahve', emoji: '☕');

    // 1. Without specific setting: uses auto priority
    var payload = store.widgetPayload();
    expect(payload['activities'], isNotEmpty);
    final actsList = (payload['activities'] as List).cast<Map<String, dynamic>>();
    expect(actsList.any((a) => a['id'] == act1.id && a['name'] == 'Su'), isTrue);
    expect(actsList.any((a) => a['id'] == act2.id && a['name'] == 'Kahve'), isTrue);
    expect(payload['single_configured_act_id'], 0);

    // 2. Set specific activity: Kahve
    await store.setSingleWidgetActivityId(act2.id);
    payload = store.widgetPayload();
    expect(payload['single_act_id'], act2.id);
    expect(payload['single_title'], 'Kahve');
    expect(payload['single_emoji'], '☕');
    expect(payload['single_configured_act_id'], act2.id);
    expect(payload['single_done'], isFalse);

    // 3. Log an entry for Kahve -> single_done should be true
    await store.addEntry(act2.id);
    payload = store.widgetPayload();
    expect(payload['single_done'], isTrue);
    expect(payload['single_sub'], contains('Bugün 1'));
  });

  test('deleteActivity and mergeActivity handle singleWidgetActivityId', () async {
    final act1 = await store.addActivity('Su', emoji: '💧');
    final act2 = await store.addActivity('Su (2)', emoji: '💧');

    await store.setSingleWidgetActivityId(act1.id);
    expect(store.singleWidgetActivityId, act1.id);

    // Delete activity -> should reset to null
    await store.deleteActivity(act1.id);
    expect(store.singleWidgetActivityId, isNull);

    // Set to act2 and merge act2 into a new act3
    final act3 = await store.addActivity('Su Yeni', emoji: '💧');
    await store.setSingleWidgetActivityId(act2.id);
    expect(store.singleWidgetActivityId, act2.id);

    await store.mergeActivity(act2.id, act3.id);
    expect(store.singleWidgetActivityId, act3.id);
  });

  testWidgets('ManagePage 1x1 widget picker opens and selects activity', (tester) async {
    tester.view.physicalSize = const Size(412, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    late Activity act;
    await tester.runAsync(() async {
      act = await store.addActivity('Yürüyüş', emoji: '🚶', isHabit: true);
    });

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: ManagePage()),
      ),
    );
    await _settle(tester);

    final addWidgetBtn = find.widgetWithText(FilledButton, 'Ekle');
    expect(addWidgetBtn, findsOneWidget);
    await tester.tap(addWidgetBtn);
    await _settle(tester);

    final miniWidgetTile = find.text('Mini Widget (1x1)');
    expect(miniWidgetTile, findsOneWidget);
    await tester.tap(miniWidgetTile);
    await _settle(tester);

    expect(find.text('1x1 Mini Widget Aktivitesi'), findsOneWidget);
    expect(find.text('Akıllı / Otomatik Öneri'), findsOneWidget);
    expect(find.text('Yürüyüş'), findsOneWidget);

    await tester.tap(find.text('Yürüyüş'));
    await _settle(tester);

    expect(store.singleWidgetActivityId, act.id);
  });
}
