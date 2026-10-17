import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/models.dart';
import '../../data/store.dart';
import '../../logic/format.dart';
import '../../logic/l10n.dart';
import '../app_font.dart';
import '../common.dart';

/// Bugün ekranında rutinleri (aktivite paketlerini) gösteren ve tek dokunuşla çalıştıran panel
class TodayRoutinesPanel extends StatelessWidget {
  final DateTime currentDay;

  const TodayRoutinesPanel({super.key, required this.currentDay});

  @override
  Widget build(BuildContext context) {
    final s = strings.value;
    final isTr = s.isTr;
    final scheme = Theme.of(context).colorScheme;
    final routines = store.routines;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionTitle(
          isTr ? '⚡ Rutinler & Paketler' : '⚡ Routines & Bundles',
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.add_circle_outline, size: 20),
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                tooltip: isTr ? 'Yeni Rutin Ekle' : 'Add Routine',
                onPressed: () => RoutineEditSheet.show(context),
              ),
            ],
          ),
        ),
        if (routines.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => RoutineEditSheet.show(context),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: scheme.primaryContainer,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(Icons.flash_on_rounded, size: 20, color: scheme.primary),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isTr ? 'Tek Dokunuşla Çoklu Kayıt: Rutinler' : 'One-Tap Multi-Log: Routines',
                            style: const TextStyle(fontSize: AppFont.small, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            isTr
                                ? 'Sabah, spor veya gece aktivitelerini paketleyin.'
                                : 'Bundle your morning, workout or night activities.',
                            style: TextStyle(fontSize: AppFont.micro, color: scheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.add, size: 20, color: scheme.primary),
                  ],
                ),
              ),
            ),
          )
        else
          SizedBox(
            height: 48,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              scrollDirection: Axis.horizontal,
              itemCount: routines.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final r = routines[i];
                final itemCount = r.items.length;

                return InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () async {
                    HapticFeedback.mediumImpact();
                    final entries = await store.executeRoutine(r.id, at: currentDay);
                    if (context.mounted && entries.isNotEmpty) {
                      showSnack(
                        context,
                        '${r.emoji} ${r.name} ${isTr ? "kaydedildi" : "logged"} ($itemCount ${isTr ? "aktivite" : "activities"}) ✨',
                        undo: () async {
                          for (final e in entries) {
                            await store.deleteEntry(e);
                          }
                        },
                      );
                    }
                  },
                  onLongPress: () => _showRoutineOptions(context, r),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: scheme.primary.withValues(alpha: 0.2)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(r.emoji, style: const TextStyle(fontSize: 18)),
                        const SizedBox(width: 6),
                        Text(
                          r.name,
                          style: const TextStyle(fontSize: AppFont.small, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: scheme.primaryContainer,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '$itemCount',
                            style: TextStyle(
                              fontSize: AppFont.micro,
                              fontWeight: FontWeight.bold,
                              color: scheme.onPrimaryContainer,
                            ),
                          ),
                        ),
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

  void _showRoutineOptions(BuildContext context, Routine r) {
    final s = strings.value;
    final isTr = s.isTr;

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetCtx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Text(r.emoji, style: const TextStyle(fontSize: 24)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          r.name,
                          style: const TextStyle(fontSize: AppFont.subtitle, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          '${r.items.length} ${isTr ? "aktivite içeriyor" : "activities included"}',
                          style: TextStyle(fontSize: AppFont.small, color: Theme.of(context).colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.play_arrow_rounded),
                title: Text(isTr ? 'Şimdi Kaydet / Çalıştır' : 'Execute Routine Now'),
                onTap: () async {
                  Navigator.pop(sheetCtx);
                  final entries = await store.executeRoutine(r.id, at: currentDay);
                  if (context.mounted && entries.isNotEmpty) {
                    showSnack(
                      context,
                      '${r.emoji} ${r.name} ${isTr ? "kaydedildi" : "logged"} (${r.items.length} ${isTr ? "aktivite" : "activities"})',
                      undo: () async {
                        for (final e in entries) {
                          await store.deleteEntry(e);
                        }
                      },
                    );
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: Text(isTr ? 'Rutini Düzenle' : 'Edit Routine'),
                onTap: () {
                  Navigator.pop(sheetCtx);
                  RoutineEditSheet.show(context, routine: r);
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: Text(isTr ? 'Rutini Sil' : 'Delete Routine', style: const TextStyle(color: Colors.red)),
                onTap: () async {
                  Navigator.pop(sheetCtx);
                  await store.deleteRoutine(r.id);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Rutin oluşturma ve düzenleme alt sayfası
class RoutineEditSheet extends StatefulWidget {
  final Routine? routine;

  const RoutineEditSheet({super.key, this.routine});

  static Future<void> show(BuildContext context, {Routine? routine}) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => RoutineEditSheet(routine: routine),
    );
  }

  @override
  State<RoutineEditSheet> createState() => _RoutineEditSheetState();
}

class _RoutineEditSheetState extends State<RoutineEditSheet> {
  late final TextEditingController _nameController;
  late String _emoji;
  late List<RoutineItem> _items;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.routine?.name ?? '');
    _emoji = widget.routine?.emoji ?? '⚡';
    _items = widget.routine != null
        ? widget.routine!.items
            .map((it) => RoutineItem(
                  id: it.id,
                  routineId: it.routineId,
                  activityId: it.activityId,
                  measureId: it.measureId,
                  qty: it.qty,
                  note: it.note,
                  sort: it.sort,
                ))
            .toList()
        : [];
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _applyPreset(String name, String emoji, List<String> activityKeywords) {
    _nameController.text = name;
    _emoji = emoji;

    // Eşleşen aktiviteleri bul
    final matchedActIds = <int>[];
    for (final kw in activityKeywords) {
      for (final a in store.activities.values) {
        if (!a.isArchived && a.name.toLowerCase().contains(kw.toLowerCase())) {
          if (!matchedActIds.contains(a.id)) {
            matchedActIds.add(a.id);
            break;
          }
        }
      }
    }

    if (matchedActIds.isNotEmpty) {
      _items = matchedActIds
          .map((id) => RoutineItem(
                activityId: id,
                qty: 1.0,
              ))
          .toList();
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final s = strings.value;
    final isTr = s.isTr;
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 4,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () async {
                    final emojis = ['⚡', '🌅', '🌙', '🏋️', '☕', '🧘', '💧', '📚', '💊', '🎯'];
                    final picked = await showDialog<String>(
                      context: context,
                      builder: (ctx) => SimpleDialog(
                        title: Text(isTr ? 'Emoji Seç' : 'Choose Emoji'),
                        children: [
                          Wrap(
                            alignment: WrapAlignment.center,
                            spacing: 12,
                            runSpacing: 12,
                            children: emojis
                                .map((e) => InkWell(
                                      onTap: () => Navigator.pop(ctx, e),
                                      borderRadius: BorderRadius.circular(8),
                                      child: Padding(
                                        padding: const EdgeInsets.all(8),
                                        child: Text(e, style: const TextStyle(fontSize: 28)),
                                      ),
                                    ))
                                .toList(),
                          ),
                        ],
                      ),
                    );
                    if (picked != null) setState(() => _emoji = picked);
                  },
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(_emoji, style: const TextStyle(fontSize: 24)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _nameController,
                    decoration: InputDecoration(
                      labelText: isTr ? 'Rutin Adı' : 'Routine Name',
                      hintText: isTr ? 'Örn: Sabah Rutini' : 'e.g. Morning Routine',
                      border: const OutlineInputBorder(),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Hazır Şablon Çipleri
            if (widget.routine == null) ...[
              Text(
                isTr ? 'Hızlı Şablonlar:' : 'Quick Presets:',
                style: TextStyle(fontSize: AppFont.micro, color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  ActionChip(
                    avatar: const Text('🌅'),
                    label: Text(isTr ? 'Sabah Rutini' : 'Morning Routine'),
                    onPressed: () => _applyPreset(
                      isTr ? 'Sabah Rutini' : 'Morning Routine',
                      '🌅',
                      ['su', 'vitamin', 'meditasyon', 'kahve', 'kahvaltı'],
                    ),
                  ),
                  ActionChip(
                    avatar: const Text('🏋️'),
                    label: Text(isTr ? 'Spor Paketi' : 'Workout Bundle'),
                    onPressed: () => _applyPreset(
                      isTr ? 'Spor Paketi' : 'Workout Bundle',
                      '🏋️',
                      ['koşu', 'yürüyüş', 'şınav', 'su', 'protein', 'esneme'],
                    ),
                  ),
                  ActionChip(
                    avatar: const Text('🌙'),
                    label: Text(isTr ? 'Gece Rutini' : 'Night Routine'),
                    onPressed: () => _applyPreset(
                      isTr ? 'Gece Rutini' : 'Night Routine',
                      '🌙',
                      ['kitap', 'diş', 'su', 'uyku', 'günlük'],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],

            // Aktiviteler Listesi
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  isTr ? 'Paketteki Aktiviteler (${_items.length})' : 'Activities in Bundle (${_items.length})',
                  style: const TextStyle(fontSize: AppFont.small, fontWeight: FontWeight.bold),
                ),
                TextButton.icon(
                  icon: const Icon(Icons.add, size: 18),
                  label: Text(isTr ? 'Aktivite Ekle' : 'Add Activity'),
                  onPressed: () async {
                    final act = await showActivityPicker(
                      context,
                      title: isTr ? 'Rutine Aktivite Ekle' : 'Add Activity to Routine',
                    );
                    if (act != null) {
                      setState(() {
                        _items.add(RoutineItem(activityId: act.id, qty: 1.0));
                      });
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 6),

            if (_items.isEmpty)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 20),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  isTr
                      ? 'Pakette henüz aktivite yok. Yukarıdan ekleyin.'
                      : 'No activities in bundle yet. Add from above.',
                  style: TextStyle(fontSize: AppFont.small, color: scheme.onSurfaceVariant),
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _items.length,
                separatorBuilder: (_, _) => const SizedBox(height: 6),
                itemBuilder: (context, i) {
                  final it = _items[i];
                  final act = store.activity(it.activityId);
                  final m = store.measureById(it.measureId);

                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Text(act.emoji ?? '📌', style: const TextStyle(fontSize: 18)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(act.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                              if (m != null)
                                Text(
                                  '${fmtNum(it.qty)} ${m.name}',
                                  style: TextStyle(fontSize: AppFont.micro, color: scheme.onSurfaceVariant),
                                ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.remove_circle_outline, size: 20, color: Colors.red),
                          visualDensity: VisualDensity.compact,
                          onPressed: () => setState(() => _items.removeAt(i)),
                        ),
                      ],
                    ),
                  );
                },
              ),

            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(s.cancel),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: _nameController.text.trim().isEmpty || _items.isEmpty
                        ? null
                        : () async {
                            final r = Routine(
                              id: widget.routine?.id ?? 0,
                              name: _nameController.text.trim(),
                              emoji: _emoji,
                              items: _items,
                            );
                            await store.saveRoutine(r);
                            if (context.mounted) Navigator.pop(context);
                          },
                    child: Text(s.save),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
