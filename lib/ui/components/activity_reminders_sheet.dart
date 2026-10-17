import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../../data/store.dart';
import '../../logic/l10n.dart';
import '../app_font.dart';

/// Aktiviteye ait özel periyodik hatırlatıcıları yöneten alt sayfa
class ActivityRemindersSheet extends StatefulWidget {
  final Activity activity;

  const ActivityRemindersSheet({super.key, required this.activity});

  static Future<void> show(BuildContext context, Activity activity) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => ActivityRemindersSheet(activity: activity),
    );
  }

  @override
  State<ActivityRemindersSheet> createState() => _ActivityRemindersSheetState();
}

class _ActivityRemindersSheetState extends State<ActivityRemindersSheet> {
  @override
  Widget build(BuildContext context) {
    final s = strings.value;
    final isTr = s.isTr;
    final scheme = Theme.of(context).colorScheme;

    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final currentReminders = store.remindersForActivity(widget.activity.id);

        return Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 4,
            bottom: MediaQuery.of(context).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.alarm_on_rounded, color: scheme.primary, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isTr ? 'Aktivite Hatırlatıcıları' : 'Activity Reminders',
                          style: const TextStyle(fontSize: AppFont.subtitle, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          '${widget.activity.emoji ?? ""} ${widget.activity.name}'.trim(),
                          style: TextStyle(fontSize: AppFont.small, color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  IconButton.filledTonal(
                    icon: const Icon(Icons.add, size: 20),
                    tooltip: isTr ? 'Yeni Hatırlatıcı Ekle' : 'Add Reminder',
                    onPressed: () => _showAddEditReminderDialog(context),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (currentReminders.isEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    children: [
                      Icon(Icons.notifications_none_rounded, size: 36, color: scheme.onSurfaceVariant),
                      const SizedBox(height: 8),
                      Text(
                        isTr
                            ? 'Bu aktivite için henüz kurulmuş bir hatırlatıcı yok.'
                            : 'No reminders set for this activity yet.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: AppFont.small, color: scheme.onSurfaceVariant),
                      ),
                      const SizedBox(height: 12),
                      FilledButton.tonalIcon(
                        icon: const Icon(Icons.add_alarm_rounded, size: 18),
                        label: Text(isTr ? 'Hatırlatıcı Kur' : 'Set Reminder'),
                        onPressed: () => _showAddEditReminderDialog(context),
                      ),
                    ],
                  ),
                )
              else
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: currentReminders.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final rem = currentReminders[i];
                    return Container(
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: rem.isEnabled ? scheme.primary.withValues(alpha: 0.25) : Colors.transparent,
                        ),
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                        leading: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: rem.isEnabled ? scheme.primary.withValues(alpha: 0.15) : scheme.surfaceContainer,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            rem.isEnabled ? Icons.alarm_rounded : Icons.alarm_off_rounded,
                            color: rem.isEnabled ? scheme.primary : scheme.outline,
                            size: 22,
                          ),
                        ),
                        title: Text(
                          rem.time,
                          style: TextStyle(
                            fontSize: AppFont.title,
                            fontWeight: FontWeight.bold,
                            color: rem.isEnabled ? scheme.onSurface : scheme.outline,
                          ),
                        ),
                        subtitle: Text(
                          _formatDaysOfWeek(rem.daysOfWeek, isTr),
                          style: TextStyle(fontSize: AppFont.micro, color: scheme.onSurfaceVariant),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Switch(
                              value: rem.isEnabled,
                              onChanged: (val) => store.toggleActivityReminder(rem.id, val),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, size: 20),
                              tooltip: isTr ? 'Sil' : 'Delete',
                              onPressed: () async {
                                await store.deleteActivityReminder(rem.id);
                              },
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  String _formatDaysOfWeek(String daysStr, bool isTr) {
    final days = daysStr.split(',').map(int.tryParse).whereType<int>().toSet();
    if (days.length == 7) {
      return isTr ? 'Her gün' : 'Every day';
    }
    if (days.length == 5 && !days.contains(6) && !days.contains(7)) {
      return isTr ? 'Hafta içi (Pzt-Cum)' : 'Weekdays (Mon-Fri)';
    }
    if (days.length == 2 && days.contains(6) && days.contains(7)) {
      return isTr ? 'Hafta sonu (Cmt-Paz)' : 'Weekends (Sat-Sun)';
    }
    const dayNamesTr = {1: 'Pzt', 2: 'Sal', 3: 'Çar', 4: 'Per', 5: 'Cum', 6: 'Cmt', 7: 'Paz'};
    const dayNamesEn = {1: 'Mon', 2: 'Tue', 3: 'Wed', 4: 'Thu', 5: 'Fri', 6: 'Sat', 7: 'Sun'};
    final names = days.map((d) => (isTr ? dayNamesTr[d] : dayNamesEn[d]) ?? '').where((n) => n.isNotEmpty);
    return names.join(', ');
  }

  Future<void> _showAddEditReminderDialog(BuildContext context, [ActivityReminder? existing]) async {
    final s = strings.value;
    final isTr = s.isTr;

    TimeOfDay selectedTime = TimeOfDay.now();
    if (existing != null) {
      final parts = existing.time.split(':');
      if (parts.length == 2) {
        selectedTime = TimeOfDay(
          hour: int.tryParse(parts[0]) ?? 9,
          minute: int.tryParse(parts[1]) ?? 0,
        );
      }
    }

    Set<int> selectedDays = existing?.days ?? {1, 2, 3, 4, 5, 6, 7};
    final msgController = TextEditingController(text: existing?.customMessage ?? '');

    await showDialog<void>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final timeStr =
              '${selectedTime.hour.toString().padLeft(2, '0')}:${selectedTime.minute.toString().padLeft(2, '0')}';

          return AlertDialog(
            title: Text(existing == null
                ? (isTr ? 'Yeni Hatırlatıcı Ekle' : 'Add Reminder')
                : (isTr ? 'Hatırlatıcıyı Düzenle' : 'Edit Reminder')),
            content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      isTr ? 'Saat' : 'Time',
                      style: const TextStyle(fontSize: AppFont.small, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 6),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.access_time_rounded),
                      label: Text(
                        timeStr,
                        style: const TextStyle(fontSize: AppFont.subtitle, fontWeight: FontWeight.bold),
                      ),
                      onPressed: () async {
                        final picked = await showTimePicker(
                          context: ctx,
                          initialTime: selectedTime,
                        );
                        if (picked != null) {
                          setDialogState(() => selectedTime = picked);
                        }
                      },
                    ),
                    const SizedBox(height: 16),
                    Text(
                      isTr ? 'Tekrarlama Günleri' : 'Repeat Days',
                      style: const TextStyle(fontSize: AppFont.small, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (int d = 1; d <= 7; d++)
                          FilterChip(
                            label: Text(_shortDayName(d, isTr)),
                            selected: selectedDays.contains(d),
                            onSelected: (sel) {
                              setDialogState(() {
                                if (sel) {
                                  selectedDays.add(d);
                                } else {
                                  if (selectedDays.length > 1) {
                                    selectedDays.remove(d);
                                  }
                                }
                              });
                            },
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: msgController,
                      decoration: InputDecoration(
                        labelText: isTr ? 'Özel Hatırlatma Mesajı (İsteğe bağlı)' : 'Custom Message (Optional)',
                        hintText: isTr ? 'Örn: Su içmeyi unutma!' : 'e.g. Drink water!',
                        border: const OutlineInputBorder(),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogCtx),
                child: Text(s.cancel),
              ),
              FilledButton(
                onPressed: () async {
                  final daysJoined = (selectedDays.toList()..sort()).join(',');
                  final reminder = ActivityReminder(
                    id: existing?.id ?? 0,
                    activityId: widget.activity.id,
                    time: timeStr,
                    daysOfWeek: daysJoined,
                    isEnabled: true,
                    customMessage: msgController.text.trim().isEmpty ? null : msgController.text.trim(),
                  );
                  await store.saveActivityReminder(reminder);
                  if (dialogCtx.mounted) Navigator.pop(dialogCtx);
                },
                child: Text(s.save),
              ),
            ],
          );
        },
      ),
    );
  }

  String _shortDayName(int d, bool isTr) {
    const tr = {1: 'Pzt', 2: 'Sal', 3: 'Çar', 4: 'Per', 5: 'Cum', 6: 'Cmt', 7: 'Paz'};
    const en = {1: 'Mon', 2: 'Tue', 3: 'Wed', 4: 'Thu', 5: 'Fri', 6: 'Sat', 7: 'Sun'};
    return (isTr ? tr[d] : en[d]) ?? '';
  }
}
