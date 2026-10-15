import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../../data/store.dart';
import '../../logic/format.dart';
import '../../logic/l10n.dart';
import '../common.dart';
import '../app_font.dart';
import '../activity_page.dart';

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
                      style: TextStyle(fontSize: AppFont.subtitle, fontWeight: FontWeight.w600, color: scheme.onSurface),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      s.isTr
                          ? 'Aşağıdaki kutuya yazarak yeni bir kayıt ekleyebilir veya hızlı kısayolları kullanabilirsin.'
                          : 'Type in the box below to add an entry, or tap one of the quick shortcuts.',
                      style: TextStyle(fontSize: AppFont.small, color: scheme.onSurfaceVariant),
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
            onLongPress: () => showActivityEditDialog(context, act),
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
                                  fontSize: AppFont.body,
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
                                  fontSize: AppFont.caption,
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
                                        fontSize: AppFont.micro,
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
                                  fontSize: AppFont.micro,
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
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
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
            onLongPress: () => showActivityEditDialog(context, act),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // 1. Sol: Büyük ve net ikon (yuvarlak disk olmadan)
                  ActivityAvatar(act.id, size: 36),
                  const SizedBox(width: 12),

                  // 2. Orta: Bilgiler (Hiyerarşik ve şık)
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        NameWithCategory(
                          activity: act,
                          nameStyle: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: AppFont.subtitle,
                            letterSpacing: -0.2,
                          ),
                        ),
                        if (activeTimer != null || detail.isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Row(
                            children: [
                              if (activeTimer != null) ...[
                                // Yalnızca simge ve süre: "Sayaç çalışıyor" yazısı telefon genişliğinde
                                // satıra sığmıyordu, satırın yeşil çerçevesi de aynı şeyi söylüyor.
                                Tooltip(
                                  message: s.isTr ? 'Sayaç çalışıyor' : 'Timer running',
                                  child: Container(
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
                                          activeTimer.displayDuration,
                                          style: const TextStyle(
                                            fontSize: AppFont.micro,
                                            color: Colors.green,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
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
                                      fontSize: AppFont.small,
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
                                    fontSize: AppFont.caption,
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
                            fontSize: AppFont.small,
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
                            fontSize: AppFont.micro,
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

  void _showEntryEditSheet(BuildContext context, Entry e) => showEntryEditSheet(context, e, onStartTimer: onStartTimer);

  static void showEntryEditSheet(BuildContext context, Entry e, {Future<void> Function(Activity)? onStartTimer}) {
    final s = strings.value;
    final act = store.activity(e.activityId);
    var measureId = e.measureId;
    var qty = e.qty;
    final noteCtrl = TextEditingController(text: e.note ?? '');
    var refTime = e.time;
    var isEndMode = false;

    int calcDurMins(int? mId, double q) {
      final currentM = store.measureById(mId);
      if (currentM != null && (currentM.unitId == 'dk' || currentM.unitId == 'sa')) {
        return (currentM.amount * q * (currentM.unitId == 'sa' ? 60 : 1)).round();
      } else if (e.duration != null && e.duration!.inMinutes > 0) {
        return e.duration!.inMinutes;
      }
      return 0;
    }

    DateTime calcStartTime(DateTime ref, bool endMode, int dur) {
      if (dur <= 0 || !endMode) return ref;
      return ref.subtract(Duration(minutes: dur));
    }

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
                // 1. Üst Başlık ve Avatar / İkon Değiştirme
                Row(
                  children: [
                    Tooltip(
                      message: s.isTr ? 'İkonu / Emojiyi Değiştir' : 'Change Emoji',
                      child: InkWell(
                        borderRadius: BorderRadius.circular(24),
                        onTap: () async {
                          final chosen = await showEmojiPicker(context, currentEmoji: act.emoji);
                          if (chosen != null) {
                            act.emoji = chosen.trim().isEmpty ? null : chosen.trim();
                            await store.updateActivity(act);
                            setS(() {});
                          }
                        },
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            ActivityAvatar(act.id, size: 48),
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
                                  size: 11,
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
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  act.name,
                                  style: const TextStyle(fontSize: AppFont.title, fontWeight: FontWeight.bold),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                padding: const EdgeInsets.all(4),
                                constraints: const BoxConstraints(),
                                icon: const Icon(Icons.insights_rounded, size: 18),
                                tooltip: s.isTr ? 'Aktivite Sayfasını Aç' : 'View Activity Page',
                                onPressed: () {
                                  Navigator.pop(c);
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(builder: (_) => ActivityPage(activity: act)),
                                  );
                                },
                              ),
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                padding: const EdgeInsets.all(4),
                                constraints: const BoxConstraints(),
                                icon: const Icon(Icons.edit_outlined, size: 18),
                                tooltip: s.isTr ? 'Aktiviteyi Düzenle (İsim, Kategori, İkon)' : 'Edit Activity',
                                onPressed: () async {
                                  await showActivityEditDialog(context, act);
                                  setS(() {});
                                },
                              ),
                            ],
                          ),
                          Builder(builder: (ctx) {
                            final durMins = calcDurMins(measureId, qty);
                            final startTime = calcStartTime(refTime, isEndMode, durMins);
                            final endTime = startTime.add(Duration(minutes: durMins));
                            return Text(
                              durMins > 0
                                  ? '${s.isTr ? "Süre Aralığı" : "Interval"}: ${fmtTime(startTime)}–${fmtTime(endTime)} (${fmtDateShort(startTime)})'
                                  : '${s.isTr ? "Eklenme" : "Logged"}: ${fmtTime(refTime)} - ${fmtDateShort(refTime)}',
                              style: TextStyle(
                                fontSize: AppFont.caption,
                                color: Theme.of(c).colorScheme.onSurfaceVariant,
                              ),
                            );
                          }),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.timer_outlined),
                      tooltip: s.startStopwatch,
                      onPressed: () async {
                        Navigator.pop(c);
                        if (onStartTimer != null) {
                          await onStartTimer(act);
                        } else {
                          await store.startTimer(act.id);
                        }
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.access_time),
                      tooltip: s.isTr ? 'Saati değiştir' : 'Change time',
                      onPressed: () async {
                        final t = await showTimePicker(
                          context: c,
                          initialTime: TimeOfDay.fromDateTime(refTime),
                        );
                        if (t != null) {
                          setS(() {
                            refTime = DateTime(
                              refTime.year,
                              refTime.month,
                              refTime.day,
                              t.hour,
                              t.minute,
                            );
                          });
                        }
                      },
                    ),
                  ],
                ),
                Builder(builder: (ctx) {
                  final durMins = calcDurMins(measureId, qty);
                  if (durMins <= 0) return const SizedBox.shrink();
                  final startTime = calcStartTime(refTime, isEndMode, durMins);
                  final endTime = startTime.add(Duration(minutes: durMins));

                  return Padding(
                    padding: const EdgeInsets.only(top: 10, bottom: 4),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(c).colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Theme.of(c).colorScheme.outlineVariant.withValues(alpha: 0.5),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.schedule_rounded, size: 18, color: Theme.of(c).colorScheme.primary),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text.rich(
                                  TextSpan(
                                    children: [
                                      TextSpan(
                                        text: s.isTr ? 'Girilen Zaman: ' : 'Entered Time: ',
                                        style: TextStyle(
                                          fontSize: AppFont.caption,
                                          color: Theme.of(c).colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                      TextSpan(
                                        text: fmtTime(refTime),
                                        style: const TextStyle(
                                          fontSize: AppFont.body,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      TextSpan(
                                        text: ' (${fmtAmount(durMins.toDouble(), 'time')})',
                                        style: TextStyle(
                                          fontSize: AppFont.caption,
                                          color: Theme.of(c).colorScheme.primary,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              TextButton.icon(
                                style: TextButton.styleFrom(
                                  visualDensity: VisualDensity.compact,
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                ),
                                icon: const Icon(Icons.edit_outlined, size: 14),
                                label: Text(
                                  s.isTr ? 'Değiştir' : 'Change',
                                  style: const TextStyle(fontSize: AppFont.caption),
                                ),
                                onPressed: () async {
                                  final t = await showTimePicker(
                                    context: c,
                                    initialTime: TimeOfDay.fromDateTime(refTime),
                                  );
                                  if (t != null) {
                                    setS(() {
                                      refTime = DateTime(
                                        refTime.year,
                                        refTime.month,
                                        refTime.day,
                                        t.hour,
                                        t.minute,
                                      );
                                    });
                                  }
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          SegmentedButton<bool>(
                            showSelectedIcon: true,
                            style: SegmentedButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                            ),
                            segments: [
                              ButtonSegment<bool>(
                                value: false,
                                icon: const Icon(Icons.play_arrow_rounded, size: 18),
                                label: Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 4),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        s.isTr ? 'Başlangıç Al' : 'As Start',
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: AppFont.caption),
                                      ),
                                      Text(
                                        '${fmtTime(refTime)}–${fmtTime(refTime.add(Duration(minutes: durMins)))}',
                                        style: TextStyle(
                                          fontSize: AppFont.micro,
                                          color: !isEndMode
                                              ? Theme.of(c).colorScheme.onPrimaryContainer
                                              : Theme.of(c).colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              ButtonSegment<bool>(
                                value: true,
                                icon: const Icon(Icons.flag_rounded, size: 18),
                                label: Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 4),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        s.isTr ? 'Bitiş Al' : 'As End',
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: AppFont.caption),
                                      ),
                                      Text(
                                        '${fmtTime(refTime.subtract(Duration(minutes: durMins)))}–${fmtTime(refTime)}',
                                        style: TextStyle(
                                          fontSize: AppFont.micro,
                                          color: isEndMode
                                              ? Theme.of(c).colorScheme.onPrimaryContainer
                                              : Theme.of(c).colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                            selected: {isEndMode},
                            onSelectionChanged: (Set<bool> sel) {
                              setS(() {
                                isEndMode = sel.first;
                              });
                            },
                          ),
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: Theme.of(c).colorScheme.primaryContainer.withValues(alpha: 0.45),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.check_circle_outline, size: 14, color: Theme.of(c).colorScheme.primary),
                                const SizedBox(width: 6),
                                Text(
                                  '${s.isTr ? "Kayıt Aralığı" : "Interval"}: ${fmtTime(startTime)} – ${fmtTime(endTime)}',
                                  style: TextStyle(
                                    fontSize: AppFont.caption,
                                    fontWeight: FontWeight.w600,
                                    color: Theme.of(c).colorScheme.primary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
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
                    (measureId, qty) = store.entryEditSelection(e, mId, qVal);
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
                    Expanded(
                      child: Text(
                        s.linkedGoals,
                        style: TextStyle(
                          fontSize: AppFont.caption,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(c).colorScheme.primary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                      ),
                      icon: const Icon(Icons.tune, size: 14),
                      label: Text(s.isTr ? 'Hedefleri Düzenle' : 'Manage Goals', style: const TextStyle(fontSize: AppFont.caption)),
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
                            fontSize: AppFont.caption,
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
                                style: const TextStyle(fontSize: AppFont.caption),
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
                        final durMins = calcDurMins(measureId, qty);
                        final startTime = calcStartTime(refTime, isEndMode, durMins);
                        await store.updateEntry(
                          e,
                          activityId: e.activityId,
                          time: startTime,
                          measureId: measureId,
                          qty: qty,
                          note: noteCtrl.text,
                          endTs: durMins > 0 ? startTime.add(Duration(minutes: durMins)).millisecondsSinceEpoch : null,
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
