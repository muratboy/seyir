import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:takip/data/store.dart';
import 'package:takip/logic/l10n.dart';

import 'support/real_db.dart';

void main() {
  useRealDatabase();

  final savedWidgetData = <String, Object?>{};
  final updatedWidgets = <String>[];

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(const MethodChannel('home_widget'), (call) async {
      if (call.method == 'saveWidgetData') {
        final args = call.arguments as Map<dynamic, dynamic>?;
        if (args != null) {
          final id = args['id'] as String?;
          final data = args['data'];
          if (id != null) {
            savedWidgetData[id] = data;
          }
        }
        return true;
      }
      if (call.method == 'updateWidget') {
        final args = call.arguments as Map<dynamic, dynamic>?;
        final name = args?['name'] as String? ?? '';
        updatedWidgets.add(name);
        return true;
      }
      return null;
    });
  });

  setUp(() async {
    savedWidgetData.clear();
    updatedWidgets.clear();
    store.language = AppLanguage.tr;
    strings.value = const AppStrings(AppLanguage.tr);
    await store.load();
    final d = await store.db;
    await d.delete('entries');
    await d.delete('activities');
    await d.delete('settings');
    await d.delete('todos');
    await store.load();
  });

  test('payload theme mode values for system, light, dark', () async {
    // 1. Sistem modu
    await store.setThemeMode(ThemeMode.system);
    expect(store.themeMode, ThemeMode.system);
    expect(store.themeModeString, 'system');
    final pSystem = store.widgetPayload();
    final tpSystem = store.todoWidgetPayload();
    expect(pSystem['theme'], 'system');
    expect(tpSystem['theme'], 'system');

    // 2. Koyu mod
    await store.setThemeMode(ThemeMode.dark);
    expect(store.themeMode, ThemeMode.dark);
    expect(store.themeModeString, 'dark');
    final pDark = store.widgetPayload();
    final tpDark = store.todoWidgetPayload();
    expect(pDark['theme'], 'dark');
    expect(tpDark['theme'], 'dark');

    // 3. Açık mod
    await store.setThemeMode(ThemeMode.light);
    expect(store.themeMode, ThemeMode.light);
    expect(store.themeModeString, 'light');
    final pLight = store.widgetPayload();
    final tpLight = store.todoWidgetPayload();
    expect(pLight['theme'], 'light');
    expect(tpLight['theme'], 'light');
  });

  test('setThemeMode immediately triggers widget sync with correct theme payload', () async {
    savedWidgetData.clear();
    updatedWidgets.clear();

    await store.setThemeMode(ThemeMode.dark);
    // Asenkron widget kayıtlarının tamamlanması için bekle
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(savedWidgetData['widget_theme'], 'dark');
    expect(savedWidgetData.containsKey('payload'), isTrue);
    expect(savedWidgetData.containsKey('todo_payload'), isTrue);

    final payload = jsonDecode(savedWidgetData['payload'] as String) as Map<String, dynamic>;
    final todoPayload = jsonDecode(savedWidgetData['todo_payload'] as String) as Map<String, dynamic>;
    expect(payload['theme'], 'dark');
    expect(todoPayload['theme'], 'dark');

    expect(updatedWidgets.contains('TakipWidgetProvider'), isTrue);
    expect(updatedWidgets.contains('TakipSingleWidgetProvider'), isTrue);
    expect(updatedWidgets.contains('TodoWidgetProvider'), isTrue);
  });

  test('widget dark theme color contrast satisfies WCAG AA (>= 4.5:1)', () {
    final dark = ColorScheme.fromSeed(seedColor: const Color(0xFF3D6FE0), brightness: Brightness.dark);

    double luminance(Color c) {
      double channel(double v) {
        v = v / 255.0;
        return v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4).toDouble();
      }
      return 0.2126 * channel(c.r * 255) + 0.7152 * channel(c.g * 255) + 0.0722 * channel(c.b * 255);
    }

    double contrast(Color c1, Color c2) {
      final l1 = luminance(c1);
      final l2 = luminance(c2);
      final lighter = l1 > l2 ? l1 : l2;
      final darker = l1 > l2 ? l2 : l1;
      return (lighter + 0.05) / (darker + 0.05);
    }

    final darkWidgetBg = dark.surfaceContainerLow; // #1A1B21
    final darkChipBg = dark.surfaceContainerHigh; // #292A2F
    const darkChipDoneBg = Color(0xFF16291C); // #16291C
    final darkBtnBg = dark.primary; // #B2C5FF
    final darkBtnText = dark.onPrimary; // #182E60
    final darkTitle = dark.primary; // #B2C5FF
    final darkTextPrimary = dark.onSurface; // #E3E2E9
    final darkTextSecondary = dark.onSurfaceVariant; // #C5C6D0
    final darkEmpty = dark.onSurfaceVariant; // #C5C6D0
    final darkOverdue = dark.error; // #FFB4AB

    expect(contrast(darkTitle, darkWidgetBg), greaterThanOrEqualTo(4.5));
    expect(contrast(darkTextPrimary, darkChipBg), greaterThanOrEqualTo(4.5));
    expect(contrast(darkTextPrimary, darkChipDoneBg), greaterThanOrEqualTo(4.5));
    expect(contrast(darkBtnText, darkBtnBg), greaterThanOrEqualTo(4.5));
    expect(contrast(darkTextSecondary, darkWidgetBg), greaterThanOrEqualTo(4.5));
    expect(contrast(darkEmpty, darkWidgetBg), greaterThanOrEqualTo(4.5));
    expect(contrast(darkOverdue, darkWidgetBg), greaterThanOrEqualTo(4.5));
  });
}
