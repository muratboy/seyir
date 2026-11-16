import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:takip/data/db.dart';
import 'package:takip/data/store.dart';
import 'package:takip/logic/l10n.dart';
import 'package:takip/services/nl_parser.dart';

import 'support/real_db.dart';

void main() {
  useRealDatabase();

  setUpAll(() async {
    await initializeDateFormatting('tr_TR', null);
    await initializeDateFormatting('en_US', null);
  });

  tearDown(() {
    AppDb.preferredLanguage = null;
  });

  group('Başlangıç dili çözümleme', () {
    test('cihaz dili Türkçe ise tr, diğer tüm dillerde en döner', () {
      expect(resolveInitialLanguage('tr'), equals('tr'));
      expect(resolveInitialLanguage('TR'), equals('tr'));
      expect(resolveInitialLanguage('tr_TR'), equals('en')); // birincil dil kodu 2 harf tr
      expect(resolveInitialLanguage('en'), equals('en'));
      expect(resolveInitialLanguage('de'), equals('en'));
      expect(resolveInitialLanguage('fr'), equals('en'));
      expect(resolveInitialLanguage('es'), equals('en'));
    });
  });

  group('Yeni kurulum dil ve hazır ölçü davranışı', () {
    test('Yeni kurulum, cihaz dili en: dil İngilizce, ayar en, ölçüler İngilizce ve Türkçe harfsiz', () async {
      AppDb.preferredLanguage = 'en';
      await store.load();

      expect(store.language, equals(AppLanguage.en));
      expect(strings.value.isTr, isFalse);

      final d = await store.db;
      final settingRows = await d.query('settings', where: 'key = ?', whereArgs: ['lang']);
      expect(settingRows, isNotEmpty);
      expect(settingRows.first['value'], equals('en'));

      final measures = store.measures;
      expect(measures.length, greaterThanOrEqualTo(17));

      final expectedMeasuresEn = [
        ('Tea glass', 'l', 0.1),
        ('Glass', 'l', 0.2),
        ('Cup', 'l', 0.08),
        ('Mug', 'l', 0.3),
        ('Bottle', 'l', 0.5),
        ('Bowl', 'l', 0.25),
        ('Litre', 'l', 1.0),
        ('Millilitre', 'ml', 1.0),
        ('Minute', 'dk', 1.0),
        ('Hour', 'sa', 1.0),
        ('Second', 'sn', 1.0),
        ('Piece', 'adet', 1.0),
        ('Gram', 'g', 1.0),
        ('Kilogram', 'kg', 1.0),
        ('Metre', 'm', 1.0),
        ('Kilometre', 'km', 1.0),
        ('Calorie', 'kcal', 1.0),
      ];

      for (var i = 0; i < expectedMeasuresEn.length; i++) {
        final expected = expectedMeasuresEn[i];
        final actual = measures[i];
        expect(actual.name, equals(expected.$1), reason: '$i sırasındaki ölçü adı İngilizce değil');
        expect(actual.unitId, equals(expected.$2), reason: '$i sırasındaki birim uyuşmadı');
        expect(actual.amount, closeTo(expected.$3, 1e-6), reason: '$i sırasındaki miktar uyuşmadı');
      }

      final trCharRegex = RegExp(r'[çÇğĞıİöÖşŞüÜ]');
      for (final m in measures) {
        expect(trCharRegex.hasMatch(m.name), isFalse, reason: '"${m.name}" ölçü adında Türkçe harf var');
      }
    });

    test('Yeni kurulum, cihaz dili de: İngilizce açılır', () async {
      AppDb.preferredLanguage = 'de';
      await store.load();

      expect(store.language, equals(AppLanguage.en));
      final d = await store.db;
      final settingRows = await d.query('settings', where: 'key = ?', whereArgs: ['lang']);
      expect(settingRows.first['value'], equals('en'));
      expect(store.measures.first.name, equals('Tea glass'));
    });

    test('Yeni kurulum, cihaz dili tr: Türkçe ölçüler ve tr ayarı', () async {
      AppDb.preferredLanguage = 'tr';
      await store.load();

      expect(store.language, equals(AppLanguage.tr));
      expect(strings.value.isTr, isTrue);

      final d = await store.db;
      final settingRows = await d.query('settings', where: 'key = ?', whereArgs: ['lang']);
      expect(settingRows.first['value'], equals('tr'));
      expect(store.measures.first.name, equals('Çay bardağı'));
      expect(store.measures[1].name, equals('Su bardağı'));
    });

    test('Cihaz dili bildirilmemiş: bugünkü gibi Türkçe açılır ve lang ayarı yazılmaz', () async {
      AppDb.preferredLanguage = null;
      await store.load();

      expect(store.language, equals(AppLanguage.tr));
      expect(strings.value.isTr, isTrue);

      final d = await store.db;
      final settingRows = await d.query('settings', where: 'key = ?', whereArgs: ['lang']);
      expect(settingRows, isEmpty, reason: 'Bildirilmemiş açılışta lang ayarı yazılmamalı');
      expect(store.measures.first.name, equals('Çay bardağı'));
    });

    test('Var olan kurulum: Türkçe ve lang ayarı olmayan veritabanı, en bildirilerek yeniden açılınca Türkçe kalır', () async {
      // 1. Kurulum: cihaz dili bildirilmeden kurulur (Türkçe, lang ayarı yok)
      AppDb.preferredLanguage = null;
      await store.load();
      expect(store.language, equals(AppLanguage.tr));
      expect(store.measures.first.name, equals('Çay bardağı'));

      final d = await store.db;
      expect(await d.query('settings', where: 'key = ?', whereArgs: ['lang']), isEmpty);

      // 2. Yeniden açılış: cihaz dili en bildirilse bile var olan kurulum bozulmaz
      AppDb.preferredLanguage = 'en';
      final store2 = AppStore();
      await store2.load();

      expect(store2.language, equals(AppLanguage.tr), reason: 'Var olan veritabanı cihaz dili değişince dilini değiştirmemeli');
      expect(store2.measures.first.name, equals('Çay bardağı'));
      expect(await d.query('settings', where: 'key = ?', whereArgs: ['lang']), isEmpty, reason: 'lang ayarı sonradan yazılmamalı');
    });

    test('İkinci açılış: en ile kurulmuş veritabanı cihaz dili tr bildirilerek açılınca İngilizce kalır', () async {
      // 1. Kurulum: en ile kurulur
      AppDb.preferredLanguage = 'en';
      await store.load();
      expect(store.language, equals(AppLanguage.en));
      expect(store.measures.first.name, equals('Tea glass'));

      // 2. İkinci açılış: cihaz dili tr bildirilse bile İngilizce kalır
      AppDb.preferredLanguage = 'tr';
      final store2 = AppStore();
      await store2.load();

      expect(store2.language, equals(AppLanguage.en));
      expect(store2.measures.first.name, equals('Tea glass'));
    });
  });

  group('Aktivite varsayılan ölçü seçimi (defaultMeasureFor)', () {
    test('İngilizce kurulumda Water -> Glass, Tea -> Tea glass, Coffee -> Cup; Steak/Teaching/Team meeting çay almaz', () async {
      AppDb.preferredLanguage = 'en';
      await store.load();

      final waterAct = await store.addActivity('Water');
      final teaAct = await store.addActivity('Tea');
      final coffeeAct = await store.addActivity('Coffee');
      final steakAct = await store.addActivity('Steak');
      final teachAct = await store.addActivity('Teaching');
      final meetingAct = await store.addActivity('Team meeting');

      expect(store.defaultMeasureFor(waterAct.id)?.name, equals('Glass'));
      expect(store.defaultMeasureFor(teaAct.id)?.name, equals('Tea glass'));
      expect(store.defaultMeasureFor(coffeeAct.id)?.name, equals('Cup'));

      expect(store.defaultMeasureFor(steakAct.id)?.name, isNot(equals('Tea glass')));
      expect(store.defaultMeasureFor(teachAct.id)?.name, isNot(equals('Tea glass')));
      expect(store.defaultMeasureFor(meetingAct.id)?.name, isNot(equals('Tea glass')));
    });

    test('Türkçe kurulumda Su -> Su bardağı, Çay -> Çay bardağı, Kahve -> Fincan', () async {
      AppDb.preferredLanguage = 'tr';
      await store.load();

      final suAct = await store.addActivity('Su');
      final cayAct = await store.addActivity('Çay');
      final kahveAct = await store.addActivity('Kahve');

      expect(store.defaultMeasureFor(suAct.id)?.name, equals('Su bardağı'));
      expect(store.defaultMeasureFor(cayAct.id)?.name, equals('Çay bardağı'));
      expect(store.defaultMeasureFor(kahveAct.id)?.name, equals('Fincan'));
    });
  });

  group('İngilizce kurulumda ölçü kelimelerinin doğal dil ayrıştırması', () {
    final fixedNow = DateTime(2026, 11, 16, 10, 0);

    setUp(() async {
      AppDb.preferredLanguage = 'en';
      await store.load();
      await store.addActivity('Water', emoji: '💧');
      await store.addActivity('Coffee', emoji: '☕');
      await store.addActivity('Reading', emoji: '📖');
      await store.addActivity('Tea', emoji: '🍵');
      await store.addActivity('Soup', emoji: '🍲');
    });

    test('İngilizce ölçü girdileri ölçüyü, adedi ve aktiviteyi doğru bulur', () {
      final acts = store.activities.values.toList();
      final measures = store.measures;

      final cases = [
        ('2 glass water', 2.0, 'Glass', 'Water'),
        ('2 glasses water', 2.0, 'Glass', 'Water'),
        ('2 glasses of water', 2.0, 'Glass', 'Water'),
        ('1 cup coffee', 1.0, 'Cup', 'Coffee'),
        ('3 cups of coffee', 3.0, 'Cup', 'Coffee'),
        ('1 bottle water', 1.0, 'Bottle', 'Water'),
        ('2 bottles of water', 2.0, 'Bottle', 'Water'),
        ('1 mug coffee', 1.0, 'Mug', 'Coffee'),
        ('2 mugs of tea', 2.0, 'Mug', 'Tea'),
        ('2 bowls of soup', 2.0, 'Bowl', 'Soup'),
        ('2 litres of water', 2.0, 'Litre', 'Water'),
        ('30 minutes reading', 30.0, 'Minute', 'Reading'),
        ('30 min reading', 30.0, 'Minute', 'Reading'),
      ];

      for (final (input, expectedQty, expectedMeasure, expectedActivity) in cases) {
        final res = NaturalLanguageParser.parseMulti(
          input,
          activities: acts,
          measures: measures,
          openTodos: store.todos,
          now: fixedNow,
          fallbackDay: fixedNow,
        );

        expect(res.items, isNotEmpty, reason: '"$input" ayrıştırılamadı');
        final item = res.items.first as EntryParsedItem;
        expect(item.quantity, equals(expectedQty), reason: '"$input" miktarı hatalı');
        expect(item.measure?.name, equals(expectedMeasure), reason: '"$input" ölçüsü hatalı');
        expect(item.activity?.name, equals(expectedActivity), reason: '"$input" aktivitesi hatalı');
      }
    });

    test('İngilizce fiil çekimleri ölçü kelimesiyle eşleşmez', () {
      final acts = store.activities.values.toList();
      final measures = store.measures;

      final inputs = ['bowling', '2 bowling', 'cupping 1', 'bowled 2'];
      for (final input in inputs) {
        final res = NaturalLanguageParser.parseMulti(
          input,
          activities: acts,
          measures: measures,
          openTodos: store.todos,
          now: fixedNow,
          fallbackDay: fixedNow,
        );
        expect(res.items, isNotEmpty, reason: '"$input" ayrıştırılamadı');
        final item = res.items.first as EntryParsedItem;
        expect(item.measure, isNull, reason: '"$input" girdisi ölçü almamalı');
      }
    });
  });
}
