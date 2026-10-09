import 'dart:async';

import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/store.dart';
import '../logic/format.dart';
import '../logic/l10n.dart';
import '../services/nl_parser.dart';
import 'common.dart';
import 'components/active_timer_card.dart';
import 'components/today_day_summary.dart';
import 'voice_dialog.dart';

class TodayPage extends StatefulWidget {
  final ValueNotifier<int> focusRequest;
  const TodayPage({super.key, required this.focusRequest});

  @override
  State<TodayPage> createState() => _TodayPageState();
}

class _TodayPageState extends State<TodayPage> {
  DateTime _currentDay = dayStart(DateTime.now());
  final _inputFocus = FocusNode();
  final _textController = TextEditingController();

  // Composer state
  Activity? _selectedActivity;
  String? _draftEmoji;
  int? _selectedMeasureId;
  double _qty = 1.0;
  final _noteController = TextEditingController();
  bool _showOptions = false;

  @override
  void initState() {
    super.initState();
    widget.focusRequest.addListener(_onFocusRequested);
  }

  @override
  void dispose() {
    widget.focusRequest.removeListener(_onFocusRequested);
    _inputFocus.dispose();
    _textController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  void _onFocusRequested() {
    if (mounted) {
      setState(() => _currentDay = dayStart(DateTime.now()));
      _inputFocus.requestFocus();
    }
  }

  void _resetComposer() {
    _textController.clear();
    _noteController.clear();
    setState(() {
      _selectedActivity = null;
      _draftEmoji = null;
      _selectedMeasureId = null;
      _qty = 1.0;
      _showOptions = false;
    });
    _inputFocus.unfocus();
  }

  void _selectActivity(Activity a) {
    final st = store.stats[a.id];
    setState(() {
      _selectedActivity = a;
      _draftEmoji = a.emoji;
      _textController.text = a.name;
      _selectedMeasureId = st?.lastMeasureId;
      _qty = 1.0;
      _showOptions = true;
    });
  }

  Future<void> _submitEntry() async {
    final s = strings.value;
    final text = _textController.text.trim();
    if (text.isEmpty && _selectedActivity == null) return;

    Activity act;
    double finalQty = _qty;
    int? finalMeasureId = _selectedMeasureId;

    if (_selectedActivity != null) {
      act = _selectedActivity!;
      if (_draftEmoji != act.emoji) {
        act.emoji = _draftEmoji;
        await store.updateActivity(act);
      }
    } else {
      // Natural language smart parsing for keyboard input too
      final parsed = NaturalLanguageParser.parse(
        text,
        activities: store.activities.values.toList(),
        measures: store.measures,
      );

      if (parsed.matchedActivity != null) {
        act = parsed.matchedActivity!;
      } else {
        final existing = store.exactMatch(parsed.activityName);
        if (existing != null) {
          act = existing;
        } else {
          act = await store.addActivity(parsed.activityName, emoji: _draftEmoji);
        }
      }

      if (_draftEmoji != null && act.emoji != _draftEmoji) {
        act.emoji = _draftEmoji;
        await store.updateActivity(act);
      }

      if (finalMeasureId == null && parsed.matchedMeasure != null) {
        finalMeasureId = parsed.matchedMeasure!.id;
      }
      if (finalQty == 1.0 && parsed.quantity > 0) {
        finalQty = parsed.quantity;
      }

      // If user typed "kronometre" or "pomodoro" directly in the box
      if (parsed.actionType == NlActionType.startStopwatch) {
        await store.startTimer(act.id, mode: 'stopwatch');
        _resetComposer();
        return;
      } else if (parsed.actionType == NlActionType.startPomodoro) {
        final mins = parsed.targetMinutes ?? 25;
        await store.startTimer(act.id, mode: 'pomodoro', targetMs: mins * 60 * 1000);
        _resetComposer();
        return;
      }
    }

    final entryTime = sameDay(_currentDay, DateTime.now())
        ? DateTime.now()
        : DateTime(_currentDay.year, _currentDay.month, _currentDay.day, 12, 0);

    final res = await store.addEntry(
      act.id,
      measureId: finalMeasureId,
      qty: finalQty,
      at: entryTime,
      note: _noteController.text,
    );

    if (mounted) {
      final actName = act.emoji != null ? '${act.emoji} ${act.name}' : act.name;
      final msg = '$actName ${s.isTr ? "eklendi" : "logged"}';
      showSnack(
        context,
        msg,
        achieved: res.achieved,
        exceeded: res.exceeded,
        undo: () => store.deleteEntry(res.entry),
      );
    }

    _resetComposer();
  }

  Future<void> _openVoiceInput() async {
    final s = strings.value;
    await showVoiceInputDialog(
      context,
      onConfirmed: (result) async {
        Activity act;
        if (result.matchedActivity != null) {
          act = result.matchedActivity!;
        } else {
          act = await store.addActivity(result.activityName);
        }

        if (result.actionType == NlActionType.startStopwatch) {
          await store.startTimer(act.id, mode: 'stopwatch');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(s.isTr ? '${act.name} için kronometre başlatıldı ⏱️' : 'Stopwatch started for ${act.name} ⏱️')),
            );
          }
        } else if (result.actionType == NlActionType.startPomodoro) {
          final mins = result.targetMinutes ?? 25;
          await store.startTimer(act.id, mode: 'pomodoro', targetMs: mins * 60 * 1000);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(s.isTr ? '${act.name} için $mins Dk Pomodoro başlatıldı 🍅' : '$mins min Pomodoro started for ${act.name} 🍅')),
            );
          }
        } else if (result.actionType == NlActionType.startCountdown) {
          final mins = result.targetMinutes ?? result.quantity.round();
          await store.startTimer(act.id, mode: 'countdown', targetMs: mins * 60 * 1000);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(s.isTr ? '${act.name} için $mins Dk Geri Sayım başlatıldı ⌛' : '$mins min Countdown started for ${act.name} ⌛')),
            );
          }
        } else {
          // addEntry
          final entryTime = sameDay(_currentDay, DateTime.now())
              ? DateTime.now()
              : DateTime(_currentDay.year, _currentDay.month, _currentDay.day, 12, 0);
          final res = await store.addEntry(
            act.id,
            measureId: result.matchedMeasure?.id,
            qty: result.quantity,
            at: entryTime,
          );
          if (mounted) {
            final mName = result.matchedMeasure?.name ?? '';
            final qtyStr = result.quantity == result.quantity.roundToDouble()
                ? result.quantity.toInt().toString()
                : result.quantity.toString();
            final actionWord = s.isTr ? 'eklendi' : 'added';
            final msg = '$qtyStr $mName ${act.name} $actionWord ✨'.trim();
            showSnack(
              context,
              msg,
              achieved: res.achieved,
              exceeded: res.exceeded,
              undo: () => store.deleteEntry(res.entry),
            );
          }
        }
      },
    );
  }

  Future<void> _startStopwatchFromComposer() async {
    final s = strings.value;
    final text = _textController.text.trim();
    Activity? act;
    if (_selectedActivity != null) {
      act = _selectedActivity!;
      if (_draftEmoji != act.emoji) {
        act.emoji = _draftEmoji;
        await store.updateActivity(act);
      }
    } else if (text.isNotEmpty) {
      final existing = store.exactMatch(text);
      if (existing != null) {
        act = existing;
        if (_draftEmoji != null && act.emoji != _draftEmoji) {
          act.emoji = _draftEmoji;
          await store.updateActivity(act);
        }
      } else {
        act = await store.addActivity(text, emoji: _draftEmoji);
      }
    } else {
      act = await showActivityPicker(
        context,
        title: s.isTr ? 'Sayaç Başlatmak İçin Seç' : 'Choose Activity for Timer',
      );
      if (act == null || !mounted) return;
    }

    final existing = store.getTimerForActivity(act.id);
    if (existing != null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(s.isTr
                ? '"${act.name}" için zaten bir sayaç çalışıyor!'
                : 'A timer is already active for "${act.name}"!'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
      _resetComposer();
      return;
    }

    if (!mounted) return;
    final config = await showTimerModeDialog(context, act);
    if (config == null || !mounted) return;

    await store.startTimer(
      act.id,
      note: _noteController.text,
      mode: config.mode,
      targetMs: config.targetMs,
    );

    if (mounted) {
      final actName = act.emoji != null ? '${act.emoji} ${act.name}' : act.name;
      final modeStr = config.mode == 'pomodoro'
          ? 'Pomodoro'
          : (config.mode == 'countdown'
              ? (s.isTr ? 'Geri Sayım' : 'Countdown')
              : (s.isTr ? 'Kronometre' : 'Stopwatch'));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$actName $modeStr ${s.isTr ? "başlatıldı" : "started"}'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
    _resetComposer();
  }

  Future<void> _startTimerForActivity(Activity act) async {
    final s = strings.value;
    final existing = store.getTimerForActivity(act.id);
    if (existing != null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(s.isTr
                ? '"${act.name}" için zaten bir sayaç çalışıyor!'
                : 'A timer is already active for "${act.name}"!'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
      return;
    }

    final config = await showTimerModeDialog(context, act);
    if (config == null || !mounted) return;

    await store.startTimer(
      act.id,
      mode: config.mode,
      targetMs: config.targetMs,
    );

    if (mounted) {
      final actName = act.emoji != null ? '${act.emoji} ${act.name}' : act.name;
      final modeStr = config.mode == 'pomodoro'
          ? 'Pomodoro'
          : (config.mode == 'countdown'
              ? (s.isTr ? 'Geri Sayım' : 'Countdown')
              : (s.isTr ? 'Kronometre' : 'Stopwatch'));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$actName $modeStr ${s.isTr ? "başlatıldı" : "started"}'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Widget _buildComposer() {
    final s = strings.value;
    final scheme = Theme.of(context).colorScheme;
    final q = _textController.text.trim();
    final suggestions = store.suggest(q, limit: 5);
    final canAddNew = q.isNotEmpty && store.exactMatch(q) == null && _selectedActivity == null;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                // Emoji button
                InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () async {
                    final chosen = await showEmojiPicker(context, currentEmoji: _draftEmoji);
                    if (chosen != null) setState(() => _draftEmoji = chosen);
                  },
                  child: Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      _draftEmoji?.isNotEmpty == true ? _draftEmoji! : '✨',
                      style: const TextStyle(fontSize: 20),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _textController,
                    focusNode: _inputFocus,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      hintText: s.composerHint,
                      border: InputBorder.none,
                      filled: false,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                      suffixIcon: _textController.text.isNotEmpty || _selectedActivity != null
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                              onPressed: _resetComposer,
                            )
                          : null,
                    ),
                    onChanged: (text) {
                      setState(() {
                        if (_selectedActivity != null && _selectedActivity!.name != text) {
                          _selectedActivity = null;
                        }
                      });
                    },
                    onSubmitted: (_) {
                      if (_showOptions) {
                        _submitEntry();
                      } else {
                        setState(() => _showOptions = true);
                      }
                    },
                  ),
                ),
                const SizedBox(width: 4),
                IconButton.filledTonal(
                  tooltip: s.isTr ? 'Sesli / Akıllı Giriş' : 'Voice / Smart Input',
                  style: IconButton.styleFrom(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.all(8),
                    minimumSize: const Size(38, 38),
                  ),
                  icon: const Icon(Icons.mic, size: 19),
                  onPressed: _openVoiceInput,
                ),
                const SizedBox(width: 4),
                IconButton.filledTonal(
                  tooltip: s.startStopwatch,
                  style: IconButton.styleFrom(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.all(8),
                    minimumSize: const Size(38, 38),
                  ),
                  icon: const Icon(Icons.timer_outlined, size: 19),
                  onPressed: _startStopwatchFromComposer,
                ),
                const SizedBox(width: 4),
                IconButton.filled(
                  tooltip: s.logButton,
                  style: IconButton.styleFrom(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.all(8),
                    minimumSize: const Size(38, 38),
                  ),
                  icon: const Icon(Icons.check_rounded, size: 21),
                  onPressed: (q.isNotEmpty || _selectedActivity != null)
                      ? () {
                          if (!_showOptions && q.isNotEmpty && _selectedActivity == null) {
                            setState(() => _showOptions = true);
                          } else {
                            _submitEntry();
                          }
                        }
                      : null,
                ),
              ],
            ),

            // Suggestions while typing
            if (_selectedActivity == null && (q.isNotEmpty || _inputFocus.hasFocus)) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  for (final a in suggestions)
                    ActionChip(
                      avatar: a.emoji != null ? Text(a.emoji!, style: const TextStyle(fontSize: 16)) : null,
                      label: Text(a.name),
                      onPressed: () => _selectActivity(a),
                    ),
                  if (canAddNew)
                    ActionChip(
                      avatar: const Icon(Icons.add, size: 18),
                      label: Text('${s.addNewAction}: "$q"'),
                      onPressed: () {
                        setState(() {
                          _showOptions = true;
                        });
                      },
                    ),
                ],
              ),
            ],

            // Options expanded (Measure & Quantity)
            if (_showOptions || _selectedActivity != null) ...[
              const Divider(height: 24),
              Row(
                children: [
                  Text(
                    s.selectMeasure,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: scheme.primary,
                    ),
                  ),
                  const Spacer(),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    ),
                    icon: const Icon(Icons.timer_outlined, size: 15),
                    label: Text(s.startStopwatch, style: const TextStyle(fontSize: 12)),
                    onPressed: _startStopwatchFromComposer,
                  ),
                  const SizedBox(width: 4),
                  if (_selectedActivity != null)
                    IconButton(
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      tooltip: s.isTr ? 'Aktiviteyi düzenle' : 'Edit activity',
                      onPressed: () => showActivityEditDialog(context, _selectedActivity!),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              MeasureQtyPicker(
                activityId: _selectedActivity?.id,
                measureId: _selectedMeasureId,
                qty: _qty,
                onChanged: (mId, qVal) {
                  setState(() {
                    _selectedMeasureId = mId;
                    _qty = qVal;
                  });
                },
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _noteController,
                decoration: InputDecoration(
                  hintText: s.noteHint,
                  isDense: true,
                  prefixIcon: const Icon(Icons.notes, size: 20),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _submitEntry,
                icon: const Icon(Icons.check_rounded, size: 18),
                label: Text(s.logButton),
                style: FilledButton.styleFrom(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 11),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildQuickShortcuts() {
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
            onPressed: () => _showAddQuickItemDialog(),
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
                    if (mounted) {
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
                  onLongPress: () => _showQuickItemOptions(item),
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

  Widget _buildTimelineViewToggle() {
    final s = strings.value;
    final isGrid = store.timelineView == 'grid';
    return SegmentedButton<String>(
      style: SegmentedButton.styleFrom(
        visualDensity: VisualDensity.compact,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        side: BorderSide(
          color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      showSelectedIcon: false,
      segments: [
        ButtonSegment<String>(
          value: 'list',
          icon: const Icon(Icons.view_list_rounded, size: 18),
          tooltip: s.isTr ? 'Liste Görünümü' : 'List View',
        ),
        ButtonSegment<String>(
          value: 'grid',
          icon: const Icon(Icons.view_compact_rounded, size: 18),
          tooltip: s.isTr ? 'Kompakt Şerit Görünümü' : 'Compact Strips View',
        ),
      ],
      selected: {isGrid ? 'grid' : 'list'},
      onSelectionChanged: (vals) => store.setTimelineView(vals.first),
    );
  }

  Widget _buildTimeline() {
    final s = strings.value;
    final entries = store.entriesOfDay(_currentDay).reversed.toList();
    final scheme = Theme.of(context).colorScheme;

    if (entries.isEmpty) {
      return Padding(
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
      );
    }

    if (store.timelineView == 'grid') {
      return _buildTimelineGrid(entries);
    }
    return _buildTimelineList(entries);
  }

  Widget _buildTimelineGrid(List<Entry> entries) {
    final scheme = Theme.of(context).colorScheme;
    final s = strings.value;

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 8,
        mainAxisSpacing: 6,
        childAspectRatio: 2.85,
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
            borderRadius: BorderRadius.circular(12),
            side: activeTimer != null
                ? BorderSide(color: Colors.green.shade600, width: 1.5)
                : BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.25)),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => _showEntryEditSheet(entry),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(
                children: [
                  // 1. Minik Avatar
                  ActivityAvatar(act.id, size: 28),
                  const SizedBox(width: 8),

                  // 2. Orta: İsim ve Miktar/Kategori
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                act.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12.5,
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
                        const SizedBox(height: 1),
                        Text(
                          detail.isNotEmpty
                              ? detail
                              : (act.category != null
                                  ? '${act.categoryDef.emoji} ${act.categoryDef.name(s.isTr)}'
                                  : timeStr),
                          style: TextStyle(
                            fontSize: 11,
                            color: scheme.onSurfaceVariant,
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 4),

                  // 3. Sağ: Saat veya Canlı Sayaç
                  if (activeTimer != null) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.green.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
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
                    ),
                  ] else ...[
                    Text(
                      timeStr,
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        color: scheme.primary.withValues(alpha: 0.85),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildTimelineList(List<Entry> entries) {
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
                ? '${fmtTime(entry.time)}–${fmtTime(entry.endTime!)} (${fmtAmount(entry.duration!.inMinutes.toDouble(), 'time')})'
                : '${fmtTime(entry.time)}–${fmtTime(entry.endTime!)}')
            : fmtTime(entry.time);

        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          elevation: 0,
          color: scheme.surfaceContainerLow,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
            leading: ActivityAvatar(act.id, size: 42),
            title: Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          act.name,
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (act.category != null) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                          decoration: BoxDecoration(
                            color: act.displayColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '${act.categoryDef.emoji} ${act.categoryDef.name(s.isTr)}',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: act.displayColor,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Text(
                  timeStr,
                  style: TextStyle(
                    fontSize: 13,
                    color: scheme.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (store.getTimerForActivity(act.id) != null) ...[
                  const SizedBox(height: 3),
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
                          '${s.isTr ? "Sayaç çalışıyor" : "Timer running"} (${store.getTimerForActivity(act.id)!.displayDuration})',
                          style: const TextStyle(fontSize: 11, color: Colors.green, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ],
                if (detail.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      detail,
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                if (entry.note != null)
                  Text(
                    entry.note!,
                    style: TextStyle(
                      fontStyle: FontStyle.italic,
                      color: scheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
              ],
            ),
            onTap: () => _showEntryEditSheet(entry),
          ),
        );
      },
    );
  }

  void _showEntryEditSheet(Entry e) {
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
                        await _startTimerForActivity(act);
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

  void _showAddQuickItemDialog() async {
    final s = strings.value;
    final act = await showActivityPicker(context, title: s.isTr ? 'Hızlı Liste İçin Seç' : 'Choose for Shortcut');
    if (act == null || !mounted) return;

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

  void _showQuickItemOptions(QuickItem item) {
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
                await _startTimerForActivity(act);
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

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final s = strings.value;
        final isToday = sameDay(_currentDay, DateTime.now());
        return Scaffold(
          appBar: AppBar(
            titleSpacing: 8,
            title: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left, size: 22),
                  tooltip: s.isTr ? 'Önceki gün' : 'Previous day',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  onPressed: () => setState(() => _currentDay = _currentDay.subtract(const Duration(days: 1))),
                ),
                InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _currentDay,
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    );
                    if (picked != null) setState(() => _currentDay = dayStart(picked));
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              fmtDayTitle(_currentDay, isTr: s.isTr),
                              style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(width: 3),
                            const Icon(Icons.arrow_drop_down, size: 18),
                          ],
                        ),
                        Text(
                          fmtDateShort(_currentDay, isTr: s.isTr),
                          style: TextStyle(
                            fontSize: 11,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right, size: 22),
                  tooltip: s.isTr ? 'Sonraki gün' : 'Next day',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  onPressed: () => setState(() => _currentDay = _currentDay.add(const Duration(days: 1))),
                ),
              ],
            ),
            actions: [
              if (!isToday)
                IconButton(
                  icon: const Icon(Icons.today_rounded),
                  tooltip: s.isTr ? 'Bugüne dön' : 'Go to today',
                  onPressed: () => setState(() => _currentDay = dayStart(DateTime.now())),
                ),
              IconButton(
                icon: const Icon(Icons.search),
                tooltip: s.isTr ? 'Aktivite Ara' : 'Search Activity',
                onPressed: () async {
                  final a = await showActivityPicker(context);
                  if (a != null) _selectActivity(a);
                },
              ),
            ],
          ),
          body: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (store.activeTimers.isNotEmpty)
                  ActiveTimersSection(timers: store.activeTimers),
                _buildComposer(),
                TodayDaySummary(currentDay: _currentDay),
                _buildQuickShortcuts(),
                SectionTitle(
                  strings.value.timelineTitle,
                  trailing: _buildTimelineViewToggle(),
                ),
                _buildTimeline(),
                const SizedBox(height: 40),
              ],
            ),
          ),
        );
      },
    );
  }
}
