import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'data/store.dart';

const widgetProviderName = 'dev.takip.takip.TakipWidgetProvider';

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
      await HomeWidget.updateWidget(qualifiedAndroidName: widgetProviderName);
    } catch (e) {
      debugPrint('Widget güncellenemedi: $e');
    }
  }

  static Future<bool> requestPin() async {
    try {
      if (await HomeWidget.isRequestPinWidgetSupported() ?? false) {
        await HomeWidget.requestPinWidget(qualifiedAndroidName: widgetProviderName);
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
  await store.load();
  if (uri.host == 'tap') {
    final id = int.tryParse(uri.queryParameters['id'] ?? '');
    if (id != null) await store.tapQuickItem(id);
  }
  await WidgetSync.push();
}
