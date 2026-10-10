import 'package:flutter/material.dart';
import '../../data/store.dart';
import '../../logic/format.dart';
import '../../logic/l10n.dart';

class TodayHealthPanel extends StatelessWidget {
  final DateTime currentDay;
  final VoidCallback onRefresh;

  const TodayHealthPanel({
    super.key,
    required this.currentDay,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final s = strings.value;
    final scheme = Theme.of(context).colorScheme;

    // Eğer her iki özellik de kapalıysa tek bir piksel bile yer kaplamaz
    if (!store.stepTrackerEnabled && !store.sleepTrackerEnabled) {
      return const SizedBox.shrink();
    }

    final isToday = sameDay(currentDay, DateTime.now());

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. ADIM SAYAR KARTI
          if (store.stepTrackerEnabled) ...[
            _buildStepCard(context, s, scheme, isToday),
            const SizedBox(height: 8),
          ],

          // 2. UYKU TAKİBİ KARTI
          if (store.sleepTrackerEnabled) ...[
            _buildSleepCard(context, s, scheme, isToday),
            const SizedBox(height: 6),
          ],
        ],
      ),
    );
  }

  Widget _buildStepCard(BuildContext context, AppStrings s, ColorScheme scheme, bool isToday) {
    final steps = store.todaySteps;
    final goal = store.stepDailyGoal;
    final pct = (goal > 0 ? (steps / goal) : 0.0).clamp(0.0, 1.0);
    final kcal = (steps * 0.04).round();
    final km = (steps * 0.00075).toStringAsFixed(1);

    return Card(
      elevation: 0,
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.teal.withValues(alpha: 0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: Colors.teal.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  alignment: Alignment.center,
                  child: const Text('👟', style: TextStyle(fontSize: 20)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            s.isTr ? 'Adım Sayar' : 'Step Counter',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                          const Spacer(),
                          Text(
                            '${fmtNum(steps.toDouble())} / ${fmtNum(goal.toDouble())}',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.bold,
                              color: Colors.teal.shade700,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          value: pct,
                          minHeight: 6,
                          backgroundColor: Colors.teal.withValues(alpha: 0.12),
                          valueColor: AlwaysStoppedAnimation<Color>(
                            pct >= 1.0 ? Colors.green : Colors.teal,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Text(
                            '🔥 $kcal kcal · 📍 $km km',
                            style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                          ),
                          const Spacer(),
                          Text(
                            '%${(pct * 100).toInt()}',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.teal.shade700),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Wrap(
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 6,
              runSpacing: 4,
              children: [
                ActionChip(
                  visualDensity: VisualDensity.compact,
                  avatar: const Icon(Icons.add, size: 14),
                  label: const Text('+500', style: TextStyle(fontSize: 11)),
                  onPressed: () async {
                    await store.addManualSteps(500);
                    onRefresh();
                  },
                ),
                ActionChip(
                  visualDensity: VisualDensity.compact,
                  avatar: const Icon(Icons.add, size: 14),
                  label: const Text('+1000', style: TextStyle(fontSize: 11)),
                  onPressed: () async {
                    await store.addManualSteps(1000);
                    onRefresh();
                  },
                ),
                FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                  ),
                  icon: const Icon(Icons.sync, size: 14),
                  label: Text(s.syncSteps, style: const TextStyle(fontSize: 11.5)),
                  onPressed: () async {
                    final res = await store.syncTodayStepsToEntry();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(res != null
                              ? (s.isTr
                                  ? '${fmtNum(steps.toDouble())} adım kaydedildi ✓'
                                  : '${fmtNum(steps.toDouble())} steps logged ✓')
                              : (s.isTr ? 'Adım sayısı henüz 0.' : 'Steps currently 0.')),
                        ),
                      );
                      onRefresh();
                    }
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSleepCard(BuildContext context, AppStrings s, ColorScheme scheme, bool isToday) {
    final activeStartTs = store.sleepSessionStartTs;
    final isSessionActive = activeStartTs != null;
    final loggedHours = store.getTodaySleepHours(currentDay);
    final goalHours = store.sleepDailyGoalHours;
    final pct = (goalHours > 0 ? (loggedHours / goalHours) : 0.0).clamp(0.0, 1.0);

    if (isSessionActive) {
      final start = DateTime.fromMillisecondsSinceEpoch(activeStartTs);
      final elapsedMins = DateTime.now().difference(start).inMinutes;
      final elapsedStr = '${elapsedMins ~/ 60} sa ${elapsedMins % 60} dk';

      return Card(
        elevation: 0,
        color: Colors.indigo.withValues(alpha: 0.12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Colors.indigo.shade400, width: 1.5),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              const Text('😴', style: TextStyle(fontSize: 26)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s.isTr ? 'Uyku Oturumu Aktif' : 'Sleep Session Active',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.indigo),
                    ),
                    Text(
                      '${s.isTr ? "Yatma" : "Bedtime"}: ${fmtTime(start)} · $elapsedStr',
                      style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.indigo,
                  visualDensity: VisualDensity.compact,
                ),
                icon: const Icon(Icons.wb_sunny_outlined, size: 15),
                label: Text(s.wakeUp, style: const TextStyle(fontSize: 12)),
                onPressed: () async {
                  final entry = await store.stopSleepSession();
                  if (context.mounted && entry != null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(s.isTr
                            ? 'Günaydın! ${entry.qty} sa uyku kaydedildi 🛌'
                            : 'Good morning! ${entry.qty} hrs sleep logged 🛌'),
                      ),
                    );
                    onRefresh();
                  }
                },
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      elevation: 0,
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.indigo.withValues(alpha: 0.25)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: Colors.indigo.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  alignment: Alignment.center,
                  child: const Text('🛌', style: TextStyle(fontSize: 20)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            s.isTr ? 'Uyku Takibi' : 'Sleep Tracker',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                          const Spacer(),
                          Text(
                            '${fmtNum1(loggedHours)} / ${fmtNum1(goalHours)} sa',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.bold,
                              color: Colors.indigo.shade600,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          value: pct,
                          minHeight: 6,
                          backgroundColor: Colors.indigo.withValues(alpha: 0.12),
                          valueColor: AlwaysStoppedAnimation<Color>(
                            pct >= 1.0 ? Colors.green : Colors.indigo,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Text(
                            loggedHours > 0
                                ? (s.isTr ? 'Bugün kaydedilen uyku' : 'Logged sleep today')
                                : (s.isTr ? 'Henüz uyku girilmedi' : 'No sleep logged yet'),
                            style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                          ),
                          const Spacer(),
                          Text(
                            '%${(pct * 100).toInt()}',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.indigo.shade600),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Wrap(
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 4,
              children: [
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
                  icon: const Icon(Icons.nights_stay_outlined, size: 14, color: Colors.indigo),
                  label: Text(s.startSleepSession, style: const TextStyle(fontSize: 11.5)),
                  onPressed: () async {
                    await store.startSleepSession();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(s.isTr
                              ? 'İyi geceler! Uyku oturumu başlatıldı 🌙'
                              : 'Good night! Sleep session started 🌙'),
                        ),
                      );
                      onRefresh();
                    }
                  },
                ),
                FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
                  icon: const Icon(Icons.add, size: 14),
                  label: Text(s.logSleep, style: const TextStyle(fontSize: 11.5)),
                  onPressed: () => _showManualSleepDialog(context, s),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showManualSleepDialog(BuildContext context, AppStrings s) {
    TimeOfDay bedTime = const TimeOfDay(hour: 23, minute: 30);
    TimeOfDay wakeTime = const TimeOfDay(hour: 7, minute: 30);

    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) {
          final bedDt = DateTime(2026, 1, 1, bedTime.hour, bedTime.minute);
          var wakeDt = DateTime(2026, 1, 2, wakeTime.hour, wakeTime.minute);
          if (wakeDt.isBefore(bedDt)) {
            wakeDt = wakeDt.add(const Duration(days: 1));
          }
          final durMins = wakeDt.difference(bedDt).inMinutes;
          final durHours = durMins / 60.0;

          return AlertDialog(
            title: Row(
              children: [
                const Text('🛌 '),
                Text(s.isTr ? 'Uyku Kaydı Gir' : 'Log Sleep'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  title: Text(s.isTr ? 'Yatma Saati' : 'Bedtime'),
                  trailing: TextButton(
                    child: Text(bedTime.format(ctx)),
                    onPressed: () async {
                      final picked = await showTimePicker(context: ctx, initialTime: bedTime);
                      if (picked != null) setD(() => bedTime = picked);
                    },
                  ),
                ),
                ListTile(
                  title: Text(s.isTr ? 'Uyanma Saati' : 'Wake Time'),
                  trailing: TextButton(
                    child: Text(wakeTime.format(ctx)),
                    onPressed: () async {
                      final picked = await showTimePicker(context: ctx, initialTime: wakeTime);
                      if (picked != null) setD(() => wakeTime = picked);
                    },
                  ),
                ),
                const Divider(),
                Text(
                  '${s.isTr ? "Toplam Süre" : "Total Duration"}: ${durHours.toStringAsFixed(1)} sa ($durMins dk)',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(s.isTr ? 'İptal' : 'Cancel'),
              ),
              FilledButton(
                onPressed: () async {
                  Navigator.pop(ctx);
                  final today = DateTime.now();
                  final end = DateTime(today.year, today.month, today.day, wakeTime.hour, wakeTime.minute);
                  final start = end.subtract(Duration(minutes: durMins));
                  await store.logManualSleep(start: start, end: end);
                  onRefresh();
                },
                child: Text(s.isTr ? 'Kaydet' : 'Save'),
              ),
            ],
          );
        },
      ),
    );
  }
}
