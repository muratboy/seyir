import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/models.dart';
import '../../data/store.dart';
import '../../logic/l10n.dart';
import '../../services/export_service.dart';
import '../app_font.dart';
import '../common.dart';

/// Dışa aktarma öncesinde format (CSV/PDF), tarih aralığı ve aktivite filtresi seçtiren modern alt sayfa.
class ExportFilterSheet extends StatefulWidget {
  final AppStore store;
  final String initialFormat;
  final int? initialActivityId;

  const ExportFilterSheet({
    super.key,
    required this.store,
    this.initialFormat = 'csv',
    this.initialActivityId,
  });

  static Future<void> show(
    BuildContext context,
    AppStore store, {
    String initialFormat = 'csv',
    int? initialActivityId,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => ExportFilterSheet(
        store: store,
        initialFormat: initialFormat,
        initialActivityId: initialActivityId,
      ),
    );
  }

  @override
  State<ExportFilterSheet> createState() => _ExportFilterSheetState();
}

class _ExportFilterSheetState extends State<ExportFilterSheet> {
  late String _format;
  String _dateOption = 'all'; // 'all', '30days', 'this_month', 'custom'
  DateTimeRange? _customDateRange;
  int? _selectedActivityId;

  @override
  void initState() {
    super.initState();
    _format = widget.initialFormat;
    _selectedActivityId = widget.initialActivityId;
  }

  DateTimeRange? get _effectiveDateRange {
    final now = DateTime.now();
    switch (_dateOption) {
      case '30days':
        return DateTimeRange(
          start: DateTime(now.year, now.month, now.day - 30),
          end: now,
        );
      case 'this_month':
        return DateTimeRange(
          start: DateTime(now.year, now.month, 1),
          end: now,
        );
      case 'custom':
        return _customDateRange;
      case 'all':
      default:
        return null;
    }
  }

  List<Entry> get _filteredEntries {
    var list = widget.store.entries;
    if (_selectedActivityId != null) {
      list = list.where((e) => e.activityId == _selectedActivityId).toList();
    }
    final range = _effectiveDateRange;
    if (range != null) {
      final startMs = range.start.millisecondsSinceEpoch;
      final endMs = DateTime(range.end.year, range.end.month, range.end.day, 23, 59, 59, 999).millisecondsSinceEpoch;
      list = list.where((e) => e.ts >= startMs && e.ts <= endMs).toList();
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final s = strings.value;
    final isTr = s.isTr;
    final scheme = Theme.of(context).colorScheme;
    final filteredCount = _filteredEntries.length;
    final selectedAct = _selectedActivityId != null ? widget.store.activities[_selectedActivityId] : null;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 8, 20, MediaQuery.of(context).viewInsets.bottom + 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.tune_rounded, color: scheme.primary, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  isTr ? 'Dışa Aktarma & Raporlama' : 'Export & Report Options',
                  style: const TextStyle(fontSize: AppFont.title, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Format Seçimi (CSV / PDF)
          Text(
            isTr ? 'Dosya Formatı' : 'File Format',
            style: TextStyle(fontSize: AppFont.small, fontWeight: FontWeight.bold, color: scheme.primary),
          ),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: [
              ButtonSegment(
                value: 'csv',
                icon: const Icon(Icons.table_chart_outlined, size: 18),
                label: Text(isTr ? 'CSV (Excel Uyumlu)' : 'CSV (Spreadsheet)'),
              ),
              ButtonSegment(
                value: 'pdf',
                icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                label: Text(isTr ? 'PDF (Görsel Rapor)' : 'PDF (Visual Report)'),
              ),
            ],
            selected: {_format},
            onSelectionChanged: (set) => setState(() => _format = set.first),
          ),
          const SizedBox(height: 16),

          // Tarih Aralığı Seçimi
          Text(
            isTr ? 'Tarih Aralığı' : 'Date Range',
            style: TextStyle(fontSize: AppFont.small, fontWeight: FontWeight.bold, color: scheme.primary),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                label: Text(isTr ? 'Tüm Zamanlar' : 'All Time'),
                selected: _dateOption == 'all',
                onSelected: (val) {
                  if (val) setState(() => _dateOption = 'all');
                },
              ),
              ChoiceChip(
                label: Text(isTr ? 'Son 30 Gün' : 'Last 30 Days'),
                selected: _dateOption == '30days',
                onSelected: (val) {
                  if (val) setState(() => _dateOption = '30days');
                },
              ),
              ChoiceChip(
                label: Text(isTr ? 'Bu Ay' : 'This Month'),
                selected: _dateOption == 'this_month',
                onSelected: (val) {
                  if (val) setState(() => _dateOption = 'this_month');
                },
              ),
              ChoiceChip(
                label: Text(
                  _customDateRange != null
                      ? '${DateFormat("d MMM", isTr ? "tr" : "en").format(_customDateRange!.start)} - ${DateFormat("d MMM", isTr ? "tr" : "en").format(_customDateRange!.end)}'
                      : (isTr ? 'Özel Aralık...' : 'Custom Range...'),
                ),
                selected: _dateOption == 'custom',
                onSelected: (val) async {
                  final picked = await showDateRangePicker(
                    context: context,
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now(),
                    initialDateRange: _customDateRange ??
                        DateTimeRange(
                          start: DateTime.now().subtract(const Duration(days: 7)),
                          end: DateTime.now(),
                        ),
                  );
                  if (picked != null) {
                    setState(() {
                      _customDateRange = picked;
                      _dateOption = 'custom';
                    });
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Aktivite Filtresi
          Text(
            isTr ? 'Aktivite Filtresi' : 'Activity Filter',
            style: TextStyle(fontSize: AppFont.small, fontWeight: FontWeight.bold, color: scheme.primary),
          ),
          const SizedBox(height: 8),
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () async {
              final act = await showActivityPicker(
                context,
                title: isTr ? 'Filtrelenecek Aktiviteyi Seç' : 'Select Activity to Filter',
              );
              if (act != null) {
                setState(() => _selectedActivityId = act.id);
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.4)),
              ),
              child: Row(
                children: [
                  Text(selectedAct?.emoji ?? '📋', style: const TextStyle(fontSize: AppFont.title)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      selectedAct != null ? selectedAct.name : (isTr ? 'Tüm Aktiviteler' : 'All Activities'),
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: AppFont.body,
                        color: selectedAct != null ? scheme.onSurface : scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  if (selectedAct != null)
                    IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                      onPressed: () => setState(() => _selectedActivityId = null),
                    )
                  else
                    const Icon(Icons.arrow_drop_down, size: 20),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Eşleşen Kayıt Özeti ve Dışa Aktar Butonu
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '$filteredCount ${s.entriesCountSuffix} ${isTr ? "dışa aktarılacak" : "will be exported"}',
                style: TextStyle(
                  fontSize: AppFont.caption,
                  fontWeight: FontWeight.bold,
                  color: filteredCount > 0 ? scheme.primary : scheme.error,
                ),
              ),
              FilledButton.icon(
                icon: const Icon(Icons.share_rounded, size: 18),
                label: Text(isTr ? 'Dışa Aktar' : 'Export'),
                onPressed: filteredCount == 0
                    ? null
                    : () async {
                        Navigator.pop(context);
                        final range = _effectiveDateRange;
                        final actId = _selectedActivityId;
                        if (_format == 'pdf') {
                          await ExportService.exportPdf(
                            context,
                            widget.store,
                            dateRange: range,
                            activityId: actId,
                          );
                        } else {
                          await ExportService.exportCsv(
                            context,
                            widget.store,
                            dateRange: range,
                            activityId: actId,
                          );
                        }
                      },
              ),
            ],
          ),
        ],
      ),
    );
  }
}
