import 'dart:io';
import 'package:csv/csv.dart';
import 'package:flutter/material.dart' show BuildContext, DateTimeRange, ScaffoldMessenger, SnackBar, Text;
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
  static Future<void> exportCsv(
    BuildContext context,
    AppStore store, {
    DateTimeRange? dateRange,
    int? activityId,
  }) async {
    try {
      final isTr = store.language == AppLanguage.tr;

      var entries = store.entries;
      if (activityId != null) {
        entries = entries.where((e) => e.activityId == activityId).toList();
      }
      if (dateRange != null) {
        final startMs = dateRange.start.millisecondsSinceEpoch;
        final endMs = DateTime(dateRange.end.year, dateRange.end.month, dateRange.end.day, 23, 59, 59, 999).millisecondsSinceEpoch;
        entries = entries.where((e) => e.ts >= startMs && e.ts <= endMs).toList();
      }

      if (entries.isEmpty) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(isTr ? 'Dışa aktarılacak kayıt bulunamadı.' : 'No entries found to export.')),
          );
        }
        return;
      }

      final rows = <List<dynamic>>[];
      // Başlık satırı
      rows.add(isTr
          ? ['ID', 'Tarih', 'Saat', 'Aktivite', 'Kategori', 'Adet / Çarpan', 'Ölçü Adı', 'Hesaplanan Miktar', 'Birim', 'Detay', 'Not']
          : ['ID', 'Date', 'Time', 'Activity', 'Category', 'Quantity', 'Measure', 'Amount', 'Unit', 'Detail', 'Note']);

      final dateFmt = DateFormat('yyyy-MM-dd');
      final timeFmt = DateFormat('HH:mm:ss');

      for (final e in entries) {
        final act = store.activities[e.activityId];
        final dt = DateTime.fromMillisecondsSinceEpoch(e.ts);
        final dateStr = dateFmt.format(dt);
        final timeStr = timeFmt.format(dt);
        final actName = '${act?.emoji ?? ''} ${act?.name ?? (isTr ? 'Bilinmeyen' : 'Unknown')}'.trim();
        final catName = act?.categoryDef.name(isTr) ?? (isTr ? 'Genel' : 'General');
        final m = store.measureById(e.measureId);
        final measureName = m?.name ?? '';
        final unitStr = e.unitId == null ? '' : store.unit(e.unitId!).symbol;
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
          text: isTr ? 'Takip Kayıtları CSV Yedeği ($nowStr)' : 'Takip entries as CSV ($nowStr)',
        ),
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${strings.value.isTr ? "CSV Dışa Aktarma Hatası" : "CSV export failed"}: $e')),
        );
      }
    }
  }

  /// PDF Raporu oluşturur ve paylaşır.
  static Future<void> exportPdf(
    BuildContext context,
    AppStore store, {
    DateTimeRange? dateRange,
    int? activityId,
  }) async {
    try {
      final isTr = store.language == AppLanguage.tr;

      var entries = store.entries;
      if (activityId != null) {
        entries = entries.where((e) => e.activityId == activityId).toList();
      }
      if (dateRange != null) {
        final startMs = dateRange.start.millisecondsSinceEpoch;
        final endMs = DateTime(dateRange.end.year, dateRange.end.month, dateRange.end.day, 23, 59, 59, 999).millisecondsSinceEpoch;
        entries = entries.where((e) => e.ts >= startMs && e.ts <= endMs).toList();
      }

      if (entries.isEmpty) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(isTr ? 'Raporlanacak kayıt bulunamadı.' : 'No entries found to report.')),
          );
        }
        return;
      }

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
      final totalEntries = entries.length;
      final uniqueActivities = entries.map((e) => e.activityId).toSet().length;
      final activeGoals = store.goals.length;

      // Kategori dağılımı
      final categoryCounts = <String, int>{};
      for (final e in entries) {
        final act = store.activities[e.activityId];
        final cat = act?.categoryDef.name(isTr) ?? (isTr ? 'Genel' : 'General');
        categoryCounts[cat] = (categoryCounts[cat] ?? 0) + 1;
      }

      // Filtrelenmiş veya son kayıtlar
      final recentEntries = entries.reversed.take(60).toList();

      final filterInfo = [
        if (activityId != null && store.activities.containsKey(activityId))
          '${isTr ? "Aktivite" : "Activity"}: ${store.activities[activityId]!.name}',
        if (dateRange != null)
          '${isTr ? "Tarih" : "Date"}: ${dateFmt.format(dateRange.start)} - ${dateFmt.format(dateRange.end)}',
      ].join('  ·  ');

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
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          isTr ? 'TAKIP - RAPOR' : 'TAKIP - REPORT',
                          style: pw.TextStyle(
                            fontSize: 24,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.blueGrey800,
                          ),
                        ),
                        if (filterInfo.isNotEmpty) ...[
                          pw.SizedBox(height: 4),
                          pw.Text(
                            filterInfo,
                            style: const pw.TextStyle(fontSize: 10, color: PdfColors.blueGrey600),
                          ),
                        ],
                      ],
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
                    _buildStatCard(isTr ? 'Toplam Kayıt' : 'Entries', '$totalEntries'),
                    _buildStatCard(isTr ? 'Aktivite Çeşidi' : 'Activities', '$uniqueActivities'),
                    _buildStatCard(isTr ? 'Tanımlı Hedef' : 'Goals', '$activeGoals'),
                  ],
                ),
              ),
              pw.SizedBox(height: 20),

              // Kategori Dağılımı Tablosu
              pw.Text(
                isTr ? 'Kategori Dağılımı' : 'Categories',
                style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(height: 8),
              pw.TableHelper.fromTextArray(
                headers: isTr ? ['Kategori', 'Kayıt Sayısı', 'Oran'] : ['Category', 'Entries', 'Share'],
                data: categoryCounts.entries.map((entry) {
                  final pct = totalEntries > 0
                      ? ((entry.value / totalEntries) * 100).toStringAsFixed(1)
                      : '0';
                  return [entry.key, '${entry.value}', fmtPercent(pct)];
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
                  isTr ? 'Hedef ve Limit Durumu' : 'Goals and Limits',
                  style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
                ),
                pw.SizedBox(height: 8),
                pw.TableHelper.fromTextArray(
                  headers: isTr
                      ? ['Hedef Adı', 'Tür', 'Periyot', 'Hedef', 'İlerleme', 'Durum']
                      : ['Goal', 'Kind', 'Period', 'Target', 'Progress', 'Status'],
                  data: store.goals.map((g) {
                    final st = store.goalStatus(g);
                    final typeStr = g.isLimit ? (isTr ? 'Limit (Maks)' : 'Limit (max)') : (isTr ? 'Hedef (Min)' : 'Goal (min)');
                    final periodStr = periodName(g.period, isTr: isTr);
                    final targetStr = store.goalValueText(g, g.target);
                    final currentStr = store.goalValueText(g, st.value);
                    final statusStr = g.isLimit
                        ? (st.isExceeded ? (isTr ? 'AŞILDI (!)' : 'EXCEEDED (!)') : (isTr ? 'Normal' : 'Within limit'))
                        : (st.done ? (isTr ? 'TAMAMLANDI' : 'DONE') : fmtPercent((st.ratio * 100).floor()));
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
                isTr ? 'Son Günlük Kayıtlar (Son ${recentEntries.length} Giriş)' : 'Latest Entries (${recentEntries.length})',
                style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(height: 8),
              pw.TableHelper.fromTextArray(
                headers: isTr
                    ? ['Tarih/Saat', 'Aktivite', 'Kategori', 'Miktar', 'Not']
                    : ['Date/Time', 'Activity', 'Category', 'Amount', 'Note'],
                data: recentEntries.map((e) {
                  final act = store.activities[e.activityId];
                  final dt = DateTime.fromMillisecondsSinceEpoch(e.ts);
                  final dtStr = '${dateFmt.format(dt)} ${timeFmt.format(dt)}';
                  final actName = act?.name ?? '';
                  final catName = act?.categoryDef.name(isTr) ?? '';
                  final qtyStr = store.entryDetail(e);
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
          text: isTr ? 'Takip Alışkanlık & Aktivite PDF Raporu ($nowStr)' : 'Takip habit & activity report ($nowStr)',
        ),
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${strings.value.isTr ? "PDF Oluşturma Hatası" : "PDF export failed"}: $e')),
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
