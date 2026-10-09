import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../../data/store.dart';
import '../../logic/format.dart';
import '../../logic/l10n.dart';
import '../common.dart';

/// Hızlı kısayollar ve günlük yapılacaklar şeridi (Shortcuts & To-Dos)
class TodayQuickShortcuts extends StatelessWidget {
  final Future<void> Function(Activity) onStartTimer;

  const TodayQuickShortcuts({
    super.key,
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
          trailing: IconButton(
            icon: const Icon(Icons.add_circle_outline, size: 22),
            onPressed: () => _showAddQuickItemDialog(context),
          ),
        ),
        if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Text(
              s.quickListEmpty,
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
            ),
          )
        else
          SizedBox(
            height: 52,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              scrollDirection: Axis.horizontal,
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (itemCtx, i) {
                final item = items[i];
                final act = store.activity(item.activityId);
                final done = store.quickDone(item);
                final isTodo = item.isTodo;

                return InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () async {
                    final res = await store.tapQuickItem(item.id);
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
                          Text(act.emoji ?? '⚡', style: const TextStyle(fontSize: 16)),
                        const SizedBox(width: 6),
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
                              fontSize: 12,
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
            Text(
              act.name,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
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
              title: Text(s.edit),
              onTap: () {
                Navigator.pop(c);
                showActivityEditDialog(context, act);
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
}
