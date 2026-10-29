import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../data/models.dart';
import '../../data/store.dart';
import '../../logic/format.dart';
import '../../logic/l10n.dart';
import '../app_font.dart';
import '../todo_edit_page.dart';
import 'todo_complete_sheet.dart';

/// Yapılacak öğesi satırı: onay halkası, başlık, tarih/aktivite/ilerleme alt satırı, kaydırma aksiyonları.
class TodoTile extends StatefulWidget {
  final Todo todo;
  final VoidCallback? onPostponed;
  final VoidCallback? onDeleted;
  final Set<int>? hiddenDueDiffs;

  const TodoTile({
    super.key,
    required this.todo,
    this.onPostponed,
    this.onDeleted,
    this.hiddenDueDiffs,
  });

  @override
  State<TodoTile> createState() => _TodoTileState();
}

class _TodoTileState extends State<TodoTile> with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  bool _isToggling = false;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  String _formatDueLabel(String? dueDate, bool isTr) {
    if (dueDate == null || dueDate.isEmpty) return '';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final due = DateTime.tryParse(dueDate);
    if (due == null) return dueDate;
    final dueDay = DateTime(due.year, due.month, due.day);

    final diff = dueDay.difference(today).inDays;
    if (diff == 0) return isTr ? 'bugün' : 'today';
    if (diff == 1) return isTr ? 'yarın' : 'tomorrow';
    if (diff == -1) return isTr ? 'dün' : 'yesterday';
    if (diff < -1) return isTr ? '${-diff} gün gecikti' : '${-diff} days overdue';
    if (diff <= 6) {
      final pattern = DateFormat.E(isTr ? 'tr_TR' : 'en_US');
      return pattern.format(due);
    }
    final pattern = DateFormat.MMMd(isTr ? 'tr_TR' : 'en_US');
    return pattern.format(due);
  }

  Future<void> _handleCheckTap(BuildContext context, TodoProgress progress) async {
    if (_isToggling) return;

    // Bağlı yapılacak elle işaretlendiğinde "önce göster, sonra yap" sheet'i açılır
    if (widget.todo.isLinked && !progress.isCompleted) {
      await TodoCompleteSheet.show(context, widget.todo);
      return;
    }

    HapticFeedback.lightImpact();
    setState(() => _isToggling = true);

    final willComplete = !progress.isCompleted;
    if (willComplete) {
      _animController.forward();
    } else {
      _animController.reverse();
    }

    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final isTr = strings.value.isTr;

    await Future<void>.delayed(const Duration(milliseconds: 250));
    if (!mounted) return;

    await store.toggleTodo(widget.todo.id);
    if (mounted) setState(() => _isToggling = false);

    if (willComplete && mounted) {
      scaffoldMessenger.hideCurrentSnackBar();
      scaffoldMessenger.showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 4),
          content: Text(
            isTr ? '✓ Tamamlandı: ${widget.todo.title}' : '✓ Completed: ${widget.todo.title}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          action: SnackBarAction(
            label: isTr ? 'Geri al' : 'Undo',
            onPressed: () => store.toggleTodo(widget.todo.id, completed: false),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = strings.value;
    final scheme = Theme.of(context).colorScheme;
    final progress = store.todoProgress(widget.todo);
    final isDone = progress.isCompleted;

    final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final isOverdue = widget.todo.dueDate != null &&
        widget.todo.dueDate!.isNotEmpty &&
        widget.todo.dueDate!.compareTo(todayStr) < 0 &&
        !isDone;
    final isDueToday = widget.todo.dueDate == todayStr && !isDone;

    final today = DateTime.now();
    final todayDay = DateTime(today.year, today.month, today.day);
    final due = widget.todo.dueDate != null ? DateTime.tryParse(widget.todo.dueDate!) : null;
    final diff = due != null ? DateTime(due.year, due.month, due.day).difference(todayDay).inDays : null;
    final shouldHideDue = !isOverdue && diff != null && (widget.hiddenDueDiffs?.contains(diff) ?? false);
    final dueLabel = shouldHideDue ? '' : _formatDueLabel(widget.todo.dueDate, s.isTr);

    return Dismissible(
      key: Key('todo_${widget.todo.id}'),
      background: Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        color: Colors.green.shade600,
        child: Row(
          children: [
            const Icon(Icons.check_circle_outline, color: Colors.white),
            const SizedBox(width: 8),
            Text(
              s.isTr ? 'Tamamla' : 'Complete',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
      secondaryBackground: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        color: Colors.orange.shade700,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text(
              s.isTr ? 'Ertele' : 'Postpone',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.schedule_rounded, color: Colors.white),
          ],
        ),
      ),
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.startToEnd) {
          // Sağa kaydırma: Tamamla
          await _handleCheckTap(context, progress);
          return false; // Satır kayıp gitmesin, listeyi animasyonla güncelle
        } else {
          // Sola kaydırma: Ertele
          await store.postponeTodo(widget.todo.id);
          widget.onPostponed?.call();
          if (context.mounted) {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                duration: const Duration(seconds: 3),
                content: Text(
                  s.isTr
                      ? '"${widget.todo.title}" ertelendi (${widget.todo.dueDate})'
                      : '"${widget.todo.title}" postponed to ${widget.todo.dueDate}',
                ),
              ),
            );
          }
          return false;
        }
      },
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => TodoEditPage(todo: widget.todo)),
          );
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Yuvarlak onay halkası
              Padding(
                padding: const EdgeInsets.only(top: 2, right: 12),
                child: GestureDetector(
                  onTap: () => _handleCheckTap(context, progress),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isDone ? scheme.primary : Colors.transparent,
                      border: Border.all(
                        color: isDone
                            ? scheme.primary
                            : (isOverdue ? scheme.error : scheme.outline),
                        width: 2,
                      ),
                    ),
                    child: isDone
                        ? const Icon(Icons.check, size: 16, color: Colors.white)
                        : null,
                  ),
                ),
              ),

              // Başlık ve alt bilgi
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.todo.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: AppFont.body,
                        fontWeight: FontWeight.w500,
                        decoration: isDone ? TextDecoration.lineThrough : null,
                        color: isDone
                            ? scheme.onSurfaceVariant.withValues(alpha: 0.6)
                            : scheme.onSurface,
                      ),
                    ),

                    const SizedBox(height: 4),

                    // Bilgi satırı: Gün etiketi, bağlı aktivite çipleri, ilerleme
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (dueLabel.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: isOverdue
                                  ? scheme.errorContainer
                                  : (isDueToday
                                      ? scheme.primaryContainer.withValues(alpha: 0.4)
                                      : scheme.surfaceContainerHighest),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              dueLabel,
                              style: TextStyle(
                                fontSize: AppFont.micro,
                                fontWeight: FontWeight.w600,
                                color: isOverdue
                                    ? scheme.onErrorContainer
                                    : (isDueToday ? scheme.primary : scheme.onSurfaceVariant),
                              ),
                            ),
                          ),

                        // Bağlı aktivite çipleri
                        for (final actId in widget.todo.linkedActivityIds)
                          Builder(builder: (c) {
                            final act = store.activity(actId);
                            return Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: scheme.surfaceContainerHighest.withValues(alpha: 0.7),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(act.emoji ?? '🔹', style: const TextStyle(fontSize: 11)),
                                  const SizedBox(width: 4),
                                  Text(
                                    act.name,
                                    style: TextStyle(
                                      fontSize: AppFont.micro,
                                      color: scheme.onSurfaceVariant,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }),

                        // Hedef miktar ve ince ilerleme çubuğu
                        if (widget.todo.isLinked && widget.todo.targetAmount != null) ...[
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 60),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(2),
                              child: LinearProgressIndicator(
                                value: progress.ratio,
                                minHeight: 4,
                                backgroundColor: scheme.surfaceContainerHighest,
                                valueColor: AlwaysStoppedAnimation(
                                  progress.isCompleted ? Colors.green.shade600 : scheme.primary,
                                ),
                              ),
                            ),
                          ),
                          Text(
                            '${fmtNum(progress.currentAmount)}/${fmtNum(widget.todo.targetAmount!)}${progress.unitSymbol != null ? " ${progress.unitSymbol}" : ""}',
                            style: TextStyle(
                              fontSize: AppFont.micro,
                              color: scheme.onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
