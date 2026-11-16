import 'package:flutter_test/flutter_test.dart';
import 'package:takip/data/models.dart';
import 'package:takip/data/store.dart';
import 'package:takip/services/export_service.dart';

import 'support/real_db.dart';

void main() {
  useRealDatabase();

  group('CSV Dışa Aktarma BOM ve Formül Güvenliği', () {
    test('sanitizeCsvCell tehlikeli karakterleri tek tırnakla kaçırır, sıradan metne dokunmaz', () {
      expect(ExportService.sanitizeCsvCell('=1+1'), "'=1+1");
      expect(ExportService.sanitizeCsvCell('+905321234567'), "'+905321234567");
      expect(ExportService.sanitizeCsvCell('-deneme'), "'-deneme");
      expect(ExportService.sanitizeCsvCell('@kullanici'), "'@kullanici");
      expect(ExportService.sanitizeCsvCell('\ttab_metin'), "'\ttab_metin");
      expect(ExportService.sanitizeCsvCell('\nsatir_metin'), "'\nsatir_metin");
      expect(ExportService.sanitizeCsvCell('\rsatir_metin'), "'\rsatir_metin");

      // Güvenli sıradan metinler değişmez
      expect(ExportService.sanitizeCsvCell('Normal Metin'), 'Normal Metin');
      expect(ExportService.sanitizeCsvCell('123'), '123');
      expect(ExportService.sanitizeCsvCell(''), '');
    });

    test('generateCsvContent tek bir BOM ile başlar ve formül başlangıçlı notları kaçırır', () async {
      await store.load();

      final act = await store.addActivity('Su', emoji: '💧');

      final baseTime = DateTime(2026, 11, 16, 12, 0).millisecondsSinceEpoch;
      final e1 = Entry(id: 1, activityId: act.id, qty: 1.0, value: -10.5, ts: baseTime, note: '=1+1');
      final e2 = Entry(id: 2, activityId: act.id, qty: 2.0, value: 200.0, ts: baseTime + 1000, note: '+905321234567');
      final e3 = Entry(id: 3, activityId: act.id, qty: 3.0, ts: baseTime + 2000, note: '-deneme');
      final e4 = Entry(id: 4, activityId: act.id, qty: 4.0, ts: baseTime + 3000, note: '@x');
      final e5 = Entry(id: 5, activityId: act.id, qty: 5.0, ts: baseTime + 4000, note: 'Sıradan not');

      final csv = ExportService.generateCsvContent(
        store,
        entries: [e1, e2, e3, e4, e5],
        isTr: true,
      );

      // 1. İlk kod birimi BOM (0xFEFF), ikincisi BOM değil (tam tek BOM)
      expect(csv.isNotEmpty, isTrue);
      expect(csv.codeUnitAt(0), 0xFEFF, reason: 'İlk karakter UTF-8 BOM olmalı');
      expect(csv.codeUnitAt(1), isNot(0xFEFF), reason: 'İkinci karakter BOM olmamalı (çift BOM önlendi)');

      // 2. Tehlikeli notlar tek tırnakla başlamalı
      expect(csv.contains("'=1+1"), isTrue);
      expect(csv.contains("'+905321234567"), isTrue);
      expect(csv.contains("'-deneme"), isTrue);
      expect(csv.contains("'@x"), isTrue);

      // 3. Sıradan not ve aktivite adı değişmemeli
      expect(csv.contains('Sıradan not'), isTrue);
      expect(csv.contains("'Sıradan not"), isFalse);
      expect(csv.contains('💧 Su'), isTrue);
      expect(csv.contains("'💧 Su"), isFalse);

      // 4. Sayı sütunları eksi olsa bile tek tırnak almamalı
      expect(csv.contains("'-10.5"), isFalse);
      expect(csv.contains("-10.5") || csv.contains("-10,5"), isTrue);
    });
  });
}
