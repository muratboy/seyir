import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/models.dart';
import '../data/store.dart';
import '../logic/format.dart';
import '../logic/l10n.dart';
import '../logic/text_match.dart';
import 'app_font.dart';
import 'common.dart';

/// Yapılacak düzenleme sayfası.
class TodoEditPage extends StatefulWidget {
  final Todo todo;

  const TodoEditPage({super.key, required this.todo});

  @override
  State<TodoEditPage> createState() => _TodoEditPageState();
}

class _TodoEditPageState extends State<TodoEditPage> {
  late TextEditingController _titleController;
  late TextEditingController _noteController;
  late TextEditingController _amountController;

  DateTime? _dueDate;
  late List<int> _linkedActivityIds;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.todo.title);
    _noteController = TextEditingController(text: widget.todo.note ?? '');
    _amountController = TextEditingController(
      text: widget.todo.targetAmount != null ? fmtNum(widget.todo.targetAmount!) : '',
    );
    _dueDate = widget.todo.dueDate != null && widget.todo.dueDate!.isNotEmpty
        ? DateTime.tryParse(widget.todo.dueDate!)
        : null;
    _linkedActivityIds = List.from(widget.todo.linkedActivityIds);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _noteController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) return;

    final note = _noteController.text.trim();
    final amountText = _amountController.text.trim();
    final targetAmount = amountText.isNotEmpty ? parseNum(amountText) : null;
    final dueDateStr = _dueDate != null ? DateFormat('yyyy-MM-dd').format(_dueDate!) : null;

    final updated = widget.todo.copyWith(
      title: title,
      note: note.isNotEmpty ? note : null,
      dueDate: dueDateStr,
      targetAmount: targetAmount,
    );

    await store.updateTodo(updated, activityIds: _linkedActivityIds);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _delete() async {
    final s = strings.value;
    final deleted = await store.deleteTodo(widget.todo.id);
    if (mounted && deleted != null) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(s.isTr ? 'Yapılacak silindi' : 'To-do deleted'),
          action: SnackBarAction(
            label: s.isTr ? 'Geri al' : 'Undo',
            onPressed: () => store.restoreTodo(deleted.$1, deleted.$2),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final s = strings.value;
        final scheme = Theme.of(context).colorScheme;
        final progress = store.todoProgress(widget.todo);
        final isDone = progress.isCompleted;

        return Scaffold(
          appBar: AppBar(
            title: Text(s.isTr ? 'Yapılacak Düzenle' : 'Edit To-do'),
            actions: [
              IconButton(
                tooltip: s.isTr ? 'Sil' : 'Delete',
                icon: const Icon(Icons.delete_outline),
                onPressed: _delete,
              ),
              IconButton(
                tooltip: s.isTr ? 'Kaydet' : 'Save',
                icon: const Icon(Icons.check),
                onPressed: _save,
              ),
            ],
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Başlık
                TextField(
                  controller: _titleController,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    labelText: s.isTr ? 'Başlık' : 'Title',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 14),

                // Not
                TextField(
                  controller: _noteController,
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: s.isTr ? 'Not (isteğe bağlı)' : 'Note (optional)',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 14),

                // Son Gün (Tarih Seçici)
                Card(
                  elevation: 0,
                  color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: ListTile(
                    leading: const Icon(Icons.event_outlined),
                    title: Text(s.isTr ? 'Son Gün' : 'Due Date'),
                    subtitle: Text(
                      _dueDate != null
                          ? DateFormat.yMMMMd(s.isTr ? 'tr_TR' : 'en_US').format(_dueDate!)
                          : (s.isTr ? 'Tarihsiz' : 'No date'),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_dueDate != null)
                          IconButton(
                            icon: const Icon(Icons.clear, size: 20),
                            onPressed: () => setState(() => _dueDate = null),
                          ),
                        IconButton(
                          icon: const Icon(Icons.calendar_today_rounded, size: 20),
                          onPressed: () async {
                            final now = DateTime.now();
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: _dueDate ?? now,
                              firstDate: now.subtract(const Duration(days: 365)),
                              lastDate: now.add(const Duration(days: 365 * 3)),
                            );
                            if (picked != null) {
                              setState(() => _dueDate = picked);
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Bağlı Aktiviteler Bölümü
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      s.isTr ? 'Bağlı Aktiviteler' : 'Linked Activities',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: AppFont.body),
                    ),
                    TextButton.icon(
                      icon: const Icon(Icons.add, size: 18),
                      label: Text(s.isTr ? 'Aktivite Bağla' : 'Link Activity'),
                      onPressed: () async {
                        final act = await showActivityPicker(
                          context,
                          title: s.isTr ? 'Aktivite Bağla' : 'Link Activity',
                          exclude: _linkedActivityIds.toSet(),
                        );
                        if (act != null) {
                          setState(() => _linkedActivityIds.add(act.id));
                        }
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 6),

                if (_linkedActivityIds.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      s.isTr
                          ? 'Aktivite bağlamak zorunlu değildir. Bağlantısız yapılacaklar elle tamamlanır ve kayıt üretmez.'
                          : 'Linking activities is optional. Unlinked to-dos are completed manually and do not generate records.',
                      style: TextStyle(fontSize: AppFont.small, color: scheme.onSurfaceVariant),
                    ),
                  )
                else
                  for (final actId in _linkedActivityIds)
                    Builder(builder: (c) {
                      final act = store.activity(actId);
                      return Card(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        child: ListTile(
                          leading: Text(act.emoji ?? '🔹', style: const TextStyle(fontSize: 22)),
                          title: Text(act.name),
                          trailing: IconButton(
                            icon: const Icon(Icons.close, size: 20),
                            onPressed: () => setState(() => _linkedActivityIds.remove(actId)),
                          ),
                        ),
                      );
                    }),

                const SizedBox(height: 14),

                // Hedef Miktar
                if (_linkedActivityIds.isNotEmpty) ...[
                  TextField(
                    controller: _amountController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: s.isTr ? 'Hedef Miktar (isteğe bağlı)' : 'Target Amount (optional)',
                      hintText: s.isTr ? 'Boş bırakılırsa ilk bağlı kayıt yeterlidir' : 'Leave empty to complete on first entry',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // İlerleme ve Katkı Veren Kayıtlar
                if (widget.todo.isLinked) ...[
                  Card(
                    elevation: 0,
                    color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                s.isTr ? 'İlerleme' : 'Progress',
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                              Text(
                                widget.todo.targetAmount != null
                                    ? '${fmtNum(progress.currentAmount)} / ${fmtNum(widget.todo.targetAmount!)}${progress.unitSymbol != null ? " ${progress.unitSymbol}" : ""}'
                                    : (progress.contributingEntries.isNotEmpty
                                        ? (s.isTr ? 'Tamamlandı' : 'Completed')
                                        : (s.isTr ? 'Bekliyor' : 'Pending')),
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: isDone ? Colors.green.shade600 : scheme.primary,
                                ),
                              ),
                            ],
                          ),
                          if (widget.todo.targetAmount != null) ...[
                            const SizedBox(height: 8),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: progress.ratio,
                                minHeight: 6,
                                backgroundColor: scheme.surfaceContainerHighest,
                                valueColor: AlwaysStoppedAnimation(
                                  isDone ? Colors.green.shade600 : scheme.primary,
                                ),
                              ),
                            ),
                          ],
                          if (progress.contributingEntries.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            Text(
                              s.isTr ? 'Katkı Veren Kayıtlar:' : 'Contributing Entries:',
                              style: TextStyle(
                                fontSize: AppFont.small,
                                fontWeight: FontWeight.w600,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 6),
                            for (final e in progress.contributingEntries.take(5))
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 2),
                                child: Row(
                                  children: [
                                    Text(
                                      DateFormat.Md(s.isTr ? 'tr_TR' : 'en_US').format(e.time),
                                      style: TextStyle(fontSize: AppFont.micro, color: scheme.onSurfaceVariant),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      '+${fmtNum(e.value ?? e.qty)}',
                                      style: const TextStyle(fontSize: AppFont.micro, fontWeight: FontWeight.bold),
                                    ),
                                    if (e.note != null && e.note!.isNotEmpty) ...[
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          e.note!,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(fontSize: AppFont.micro, color: scheme.onSurfaceVariant),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // Tamamla / Geri Aç Düğmesi
                FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  icon: Icon(isDone ? Icons.replay : Icons.check_circle_outline),
                  label: Text(
                    isDone
                        ? (s.isTr ? 'Yeniden Aç' : 'Reopen')
                        : (s.isTr ? 'Tamamlandı Olarak İşaretle' : 'Mark as Completed'),
                  ),
                  onPressed: () async {
                    await store.toggleTodo(widget.todo.id);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
