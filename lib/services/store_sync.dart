import 'dart:isolate';
import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../data/store.dart';

/// Arayüz, bildirim aksiyonları ve ana ekran widget'ı ayrı isolate'larda, her biri kendi [AppStore]
/// kopyasıyla aynı veritabanı üzerinde çalışır. Arka plandaki bir isolate veriyi değiştirdiğinde bunu
/// arayüze haber verir, arayüz de verileri yeniden okur. Haber olmadan değişiklik ancak uygulama yeniden
/// öne geldiğinde görünürdü: bildirimden bitirilen sayaç, açık duran uygulamada saymaya devam ederdi.
class StoreSync {
  static const _portName = 'dev.takip.takip.store_changed';
  static ReceivePort? _port;

  /// Arayüz isolate'ında bir kez çağrılır: başka isolate'lardan gelen haberleri dinlemeye başlar.
  static void listen(AppStore store) {
    if (_port != null) return;
    final port = ReceivePort();
    // Süreç yaşarken arayüz yeniden yaratıldıysa eski kaydın yerine yenisi geçer.
    IsolateNameServer.removePortNameMapping(_portName);
    if (!IsolateNameServer.registerPortWithName(port.sendPort, _portName)) {
      port.close();
      return;
    }
    port.listen((_) async {
      debugPrint('StoreSync: veriler başka bir isolate\'ta değişti, yeniden okunuyor');
      try {
        await store.refresh();
      } catch (e) {
        debugPrint('StoreSync: veriler yeniden okunamadı: $e');
      }
    });
    _port = port;
  }

  /// Bu isolate'ın veritabanında yaptığı değişikliği arayüze haber verir. Arayüz isolate'ının kendisinde
  /// ya da arayüz açık değilken hiçbir şey yapmaz.
  static void notifyChanged() {
    if (_port != null) return;
    IsolateNameServer.lookupPortByName(_portName)?.send(null);
  }

  /// Testler içindir: dinlemeyi bırakır.
  @visibleForTesting
  static void close() {
    if (_port == null) return;
    IsolateNameServer.removePortNameMapping(_portName);
    _port!.close();
    _port = null;
  }
}
