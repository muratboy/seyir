import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/models.dart';
import '../../data/store.dart';
import '../../logic/l10n.dart';
import '../app_font.dart';
import '../todos_page.dart';
import 'todo_quick_add_sheet.dart';
import 'todo_tile.dart';

/// Günlük sayfasındaki Yapılacaklar kartı.
class TodayTodosCard extends StatefulWidget {
  const TodayTodosCard({super.key});

  @override
  State<TodayTodosCard> createState() => _TodayTodosCardState();
}

class _TodayTodosCardState extends State<TodayTodosCard> {
  bool _completedExpanded = false;

  bool _isToday(int? ms) {
    if (ms == null) return false;
    final now = DateTime.now();
    final dt = DateTime.fromMillisecondsSinceEpoch(ms);
    return dt.year == now.year && dt.month == now.month && dt.day == now.day;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final s = strings.value;
        final scheme = Theme.of(context).colorScheme;
        final now = DateTime.now();
        final todayStr = DateFormat('yyyy-MM-dd').format(now);

        final allTodos = store.todos;
        final openTodos = <Todo>[];
        final completedToday = <Todo>[];

        final overdue = <Todo>[];
        final today = <Todo>[];
        final dateless = <Todo>[];

        for (final t in allTodos) {
          final p = store.todoProgress(t);
          if (p.isCompleted) {
            if (_isToday(t.doneAt)) {
              completedToday.add(t);
            }
          } else {
            openTodos.add(t);
            if (t.dueDate == null || t.dueDate!.isEmpty) {
              dateless.add(t);
            } else if (t.dueDate!.compareTo(todayStr) < 0) {
              overdue.add(t);
            } else if (t.dueDate == todayStr) {
              today.add(t);
            }
          }
        }

        // Sıralama
        overdue.sort((a, b) => (a.dueDate ?? '').compareTo(b.dueDate ?? ''));
        today.sort((a, b) => a.createdAt.compareTo(b.createdAt));
        dateless.sort((a, b) => a.createdAt.compareTo(b.createdAt));

        // En çok 4 satır: gecikmişler + bugünküler; yer kalırsa tarihsizler
        final displayList = <Todo>[...overdue, ...today];
        if (displayList.length < 4) {
          displayList.addAll(dateless.take(4 - displayList.length));
        }

        // Rozet metni ve stili
        final hasOverdue = overdue.isNotEmpty;
        final hasToday = today.isNotEmpty;
        final showBadge = hasOverdue || hasToday;
        final badgeText = hasOverdue
            ? (s.isTr ? '${overdue.length} gecikmiş' : '${overdue.length} overdue')
            : (s.isTr ? '${today.length} bugün' : '${today.length} today');

        final totalOpen = openTodos.length;

        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          elevation: 0,
          color: scheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.35)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Gösterilecek açık yapılacak yoksa tek satır kompakt kart
                if (displayList.isEmpty) ...[
                  Row(
                    children: [
                      Icon(Icons.checklist_rounded, size: 20, color: scheme.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          s.isTr ? 'Yapılacaklar' : 'To-dos',
                          style: const TextStyle(
                            fontSize: AppFont.subtitle,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (totalOpen > 0) ...[
                        TextButton(
                          style: TextButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                          ),
                          child: Text('${s.isTr ? "Tümü" : "All"} ($totalOpen) ›'),
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => const TodosPage()),
                            );
                          },
                        ),
                        const SizedBox(width: 4),
                      ],
                      FilledButton.tonalIcon(
                        style: FilledButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                        ),
                        icon: const Icon(Icons.add, size: 16),
                        label: Text(s.isTr ? 'Ekle' : 'Add'),
                        onPressed: () => TodoQuickAddSheet.show(context),
                      ),
                    ],
                  ),
                ] else ...[
                  // Başlık Satırı
                  Row(
                    children: [
                      Icon(Icons.checklist_rounded, size: 20, color: scheme.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          s.isTr ? 'Yapılacaklar' : 'To-dos',
                          style: const TextStyle(
                            fontSize: AppFont.subtitle,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (showBadge) ...[
                        const SizedBox(width: 8),
                        // Rozet (yalnızca gecikmiş veya bugünkü varsa)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: hasOverdue
                                ? scheme.errorContainer
                                : scheme.primaryContainer.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            badgeText,
                            style: TextStyle(
                              fontSize: AppFont.micro,
                              fontWeight: FontWeight.bold,
                              color: hasOverdue ? scheme.onErrorContainer : scheme.primary,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),

                  const SizedBox(height: 8),

                  // Satırlar (en çok 4 satır, Bugün kartı olduğu için 'bugün' çipi gizlenir)
                  for (final item in displayList.take(4))
                    TodoTile(
                      key: ValueKey('today_todo_${item.id}'),
                      todo: item,
                      hiddenDueDiffs: const {0},
                    ),

                  const SizedBox(height: 4),

                  // Alt Satır: [Ekle] ve [Tümü (n) ›]
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      TextButton.icon(
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                        ),
                        icon: const Icon(Icons.add, size: 18),
                        label: Text(s.isTr ? 'Ekle' : 'Add'),
                        onPressed: () => TodoQuickAddSheet.show(context),
                      ),
                      TextButton(
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                        ),
                        child: Text('${s.isTr ? "Tümü" : "All"} ($totalOpen) ›'),
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const TodosPage()),
                          );
                        },
                      ),
                    ],
                  ),
                ],

                // Bugün tamamlananlar katlanır satırı
                if (completedToday.isNotEmpty) ...[
                  const Divider(height: 12),
                  InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => setState(() => _completedExpanded = !_completedExpanded),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                      child: Row(
                        children: [
                          Icon(
                            _completedExpanded ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_right,
                            size: 18,
                            color: scheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              s.isTr
                                  ? '✓ ${completedToday.length} tamamlandı'
                                  : '✓ ${completedToday.length} completed',
                              style: TextStyle(
                                fontSize: AppFont.small,
                                color: scheme.onSurfaceVariant,
                                fontWeight: FontWeight.w500,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_completedExpanded) ...[
                    for (final item in completedToday)
                      Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: TodoTile(
                          key: ValueKey('today_done_${item.id}'),
                          todo: item,
                        ),
                      ),
                  ],
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
