import 'package:flutter/material.dart';

import '../logic/format.dart';
import '../logic/l10n.dart';

/// GitHub stili katkı / alışkanlık ısı haritası (Contributions Heatmap)
class ContributionHeatmap extends StatefulWidget {
  final Map<DateTime, int> dailyCounts;
  final Map<DateTime, int>? dailyLevels;
  final Map<DateTime, String>? dailyTooltips;
  final Color? baseColor;
  final int weekCount;
  final DateTime? endDate;
  final ValueChanged<DateTime>? onDayTapped;
  final bool showLegend;
  final bool showDayLabels;
  final bool showMonthLabels;

  const ContributionHeatmap({
    super.key,
    required this.dailyCounts,
    this.dailyLevels,
    this.dailyTooltips,
    this.baseColor,
    this.weekCount = 20,
    this.endDate,
    this.onDayTapped,
    this.showLegend = true,
    this.showDayLabels = true,
    this.showMonthLabels = true,
  });

  @override
  State<ContributionHeatmap> createState() => _ContributionHeatmapState();
}

class _ContributionHeatmapState extends State<ContributionHeatmap> {
  final ScrollController _scrollController = ScrollController();
  DateTime? _selectedDate;
  int? _selectedCount;
  String? _selectedTooltip;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Color _cellColor(BuildContext context, int level, bool isFuture, Color activeColor) {
    if (isFuture) {
      return Colors.transparent;
    }
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final emptyColor = isDark ? const Color(0xFF22272E) : const Color(0xFFEBEDF0);
    if (level <= 0) {
      return emptyColor;
    }

    final hsl = HSLColor.fromColor(activeColor);
    final vibrantColor = isDark && hsl.lightness < 0.40
        ? hsl.withLightness((hsl.lightness + 0.18).clamp(0.0, 0.85)).toColor()
        : activeColor;

    if (level == 1) {
      return Color.lerp(emptyColor, vibrantColor, isDark ? 0.46 : 0.38)!;
    }
    if (level == 2) {
      return Color.lerp(emptyColor, vibrantColor, isDark ? 0.68 : 0.60)!;
    }
    if (level == 3) {
      return Color.lerp(emptyColor, vibrantColor, isDark ? 0.86 : 0.82)!;
    }
    return vibrantColor;
  }

  @override
  Widget build(BuildContext context) {
    final s = strings.value;
    final scheme = Theme.of(context).colorScheme;
    final activeColor = widget.baseColor ?? const Color(0xFF22C55E); // GitHub Green

    final now = widget.endDate ?? DateTime.now();
    final today = dayStart(now);

    // Pazartesi haftanın ilk günü (weekday = 1)
    final endMonday = DateTime(today.year, today.month, today.day - (today.weekday - 1));
    final startMonday = DateTime(endMonday.year, endMonday.month, endMonday.day - ((widget.weekCount - 1) * 7));

    const double cellSize = 13.0;
    const double cellSpacing = 3.5;
    const double colWidth = cellSize + cellSpacing;
    const double rowHeight = cellSize + cellSpacing;

    // Ay etiketleri tespiti
    final monthLabels = <int, String>{}; // colIndex -> Month name
    String? lastMonthName;
    for (int c = 0; c < widget.weekCount; c++) {
      final colMonday = DateTime(startMonday.year, startMonday.month, startMonday.day + (c * 7));
      // Sütundaki günlerden biri ayın ilk haftası mı?
      for (int r = 0; r < 7; r++) {
        final d = DateTime(colMonday.year, colMonday.month, colMonday.day + r);
        if (d.day <= 7) {
          final mName = _monthShortName(d.month, s.isTr);
          if (mName != lastMonthName) {
            monthLabels[c] = mName;
            lastMonthName = mName;
            break;
          }
        }
      }
    }

    final dayNames = s.isTr
        ? ['Pzt', '', 'Çar', '', 'Cum', '', '']
        : ['Mon', '', 'Wed', '', 'Fri', '', ''];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Isı haritası ve sol gün etiketleri
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Sol gün etiketleri (Pzt, Çar, Cum)
            if (widget.showDayLabels)
              Padding(
                padding: EdgeInsets.only(
                  top: widget.showMonthLabels ? 22 : 0,
                  right: 6,
                ),
                child: Column(
                  children: List.generate(7, (r) {
                    return SizedBox(
                      height: rowHeight,
                      width: 24,
                      child: Text(
                        dayNames[r],
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w600,
                          color: scheme.onSurfaceVariant.withValues(alpha: 0.65),
                        ),
                        textAlign: TextAlign.end,
                      ),
                    );
                  }),
                ),
              ),

            // Kaydırılabilir GitHub ızgarası
            Expanded(
              child: SingleChildScrollView(
                controller: _scrollController,
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Ay başlıkları
                      if (widget.showMonthLabels)
                        SizedBox(
                          height: 20,
                          width: widget.weekCount * colWidth,
                          child: Stack(
                            children: monthLabels.entries.map((entry) {
                              return Positioned(
                                left: entry.key * colWidth,
                                child: Text(
                                  entry.value,
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w600,
                                    color: scheme.onSurfaceVariant.withValues(alpha: 0.8),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ),

                      // 7 satır x N sütun kareler
                      Row(
                        children: List.generate(widget.weekCount, (col) {
                          final colMonday = DateTime(startMonday.year, startMonday.month, startMonday.day + (col * 7));
                          return Padding(
                            padding: const EdgeInsets.only(right: cellSpacing),
                            child: Column(
                              children: List.generate(7, (row) {
                                final cellDate = DateTime(colMonday.year, colMonday.month, colMonday.day + row);
                                final isToday = cellDate.year == today.year &&
                                    cellDate.month == today.month &&
                                    cellDate.day == today.day;
                                final isFuture = cellDate.isAfter(today);
                                final normalizedDay = dayStart(cellDate);
                                final count = widget.dailyCounts[normalizedDay] ?? 0;
                                final isSelected = _selectedDate != null &&
                                    _selectedDate!.year == cellDate.year &&
                                    _selectedDate!.month == cellDate.month &&
                                    _selectedDate!.day == cellDate.day;

                                final level = widget.dailyLevels != null
                                    ? (widget.dailyLevels![normalizedDay] ?? 0).clamp(0, 4)
                                    : (count == 0
                                        ? 0
                                        : count == 1
                                            ? 1
                                            : count == 2
                                                ? 2
                                                : count == 3
                                                    ? 3
                                                    : 4);
                                final tooltipMsg = widget.dailyTooltips?[normalizedDay] ??
                                    '$count ${s.isTr ? "kayıt" : "logs"}';
                                final bg = _cellColor(context, level, isFuture, activeColor);

                                return Padding(
                                  padding: const EdgeInsets.only(bottom: cellSpacing),
                                  child: Tooltip(
                                    message: isFuture
                                        ? ''
                                        : '${fmtDateShort(cellDate)}: $tooltipMsg',
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(3),
                                      onTap: isFuture
                                          ? null
                                          : () {
                                              setState(() {
                                                _selectedDate = cellDate;
                                                _selectedCount = count;
                                                _selectedTooltip = tooltipMsg;
                                              });
                                              widget.onDayTapped?.call(cellDate);
                                            },
                                      child: Container(
                                        width: cellSize,
                                        height: cellSize,
                                        decoration: BoxDecoration(
                                          color: bg,
                                          borderRadius: BorderRadius.circular(3),
                                          border: isSelected
                                              ? Border.all(
                                                  color: scheme.primary,
                                                  width: 2,
                                                )
                                              : (isToday
                                                  ? Border.all(
                                                      color: Colors.amber.shade600,
                                                      width: 1.5,
                                                    )
                                                  : (isFuture
                                                      ? Border.all(
                                                          color: scheme.outlineVariant
                                                              .withValues(alpha: 0.15),
                                                          width: 0.5,
                                                        )
                                                      : (level == 0
                                                          ? Border.all(
                                                              color: Theme.of(context).brightness == Brightness.dark
                                                                  ? Colors.white.withValues(alpha: 0.08)
                                                                  : Colors.black.withValues(alpha: 0.06),
                                                              width: 0.5,
                                                            )
                                                          : null))),
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              }),
                            ),
                          );
                        }),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 10),

        // Alt Satır: Seçilen gün bilgisi ve GitHub Lejantı
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Seçilen gün veya bugün detayı
            Expanded(
              child: _selectedDate != null
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: _selectedDate != null
                                ? _cellColor(
                                    context,
                                    widget.dailyLevels != null
                                        ? (widget.dailyLevels![dayStart(_selectedDate!)] ?? 0).clamp(0, 4)
                                        : (_selectedCount == 0 ? 0 : (_selectedCount! >= 4 ? 4 : _selectedCount!)),
                                    false,
                                    activeColor,
                                  )
                                : activeColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            '${fmtDateShort(_selectedDate!)}: ${_selectedTooltip ?? "$_selectedCount ${s.isTr ? "kayıt" : "logs"}"}',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.bold,
                              color: scheme.onSurface,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    )
                  : Text(
                      '${widget.dailyCounts.length} ${s.totalActiveDays.toLowerCase()}',
                      style: TextStyle(
                        fontSize: 11,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
            ),

            // Lejant: Daha az [ ⬛ 🟩 🟩 🟩 🟩 ] Daha çok
            if (widget.showLegend)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    s.heatmapLess,
                    style: TextStyle(
                      fontSize: 10,
                      color: scheme.onSurfaceVariant.withValues(alpha: 0.8),
                    ),
                  ),
                  const SizedBox(width: 4),
                  for (int lvl = 0; lvl <= 4; lvl++) ...[
                    Container(
                      width: 10,
                      height: 10,
                      margin: const EdgeInsets.symmetric(horizontal: 1.5),
                      decoration: BoxDecoration(
                        color: _cellColor(context, lvl, false, activeColor),
                        borderRadius: BorderRadius.circular(2),
                        border: lvl == 0
                            ? Border.all(
                                color: Theme.of(context).brightness == Brightness.dark
                                    ? Colors.white.withValues(alpha: 0.12)
                                    : Colors.black.withValues(alpha: 0.08),
                                width: 0.5,
                              )
                            : null,
                      ),
                    ),
                  ],
                  const SizedBox(width: 4),
                  Text(
                    s.heatmapMore,
                    style: TextStyle(
                      fontSize: 10,
                      color: scheme.onSurfaceVariant.withValues(alpha: 0.8),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ],
    );
  }

  String _monthShortName(int month, bool isTr) {
    if (isTr) {
      const trMonths = [
        'Oca', 'Şub', 'Mar', 'Nis', 'May', 'Haz',
        'Tem', 'Ağu', 'Eyl', 'Eki', 'Kas', 'Ara'
      ];
      return trMonths[month - 1];
    } else {
      const enMonths = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
      ];
      return enMonths[month - 1];
    }
  }
}
