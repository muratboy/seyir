import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../../data/store.dart';
import '../../logic/format.dart';
import '../../logic/l10n.dart';
import '../common.dart';

/// Günün akışı (Timeline) - Liste ve Kompakt Şerit görünümleri ve kayıt düzenleme
class TodayTimeline extends StatelessWidget {
  final DateTime currentDay;
  final Future<void> Function(Activity) onStartTimer;

  const TodayTimeline({
    super.key,
    required this.currentDay,
    required this.onStartTimer,
  });

  @override
  Widget build(BuildContext context) {
    final s = strings.value;
    final entries = store.entriesOfDay(currentDay).reversed.toList();
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle(
          s.timelineTitle,
          trailing: _buildTimelineViewToggle(context),
        ),
        if (entries.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
            child: Card(
              elevation: 0,
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
                side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.25)),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
                child: Column(
                  children: [
                    Icon(Icons.auto_awesome_rounded, size: 38, color: scheme.primary.withValues(alpha: 0.8)),
                    const SizedBox(height: 10),
                    Text(
                      s.timelineEmpty,
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: scheme.onSurface),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      s.isTr
                          ? 'Yukarıdaki alandan yeni bir aktivite başlatabilir veya hızlı kısayolları kullanabilirsin.'
                          : 'You can start an activity above or tap one of the quick shortcuts.',
                      style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          )
        else if (store.timelineView == 'grid')
          _buildTimelineGrid(context, entries)
        else
          _buildTimelineList(context, entries),
      ],
    );
  }

  Widget _buildTimelineViewToggle(BuildContext context) {
    final s = strings.value;
    final isGrid = store.timelineView == 'grid';

    return SegmentedButton<String>(
      showSelectedIcon: false,
      style: const ButtonStyle(
        visualDensity: VisualDensity.compact,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      segments: [
        ButtonSegment(
          value: 'list',
          icon: const Icon(Icons.view_agenda_rounded, size: 18),
          tooltip: s.isTr ? 'Geniş Liste Görünümü' : 'Detailed List View',
        ),
        ButtonSegment(
          value: 'grid',
          icon: const Icon(Icons.view_compact_rounded, size: 18),
          tooltip: s.isTr ? 'Kompakt Şerit Görünümü' : 'Compact Strips View',
        ),
      ],
      selected: {isGrid ? 'grid' : 'list'},
      onSelectionChanged: (vals) => store.setTimelineView(vals.first),
    );
  }

  Widget _buildTimelineGrid(BuildContext context, List<Entry> entries) {
    final scheme = Theme.of(context).colorScheme;
    final s = strings.value;

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 10,
        mainAxisSpacing: 8,
        childAspectRatio: 2.25,
      ),
      itemCount: entries.length,
      itemBuilder: (context, i) {
        final entry = entries[i];
        final act = store.activity(entry.activityId);
        final detail = store.entryDetail(entry);
        final timeStr = entry.endTs != null
            ? '${fmtTime(entry.time)}–${fmtTime(entry.endTime!)}'
            : fmtTime(entry.time);
        final activeTimer = store.getTimerForActivity(act.id);

        return Card(
          margin: EdgeInsets.zero,
          elevation: 0,
          color: activeTimer != null
              ? Colors.green.withValues(alpha: 0.08)
              : scheme.surfaceContainerLow,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: activeTimer != null
                ? BorderSide(color: Colors.green.shade600, width: 1.5)
                : BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.3)),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => _showEntryEditSheet(context, entry),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // 1. Sol: Büyük ve net ikon (yuvarlak disk olmadan)
                  ActivityAvatar(act.id, size: 38),
                  const SizedBox(width: 10),

                  // 2. Sağ taraf: Başlık ve alt satırda Detay + Saat
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                act.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13.5,
                                  letterSpacing: -0.2,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (entry.note != null && entry.note!.isNotEmpty) ...[
                              const SizedBox(width: 3),
                              Icon(Icons.notes, size: 11, color: scheme.onSurfaceVariant),
                            ],
                          ],
                        ),
                        const SizedBox(height: 3),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Flexible(
                              child: Text(
                                detail.isNotEmpty
                                    ? detail
                                    : (act.category != null
                                        ? '${act.categoryDef.emoji} ${act.categoryDef.name(s.isTr)}'
                                        : ''),
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: scheme.onSurfaceVariant,
                                  fontWeight: FontWeight.w500,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 4),
                            if (activeTimer != null)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                decoration: BoxDecoration(
                                  color: Colors.green.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(5),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.timer_outlined, size: 10, color: Colors.green),
                                    const SizedBox(width: 2),
                                    Text(
                                      activeTimer.displayDuration,
                                      style: const TextStyle(
                                        fontSize: 9.5,
                                        color: Colors.green,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            else
                              Text(
                                timeStr,
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w600,
                                  color: scheme.primary.withValues(alpha: 0.85),
                                ),
                              ),
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
      },
    );
  }

  Widget _buildTimelineList(BuildContext context, List<Entry> entries) {
    final s = strings.value;
    final scheme = Theme.of(context).colorScheme;

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: entries.length,
      itemBuilder: (context, i) {
        final entry = entries[i];
        final act = store.activity(entry.activityId);
        final detail = store.entryDetail(entry);
        final timeStr = entry.endTs != null
            ? (entry.duration != null && entry.duration!.inMinutes > 0
                ? '${fmtTime(entry.time)}–${fmtTime(entry.endTime!)}'
                : '${fmtTime(entry.time)}–${fmtTime(entry.endTime!)}')
            : fmtTime(entry.time);
        final activeTimer = store.getTimerForActivity(act.id);

        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
          elevation: 0,
          color: activeTimer != null
              ? Colors.green.withValues(alpha: 0.08)
              : scheme.surfaceContainerLow,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: activeTimer != null
                ? BorderSide(color: Colors.green.shade600, width: 1.5)
                : BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.3)),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => _showEntryEditSheet(context, entry),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // 1. Sol: Büyük ve net ikon (yuvarlak disk olmadan)
                  ActivityAvatar(act.id, size: 44),
                  const SizedBox(width: 14),

                  // 2. Orta: Bilgiler (Hiyerarşik ve şık)
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                act.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 16,
                                  letterSpacing: -0.2,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (act.category != null) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                decoration: BoxDecoration(
                                  color: act.displayColor.withValues(alpha: 0.14),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  '${act.categoryDef.emoji} ${act.categoryDef.name(s.isTr)}',
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w600,
                                    color: act.displayColor,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        if (activeTimer != null || detail.isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Row(
                            children: [
                              if (activeTimer != null) ...[
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.green.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.timer_outlined, size: 12, color: Colors.green),
                                      const SizedBox(width: 4),
                                      Text(
                                        '${s.isTr ? "Sayaç çalışıyor" : "Timer running"} (${activeTimer.displayDuration})',
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: Colors.green,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (detail.isNotEmpty) const SizedBox(width: 8),
                              ],
                              if (detail.isNotEmpty)
                                Flexible(
                                  child: Text(
                                    detail,
                                    style: TextStyle(
                                      color: scheme.onSurfaceVariant,
                                      fontWeight: FontWeight.w500,
                                      fontSize: 13,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                            ],
                          ),
                        ],
                        if (entry.note != null && entry.note!.isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Row(
                            children: [
                              Icon(Icons.notes, size: 12, color: scheme.onSurfaceVariant.withValues(alpha: 0.8)),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  entry.note!,
                                  style: TextStyle(
                                    fontStyle: FontStyle.italic,
                                    color: scheme.onSurfaceVariant,
                                    fontSize: 12,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),

                  // 3. Sağ: Şık Saat Rozeti ve Süre
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          timeStr,
                          style: TextStyle(
                            fontSize: 12.5,
                            color: scheme.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (entry.duration != null && entry.duration!.inMinutes > 0) ...[
                        const SizedBox(height: 3),
                        Text(
                          fmtAmount(entry.duration!.inMinutes.toDouble(), 'time'),
                          style: TextStyle(
                            fontSize: 11,
                            color: scheme.onSurfaceVariant,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showEntryEditSheet(BuildContext context, Entry e) {
    final s = strings.value;
    final act = store.activity(e.activityId);
    var measureId = e.measureId;
    var qty = e.qty;
    final noteCtrl = TextEditingController(text: e.note ?? '');
    var entryTime = e.time;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (c) => StatefulBuilder(
        builder: (c, setS) => Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 4,
            bottom: MediaQuery.of(c).viewInsets.bottom + 24,
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    ActivityAvatar(act.id, size: 44),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            act.name,
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          Text(
                            e.endTs != null
                                ? '${s.isTr ? "Süre Aralığı" : "Interval"}: ${fmtTime(entryTime)}–${fmtTime(e.endTime!)} (${fmtDateShort(entryTime)})'
                                : '${s.isTr ? "Eklenme" : "Logged"}: ${fmtTime(entryTime)} - ${fmtDateShort(entryTime)}',
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(c).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.timer_outlined),
                      tooltip: s.startStopwatch,
                      onPressed: () async {
                        Navigator.pop(c);
                        await onStartTimer(act);
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.access_time),
                      tooltip: s.isTr ? 'Saati değiştir' : 'Change time',
                      onPressed: () async {
                        final t = await showTimePicker(
                          context: c,
                          initialTime: TimeOfDay.fromDateTime(entryTime),
                        );
                        if (t != null) {
                          setS(() {
                            entryTime = DateTime(
                              entryTime.year,
                              entryTime.month,
                              entryTime.day,
                              t.hour,
                              t.minute,
                            );
                          });
                        }
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 16),
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
                const SizedBox(height: 12),
                TextField(
                  controller: noteCtrl,
                  decoration: InputDecoration(
                    labelText: s.noteHint,
                    prefixIcon: const Icon(Icons.notes),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Icon(Icons.flag_outlined, size: 16, color: Theme.of(c).colorScheme.primary),
                    const SizedBox(width: 6),
                    Text(
                      s.linkedGoals,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(c).colorScheme.primary,
                      ),
                    ),
                    const Spacer(),
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                      ),
                      icon: const Icon(Icons.tune, size: 14),
                      label: Text(s.isTr ? 'Hedefleri Düzenle' : 'Manage Goals', style: const TextStyle(fontSize: 12)),
                      onPressed: () {
                        Navigator.pop(c);
                        showActivityEditDialog(context, act);
                      },
                    ),
                  ],
                ),
                Builder(
                  builder: (ctx) {
                    final linked = store.goalsForActivity(act.id);
                    if (linked.isEmpty) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text(
                          s.isTr
                              ? 'Bu aktivite henüz bir hedef veya limite bağlı değil.'
                              : 'This activity is not linked to any goal or limit yet.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(c).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      );
                    }
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          for (final (g, _) in linked)
                            Chip(
                              visualDensity: VisualDensity.compact,
                              avatar: Icon(
                                g.isLimit ? Icons.shield_outlined : Icons.track_changes,
                                size: 14,
                                color: g.isLimit ? Colors.amber.shade800 : Colors.blue.shade800,
                              ),
                              label: Text(
                                g.name,
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Theme.of(c).colorScheme.error,
                      ),
                      icon: const Icon(Icons.delete_outline),
                      label: Text(s.delete),
                      onPressed: () async {
                        final ok = await confirm(
                          c,
                          s.deleteConfirmTitle,
                          '${act.name} ${s.deleteConfirmDesc}',
                        );
                        if (ok) {
                          await store.deleteEntry(e);
                          if (c.mounted) Navigator.pop(c);
                        }
                      },
                    ),
                    const Spacer(),
                    FilledButton(
                      onPressed: () async {
                        await store.updateEntry(
                          e,
                          activityId: e.activityId,
                          time: entryTime,
                          measureId: measureId,
                          qty: qty,
                          note: noteCtrl.text,
                        );
                        if (c.mounted) Navigator.pop(c);
                      },
                      child: Text(s.save),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
