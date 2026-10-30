import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:home_widget/home_widget.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'data/store.dart';
import 'services/notification_service.dart';
import 'services/store_sync.dart';

const widgetProviderName = 'dev.takip.takip.TakipWidgetProvider';
const singleWidgetProviderName = 'dev.takip.takip.TakipSingleWidgetProvider';
const todoWidgetProviderName = 'dev.takip.takip.TodoWidgetProvider';

/// Ana ekran widget'ına veri gönderir.
class WidgetSync {
  static Timer? _timer;

  static void schedule() {
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 300), push);
  }

  static Future<void> push() async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    try {
      final themeStr = store.themeModeString;
      await HomeWidget.saveWidgetData<String>('widget_theme', themeStr);
      await HomeWidget.saveWidgetData<String>('payload', jsonEncode(store.widgetPayload()));
      await HomeWidget.saveWidgetData<int>('single_act_id_global', store.singleWidgetActivityId ?? 0);
      await HomeWidget.saveWidgetData<String>('todo_payload', jsonEncode(store.todoWidgetPayload()));
      await HomeWidget.updateWidget(
        name: 'TakipWidgetProvider',
        androidName: 'TakipWidgetProvider',
        qualifiedAndroidName: widgetProviderName,
      );
      await HomeWidget.updateWidget(
        name: 'TakipSingleWidgetProvider',
        androidName: 'TakipSingleWidgetProvider',
        qualifiedAndroidName: singleWidgetProviderName,
      );
      await HomeWidget.updateWidget(
        name: 'TodoWidgetProvider',
        androidName: 'TodoWidgetProvider',
        qualifiedAndroidName: todoWidgetProviderName,
      );
    } catch (e) {
      debugPrint('Widget güncellenemedi: $e');
    }
  }

  static Future<bool> requestPin() async {
    try {
      if (await HomeWidget.isRequestPinWidgetSupported() ?? false) {
        await HomeWidget.requestPinWidget(
          name: 'TakipWidgetProvider',
          androidName: 'TakipWidgetProvider',
          qualifiedAndroidName: widgetProviderName,
        );
        return true;
      }
    } catch (_) {}
    return false;
  }

  static Future<bool> requestPinSingle({int? actId}) async {
    try {
      if (actId != null) {
        await store.setSingleWidgetActivityId(actId);
        await push();
      }
      if (await HomeWidget.isRequestPinWidgetSupported() ?? false) {
        await HomeWidget.requestPinWidget(
          name: 'TakipSingleWidgetProvider',
          androidName: 'TakipSingleWidgetProvider',
          qualifiedAndroidName: singleWidgetProviderName,
        );
        return true;
      }
    } catch (_) {}
    return false;
  }
}

/// Widget'taki bir öğeye dokunulduğunda uygulama açılmadan arka planda çalışır.
@pragma('vm:entry-point')
Future<void> widgetBackgroundCallback(Uri? uri) async {
  if (uri == null) return;
  await initializeDateFormatting('tr_TR');
  await store.refresh();
  if (uri.host == 'tap') {
    final id = int.tryParse(uri.queryParameters['id'] ?? '');
    if (id != null) {
      if (id < 0) {
        await store.repeatLastEntry(-id);
      } else {
        await store.tapQuickItem(id);
      }
      StoreSync.notifyChanged();
    }
  } else if (uri.host == 'repeat') {
    final actId = int.tryParse(uri.queryParameters['actId'] ?? '');
    if (actId != null && actId > 0) {
      await store.repeatLastEntry(actId);
      StoreSync.notifyChanged();
    }
  } else if (uri.host == 'single_tap') {
    final actId = int.tryParse(uri.queryParameters['actId'] ?? '');
    if (actId != null && actId > 0) {
      await store.repeatLastEntry(actId);
      StoreSync.notifyChanged();
    }
  } else if (uri.host == 'todo_toggle') {
    final id = int.tryParse(uri.queryParameters['id'] ?? '');
    if (id != null) {
      await store.toggleTodo(id);
      StoreSync.notifyChanged();
    }
  } else if (uri.host == 'theme') {
    final mode = uri.queryParameters['mode'];
    if (mode == 'dark') {
      await store.setThemeMode(ThemeMode.dark);
    } else if (mode == 'light') {
      await store.setThemeMode(ThemeMode.light);
    } else if (mode == 'system') {
      await store.setThemeMode(ThemeMode.system);
    }
    StoreSync.notifyChanged();
  } else if (uri.host == 'quick_text') {
    final text = uri.queryParameters['text'] ?? '';
    if (text.trim().isNotEmpty) {
      final msg = await store.logFromQuickText(text.trim());
      if (store.persistentQuickLogEnabled && msg != null) {
        await NotificationService.updatePersistentQuickLogNotification(store, lastLogMessage: msg);
      }
      StoreSync.notifyChanged();
    }
  }
  await WidgetSync.push();
}
