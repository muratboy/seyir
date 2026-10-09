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
import 'components/today_quick_shortcuts.dart';
import 'components/today_timeline.dart';
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
                  onPressed: () => setState(() => _currentDay = subDays(_currentDay, 1)),
                ),
                InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _currentDay,
                      firstDate: DateTime(2020),
                      lastDate: addDays(DateTime.now(), 365),
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
                  onPressed: () => setState(() => _currentDay = addDays(_currentDay, 1)),
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
                TodayQuickShortcuts(onStartTimer: _startTimerForActivity),
                TodayTimeline(
                  currentDay: _currentDay,
                  onStartTimer: _startTimerForActivity,
                ),
                const SizedBox(height: 40),
              ],
            ),
          ),
        );
      },
    );
  }
}
