import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../../data/store.dart';
import '../../logic/activity_format_analysis.dart';
import '../../logic/format.dart';
import '../../logic/l10n.dart';
import '../../logic/text_match.dart';
import '../app_font.dart';

/// Bağlı bir yapılacağı tamamlarken açılan "önce göster, sonra yap" onay bottom sheet'i.
class TodoCompleteSheet extends StatefulWidget {
  final Todo todo;

  const TodoCompleteSheet({super.key, required this.todo});

  static Future<bool?> show(BuildContext context, Todo todo) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => TodoCompleteSheet(todo: todo),
    );
  }

  @override
  State<TodoCompleteSheet> createState() => _TodoCompleteSheetState();
}

class _TodoCompleteSheetState extends State<TodoCompleteSheet> {
  late int _selectedActivityId;
  late TextEditingController _amountController;

  @override
  void initState() {
    super.initState();
    _selectedActivityId = widget.todo.linkedActivityIds.firstOrNull ?? 0;

    final progress = store.todoProgress(widget.todo);
    double initialAmount = 1.0;
    if (widget.todo.targetAmount != null) {
      initialAmount = progress.remainingAmount > 0 ? progress.remainingAmount : widget.todo.targetAmount!;
    } else {
      // Aktivitenin hızlı varsayılanı
      final (usedMeasures, otherMeasures) = store.measuresFor(_selectedActivityId);
      final m = usedMeasures.firstOrNull ?? otherMeasures.firstOrNull;
      initialAmount = m?.amount ?? 1.0;
    }

    _amountController = TextEditingController(text: fmtNum(initialAmount));
    _amountController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = strings.value;
    final scheme = Theme.of(context).colorScheme;

    final selectedAct = store.activity(_selectedActivityId);
    final goal = store.todoGoal(widget.todo);
    final baseUnit = (goal.unitId != null && goal.unitId!.isNotEmpty)
        ? goal.unitId!
        : store.activityBaseUnit(_selectedActivityId);
    final unitLabel = (widget.todo.targetAmount == null &&
            store.activityFormat(_selectedActivityId) == ActivityFormat.event &&
            baseUnit == 'adet')
        ? ''
        : store.unit(baseUnit).symbol;

    return Container(
      padding: EdgeInsets.fromLTRB(
        20,
        16,
        20,
        16 + MediaQuery.of(context).viewInsets.bottom,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Çizgi tutamaç
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: scheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 14),

          // Başlık
          Text(
            widget.todo.title,
            style: const TextStyle(
              fontSize: AppFont.subtitle,
              fontWeight: FontWeight.bold,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 6),
          Text(
            s.isTr
                ? 'Bu yapılacak bağlı bir aktiviteye sahiptir. Tamamlamak için kayıt ekleyebilir veya kayıtsız tamamlayabilirsiniz.'
                : 'This to-do is linked to an activity. You can complete it with a new entry or without adding one.',
            style: TextStyle(
              fontSize: AppFont.caption,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),

          // Birden fazla bağlı aktivite varsa seçici
          if (widget.todo.linkedActivityIds.length > 1) ...[
            Text(
              s.isTr ? 'Kayıt eklenecek aktivite:' : 'Activity to log:',
              style: TextStyle(
                fontSize: AppFont.small,
                fontWeight: FontWeight.w600,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final actId in widget.todo.linkedActivityIds)
                  Builder(builder: (c) {
                    final act = store.activity(actId);
                    final isSel = actId == _selectedActivityId;
                    return ChoiceChip(
                      label: Text('${act.emoji ?? "🔹"} ${act.name}'),
                      selected: isSel,
                      onSelected: (_) => setState(() => _selectedActivityId = actId),
                    );
                  }),
              ],
            ),
            const SizedBox(height: 16),
          ],

          // Miktar Düzenleme
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _amountController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: s.isTr ? 'Kaydedilecek Miktar' : 'Amount to Log',
                    suffixText: unitLabel.isNotEmpty ? unitLabel : null,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          // Birincil Seçenek: "[Aktivite] · +X [Birim] kaydet ve tamamla"
          Builder(builder: (c) {
            final amountText = _amountController.text.trim();
            final amountPart = unitLabel.isNotEmpty ? '+$amountText $unitLabel' : '+$amountText';
            return FilledButton.icon(
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              icon: const Icon(Icons.add_task_rounded),
              label: Text(
                '${selectedAct.name} · $amountPart ${s.isTr ? "kaydet ve tamamla" : "log & complete"}'
                    .trim(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              onPressed: () async {
                final val = parseNum(_amountController.text) ?? 1.0;
                await store.completeTodoWithEntry(
                  widget.todo,
                  activityId: _selectedActivityId,
                  amount: val,
                );
                if (context.mounted) {
                  Navigator.pop(context, true);
                }
              },
            );
          }),

          const SizedBox(height: 8),

          // İkincil Seçenek: "Kayıt eklemeden tamamla"
          TextButton(
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
            child: Text(s.isTr ? 'Kayıt eklemeden tamamla' : 'Complete without logging'),
            onPressed: () async {
              await store.toggleTodo(widget.todo.id, completed: true);
              if (context.mounted) {
                Navigator.pop(context, true);
              }
            },
          ),
        ],
      ),
    );
  }
}
