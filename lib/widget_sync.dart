import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'data/store.dart';
import 'services/store_sync.dart';

const widgetProviderName = 'dev.takip.takip.TakipWidgetProvider';
const singleWidgetProviderName = 'dev.takip.takip.TakipSingleWidgetProvider';

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
      await HomeWidget.saveWidgetData<String>('payload', jsonEncode(store.widgetPayload()));
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

  static Future<bool> requestPinSingle() async {
    try {
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
  }
  await WidgetSync.push();
}
