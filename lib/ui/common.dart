import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/store.dart';
import '../logic/format.dart';
import '../logic/l10n.dart';
import '../logic/text_match.dart';

// ---------------------------------------------------------------- avatar

class ActivityAvatar extends StatelessWidget {
  final int activityId;
  final double size;
  const ActivityAvatar(this.activityId, {super.key, this.size = 40});

  @override
  Widget build(BuildContext context) {
    final a = store.activity(activityId);
    final hue = (a.norm.hashCode % 360).abs().toDouble();
    final dark = Theme.of(context).brightness == Brightness.dark;
    final bg = HSLColor.fromAHSL(1, hue, 0.55, dark ? 0.28 : 0.86).toColor();
    final fg = HSLColor.fromAHSL(1, hue, 0.6, dark ? 0.85 : 0.28).toColor();
    final hasEmoji = a.emoji != null && a.emoji!.isNotEmpty;
    final letter = a.name.isEmpty ? '?' : trUpper(a.name.substring(0, 1));
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
      child: Text(
        hasEmoji ? a.emoji! : letter,
        style: TextStyle(
          fontSize: size * (hasEmoji ? 0.5 : 0.42),
          fontWeight: FontWeight.w700,
          color: fg,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- snackbar

void showSnack(
  BuildContext context,
  String msg, {
  VoidCallback? undo,
  List<Goal> achieved = const [],
  List<Goal> exceeded = const [],
}) {
  final m = ScaffoldMessenger.of(context);
  m.hideCurrentSnackBar();
  var text = msg;
  if (achieved.isNotEmpty) {
    text += '\n🎉 Tebrikler! "${achieved.map((g) => g.name).join('", "')}" hedefine ulaştın!';
  }
  if (exceeded.isNotEmpty) {
    text += '\n⚠️ Dikkat! "${exceeded.map((g) => g.name).join('", "')}" limiti aşıldı!';
  }
  m.showSnackBar(SnackBar(
    content: Text(text),
    persist: false,
    duration: Duration(seconds: (achieved.isNotEmpty || exceeded.isNotEmpty) ? 6 : 4),
    action: undo == null ? null : SnackBarAction(label: 'Geri al', onPressed: undo),
  ));
}

Future<bool> confirm(
  BuildContext context,
  String title,
  String message, {
  String ok = 'Sil',
  bool destructive = true,
}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Vazgeç')),
        FilledButton(
          style: destructive
              ? FilledButton.styleFrom(backgroundColor: Theme.of(c).colorScheme.error)
              : null,
          onPressed: () => Navigator.pop(c, true),
          child: Text(ok),
        ),
      ],
    ),
  );
  return r ?? false;
}

class SectionTitle extends StatelessWidget {
  final String text;
  final Widget? trailing;
  const SectionTitle(this.text, {super.key, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- miktar alanı

class QtyField extends StatefulWidget {
  final double value;
  final ValueChanged<double> onChanged;
  final double width;
  const QtyField({super.key, required this.value, required this.onChanged, this.width = 72});

  @override
  State<QtyField> createState() => _QtyFieldState();
}

class _QtyFieldState extends State<QtyField> {
  late final _c = TextEditingController(text: fmtNum(widget.value));

  @override
  void didUpdateWidget(QtyField old) {
    super.didUpdateWidget(old);
    if (parseNum(_c.text) != widget.value) _c.text = fmtNum(widget.value);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.width,
      child: TextField(
        controller: _c,
        textAlign: TextAlign.center,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        decoration: const InputDecoration(
          isDense: true,
          contentPadding: EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        ),
        onTap: () => _c.selection = TextSelection(baseOffset: 0, extentOffset: _c.text.length),
        onChanged: (t) {
          final v = parseNum(t);
          if (v != null && v > 0) widget.onChanged(v);
        },
      ),
    );
  }
}

// ---------------------------------------------------------------- kare ızgara boyama

class GridPainterWidget extends StatefulWidget {
  final int rows;
  final int cols;
  final double currentQty;
  final ValueChanged<double> onChanged;

  const GridPainterWidget({
    super.key,
    required this.rows,
    required this.cols,
    required this.currentQty,
    required this.onChanged,
  });

  @override
  State<GridPainterWidget> createState() => _GridPainterWidgetState();
}

class _GridPainterWidgetState extends State<GridPainterWidget> {
  final GlobalKey _gridKey = GlobalKey();

  void _handleTouch(Offset localPos) {
    final renderBox = _gridKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    final size = renderBox.size;
    final cellWidth = size.width / widget.cols;
    final cellHeight = size.height / widget.rows;

    final col = (localPos.dx / cellWidth).floor().clamp(0, widget.cols - 1);
    final row = (localPos.dy / cellHeight).floor().clamp(0, widget.rows - 1);
    final index = row * widget.cols + col + 1; // 1-indexed

    if (index != widget.currentQty.round()) {
      widget.onChanged(index.toDouble());
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = strings.value;
    final scheme = Theme.of(context).colorScheme;
    final count = widget.currentQty.round();
    final total = widget.rows * widget.cols;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Text(
                '🔲 $count ${s.paintedCount}',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: scheme.primary,
                ),
              ),
              const Spacer(),
              if (count > 0)
                TextButton(
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  onPressed: () => widget.onChanged(0),
                  child: Text(s.isTr ? 'Temizle' : 'Clear', style: const TextStyle(fontSize: 12)),
                ),
              TextButton(
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                onPressed: () => widget.onChanged((count + total).toDouble()),
                child: Text('+$total', style: const TextStyle(fontSize: 12)),
              ),
            ],
          ),
        ),
        GestureDetector(
          key: _gridKey,
          onTapDown: (details) => _handleTouch(details.localPosition),
          onPanUpdate: (details) => _handleTouch(details.localPosition),
          child: AspectRatio(
            aspectRatio: widget.cols / widget.rows,
            child: Container(
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: scheme.outlineVariant),
              ),
              padding: const EdgeInsets.all(6),
              child: Column(
                children: List.generate(widget.rows, (r) {
                  return Expanded(
                    child: Row(
                      children: List.generate(widget.cols, (c) {
                        final idx = r * widget.cols + c + 1;
                        final isPainted = idx <= count;
                        return Expanded(
                          child: Container(
                            margin: const EdgeInsets.all(3),
                            decoration: BoxDecoration(
                              color: isPainted ? scheme.primary : scheme.surfaceContainerLow,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: isPainted
                                    ? scheme.primary
                                    : scheme.outlineVariant.withValues(alpha: 0.5),
                                width: isPainted ? 1.5 : 1,
                              ),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              '$idx',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: isPainted
                                    ? scheme.onPrimary
                                    : scheme.onSurfaceVariant.withValues(alpha: 0.7),
                              ),
                            ),
                          ),
                        );
                      }),
                    ),
                  );
                }),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------- çoktan seçmeli miktar

class ChoiceChipsQtyWidget extends StatelessWidget {
  final List<double> choices;
  final double currentQty;
  final ValueChanged<double> onChanged;

  const ChoiceChipsQtyWidget({
    super.key,
    required this.choices,
    required this.currentQty,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final list = choices.isEmpty ? [1.0, 2.0, 3.0, 4.0, 5.0] : choices;

    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: [
        for (final val in list)
          FilterChip(
            selected: currentQty == val,
            label: Text('+${fmtNum(val)}', style: const TextStyle(fontWeight: FontWeight.bold)),
            onSelected: (_) => onChanged(val),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------- ölçü seçici

/// "Çay" seçildiğinde çıkan seçenekler: Çay bardağı, Demlik, Su bardağı... + miktar.
class MeasureQtyPicker extends StatefulWidget {
  final int? activityId;
  final int? measureId;
  final double qty;
  final void Function(int? measureId, double qty) onChanged;

  const MeasureQtyPicker({
    super.key,
    required this.activityId,
    required this.measureId,
    required this.qty,
    required this.onChanged,
  });

  @override
  State<MeasureQtyPicker> createState() => _MeasureQtyPickerState();
}

class _MeasureQtyPickerState extends State<MeasureQtyPicker> {
  bool _showAll = false;
  String? _modeOverride;
  int? _lastMeasureId;

  Widget _chip(Measure m) {
    final u = store.unit(m.unitId);
    final selected = widget.measureId == m.id;
    return ChoiceChip(
      selected: selected,
      label: Text.rich(TextSpan(children: [
        TextSpan(text: m.name),
        TextSpan(
          text: '  ${fmtNum(m.amount)} ${u.symbol}',
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ])),
      onSelected: (_) => widget.onChanged(selected ? null : m.id, selected ? 1 : widget.qty),
    );
  }

  @override
  Widget build(BuildContext context) {
    final (used, others) = store.measuresFor(widget.activityId);
    final selectedOther = others.where((m) => m.id == widget.measureId).toList();
    final showOthers = used.isEmpty || _showAll;
    final m = store.measureById(widget.measureId);
    final scheme = Theme.of(context).colorScheme;

    if (m != null && _lastMeasureId != m.id) {
      _lastMeasureId = m.id;
      _modeOverride = null;
    }
    final effectiveMode = m != null ? (_modeOverride ?? m.qtyMode) : 'stepper';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final x in used) _chip(x),
            if (!showOthers) ...[
              for (final x in selectedOther) _chip(x),
              ActionChip(
                avatar: const Icon(Icons.expand_more, size: 18),
                label: const Text('Diğer'),
                onPressed: () => setState(() => _showAll = true),
              ),
            ],
            if (showOthers) for (final x in others) _chip(x),
            ActionChip(
              avatar: const Icon(Icons.add, size: 18),
              label: const Text('Yeni ölçü'),
              onPressed: () async {
                final st = widget.activityId == null ? null : store.stats[widget.activityId];
                final nm = await showMeasureDialog(context, suggestedDim: st?.mainDim);
                if (nm != null) widget.onChanged(nm.id, 1);
              },
            ),
          ],
        ),
        if (m != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${m.name} = ${fmtAmount(m.amount * widget.qty * store.unit(m.unitId).factor, store.unit(m.unitId).dim, customUnit: store.unit(m.unitId))}',
                          style: TextStyle(fontWeight: FontWeight.bold, color: scheme.primary),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: Icon(Icons.pin_outlined, size: 20, color: effectiveMode == 'stepper' ? scheme.primary : scheme.outline),
                        tooltip: 'Klavye / Stepper',
                        onPressed: () => setState(() => _modeOverride = 'stepper'),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: Icon(Icons.touch_app_outlined, size: 20, color: effectiveMode == 'choices' ? scheme.primary : scheme.outline),
                        tooltip: 'Çoktan Seçmeli',
                        onPressed: () => setState(() => _modeOverride = 'choices'),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: Icon(Icons.grid_view_outlined, size: 20, color: effectiveMode == 'grid' ? scheme.primary : scheme.outline),
                        tooltip: 'Izgara Boyama',
                        onPressed: () => setState(() => _modeOverride = 'grid'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (effectiveMode == 'grid') ...[
                    GridPainterWidget(
                      rows: m.gridRows,
                      cols: m.gridCols,
                      currentQty: widget.qty,
                      onChanged: (q) => widget.onChanged(m.id, q),
                    ),
                  ] else if (effectiveMode == 'choices') ...[
                    ChoiceChipsQtyWidget(
                      choices: m.choiceList,
                      currentQty: widget.qty,
                      onChanged: (q) => widget.onChanged(m.id, q),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        IconButton.filledTonal(
                          icon: const Icon(Icons.remove),
                          onPressed: () {
                            final q = widget.qty;
                            widget.onChanged(m.id, q > 1 ? q - 1 : (q > 0.5 ? 0.5 : q));
                          },
                        ),
                        const SizedBox(width: 6),
                        QtyField(value: widget.qty, onChanged: (v) => widget.onChanged(m.id, v)),
                        const SizedBox(width: 6),
                        IconButton.filledTonal(
                          icon: const Icon(Icons.add),
                          onPressed: () {
                            final q = widget.qty;
                            widget.onChanged(m.id, q < 1 ? 1 : q + 1);
                          },
                        ),
                      ],
                    ),
                  ] else ...[
                    Row(
                      children: [
                        IconButton.filledTonal(
                          icon: const Icon(Icons.remove),
                          onPressed: () {
                            final q = widget.qty;
                            widget.onChanged(m.id, q > 1 ? q - 1 : (q > 0.5 ? 0.5 : q));
                          },
                        ),
                        const SizedBox(width: 6),
                        QtyField(value: widget.qty, onChanged: (v) => widget.onChanged(m.id, v)),
                        const SizedBox(width: 6),
                        IconButton.filledTonal(
                          icon: const Icon(Icons.add),
                          onPressed: () {
                            final q = widget.qty;
                            widget.onChanged(m.id, q < 1 ? 1 : q + 1);
                          },
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------- ölçü diyaloğu

const _defaultUnitForDim = {
  'volume': 'l',
  'mass': 'g',
  'time': 'dk',
  'count': 'adet',
  'distance': 'km',
  'energy': 'kcal',
};

/// Yeni ölçü oluşturur ya da [existing] ölçüyü düzenler.
Future<Measure?> showMeasureDialog(
  BuildContext context, {
  Measure? existing,
  String? suggestedDim,
}) {
  final s = strings.value;
  final name = TextEditingController(text: existing?.name ?? '');
  final amount = TextEditingController(text: existing == null ? '1' : fmtNum(existing.amount));
  var unitId = existing?.unitId ??
      _defaultUnitForDim[suggestedDim] ??
      (suggestedDim != null && store.customUnits.any((u) => u.id == suggestedDim)
          ? suggestedDim
          : 'l');
  var qtyMode = existing?.qtyMode ?? 'stepper';
  final choicesCtrl = TextEditingController(text: existing?.choices ?? '1,2,3,4,5');
  var gridRows = existing?.gridRows ?? 2;
  var gridCols = existing?.gridCols ?? 5;
  String? error;

  return showDialog<Measure>(
    context: context,
    builder: (c) => StatefulBuilder(builder: (c, setS) {
      final u = store.unit(unitId);
      final a = parseNum(amount.text);
      final n = name.text.trim();
      return AlertDialog(
        title: Text(existing == null ? s.newMeasure : (s.isTr ? 'Ölçüyü Düzenle' : 'Edit Measure')),
        content: SingleChildScrollView(
          padding: const EdgeInsets.only(top: 12, bottom: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: name,
                autofocus: existing == null,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: s.measureName,
                  hintText: s.isTr ? 'örn. Çay bardağı, Demlik' : 'e.g. Cup, Pot',
                ),
                onChanged: (_) => setS(() {}),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: amount,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        labelText: s.measureAmount,
                        hintText: '0,7',
                      ),
                      onChanged: (_) => setS(() {}),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 3,
                    child: DropdownButtonFormField<String>(
                      initialValue: unitId,
                      isExpanded: true,
                      decoration: InputDecoration(labelText: s.unit),
                      items: [
                        for (final x in store.allUnits)
                          DropdownMenuItem(
                            value: x.id,
                            child: Text('${x.name} (${x.symbol})', overflow: TextOverflow.ellipsis),
                          ),
                        DropdownMenuItem(
                          value: '__new',
                          child: Text('+ ${s.newUnit}…', overflow: TextOverflow.ellipsis),
                        ),
                      ],
                      onChanged: (v) async {
                        if (v == '__new') {
                          final nu = await showUnitDialog(c);
                          setS(() => unitId = nu?.id ?? unitId);
                        } else if (v != null) {
                          setS(() => unitId = v);
                        }
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              if (n.isNotEmpty && a != null && a > 0)
                Text(
                  '1 $n = ${fmtNum(a)} ${u.symbol}',
                  style: Theme.of(c).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
                ),

              const Divider(height: 24),

              // Quantity Input Mode selection
              Text(
                s.qtyModeTitle,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(c).colorScheme.primary,
                ),
              ),
              const SizedBox(height: 8),
              SegmentedButton<String>(
                segments: [
                  ButtonSegment(
                    value: 'stepper',
                    icon: const Icon(Icons.pin_outlined, size: 16),
                    label: Text(s.qtyModeStepper),
                  ),
                  ButtonSegment(
                    value: 'choices',
                    icon: const Icon(Icons.touch_app_outlined, size: 16),
                    label: Text(s.qtyModeChoices),
                  ),
                  ButtonSegment(
                    value: 'grid',
                    icon: const Icon(Icons.grid_view_outlined, size: 16),
                    label: Text(s.qtyModeGrid),
                  ),
                ],
                selected: {qtyMode},
                onSelectionChanged: (set) => setS(() => qtyMode = set.first),
              ),

              if (qtyMode == 'choices') ...[
                const SizedBox(height: 10),
                TextField(
                  controller: choicesCtrl,
                  decoration: InputDecoration(
                    labelText: s.choicesLabel,
                    hintText: s.choicesHint,
                  ),
                ),
              ],

              if (qtyMode == 'grid') ...[
                const SizedBox(height: 10),
                Text(s.gridSize, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text('2x5 (10)'),
                      selected: gridRows == 2 && gridCols == 5,
                      onSelected: (_) => setS(() { gridRows = 2; gridCols = 5; }),
                    ),
                    ChoiceChip(
                      label: const Text('3x4 (12)'),
                      selected: gridRows == 3 && gridCols == 4,
                      onSelected: (_) => setS(() { gridRows = 3; gridCols = 4; }),
                    ),
                    ChoiceChip(
                      label: const Text('4x5 (20)'),
                      selected: gridRows == 4 && gridCols == 5,
                      onSelected: (_) => setS(() { gridRows = 4; gridCols = 5; }),
                    ),
                  ],
                ),
              ],

              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(error!, style: TextStyle(color: Theme.of(c).colorScheme.error)),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: Text(s.cancel)),
          FilledButton(
            onPressed: () async {
              if (n.isEmpty) return setS(() => error = s.nameRequired);
              if (a == null || a <= 0) return setS(() => error = 'Geçerli bir miktar yaz.');
              Measure m;
              final choicesVal = choicesCtrl.text.trim().isEmpty ? '1,2,3,4,5' : choicesCtrl.text.trim();
              if (existing != null) {
                existing
                  ..name = trCapitalize(n)
                  ..amount = a
                  ..unitId = unitId
                  ..qtyMode = qtyMode
                  ..choices = choicesVal
                  ..gridRows = gridRows
                  ..gridCols = gridCols;
                await store.updateMeasure(existing);
                m = existing;
              } else {
                m = await store.addMeasure(
                  trCapitalize(n),
                  unitId,
                  a,
                  qtyMode: qtyMode,
                  choices: choicesVal,
                  gridRows: gridRows,
                  gridCols: gridCols,
                );
              }
              if (c.mounted) Navigator.pop(c, m);
            },
            child: Text(s.save),
          ),
        ],
      );
    }),
  );
}

Future<Unit?> showUnitDialog(BuildContext context) {
  final name = TextEditingController();
  final symbol = TextEditingController();
  return showDialog<Unit>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('Yeni birim'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Listede olmayan bir şeyi saymak için (örn. sayfa, soru, tekrar).',
          ),
          const SizedBox(height: 12),
          TextField(
            controller: name,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Birim adı', hintText: 'örn. Sayfa'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: symbol,
            decoration:
                const InputDecoration(labelText: 'Kısaltma (isteğe bağlı)', hintText: 'örn. sf'),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('Vazgeç')),
        FilledButton(
          onPressed: () async {
            final n = name.text.trim();
            if (n.isEmpty) return;
            final s = symbol.text.trim().isEmpty ? n.toLowerCase() : symbol.text.trim();
            final u = await store.addUnit(trCapitalize(n), s);
            if (c.mounted) Navigator.pop(c, u);
          },
          child: const Text('Ekle'),
        ),
      ],
    ),
  );
}

// ---------------------------------------------------------------- kayıt türü seçici

/// Arama yapılabilen kayıt türü seçici. İstenirse yazılan metinle yeni tür oluşturur.
Future<Activity?> showActivityPicker(
  BuildContext context, {
  String title = 'Seç',
  Set<int> exclude = const {},
  bool allowCreate = true,
}) {
  return showModalBottomSheet<Activity>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (c) => _ActivityPickerSheet(title: title, exclude: exclude, allowCreate: allowCreate),
  );
}

class _ActivityPickerSheet extends StatefulWidget {
  final String title;
  final Set<int> exclude;
  final bool allowCreate;
  const _ActivityPickerSheet({required this.title, required this.exclude, required this.allowCreate});

  @override
  State<_ActivityPickerSheet> createState() => _ActivityPickerSheetState();
}

class _ActivityPickerSheetState extends State<_ActivityPickerSheet> {
  final _c = TextEditingController();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  List<Activity> get _items {
    final q = _c.text.trim();
    Iterable<Activity> list;
    if (q.isEmpty) {
      final all = store.activities.values.toList()
        ..sort((a, b) => (store.stats[b.id]?.count ?? 0).compareTo(store.stats[a.id]?.count ?? 0));
      list = all;
    } else {
      list = store.suggest(q, limit: 30);
    }
    return list.where((a) => !widget.exclude.contains(a.id)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final q = _c.text.trim();
    final items = _items;
    final canCreate = widget.allowCreate && q.isNotEmpty && store.exactMatch(q) == null;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(widget.title, style: Theme.of(context).textTheme.titleMedium),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _c,
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Ara ya da yeni yaz',
                ),
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) async {
                  if (canCreate) {
                    final a = await store.addActivity(q);
                    if (context.mounted) Navigator.pop(context, a);
                  } else if (items.isNotEmpty) {
                    Navigator.pop(context, items.first);
                  }
                },
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView(
                children: [
                  if (canCreate)
                    ListTile(
                      leading: const CircleAvatar(child: Icon(Icons.add)),
                      title: Text('"${trCapitalize(q)}" oluştur'),
                      onTap: () async {
                        final a = await store.addActivity(q);
                        if (context.mounted) Navigator.pop(context, a);
                      },
                    ),
                  for (final a in items)
                    ListTile(
                      leading: ActivityAvatar(a.id),
                      title: Text(a.name),
                      subtitle: Text('${store.stats[a.id]?.count ?? 0} kayıt'),
                      onTap: () => Navigator.pop(context, a),
                    ),
                  if (items.isEmpty && !canCreate)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('Henüz kayıt yok.', textAlign: TextAlign.center),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- ilerleme halkası

class ProgressRing extends StatelessWidget {
  final double ratio;
  final double size;
  final bool done;
  final bool isLimit;
  final bool isExceeded;
  final Widget? child;
  const ProgressRing({
    super.key,
    required this.ratio,
    this.size = 48,
    this.done = false,
    this.isLimit = false,
    this.isExceeded = false,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final Color color;
    if (isLimit) {
      if (isExceeded) {
        color = Colors.red.shade600;
      } else if (ratio > 0.8) {
        color = Colors.orange.shade600;
      } else {
        color = Colors.green.shade600;
      }
    } else {
      color = done ? Colors.green.shade600 : scheme.primary;
    }

    final Widget centerWidget = child ??
        (isLimit
            ? (isExceeded
                ? Icon(Icons.warning_amber_rounded, color: color, size: size * 0.5)
                : Icon(Icons.shield_outlined, color: color, size: size * 0.45))
            : (done
                ? Icon(Icons.check_rounded, color: color, size: size * 0.5)
                : Text(
                    '%${(ratio * 100).floor()}',
                    style: TextStyle(fontSize: size * 0.24, fontWeight: FontWeight.w700),
                  )));

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox.expand(
            child: CircularProgressIndicator(
              value: ratio.clamp(0.0, 1.0),
              strokeWidth: size / 9,
              backgroundColor: scheme.surfaceContainerHighest,
              color: color,
              strokeCap: StrokeCap.round,
            ),
          ),
          centerWidget,
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- emoji seçici

const emojiCategoryList = <(String, String, List<String>)>[
  ('İçecekler', 'Drinks', ['🍵', '☕', '💧', '🧃', '🥛', '🥤', '🍺', '🍷', '🍶', '🫖', '🍹', '🧉']),
  ('Yiyecekler', 'Food', ['🍎', '🍌', '🥪', '🥗', '🍕', '🍔', '🍳', '🍲', '🥐', '🍫', '🍉', '🍜', '🍱', '🍰', '🍪']),
  ('Spor & Sağlık', 'Fitness & Health', ['🏃', '🏋️', '🚴', '🧘', '🏊', '🚶', '⚽', '🏸', '🎾', '🥊', '🧗', '💊', '🩺', '🩹', '🦷', '🌿']),
  ('Çalışma & Zihin', 'Study & Work', ['📚', '✍️', '💻', '🎯', '🎓', '📖', '🧪', '📐', '💼', '📊', '📅', '💡', '🎨', '🎹']),
  ('Günlük & Ev', 'Daily & Home', ['😴', '🧹', '🚗', '🛒', '🧺', '🛁', '🪴', '🛠️', '🐕', '🐈', '👶', '🚿', '🍽️', '🔑']),
  ('Semboller & Hobi', 'Symbols & Fun', ['⭐', '❤️', '🔥', '✨', '⚡', '☀️', '🌙', '🎮', '🎬', '🎵', '🧩', '✈️', '📸', '🏆', '💯']),
];

Future<String?> showEmojiPicker(BuildContext context, {String? currentEmoji}) {
  final s = strings.value;
  final customCtrl = TextEditingController();
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (c) => Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 8,
        bottom: MediaQuery.of(c).viewInsets.bottom + 24,
      ),
      child: SizedBox(
        height: MediaQuery.of(c).size.height * 0.65,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    s.chooseEmoji,
                    style: Theme.of(c).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
                if (currentEmoji != null && currentEmoji.isNotEmpty)
                  TextButton.icon(
                    icon: const Icon(Icons.close, size: 18),
                    label: Text(s.noEmoji),
                    onPressed: () => Navigator.pop(c, ''),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: customCtrl,
              decoration: InputDecoration(
                hintText: s.customEmoji,
                prefixIcon: const Icon(Icons.sentiment_satisfied_alt_outlined),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.check),
                  onPressed: () {
                    final t = customCtrl.text.trim();
                    if (t.isNotEmpty) Navigator.pop(c, t);
                  },
                ),
              ),
              onSubmitted: (t) {
                final trm = t.trim();
                if (trm.isNotEmpty) Navigator.pop(c, trm);
              },
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView(
                children: [
                  for (final cat in emojiCategoryList) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        s.isTr ? cat.$1 : cat.$2,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(c).colorScheme.primary,
                        ),
                      ),
                    ),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final emoji in cat.$3)
                          InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () => Navigator.pop(c, emoji),
                            child: Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: currentEmoji == emoji
                                    ? Theme.of(c).colorScheme.primaryContainer
                                    : Theme.of(c).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                                borderRadius: BorderRadius.circular(12),
                                border: currentEmoji == emoji
                                    ? Border.all(color: Theme.of(c).colorScheme.primary, width: 2)
                                    : null,
                              ),
                              alignment: Alignment.center,
                              child: Text(emoji, style: const TextStyle(fontSize: 24)),
                            ),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

Future<void> showActivityEditDialog(BuildContext context, Activity activity) {
  final s = strings.value;
  final nameCtrl = TextEditingController(text: activity.name);
  var curEmoji = activity.emoji ?? '';
  var curCategory = activity.category;
  var curIsHabit = activity.isHabit;
  final goalPcts = <int, double>{};
  for (final g in store.goals) {
    for (final l in g.links) {
      if (l.activityId == activity.id) {
        goalPcts[g.id] = l.pct;
        break;
      }
    }
  }

  return showDialog<void>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, setS) => AlertDialog(
        title: Text(s.edit),
        content: SingleChildScrollView(
          padding: const EdgeInsets.only(top: 12, bottom: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  InkWell(
                    borderRadius: BorderRadius.circular(24),
                    onTap: () async {
                      final chosen = await showEmojiPicker(c, currentEmoji: curEmoji);
                      if (chosen != null) {
                        setS(() => curEmoji = chosen);
                      }
                    },
                    child: Container(
                      width: 54,
                      height: 54,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Theme.of(c).colorScheme.primaryContainer,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        curEmoji.isEmpty
                            ? (activity.name.isNotEmpty ? trUpper(activity.name.substring(0, 1)) : '?')
                            : curEmoji,
                        style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(s.chooseEmoji, style: const TextStyle(fontSize: 12)),
                        TextButton(
                          style: TextButton.styleFrom(padding: EdgeInsets.zero),
                          onPressed: () async {
                            final chosen = await showEmojiPicker(c, currentEmoji: curEmoji);
                            if (chosen != null) setS(() => curEmoji = chosen);
                          },
                          child: Text(curEmoji.isEmpty ? s.chooseEmoji : '$curEmoji Değiştir'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: nameCtrl,
                autofocus: false,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(labelText: s.isTr ? 'Aktivite Adı' : 'Activity Name'),
              ),
              const SizedBox(height: 16),
              Text(
                s.isTr ? 'Kategori & Renk' : 'Category & Color',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: defaultCategories.map((cat) {
                  final sel = (curCategory ?? 'other') == cat.id;
                  return ChoiceChip(
                    avatar: Text(cat.emoji, style: const TextStyle(fontSize: 13)),
                    label: Text(cat.name(s.isTr), style: const TextStyle(fontSize: 12)),
                    selected: sel,
                    onSelected: (_) => setS(() => curCategory = cat.id),
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),
              Card(
                elevation: 0,
                color: curIsHabit
                    ? Theme.of(c).colorScheme.primaryContainer.withValues(alpha: 0.28)
                    : Theme.of(c).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(
                    color: curIsHabit
                        ? Theme.of(c).colorScheme.primary.withValues(alpha: 0.5)
                        : Theme.of(c).colorScheme.outlineVariant.withValues(alpha: 0.4),
                  ),
                ),
                child: SwitchListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                  title: Row(
                    children: [
                      const Text('🔥 ', style: TextStyle(fontSize: 16)),
                      Expanded(
                        child: Text(
                          s.enableHabit,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                  subtitle: Text(
                    s.enableHabitDesc,
                    style: TextStyle(fontSize: 11, color: Theme.of(c).colorScheme.onSurfaceVariant),
                  ),
                  value: curIsHabit,
                  onChanged: (val) => setS(() => curIsHabit = val),
                ),
              ),
              const SizedBox(height: 16),
              const Divider(height: 24),
              Row(
                children: [
                  Icon(Icons.flag_outlined, size: 18, color: Theme.of(c).colorScheme.primary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      s.linkedGoals,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Theme.of(c).colorScheme.primary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (store.goals.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text(
                    s.noGoalsYet,
                    style: TextStyle(color: Theme.of(c).colorScheme.onSurfaceVariant, fontSize: 13),
                  ),
                )
              else
                for (final g in store.goals) ...[
                  Builder(builder: (c) {
                    final isLinked = goalPcts.containsKey(g.id);
                    final pct = goalPcts[g.id] ?? 100.0;
                    final unitSym = store.goalUnitSymbol(g);
                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      color: isLinked
                          ? Theme.of(c).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5)
                          : Theme.of(c).colorScheme.surfaceContainerLow,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(
                          color: isLinked ? Theme.of(c).colorScheme.primary : Theme.of(c).colorScheme.outlineVariant,
                          width: isLinked ? 1.2 : 0.6,
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Icon(
                                  g.isLimit ? Icons.shield_outlined : Icons.flag_outlined,
                                  size: 20,
                                  color: g.isLimit ? Colors.orange.shade700 : Theme.of(c).colorScheme.primary,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(g.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                                      Text(
                                        '${g.isLimit ? "Limit" : "Hedef"}: ${fmtNum(g.target)} $unitSym · ${periodNames[g.period] ?? g.period.name}',
                                        style: TextStyle(fontSize: 11, color: Theme.of(c).colorScheme.onSurfaceVariant),
                                      ),
                                    ],
                                  ),
                                ),
                                Checkbox(
                                  value: isLinked,
                                  onChanged: (val) {
                                    setS(() {
                                      if (val == true) {
                                        goalPcts[g.id] = 100.0;
                                      } else {
                                        goalPcts.remove(g.id);
                                      }
                                    });
                                  },
                                ),
                              ],
                            ),
                            if (isLinked) ...[
                              Row(
                                children: [
                                  Text(
                                    '${s.contributionPct}: %${pct.round()}',
                                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                  ),
                                  Expanded(
                                    child: Slider(
                                      value: pct.clamp(5.0, 100.0),
                                      min: 5,
                                      max: 100,
                                      divisions: 19,
                                      label: '%${pct.round()}',
                                      onChanged: (v) => setS(() => goalPcts[g.id] = v),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  }),
                ],
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: Text(s.cancel)),
          FilledButton(
            onPressed: () async {
              final n = nameCtrl.text.trim();
              if (n.isEmpty) return;
              activity.name = trCapitalize(n);
              activity.rename(trCapitalize(n));
              activity.emoji = curEmoji.trim().isEmpty ? null : curEmoji.trim();
              activity.category = curCategory;
              activity.color = curCategory != null ? getCategoryDef(curCategory).colorValue : null;
              activity.isHabit = curIsHabit;
              await store.updateActivity(activity);
              await store.setActivityGoals(activity.id, goalPcts);
              if (c.mounted) Navigator.pop(c);
            },
            child: Text(s.save),
          ),
        ],
      ),
    ),
  );
}
