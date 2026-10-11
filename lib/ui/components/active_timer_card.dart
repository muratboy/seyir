import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/models.dart';
import '../../data/store.dart';
import '../../logic/format.dart';
import '../../logic/l10n.dart';
import '../common.dart';

class TimerConfig {
  final String mode; // 'stopwatch', 'pomodoro', 'countdown'
  final int targetMs;
  const TimerConfig({required this.mode, required this.targetMs});
}

Future<TimerConfig?> showTimerModeDialog(BuildContext context, Activity act) async {
  return showModalBottomSheet<TimerConfig>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => _TimerModeSheet(act: act),
  );
}

class _TimerModeSheet extends StatefulWidget {
  final Activity act;
  const _TimerModeSheet({required this.act});

  @override
  State<_TimerModeSheet> createState() => _TimerModeSheetState();
}

class _TimerModeSheetState extends State<_TimerModeSheet> {
  late final TextEditingController _minCtrl;
  int _customMinutes = 15;
  static const _presetMinutes = [5, 10, 15, 20, 25, 30, 45, 60];

  @override
  void initState() {
    super.initState();
    _minCtrl = TextEditingController(text: '$_customMinutes');
  }

  @override
  void dispose() {
    _minCtrl.dispose();
    super.dispose();
  }

  void _onMinutesChanged(String text) {
    final parsed = int.tryParse(text.trim());
    setState(() {
      _customMinutes = (parsed != null && parsed > 0) ? parsed : 0;
    });
  }

  void _selectPreset(int minutes) {
    setState(() {
      _customMinutes = minutes;
      _minCtrl.text = '$minutes';
      _minCtrl.selection = TextSelection.fromPosition(
        TextPosition(offset: _minCtrl.text.length),
      );
    });
  }

  void _startCountdown() {
    final parsed = int.tryParse(_minCtrl.text.trim()) ?? _customMinutes;
    if (parsed > 0) {
      Navigator.pop(
        context,
        TimerConfig(mode: 'countdown', targetMs: parsed * 60 * 1000),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = strings.value;
    final act = widget.act;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: bottomInset + 24,
      ),
      child: SingleChildScrollView(
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
                        style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant),
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
              color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Colors.blue,
                  child: Icon(Icons.timer_outlined, color: Colors.white, size: 20),
                ),
                title: Text(s.isTr ? '⏱️ Kronometre' : '⏱️ Stopwatch', style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text(s.isTr ? 'İleriye doğru sayar (00:00 → ...)' : 'Counts forward from 00:00'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.pop(context, const TimerConfig(mode: 'stopwatch', targetMs: 0)),
              ),
            ),
            const SizedBox(height: 8),

            // 2. Pomodoro (25 Dk)
            Card(
              elevation: 0,
              color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Colors.redAccent,
                  child: Text('🍅', style: TextStyle(fontSize: 18)),
                ),
                title: Text(s.isTr ? '🍅 Pomodoro (25 Dk)' : '🍅 Pomodoro (25 Min)', style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text(s.isTr ? '25 dakika odaklanma periyodu' : '25-minute focus session'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.pop(context, const TimerConfig(mode: 'pomodoro', targetMs: 25 * 60 * 1000)),
              ),
            ),
            const SizedBox(height: 8),

            // 3. Özel Geri Sayım
            Card(
              elevation: 0,
              color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
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
                                style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
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
                      children: _presetMinutes.map((m) {
                        final sel = _customMinutes == m;
                        return ChoiceChip(
                          label: Text('$m dk'),
                          selected: sel,
                          onSelected: (_) => _selectPreset(m),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _minCtrl,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                              LengthLimitingTextInputFormatter(4),
                            ],
                            decoration: InputDecoration(
                              labelText: s.isTr ? 'Süre (dk)' : 'Minutes',
                              hintText: 'Örn: 20',
                              suffixText: s.isTr ? 'dk' : 'min',
                              prefixIcon: const Icon(Icons.keyboard_outlined, size: 20),
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            onChanged: _onMinutesChanged,
                            onSubmitted: (_) => _startCountdown(),
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton.icon(
                          icon: const Icon(Icons.play_arrow, size: 18),
                          label: Text(_customMinutes > 0
                              ? (s.isTr ? '$_customMinutes Dk Başlat' : 'Start $_customMinutes Min')
                              : (s.isTr ? 'Başlat' : 'Start')),
                          onPressed: _customMinutes > 0 ? _startCountdown : null,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ActiveTimersSection extends StatefulWidget {
  final List<ActiveTimer> timers;
  const ActiveTimersSection({super.key, required this.timers});

  @override
  State<ActiveTimersSection> createState() => _ActiveTimersSectionState();
}

class _ActiveTimersSectionState extends State<ActiveTimersSection> {
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
              ActiveTimerCard(
                key: ValueKey(timer.id),
                timer: timer,
              ),
          ],
        ],
      ),
    );
  }
}

class ActiveTimerCard extends StatefulWidget {
  final ActiveTimer timer;
  const ActiveTimerCard({super.key, required this.timer});

  @override
  State<ActiveTimerCard> createState() => _ActiveTimerCardState();
}

class _ActiveTimerCardState extends State<ActiveTimerCard> {
  Timer? _ticker;
  bool _alertPlayed = false;

  @override
  void initState() {
    super.initState();
    _alertPlayed = widget.timer.isTargetReached;
    _startTickerIfNeeded();
  }

  @override
  void didUpdateWidget(covariant ActiveTimerCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.timer.isRunning != oldWidget.timer.isRunning) {
      _startTickerIfNeeded();
    }
  }

  void _startTickerIfNeeded() {
    _ticker?.cancel();
    if (widget.timer.isRunning) {
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        if (widget.timer.isTargetReached) {
          if (store.timerAutoSaveCompleted) {
            store.checkCompletedTimers();
            return;
          }
          if (!_alertPlayed) {
            _alertPlayed = true;
            if (store.timerSoundEnabled) {
              HapticFeedback.heavyImpact();
              SystemSound.play(SystemSoundType.alert);
            }
          }
        } else {
          _alertPlayed = false;
        }
        setState(() {});
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
                  fontFamily: 'monospace',
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: widget.timer.isTargetReached
                      ? Colors.green
                      : (isRunning ? scheme.primary : scheme.onSurfaceVariant),
                ),
              ),
              const SizedBox(width: 6),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: Icon(
                  isRunning ? Icons.pause_circle_outline : Icons.play_circle_outline,
                  color: scheme.primary,
                  size: 24,
                ),
                onPressed: () {
                  if (isRunning) {
                    store.pauseTimer(widget.timer.id);
                  } else {
                    store.resumeTimer(widget.timer.id);
                  }
                },
              ),
              Icon(Icons.expand_more, size: 20, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      );
    }

    // -------------------------------- AÇIK / DETAYLI GÖRÜNÜM --------------------------------
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.3))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Üst Satır: Avatar + İsim + Mod Rozeti + Daralt Düğmesi
          Row(
            children: [
              ActivityAvatar(act.id, size: 38),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      act.name,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: widget.timer.mode == 'pomodoro'
                                ? Colors.red.withValues(alpha: 0.15)
                                : (widget.timer.mode == 'countdown'
                                    ? Colors.orange.withValues(alpha: 0.15)
                                    : Colors.blue.withValues(alpha: 0.15)),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            modeBadgeText,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: widget.timer.mode == 'pomodoro'
                                  ? Colors.red
                                  : (widget.timer.mode == 'countdown' ? Colors.orange : Colors.blue),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '$startTimeStr\'de başladı',
                          style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: Icon(Icons.expand_less, size: 20, color: scheme.onSurfaceVariant),
                tooltip: s.isTr ? 'Daralt' : 'Collapse',
                onPressed: () => store.toggleTimerCollapse(widget.timer.id),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.close, size: 20, color: Colors.redAccent),
                tooltip: s.cancelStopwatch,
                onPressed: () => _confirmDiscardTimer(context),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Süre Sayacı & Durum
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: widget.timer.isTargetReached
                    ? Colors.green.withValues(alpha: 0.6)
                    : scheme.outlineVariant.withValues(alpha: 0.3),
              ),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isRunning ? Colors.green : Colors.amber.shade700,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      durationStr,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 32,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 2,
                        color: widget.timer.isTargetReached
                            ? Colors.green
                            : (isRunning ? scheme.primary : scheme.onSurfaceVariant),
                      ),
                    ),
                  ],
                ),
                if (widget.timer.hasTarget) ...[
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: widget.timer.progress,
                      minHeight: 6,
                      backgroundColor: scheme.surfaceContainerHighest,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        widget.timer.isTargetReached ? Colors.green : scheme.primary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        widget.timer.isTargetReached
                            ? (s.isTr ? 'Hedef süre tamamlandı! 🎉' : 'Target reached! 🎉')
                            : (widget.timer.isCountdown
                                ? '${formatTimerDuration(widget.timer.remainingMs)} kaldı'
                                : '${formatTimerDuration(widget.timer.elapsedMs)} / ${formatTimerDuration(widget.timer.targetMs)}'),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: widget.timer.isTargetReached ? Colors.green : scheme.onSurfaceVariant,
                        ),
                      ),
                      Text(
                        '${(widget.timer.progress * 100).toInt()}%',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),

          if (widget.timer.note != null && widget.timer.note!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.notes, size: 14, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      widget.timer.note!,
                      style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
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

  void _confirmDiscardTimer(BuildContext context) {
    final s = strings.value;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.cancelStopwatch),
        content: Text(s.cancelStopwatchConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(s.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              store.discardTimer(widget.timer.id);
              Navigator.pop(ctx);
            },
            child: Text(s.delete),
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
                    color: scheme.primaryContainer,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.nightlight_round, color: scheme.primary, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        s.isTr ? 'Gece Yarısı Geçişi Saptandı' : 'Midnight Crossover Detected',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      Text(
                        '${act.name} · Toplam $totalStr',
                        style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              s.isTr
                  ? 'Bu aktivite dün gece başladı ve gece yarısından sonra devam etti. Süreyi nasıl kaydetmek istersiniz?'
                  : 'This activity began yesterday and ended today after midnight. How would you like to record it?',
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 16),

            // Seçenek 1: Böl (Önerilen)
            Card(
              elevation: 0,
              color: scheme.primaryContainer.withValues(alpha: 0.3),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(color: scheme.primary.withValues(alpha: 0.5)),
              ),
              child: ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Colors.indigo,
                  child: Icon(Icons.call_split, color: Colors.white, size: 20),
                ),
                title: Text(
                  s.isTr ? 'Gerektiği Gibi Böl (Önerilen)' : 'Split across days (Recommended)',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                subtitle: Text(
                  s.isTr
                      ? 'Dün: $beforeStr · Bugün: $afterStr'
                      : 'Yesterday: $beforeStr · Today: $afterStr',
                  style: const TextStyle(fontSize: 12),
                ),
                onTap: () => Navigator.pop(ctx, MidnightSplitChoice.split),
              ),
            ),
            const SizedBox(height: 8),

            // Seçenek 2: Başlangıç gününe (Düne) yaz
            Card(
              elevation: 0,
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: scheme.surfaceContainerHigh,
                  child: Icon(Icons.today, color: scheme.onSurfaceVariant, size: 20),
                ),
                title: Text(
                  s.isTr ? 'Tamamını Başlangıç Gününe Yaz' : 'Attribute all to Start Day',
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                ),
                subtitle: Text(
                  s.isTr ? 'Düne $totalStr eklenir' : '$totalStr added to yesterday',
                  style: const TextStyle(fontSize: 11),
                ),
                onTap: () => Navigator.pop(ctx, MidnightSplitChoice.startDay),
              ),
            ),
            const SizedBox(height: 8),

            // Seçenek 3: Bitiş gününe (Bugüne) yaz
            Card(
              elevation: 0,
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: scheme.surfaceContainerHigh,
                  child: Icon(Icons.event_available, color: scheme.onSurfaceVariant, size: 20),
                ),
                title: Text(
                  s.isTr ? 'Tamamını Bitiş Gününe Yaz' : 'Attribute all to Finish Day',
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                ),
                subtitle: Text(
                  s.isTr ? 'Bugüne $totalStr eklenir' : '$totalStr added to today',
                  style: const TextStyle(fontSize: 11),
                ),
                onTap: () => Navigator.pop(ctx, MidnightSplitChoice.endDay),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.pop(ctx, null),
              child: Text(s.cancel),
            ),
          ],
        ),
      );
    },
  );
}
