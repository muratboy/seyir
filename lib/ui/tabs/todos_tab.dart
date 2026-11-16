import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/models.dart';
import '../../data/store.dart';
import '../../logic/format.dart';
import '../../logic/l10n.dart';
import '../app_font.dart';
import '../components/todo_quick_add_sheet.dart';
import '../components/todo_tile.dart';

/// Yapılacaklar tam liste görünümü: Gruplar (Gecikmiş, Bugün, Yarın, Bu hafta, Daha sonra, Tarihsiz, Tamamlananlar).
class TodosView extends StatefulWidget {
  final bool showFab;

  const TodosView({super.key, this.showFab = true});

  static String tomorrowDateStr({DateTime? now}) {
    final refNow = now ?? DateTime.now();
    return DateFormat('yyyy-MM-dd').format(addDays(refNow, 1));
  }

  static String endOfWeekDateStr({DateTime? now}) {
    final refNow = now ?? DateTime.now();
    final endOfWeek = addDays(refNow, 7 - refNow.weekday);
    return DateFormat('yyyy-MM-dd').format(endOfWeek);
  }

  @override
  State<TodosView> createState() => _TodosViewState();
}

class _TodosViewState extends State<TodosView> {
  bool _completedExpanded = false;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final s = strings.value;
        final scheme = Theme.of(context).colorScheme;
        final now = DateTime.now();
        final todayStr = DateFormat('yyyy-MM-dd').format(now);
        final tomorrowStr = TodosView.tomorrowDateStr(now: now);
        final endOfWeekStr = TodosView.endOfWeekDateStr(now: now);

        final thirtyDaysAgoMs = now.subtract(const Duration(days: 30)).millisecondsSinceEpoch;

        final overdue = <Todo>[];
        final today = <Todo>[];
        final tomorrow = <Todo>[];
        final thisWeek = <Todo>[];
        final later = <Todo>[];
        final dateless = <Todo>[];
        final completed = <Todo>[];

        for (final t in store.todos) {
          final p = store.todoProgress(t);
          if (p.isCompleted) {
            if (t.doneAt == null || t.doneAt! >= thirtyDaysAgoMs) {
              completed.add(t);
            }
          } else {
            final due = t.dueDate;
            if (due == null || due.isEmpty) {
              dateless.add(t);
            } else if (due.compareTo(todayStr) < 0) {
              overdue.add(t);
            } else if (due == todayStr) {
              today.add(t);
            } else if (due == tomorrowStr) {
              tomorrow.add(t);
            } else if (due.compareTo(endOfWeekStr) <= 0) {
              thisWeek.add(t);
            } else {
              later.add(t);
            }
          }
        }

        // Sıralamalar
        overdue.sort((a, b) {
          final c = (a.dueDate ?? '').compareTo(b.dueDate ?? '');
          return c != 0 ? c : a.createdAt.compareTo(b.createdAt);
        });
        today.sort((a, b) => a.createdAt.compareTo(b.createdAt));
        tomorrow.sort((a, b) => a.createdAt.compareTo(b.createdAt));
        thisWeek.sort((a, b) {
          final c = (a.dueDate ?? '').compareTo(b.dueDate ?? '');
          return c != 0 ? c : a.createdAt.compareTo(b.createdAt);
        });
        later.sort((a, b) {
          final c = (a.dueDate ?? '').compareTo(b.dueDate ?? '');
          return c != 0 ? c : a.createdAt.compareTo(b.createdAt);
        });
        dateless.sort((a, b) => a.createdAt.compareTo(b.createdAt));
        completed.sort((a, b) => (b.doneAt ?? 0).compareTo(a.doneAt ?? 0));

        final totalOpen = overdue.length + today.length + tomorrow.length + thisWeek.length + later.length + dateless.length;

        if (totalOpen == 0 && completed.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.checklist_rounded, size: 56, color: scheme.primary.withValues(alpha: 0.5)),
                  const SizedBox(height: 16),
                  Text(
                    s.isTr ? 'Henüz yapılacak bir iş yok' : 'No to-dos yet',
                    style: const TextStyle(fontSize: AppFont.subtitle, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    s.isTr ? 'Gününüzü veya hedeflerinizi planlamak için ilk görevinizi ekleyin.' : 'Add your first task to plan your day or single-step goals.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: AppFont.caption, color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    icon: const Icon(Icons.add),
                    label: Text(s.isTr ? 'Yapılacak Ekle' : 'Add To-do'),
                    onPressed: () => TodoQuickAddSheet.show(context),
                  ),
                ],
              ),
            ),
          );
        }

        Widget buildGroup(
          String title,
          List<Todo> items, {
          Color? titleColor,
          bool isOverdue = false,
          Set<int>? hiddenDueDiffs,
        }) {
          if (items.isEmpty) return const SizedBox.shrink();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
                child: Row(
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: AppFont.small,
                        fontWeight: FontWeight.bold,
                        color: titleColor ?? scheme.onSurfaceVariant,
                        letterSpacing: 0.3,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '(${items.length})',
                      style: TextStyle(
                        fontSize: AppFont.micro,
                        color: titleColor ?? scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              Card(
                margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                elevation: 0,
                color: scheme.surface,
                clipBehavior: Clip.antiAlias,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(
                    color: isOverdue
                        ? scheme.error.withValues(alpha: 0.3)
                        : scheme.outlineVariant.withValues(alpha: 0.3),
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < items.length; i++) ...[
                      if (i > 0)
                        Divider(
                          height: 1,
                          indent: 48,
                          color: scheme.outlineVariant.withValues(alpha: 0.2),
                        ),
                      TodoTile(
                        key: ValueKey('todo_${items[i].id}'),
                        todo: items[i],
                        hiddenDueDiffs: hiddenDueDiffs,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          );
        }

        return Stack(
          children: [
            ListView(
              padding: const EdgeInsets.only(bottom: 96),
              children: [
                buildGroup(
                  s.isTr ? 'Gecikmiş' : 'Overdue',
                  overdue,
                  titleColor: scheme.error,
                  isOverdue: true,
                ),
                buildGroup(
                  s.isTr ? 'Bugün' : 'Today',
                  today,
                  titleColor: scheme.primary,
                  hiddenDueDiffs: const {0},
                ),
                buildGroup(
                  s.isTr ? 'Yarın' : 'Tomorrow',
                  tomorrow,
                  hiddenDueDiffs: const {1},
                ),
                buildGroup(s.isTr ? 'Bu Hafta' : 'This Week', thisWeek),
                buildGroup(s.isTr ? 'Daha Sonra' : 'Later', later),
                buildGroup(s.isTr ? 'Tarihsiz' : 'No Date', dateless),

                // Katlanmış Tamamlananlar
                if (completed.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () => setState(() => _completedExpanded = !_completedExpanded),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                        child: Row(
                          children: [
                            Icon(
                              _completedExpanded ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_right,
                              size: 20,
                              color: scheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              s.isTr
                                  ? 'Tamamlananlar (${completed.length})'
                                  : 'Completed (${completed.length})',
                              style: TextStyle(
                                fontSize: AppFont.small,
                                fontWeight: FontWeight.bold,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (_completedExpanded)
                    Card(
                      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                      elevation: 0,
                      color: scheme.surface,
                      clipBehavior: Clip.antiAlias,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.3)),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (var i = 0; i < completed.length; i++) ...[
                            if (i > 0)
                              Divider(
                                height: 1,
                                indent: 48,
                                color: scheme.outlineVariant.withValues(alpha: 0.2),
                              ),
                            TodoTile(
                              key: ValueKey('todo_${completed[i].id}'),
                              todo: completed[i],
                            ),
                          ],
                        ],
                      ),
                    ),
                ],
              ],
            ),
            if (widget.showFab)
              Positioned(
                bottom: 16,
                right: 16,
                child: FloatingActionButton(
                  onPressed: () => TodoQuickAddSheet.show(context),
                  tooltip: s.isTr ? 'Yeni Yapılacak' : 'New To-do',
                  child: const Icon(Icons.add),
                ),
              ),
          ],
        );
      },
    );
  }
}
