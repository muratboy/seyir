import 'dart:io';
import 'package:csv/csv.dart';
import 'package:flutter/material.dart' show BuildContext, ScaffoldMessenger, SnackBar, Text;
import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../data/models.dart';
import '../data/store.dart';
import '../logic/format.dart';
import '../logic/l10n.dart';

class ExportService {
  /// CSV formatında dışa aktarır ve sistem paylaşım penceresini açar.
  static Future<void> exportCsv(BuildContext context, AppStore store) async {
    try {
      final rows = <List<dynamic>>[];
      // Başlık satırı
      rows.add([
        'ID',
        'Tarih',
        'Saat',
        'Aktivite',
        'Kategori',
        'Adet / Çarpan',
        'Ölçü Adı',
        'Hesaplanan Miktar',
        'Birim',
        'Detay',
        'Not',
      ]);

      final dateFmt = DateFormat('yyyy-MM-dd');
      final timeFmt = DateFormat('HH:mm:ss');

      for (final e in store.entries) {
        final act = store.activities[e.activityId];
        final dt = DateTime.fromMillisecondsSinceEpoch(e.ts);
        final dateStr = dateFmt.format(dt);
        final timeStr = timeFmt.format(dt);
        final actName = '${act?.emoji ?? ''} ${act?.name ?? 'Bilinmeyen'}'.trim();
        final catName = act?.categoryDef.name(store.language == AppLanguage.tr) ?? 'Genel';
        final m = store.measureById(e.measureId);
        final measureName = m?.name ?? '';
        final unitStr = e.unitId ?? '';
        final note = e.note ?? '';
        final calculatedVal = e.value != null ? fmtNum(e.value!) : fmtNum(e.qty);
        final detail = store.entryDetail(e);

        rows.add([
          e.id,
          dateStr,
          timeStr,
          actName,
          catName,
          fmtNum(e.qty),
          measureName,
          calculatedVal,
          unitStr,
          detail,
          note,
        ]);
      }

      // UTF-8 BOM (\uFEFF) eklenerek Excel ve Türkçe karakter uyumluluğu sağlanır
      final csvContent = '\uFEFF${excel.encode(rows)}';
      final tempDir = await getTemporaryDirectory();
      final nowStr = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final filePath = '${tempDir.path}/takip_kayitlar_$nowStr.csv';
      final file = File(filePath);
      await file.writeAsString(csvContent);

      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(filePath)],
          text: 'Takip Kayıtları CSV Yedeği ($nowStr)',
        ),
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('CSV Dışa Aktarma Hatası: $e')),
        );
      }
    }
  }

  /// PDF Raporu oluşturur ve paylaşır.
  static Future<void> exportPdf(BuildContext context, AppStore store) async {
    try {
      final isTr = store.language == AppLanguage.tr;

      // Türkçe karakter desteği için NotoSans fontlarını yükle
      final regularData = await rootBundle.load('assets/fonts/NotoSans-Regular.ttf');
      final boldData = await rootBundle.load('assets/fonts/NotoSans-Bold.ttf');
      final ttfRegular = pw.Font.ttf(regularData);
      final ttfBold = pw.Font.ttf(boldData);

      final pdfTheme = pw.ThemeData.withFont(
        base: ttfRegular,
        bold: ttfBold,
      );

      final pdf = pw.Document(theme: pdfTheme);

      final dateFmt = DateFormat('dd.MM.yyyy');
      final timeFmt = DateFormat('HH:mm');
      final now = DateTime.now();

      // İstatistik özetleri
      final totalEntries = store.entries.length;
      final uniqueActivities = store.activities.length;
      final activeGoals = store.goals.length;

      // Kategori dağılımı
      final categoryCounts = <String, int>{};
      for (final e in store.entries) {
        final act = store.activities[e.activityId];
        final cat = act?.categoryDef.name(isTr) ?? 'Genel';
        categoryCounts[cat] = (categoryCounts[cat] ?? 0) + 1;
      }

      // Son 40 kayıt
      final recentEntries = store.entries.reversed.take(40).toList();

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(32),
          build: (pw.Context ctx) {
            return [
              // Header
              pw.Header(
                level: 0,
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      'TAKIP - RAPOR',
                      style: pw.TextStyle(
                        fontSize: 24,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.blueGrey800,
                      ),
                    ),
                    pw.Text(
                      dateFmt.format(now),
                      style: const pw.TextStyle(fontSize: 12, color: PdfColors.grey700),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 12),

              // Özet Kartları
              pw.Container(
                padding: const pw.EdgeInsets.all(12),
                decoration: pw.BoxDecoration(
                  color: PdfColors.grey100,
                  borderRadius: pw.BorderRadius.circular(8),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
                  children: [
                    _buildStatCard('Toplam Kayıt', '$totalEntries'),
                    _buildStatCard('Aktivite Çeşidi', '$uniqueActivities'),
                    _buildStatCard('Tanımlı Hedef', '$activeGoals'),
                  ],
                ),
              ),
              pw.SizedBox(height: 20),

              // Kategori Dağılımı Tablosu
              pw.Text(
                'Kategori Dağılımı',
                style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(height: 8),
              pw.TableHelper.fromTextArray(
                headers: ['Kategori', 'Kayıt Sayısı', 'Oran'],
                data: categoryCounts.entries.map((entry) {
                  final pct = totalEntries > 0
                      ? ((entry.value / totalEntries) * 100).toStringAsFixed(1)
                      : '0';
                  return [entry.key, '${entry.value}', '%$pct'];
                }).toList(),
                headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white),
                headerDecoration: const pw.BoxDecoration(color: PdfColors.blueGrey700),
                cellAlignment: pw.Alignment.centerLeft,
                cellPadding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              ),
              pw.SizedBox(height: 20),

              // Hedefler ve Limitler Tablosu
              if (store.goals.isNotEmpty) ...[
                pw.Text(
                  'Hedef ve Limit Durumu',
                  style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
                ),
                pw.SizedBox(height: 8),
                pw.TableHelper.fromTextArray(
                  headers: ['Hedef Adı', 'Tür', 'Periyot', 'Hedef', 'İlerleme', 'Durum'],
                  data: store.goals.map((g) {
                    final st = store.goalStatus(g);
                    final typeStr = g.isLimit ? 'Limit (Maks)' : 'Hedef (Min)';
                    final periodStr = periodNames[g.period] ?? '';
                    final targetStr = '${g.target} ${g.unitId ?? ''}'.trim();
                    final currentStr = '${st.value.toStringAsFixed(1)} ${g.unitId ?? ''}'.trim();
                    final statusStr = g.isLimit
                        ? (st.isExceeded ? 'AŞILDI (!)' : 'Normal')
                        : (st.done ? 'TAMAMLANDI' : '%${(st.ratio * 100).floor()}');
                    return [g.name, typeStr, periodStr, targetStr, currentStr, statusStr];
                  }).toList(),
                  headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white),
                  headerDecoration: const pw.BoxDecoration(color: PdfColors.teal700),
                  cellAlignment: pw.Alignment.centerLeft,
                  cellPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                ),
                pw.SizedBox(height: 20),
              ],

              // Son Kayıtlar
              pw.Text(
                'Son Günlük Kayıtlar (Son ${recentEntries.length} Giriş)',
                style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(height: 8),
              pw.TableHelper.fromTextArray(
                headers: ['Tarih/Saat', 'Aktivite', 'Kategori', 'Miktar', 'Not'],
                data: recentEntries.map((e) {
                  final act = store.activities[e.activityId];
                  final dt = DateTime.fromMillisecondsSinceEpoch(e.ts);
                  final dtStr = '${dateFmt.format(dt)} ${timeFmt.format(dt)}';
                  final actName = act?.name ?? '';
                  final catName = act?.categoryDef.name(isTr) ?? '';
                  final m = store.measureById(e.measureId);
                  final qtyStr = '${e.qty} ${m?.name ?? e.unitId ?? ''}'.trim();
                  return [dtStr, actName, catName, qtyStr, e.note ?? ''];
                }).toList(),
                headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white),
                headerDecoration: const pw.BoxDecoration(color: PdfColors.indigo700),
                cellAlignment: pw.Alignment.centerLeft,
                cellPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              ),
            ];
          },
        ),
      );

      final tempDir = await getTemporaryDirectory();
      final nowStr = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final filePath = '${tempDir.path}/takip_rapor_$nowStr.pdf';
      final file = File(filePath);
      await file.writeAsBytes(await pdf.save());

      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(filePath)],
          text: 'Takip Alışkanlık & Aktivite PDF Raporu ($nowStr)',
        ),
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('PDF Oluşturma Hatası: $e')),
        );
      }
    }
  }

  static pw.Widget _buildStatCard(String title, String value) {
    return pw.Column(
      children: [
        pw.Text(value, style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 4),
        pw.Text(title, style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey700)),
      ],
    );
  }
}
