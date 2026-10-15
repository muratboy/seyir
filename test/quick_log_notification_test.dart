import 'package:flutter_test/flutter_test.dart';
import 'package:takip/data/store.dart';
import 'package:takip/logic/l10n.dart';

import 'support/real_db.dart';

void main() {
  useRealDatabase();

  group('Persistent Quick Log (Kilit Ekranı Hızlı Kayıt) Tests', () {
    test('persistentQuickLogEnabled is false by default and can be toggled', () async {
      await store.load();
      expect(store.persistentQuickLogEnabled, isFalse);

      await store.setPersistentQuickLogEnabled(true);
      expect(store.persistentQuickLogEnabled, isTrue);

      // Verify persistence by loading into a new store instance
      final secondStore = await openStore();
      expect(secondStore.persistentQuickLogEnabled, isTrue);

      await store.setPersistentQuickLogEnabled(false);
      expect(store.persistentQuickLogEnabled, isFalse);
    });

    test('logQuickActivity records entry with default or last measure and returns confirmation', () async {
      await store.load();
      final act = await store.addActivity(
        'Su',
        emoji: '💧',
        color: 0xFF2196F3,
      );

      final msg = await store.logQuickActivity(act.id);
      expect(msg, isNotNull);
      expect(msg, contains('Su'));
      expect(msg, contains('kaydedildi'));

      // Verify entry in database
      final todayEntries = store.entriesOfDay(DateTime.now());
      expect(todayEntries.any((e) => e.activityId == act.id), isTrue);
    });

    test('logFromQuickText parses entry text and creates record', () async {
      await store.load();
      final act = await store.addActivity(
        'Kitap',
        emoji: '📚',
        color: 0xFF4CAF50,
      );

      final msg = await store.logFromQuickText('25 dk Kitap');
      expect(msg, isNotNull);
      expect(msg, contains('Kitap'));
      expect(msg, contains('kaydedildi'));

      final todayEntries = store.entriesOfDay(DateTime.now());
      final entry = todayEntries.firstWhere((e) => e.activityId == act.id);
      expect(entry.value, equals(25));
    });

    test('logFromQuickText parses timer command and starts active timer', () async {
      await store.load();
      await store.addActivity(
        'Meditasyon',
        emoji: '🧘',
        color: 0xFF9C27B0,
      );

      final msg = await store.logFromQuickText('10 dk geri sayım Meditasyon');
      expect(msg, isNotNull);
      expect(msg, contains('başlatıldı'));

      // Check active timer
      expect(store.activeTimers.any((t) => t.isCountdown && t.targetMs == 10 * 60 * 1000), isTrue);
    });

    test('AppStrings provides accurate translations in TR and EN', () {
      final tr = const AppStrings(AppLanguage.tr);
      expect(tr.persistentQuickLogTitle, equals('Kilit Ekranı Hızlı Kayıt Bildirimi'));
      expect(tr.persistentQuickLogSubtitle, contains('bildirim panelinde'));
      expect(tr.quickLogNotificationTitle, equals('Takip — Hızlı Kayıt'));
      expect(tr.quickLogActionType, equals('✍️ Yaz'));
      expect(tr.quickLogInputLabel, contains('Ne yaptın?'));

      final en = const AppStrings(AppLanguage.en);
      expect(en.persistentQuickLogTitle, equals('Lock Screen Quick Log Notification'));
      expect(en.persistentQuickLogSubtitle, contains('lock screen'));
      expect(en.quickLogNotificationTitle, equals('Takip — Quick Log'));
      expect(en.quickLogActionType, equals('✍️ Type'));
      expect(en.quickLogInputLabel, contains('What did you do?'));
    });
  });
}
