import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../../data/store.dart';
import '../../logic/format.dart';
import '../../logic/l10n.dart';
import '../common.dart';
import '../app_font.dart';

/// Hızlı kısayollar ve günlük yapılacaklar şeridi (Shortcuts & To-Dos)
class TodayQuickShortcuts extends StatelessWidget {
  final DateTime currentDay;
  final Future<void> Function(Activity) onStartTimer;

  const TodayQuickShortcuts({
    super.key,
    required this.currentDay,
    required this.onStartTimer,
  });

  @override
  Widget build(BuildContext context) {
    final s = strings.value;
    final items = store.quickItems;
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionTitle(
          s.quickListTitle,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (items.length > 1)
                IconButton(
                  icon: const Icon(Icons.sort_rounded, size: 20),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  tooltip: s.isTr ? 'Kısayolları Sırala' : 'Reorder Shortcuts',
                  onPressed: () => _showReorderQuickItemsDialog(context),
                ),
              IconButton(
                icon: const Icon(Icons.add_circle_outline, size: 20),
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                tooltip: s.isTr ? 'Kısayol Ekle' : 'Add Shortcut',
                onPressed: () => _showAddQuickItemDialog(context),
              ),
            ],
          ),
        ),
        if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
            child: Text(
              s.quickListEmpty,
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: AppFont.small),
            ),
          )
        else
          SizedBox(
            height: 46,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              scrollDirection: Axis.horizontal,
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (itemCtx, i) {
                final item = items[i];
                final act = store.activity(item.activityId);
                final done = store.quickDone(item, at: currentDay);
                final isTodo = item.isTodo;

                return InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () async {
                    final res = await store.tapQuickItem(item.id, at: currentDay);
                    if (context.mounted) {
                      if (res.added != null) {
                        showSnack(
                          context,
                          '${act.name} ${s.isTr ? "kaydedildi" : "logged"}',
                          achieved: res.achieved,
                          exceeded: res.exceeded,
                          undo: () => store.deleteEntry(res.added!),
                        );
                      } else if (res.removed != null) {
                        showSnack(
                          context,
                          '${act.name} ${s.isTr ? "işareti kaldırıldı" : "unticked"}',
                          undo: () => store.restoreEntry(res.removed!),
                        );
                      }
                    }
                  },
                  onLongPress: () => _showQuickItemOptions(context, item),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: done
                          ? scheme.primaryContainer
                          : scheme.surfaceContainerHighest.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: done ? scheme.primary : scheme.outlineVariant,
                        width: done ? 1.5 : 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (isTodo)
                          Icon(
                            done ? Icons.check_circle : Icons.radio_button_unchecked,
                            size: 18,
                            color: done ? scheme.primary : scheme.onSurfaceVariant,
                          )
                        else
                          Text(
                            (act.emoji != null && act.emoji!.trim().isNotEmpty)
                                ? act.emoji!.trim()
                                : (act.category != null ? act.categoryDef.emoji : '⚡'),
                            style: const TextStyle(fontSize: AppFont.title),
                          ),
                        const SizedBox(width: 8),
                        Text(
                          act.name,
                          style: TextStyle(
                            fontWeight: done ? FontWeight.bold : FontWeight.w500,
                            color: done ? scheme.onPrimaryContainer : scheme.onSurface,
                          ),
                        ),
                        if (item.measureId != null) ...[
                          const SizedBox(width: 4),
                          Text(
                            '(${fmtNum(item.qty)})',
                            style: TextStyle(
                              fontSize: AppFont.caption,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  void _showAddQuickItemDialog(BuildContext context) async {
    final s = strings.value;
    final act = await showActivityPicker(context, title: s.isTr ? 'Hızlı Liste İçin Seç' : 'Choose for Shortcut');
    if (act == null || !context.mounted) return;

    var kind = 'shortcut'; // or 'todo'
    var daily = true;
    int? measureId = store.stats[act.id]?.lastMeasureId;
    double qty = 1.0;

    await showDialog<void>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setS) => AlertDialog(
          title: Text('${act.name} - ${s.isTr ? "Hızlı Listeye Ekle" : "Add to Shortcuts"}'),
          content: SingleChildScrollView(
            padding: const EdgeInsets.only(top: 12, bottom: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SegmentedButton<String>(
                  segments: [
                    ButtonSegment(
                      value: 'shortcut',
                      label: Text(s.isTr ? 'Hızlı Kayıt' : 'Instant Log'),
                      icon: const Icon(Icons.flash_on),
                    ),
                    ButtonSegment(
                      value: 'todo',
                      label: Text(s.isTr ? 'Yapılacak' : 'To-Do'),
                      icon: const Icon(Icons.check_box_outlined),
                    ),
                  ],
                  selected: {kind},
                  onSelectionChanged: (set) => setS(() => kind = set.first),
                ),
                if (kind == 'todo') ...[
                  const SizedBox(height: 12),
                  SwitchListTile(
                    title: Text(s.isTr ? 'Her gün yenilensin' : 'Repeat daily'),
                    value: daily,
                    onChanged: (v) => setS(() => daily = v),
                    contentPadding: EdgeInsets.zero,
                  ),
                ],
                const SizedBox(height: 14),
                Text(
                  s.selectMeasure,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(c).colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 6),
                MeasureQtyPicker(
                  activityId: act.id,
                  measureId: measureId,
                  qty: qty,
                  onChanged: (mId, qVal) => setS(() {
                    measureId = mId;
                    qty = qVal;
                  }),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: Text(s.cancel)),
            FilledButton(
              onPressed: () async {
                final qItem = QuickItem(
                  id: 0,
                  activityId: act.id,
                  kind: kind,
                  daily: daily,
                  measureId: measureId,
                  qty: qty,
                  createdAt: DateTime.now().millisecondsSinceEpoch,
                );
                await store.saveQuickItem(qItem);
                if (c.mounted) Navigator.pop(c);
              },
              child: Text(s.save),
            ),
          ],
        ),
      ),
    );
  }

  void _showQuickItemOptions(BuildContext context, QuickItem item) {
    final s = strings.value;
    final act = store.activity(item.activityId);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (c) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Tooltip(
                  message: s.isTr ? 'İkonu Değiştir' : 'Change Emoji',
                  child: InkWell(
                    borderRadius: BorderRadius.circular(24),
                    onTap: () async {
                      final chosen = await showEmojiPicker(context, currentEmoji: act.emoji);
                      if (chosen != null) {
                        act.emoji = chosen.trim().isEmpty ? null : chosen.trim();
                        await store.updateActivity(act);
                        if (c.mounted) Navigator.pop(c);
                      }
                    },
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        ActivityAvatar(act.id, size: 44),
                        Positioned(
                          right: -2,
                          bottom: -2,
                          child: Container(
                            padding: const EdgeInsets.all(2.5),
                            decoration: BoxDecoration(
                              color: Theme.of(c).colorScheme.primaryContainer,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Theme.of(c).colorScheme.surface,
                                width: 1.5,
                              ),
                            ),
                            child: Icon(
                              Icons.edit,
                              size: 10,
                              color: Theme.of(c).colorScheme.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        act.name,
                        style: const TextStyle(fontSize: AppFont.title, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        s.isTr ? 'İkonu değiştirmek için dokunun' : 'Tap icon to change emoji',
                        style: TextStyle(
                          fontSize: AppFont.caption,
                          color: Theme.of(c).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ListTile(
              leading: const Icon(Icons.timer_outlined),
              title: Text(s.startStopwatch),
              onTap: () async {
                Navigator.pop(c);
                await onStartTimer(act);
              },
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: Text(s.isTr ? 'Aktiviteyi & İkonu Düzenle' : 'Edit Activity & Icon'),
              onTap: () {
                Navigator.pop(c);
                showActivityEditDialog(context, act);
              },
            ),
            ListTile(
              leading: const Icon(Icons.sort_rounded),
              title: Text(s.isTr ? 'Kısayolları Sırala' : 'Reorder Shortcuts'),
              onTap: () {
                Navigator.pop(c);
                _showReorderQuickItemsDialog(context);
              },
            ),
            ListTile(
              leading: Icon(Icons.delete_outline, color: Theme.of(c).colorScheme.error),
              title: Text(
                s.isTr ? 'Hızlı Listeden Kaldır' : 'Remove from Shortcuts',
                style: TextStyle(color: Theme.of(c).colorScheme.error),
              ),
              onTap: () async {
                await store.deleteQuickItem(item);
                if (c.mounted) Navigator.pop(c);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showReorderQuickItemsDialog(BuildContext context) {
    final s = strings.value;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            final currentItems = store.quickItems;
            final scheme = Theme.of(ctx).colorScheme;

            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 4,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(Icons.sort_rounded, color: scheme.primary),
                      const SizedBox(width: 8),
                      Text(
                        s.isTr ? 'Kısayolları Sırala' : 'Reorder Shortcuts',
                        style: const TextStyle(fontSize: AppFont.title, fontWeight: FontWeight.bold),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: Text(s.isTr ? 'Tamam' : 'Done'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.of(ctx).size.height * 0.5,
                    ),
                    child: ReorderableListView.builder(
                      shrinkWrap: true,
                      itemCount: currentItems.length,
                      onReorderItem: (oldIdx, newIdx) async {
                        await store.reorderQuickItems(oldIdx, newIdx);
                        setModalState(() {});
                      },
                      itemBuilder: (c, idx) {
                        final q = currentItems[idx];
                        final act = store.activity(q.activityId);
                        return ListTile(
                          key: ValueKey('reorder_quick_${q.id}'),
                          leading: ActivityAvatar(act.id, size: 32),
                          title: Text(act.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                          trailing: const Icon(Icons.drag_handle_rounded),
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
