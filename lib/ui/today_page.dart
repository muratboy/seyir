import 'dart:async';

import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/store.dart';
import '../logic/format.dart';
import '../logic/l10n.dart';
import '../services/nl_parser.dart';
import 'common.dart';
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
    final config = await _showTimerModeDialog(context, act);
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

    final config = await _showTimerModeDialog(context, act);
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

  Widget _buildDateHeader() {
    final s = strings.value;
    final isToday = sameDay(_currentDay, DateTime.now());
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            tooltip: s.isTr ? 'Önceki gün' : 'Previous day',
            onPressed: () => setState(() => _currentDay = _currentDay.subtract(const Duration(days: 1))),
          ),
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
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
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(
                  children: [
                    Text(
                      fmtDayTitle(_currentDay),
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      fmtDate(_currentDay),
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            tooltip: s.isTr ? 'Sonraki gün' : 'Next day',
            onPressed: () => setState(() => _currentDay = _currentDay.add(const Duration(days: 1))),
          ),
          if (!isToday)
            IconButton(
              icon: const Icon(Icons.today),
              tooltip: s.isTr ? 'Bugüne dön' : 'Go to today',
              onPressed: () => setState(() => _currentDay = dayStart(DateTime.now())),
            ),
        ],
      ),
    );
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
        padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
        child: Center(
          child: Column(
            children: [
              Icon(Icons.event_note_outlined, size: 48, color: scheme.outline),
              const SizedBox(height: 12),
              Text(
                s.timelineEmpty,
                style: TextStyle(fontSize: 15, color: scheme.onSurfaceVariant),
              ),
            ],
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
        final timeStr = fmtTime(entry.time);
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
        final timeStr = fmtTime(entry.time);

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
                            '${s.isTr ? "Eklenme" : "Logged"}: ${fmtTime(entryTime)} - ${fmtDateShort(entryTime)}',
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
        return Scaffold(
          appBar: AppBar(
            title: Row(
              children: [
                Text(
                  'Takip',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ],
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.search),
                tooltip: strings.value.isTr ? 'Aktivite Ara' : 'Search Activity',
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
                _buildDateHeader(),
                if (store.activeTimers.isNotEmpty)
                  _ActiveTimersSection(timers: store.activeTimers),
                _buildComposer(),
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

class _ActiveTimersSection extends StatefulWidget {
  final List<ActiveTimer> timers;
  const _ActiveTimersSection({required this.timers});

  @override
  State<_ActiveTimersSection> createState() => _ActiveTimersSectionState();
}

class _ActiveTimersSectionState extends State<_ActiveTimersSection> {
  bool _allCollapsed = false;

  @override
  Widget build(BuildContext context) {
    final s = strings.value;
    final scheme = Theme.of(context).colorScheme;
    final count = widget.timers.length;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: scheme.primary.withValues(alpha: 0.4), width: 1.5),
      ),
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Section Header (tıklayınca tümünü açar/kapatır)
          InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => setState(() => _allCollapsed = !_allCollapsed),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.timer_outlined, size: 20, color: scheme.primary),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              s.isTr ? 'Aktif Zamanlayıcılar' : 'Active Timers',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: scheme.primary,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                '$count',
                                style: TextStyle(
                                  color: scheme.onPrimary,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (_allCollapsed) ...[
                          const SizedBox(height: 4),
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: widget.timers.map((t) {
                                final act = store.activity(t.activityId);
                                return Container(
                                  margin: const EdgeInsets.only(right: 6),
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: scheme.surfaceContainerHigh,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    '${act.emoji ?? ''} ${act.name} (${t.displayDuration})',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: scheme.onSurfaceVariant,
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Icon(
                    _allCollapsed ? Icons.expand_more : Icons.expand_less,
                    color: scheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),

          if (!_allCollapsed) ...[
            const Divider(height: 1),
            for (final timer in widget.timers)
              _ActiveTimerCard(
                key: ValueKey(timer.id),
                timer: timer,
              ),
          ],
        ],
      ),
    );
  }
}

class _ActiveTimerCard extends StatefulWidget {
  final ActiveTimer timer;
  const _ActiveTimerCard({super.key, required this.timer});

  @override
  State<_ActiveTimerCard> createState() => _ActiveTimerCardState();
}

class _ActiveTimerCardState extends State<_ActiveTimerCard> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _startTickerIfNeeded();
  }

  @override
  void didUpdateWidget(covariant _ActiveTimerCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.timer.isRunning != oldWidget.timer.isRunning) {
      _startTickerIfNeeded();
    }
  }

  void _startTickerIfNeeded() {
    _ticker?.cancel();
    if (widget.timer.isRunning) {
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = strings.value;
    final scheme = Theme.of(context).colorScheme;
    final act = store.activity(widget.timer.activityId);
    final isRunning = widget.timer.isRunning;
    final durationStr = widget.timer.displayDuration;
    final startTimeStr = fmtTime(widget.timer.startTime);
    final isCollapsed = widget.timer.isCollapsed;

    final modeBadgeText = widget.timer.mode == 'pomodoro'
        ? '🍅 Pomodoro'
        : (widget.timer.mode == 'countdown'
            ? '⏳ Geri Sayım'
            : '⏱️ Kronometre');

    if (isCollapsed) {
      // -------------------------------- KAPALI / KOMPAKT GÖRÜNÜM --------------------------------
      return InkWell(
        onTap: () => store.toggleTimerCollapse(widget.timer.id),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.3))),
          ),
          child: Row(
            children: [
              ActivityAvatar(act.id, size: 34),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      act.name,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      modeBadgeText,
                      style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isRunning ? Colors.green : Colors.amber.shade700,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                durationStr,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'monospace',
                  color: scheme.primary,
                ),
              ),
              IconButton(
                icon: Icon(isRunning ? Icons.pause : Icons.play_arrow, size: 20),
                tooltip: isRunning ? s.pause : s.resume,
                onPressed: () => isRunning
                    ? store.pauseTimer(widget.timer.id)
                    : store.resumeTimer(widget.timer.id),
              ),
              Icon(Icons.expand_more, size: 20, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      );
    }

    // -------------------------------- AÇIK / TAM SAYAÇ GÖRÜNÜMÜ --------------------------------
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.4))),
      ),
      child: Column(
        children: [
          // Header Row: Avatar, Name, Status, Collapse icon, Discard
          Row(
            children: [
              ActivityAvatar(act.id, size: 40),
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
                            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                          decoration: BoxDecoration(
                            color: scheme.secondaryContainer,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            modeBadgeText,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: scheme.onSecondaryContainer,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isRunning ? Colors.green : Colors.amber.shade700,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          isRunning
                              ? '${s.stopwatchRunning} · $startTimeStr'
                              : '${s.stopwatchPaused} · $startTimeStr',
                          style: TextStyle(
                            fontSize: 12,
                            color: scheme.onSurfaceVariant,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.expand_less, size: 22),
                tooltip: s.isTr ? 'Daralt' : 'Collapse',
                onPressed: () => store.toggleTimerCollapse(widget.timer.id),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 20),
                tooltip: s.cancelStopwatch,
                onPressed: () async {
                  final ok = await confirm(
                    context,
                    s.cancelStopwatch,
                    s.cancelStopwatchConfirm,
                    ok: s.cancelStopwatch,
                  );
                  if (ok) {
                    await store.cancelTimer(widget.timer.id);
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Digital Timer
          Center(
            child: Text(
              durationStr,
              style: TextStyle(
                fontSize: 38,
                fontWeight: FontWeight.w800,
                fontFamily: 'monospace',
                letterSpacing: 2.5,
                color: widget.timer.isTargetReached ? Colors.green : scheme.primary,
              ),
            ),
          ),

          // Countdown / Pomodoro Progress Bar
          if (widget.timer.isCountdown) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: widget.timer.progress,
                minHeight: 8,
                backgroundColor: scheme.surfaceContainerHighest,
                valueColor: AlwaysStoppedAnimation<Color>(
                  widget.timer.isTargetReached ? Colors.green : scheme.primary,
                ),
              ),
            ),
            if (widget.timer.isTargetReached) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  s.isTr ? '🎉 Hedef süre tamamlandı!' : '🎉 Target time reached!',
                  style: const TextStyle(
                    color: Colors.green,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ],

          if (widget.timer.note != null && widget.timer.note!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              '📝 ${widget.timer.note}',
              style: TextStyle(
                fontSize: 13,
                fontStyle: FontStyle.italic,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],

          const SizedBox(height: 14),

          // Action Buttons: Durdur/Devam Et & Bitir & Kaydet
          Row(
            children: [
              Expanded(
                child: isRunning
                    ? OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        icon: const Icon(Icons.pause, size: 18),
                        label: Text(s.pause, style: const TextStyle(fontWeight: FontWeight.w600)),
                        onPressed: () => store.pauseTimer(widget.timer.id),
                      )
                    : FilledButton.tonalIcon(
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        icon: const Icon(Icons.play_arrow, size: 18),
                        label: Text(s.resume, style: const TextStyle(fontWeight: FontWeight.w600)),
                        onPressed: () => store.resumeTimer(widget.timer.id),
                      ),
              ),
              const SizedBox(width: 8),
              IconButton.outlined(
                icon: const Icon(Icons.edit_note, size: 20),
                tooltip: s.isTr ? 'Not ekle' : 'Add note',
                onPressed: () async {
                  final noteCtrl = TextEditingController(text: widget.timer.note ?? '');
                  final newNote = await showDialog<String>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: Text(s.isTr ? 'Sayaç Notu' : 'Timer Note'),
                      content: TextField(
                        controller: noteCtrl,
                        autofocus: true,
                        decoration: InputDecoration(
                          hintText: s.isTr ? 'Notunuzu yazın...' : 'Enter note...',
                        ),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: Text(s.cancel),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(ctx, noteCtrl.text),
                          child: Text(s.save),
                        ),
                      ],
                    ),
                  );
                  if (newNote != null) {
                    await store.updateTimerNote(widget.timer.id, newNote);
                  }
                },
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.stop_circle_outlined, size: 18),
                  label: Text(s.finishAndSave, style: const TextStyle(fontWeight: FontWeight.w600)),
                  onPressed: () async {
                    MidnightSplitChoice splitChoice = MidnightSplitChoice.startDay;
                    if (widget.timer.spansMidnight) {
                      final choice = await _showMidnightSplitDialog(context, widget.timer, act);
                      if (choice == null) return;
                      splitChoice = choice;
                    }

                    final res = await store.finishTimer(widget.timer.id, splitChoice);
                    if (res != null && context.mounted) {
                      final finishedAct = store.activity(res.entry.activityId);
                      final detail = store.entryDetail(res.entry);
                      final displayName = finishedAct.emoji != null
                          ? '${finishedAct.emoji} ${finishedAct.name}'
                          : finishedAct.name;
                      final splitMsg = splitChoice == MidnightSplitChoice.split
                          ? (s.isTr ? ' (Gece yarısında bölündü)' : ' (Split at midnight)')
                          : '';
                      showSnack(
                        context,
                        '$displayName: $detail ${s.isTr ? "kaydedildi" : "logged"}$splitMsg',
                        achieved: res.achieved,
                        exceeded: res.exceeded,
                        undo: () => store.deleteEntry(res.entry),
                      );
                    }
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

Future<MidnightSplitChoice?> _showMidnightSplitDialog(
  BuildContext context,
  ActiveTimer timer,
  Activity act,
) async {
  final s = strings.value;
  final scheme = Theme.of(context).colorScheme;
  final totalStr = formatDurationHuman(timer.elapsedMs, s.isTr);
  final beforeStr = formatDurationHuman(timer.msBeforeMidnight, s.isTr);
  final afterStr = formatDurationHuman(timer.msAfterMidnight, s.isTr);

  return showModalBottomSheet<MidnightSplitChoice>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) {
      return Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 16,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.indigo.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.nightlight_round, color: Colors.indigo, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        s.isTr ? 'Gece Yarısı Geçişi Algılandı' : 'Midnight Crossover Detected',
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        '${act.name} · ${s.isTr ? "Toplam" : "Total"}: $totalStr',
                        style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              s.isTr
                  ? 'Bu oturum gece yarısını (00:00) aştı. Sürenin günlere nasıl dağıtılmasını istersiniz?'
                  : 'This session crossed midnight (00:00). How would you like to distribute the duration across days?',
              style: TextStyle(fontSize: 13.5, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),

            // Seçenek 1: Gece yarısında böl (Önerilen)
            Card(
              elevation: 0,
              color: scheme.primaryContainer.withValues(alpha: 0.35),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: scheme.primary.withValues(alpha: 0.5)),
              ),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: scheme.primary,
                  child: Icon(Icons.call_split_rounded, color: scheme.onPrimary, size: 20),
                ),
                title: Row(
                  children: [
                    Text(
                      s.isTr ? 'Gece Yarısında Böl' : 'Split at Midnight',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                      decoration: BoxDecoration(
                        color: scheme.primary,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        s.isTr ? 'Önerilen' : 'Recommended',
                        style: TextStyle(color: scheme.onPrimary, fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                subtitle: Text(
                  s.isTr
                      ? 'Dün: $beforeStr · Bugün: $afterStr'
                      : 'Yesterday: $beforeStr · Today: $afterStr',
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.pop(ctx, MidnightSplitChoice.split),
              ),
            ),
            const SizedBox(height: 8),

            // Seçenek 2: Tamamını düne (başlangıç gününe) yaz
            Card(
              elevation: 0,
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Colors.blueGrey,
                  child: Icon(Icons.history_toggle_off_rounded, color: Colors.white, size: 20),
                ),
                title: Text(
                  s.isTr ? 'Tamamını Düne Yaz' : 'Log All to Yesterday',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text(
                  s.isTr
                      ? 'Dünün hanesine tek parça $totalStr eklenir'
                      : 'Logs entire $totalStr to start day',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.pop(ctx, MidnightSplitChoice.startDay),
              ),
            ),
            const SizedBox(height: 8),

            // Seçenek 3: Tamamını bugüne (bitiş gününe) yaz
            Card(
              elevation: 0,
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Colors.teal,
                  child: Icon(Icons.today_rounded, color: Colors.white, size: 20),
                ),
                title: Text(
                  s.isTr ? 'Tamamını Bugüne Yaz' : 'Log All to Today',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text(
                  s.isTr
                      ? 'Bugünün hanesine tek parça $totalStr eklenir'
                      : 'Logs entire $totalStr to end day',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.pop(ctx, MidnightSplitChoice.endDay),
              ),
            ),
            const SizedBox(height: 12),

            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(s.cancel),
            ),
          ],
        ),
      );
    },
  );
}

class _TimerConfig {
  final String mode; // 'stopwatch', 'pomodoro', 'countdown'
  final int targetMs;
  const _TimerConfig({required this.mode, required this.targetMs});
}

Future<_TimerConfig?> _showTimerModeDialog(BuildContext context, Activity act) async {
  final s = strings.value;
  return showModalBottomSheet<_TimerConfig>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) {
      int customMinutes = 15;
      return StatefulBuilder(
        builder: (ctx, setSheetState) {
          return Padding(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 20,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    ActivityAvatar(act.id, size: 36),
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
                            s.isTr ? 'Sayaç türünü seçin' : 'Select timer mode',
                            style: TextStyle(fontSize: 13, color: Theme.of(ctx).colorScheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // 1. Standart Kronometre
                Card(
                  elevation: 0,
                  color: Theme.of(ctx).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: ListTile(
                    leading: const CircleAvatar(
                      backgroundColor: Colors.blue,
                      child: Icon(Icons.timer_outlined, color: Colors.white, size: 20),
                    ),
                    title: Text(s.isTr ? '⏱️ Kronometre' : '⏱️ Stopwatch', style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text(s.isTr ? 'İleriye doğru sayar (00:00 → ...)' : 'Counts forward from 00:00'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.pop(ctx, const _TimerConfig(mode: 'stopwatch', targetMs: 0)),
                  ),
                ),
                const SizedBox(height: 8),

                // 2. Pomodoro (25 Dk)
                Card(
                  elevation: 0,
                  color: Theme.of(ctx).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: ListTile(
                    leading: const CircleAvatar(
                      backgroundColor: Colors.redAccent,
                      child: Text('🍅', style: TextStyle(fontSize: 18)),
                    ),
                    title: Text(s.isTr ? '🍅 Pomodoro (25 Dk)' : '🍅 Pomodoro (25 Min)', style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text(s.isTr ? '25 dakika odaklanma periyodu' : '25-minute focus session'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.pop(ctx, const _TimerConfig(mode: 'pomodoro', targetMs: 25 * 60 * 1000)),
                  ),
                ),
                const SizedBox(height: 8),

                // 3. Özel Geri Sayım
                Card(
                  elevation: 0,
                  color: Theme.of(ctx).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const CircleAvatar(
                              backgroundColor: Colors.orange,
                              child: Icon(Icons.hourglass_bottom, color: Colors.white, size: 20),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    s.isTr ? '⏳ Özel Geri Sayım' : '⏳ Custom Countdown',
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                  ),
                                  Text(
                                    s.isTr ? 'Süre bitince otomatik uyarır' : 'Alerts when time is up',
                                    style: TextStyle(fontSize: 12, color: Theme.of(ctx).colorScheme.onSurfaceVariant),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          children: [5, 10, 15, 30, 45, 60].map((m) {
                            final sel = customMinutes == m;
                            return ChoiceChip(
                              label: Text('$m dk'),
                              selected: sel,
                              onSelected: (_) => setSheetState(() => customMinutes = m),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerRight,
                          child: FilledButton.icon(
                            icon: const Icon(Icons.play_arrow, size: 18),
                            label: Text(s.isTr ? '$customMinutes Dk Başlat' : 'Start $customMinutes Min'),
                            onPressed: () => Navigator.pop(
                              ctx,
                              _TimerConfig(mode: 'countdown', targetMs: customMinutes * 60 * 1000),
                            ),
                          ),
                        ),
                      ],
                    ),
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

