import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/store.dart';
import '../logic/activity_merge.dart';
import '../logic/l10n.dart';
import 'app_font.dart';
import 'common.dart';

/// İki aktiviteyi birleştirmek için ekran.
class ActivityMergePage extends StatefulWidget {
  final Activity? initialFromActivity;
  final Activity? initialIntoActivity;

  const ActivityMergePage({
    super.key,
    this.initialFromActivity,
    this.initialIntoActivity,
  });

  @override
  State<ActivityMergePage> createState() => _ActivityMergePageState();
}

class _ActivityMergePageState extends State<ActivityMergePage> {
  Activity? _fromActivity;
  Activity? _intoActivity;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _fromActivity = widget.initialFromActivity;
    _intoActivity = widget.initialIntoActivity;
  }

  void _swap() {
    setState(() {
      final temp = _fromActivity;
      _fromActivity = _intoActivity;
      _intoActivity = temp;
    });
  }

  ActivityMergeImpact _computeImpact(Activity from, Activity into) {
    final fromCount = store.stats[from.id]?.count ?? 0;
    final intoCount = store.stats[into.id]?.count ?? 0;
    final linkedGoals = store.goalsForActivity(from.id).length;
    final activeTimers = store.activeTimers.where((t) => t.activityId == from.id).length;

    var steps = 0;
    for (final roadmap in store.roadmaps) {
      for (final step in roadmap.steps) {
        if (step.linkedActivityId == from.id) steps++;
      }
    }

    return ActivityMergeImpact(
      fromEntriesCount: fromCount,
      intoEntriesCount: intoCount,
      linkedGoalsCount: linkedGoals,
      activeTimersCount: activeTimers,
      roadmapStepsCount: steps,
    );
  }

  Future<void> _executeMerge() async {
    final from = _fromActivity;
    final into = _intoActivity;
    if (from == null || into == null || from.id == into.id) return;

    final s = strings.value;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.isTr ? 'Aktiviteleri Birleştir' : 'Merge Activities'),
        content: Text(
          s.isTr
              ? '"${from.name}" aktivitesindeki tüm veriler "${into.name}" aktivitesine taşınacak ve "${from.name}" kalıcı olarak silinecektir.\n\nBu işlem geri alınamaz. Devam etmek istiyor musunuz?'
              : 'All entries and links from "${from.name}" will be transferred to "${into.name}", and "${from.name}" will be deleted.\n\nThis cannot be undone. Continue?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(s.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(s.isTr ? 'Evet, Birleştir' : 'Yes, Merge'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    if (!mounted) return;

    setState(() => _isProcessing = true);
    try {
      await store.mergeActivity(from.id, into.id);
      if (!mounted) return;
      showSnack(
        context,
        s.isTr
            ? '"${from.name}" başarıyla "${into.name}" ile birleştirildi.'
            : '"${from.name}" successfully merged into "${into.name}".',
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      showSnack(context, s.isTr ? 'Birleştirme başarısız: $e' : 'Merge failed: $e');
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  void _showActivityPicker({required bool isFrom}) {
    final s = strings.value;
    final currentSelectedId = isFrom ? _fromActivity?.id : _intoActivity?.id;
    final otherSelectedId = isFrom ? _intoActivity?.id : _fromActivity?.id;

    final acts = store.activities.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.7,
          minChildSize: 0.4,
          maxChildSize: 0.9,
          expand: false,
          builder: (sheetContext, scrollController) {
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Row(
                    children: [
                      Icon(
                        isFrom ? Icons.output_rounded : Icons.input_rounded,
                        color: isFrom ? Colors.orange : Colors.green,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          isFrom
                              ? (s.isTr ? 'Kaynak Aktiviteyi Seç (Silinecek)' : 'Select Source Activity (Deleted)')
                              : (s.isTr ? 'Hedef Aktiviteyi Seç (Kalıcı)' : 'Select Target Activity (Survives)'),
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: AppFont.body),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(sheetContext),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView.builder(
                    controller: scrollController,
                    itemCount: acts.length,
                    itemBuilder: (c, i) {
                      final act = acts[i];
                      final isSelected = act.id == currentSelectedId;
                      final isOther = act.id == otherSelectedId;
                      final count = store.stats[act.id]?.count ?? 0;

                      return ListTile(
                        leading: ActivityAvatar(act.id, size: 36),
                        title: Text(
                          act.name,
                          style: TextStyle(
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                            color: isOther ? Colors.grey : null,
                          ),
                        ),
                        subtitle: Text(
                          '$count ${s.isTr ? "kayıt" : "entries"}${isOther ? (s.isTr ? " (Diğer tarafta seçili)" : " (Selected on other side)") : ""}',
                        ),
                        trailing: isSelected
                            ? const Icon(Icons.check_circle, color: Colors.blue)
                            : (isOther ? const Icon(Icons.block, color: Colors.grey, size: 18) : null),
                        enabled: !isOther,
                        onTap: () {
                          setState(() {
                            if (isFrom) {
                              _fromActivity = act;
                            } else {
                              _intoActivity = act;
                            }
                          });
                          Navigator.pop(sheetContext);
                        },
                      );
                    },
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = strings.value;
    final scheme = Theme.of(context).colorScheme;

    final candidates = findMergeCandidates(
      store.activities.values,
      entryCountOf: (id) => store.stats[id]?.count ?? 0,
      goalCountOf: (id) => store.goalsForActivity(id).length,
      isTr: s.isTr,
    );

    final from = _fromActivity;
    final into = _intoActivity;
    final canMerge = from != null && into != null && from.id != into.id && !_isProcessing;
    final impact = (from != null && into != null && from.id != into.id)
        ? _computeImpact(from, into)
        : null;

    return Scaffold(
      appBar: AppBar(
        title: Text(s.isTr ? 'Aktivite Birleştir' : 'Merge Activities'),
      ),
      body: AnimatedBuilder(
        animation: store,
        builder: (context, _) {
          return ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            children: [
              // Bilgi kutusu
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.3)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline, size: 20, color: scheme.primary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        s.isTr
                            ? 'Aynı anlama gelen veya yazım hatasıyla birden fazla açılmış aktiviteleri birleştirin. Kaynak aktivitenin tüm geçmiş kayıtları ve hedefleri hedef aktiviteye taşınır.'
                            : 'Merge duplicate or misspelled activities. All past entries and linked goals from the source activity are safely moved to the target activity.',
                        style: TextStyle(fontSize: AppFont.small, color: scheme.onSurfaceVariant),
                      ),
                    ),
                  ],
                ),
              ),

              // Otomatik Benzerlik Önerileri
              if (candidates.isNotEmpty) ...[
                const SizedBox(height: 16),
                SectionTitle(s.isTr ? 'Önerilen Birleştirmeler' : 'Suggested Merges'),
                const SizedBox(height: 6),
                for (final cand in candidates.take(4))
                  Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                      side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.35)),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: scheme.primaryContainer.withValues(alpha: 0.5),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  cand.reason,
                                  style: TextStyle(
                                    fontSize: AppFont.micro,
                                    fontWeight: FontWeight.w600,
                                    color: scheme.onPrimaryContainer,
                                  ),
                                ),
                              ),
                              const Spacer(),
                              TextButton.icon(
                                style: TextButton.styleFrom(
                                  visualDensity: VisualDensity.compact,
                                  padding: const EdgeInsets.symmetric(horizontal: 8),
                                ),
                                icon: const Icon(Icons.arrow_downward, size: 14),
                                label: Text(s.isTr ? 'Bunu Seç' : 'Select'),
                                onPressed: () {
                                  setState(() {
                                    _fromActivity = cand.from;
                                    _intoActivity = cand.into;
                                  });
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              ActivityAvatar(cand.from.id, size: 28),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  cand.from.name,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: AppFont.body),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const Icon(Icons.arrow_forward_rounded, size: 16, color: Colors.grey),
                              const SizedBox(width: 6),
                              ActivityAvatar(cand.into.id, size: 28),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  cand.into.name,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: AppFont.body),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
              ],

              const SizedBox(height: 16),
              SectionTitle(s.isTr ? 'Aktivite Seçimi' : 'Select Activities'),
              const SizedBox(height: 8),

              // Kaynak Kartı (from)
              _buildSelectionCard(
                title: s.isTr ? 'Kaynak Aktivite (Silinecek)' : 'Source Activity (To be deleted)',
                subtitle: s.isTr
                    ? 'Kayıtları başka bir aktiviteye aktarılıp silinecek olan'
                    : 'Whose records will be moved, then deleted',
                color: Colors.orange,
                activity: from,
                onTap: () => _showActivityPicker(isFrom: true),
                isTr: s.isTr,
              ),

              // Swap butonu
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: IconButton.filledTonal(
                    icon: const Icon(Icons.swap_vert_rounded),
                    tooltip: s.isTr ? 'Yönü Değiştir' : 'Swap Direction',
                    onPressed: (from != null || into != null) ? _swap : null,
                  ),
                ),
              ),

              // Hedef Kartı (into)
              _buildSelectionCard(
                title: s.isTr ? 'Hedef Aktivite (Kalıcı)' : 'Target Activity (Survives)',
                subtitle: s.isTr
                    ? 'Tüm kayıtları devralacak ana aktivite'
                    : 'The primary activity that will receive all records',
                color: Colors.teal,
                activity: into,
                onTap: () => _showActivityPicker(isFrom: false),
                isTr: s.isTr,
              ),

              // Etki Önizlemesi
              if (impact != null) ...[
                const SizedBox(height: 16),
                Card(
                  elevation: 0,
                  color: scheme.surfaceContainerHigh,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.4)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.insights_rounded, size: 18, color: Colors.blue),
                            const SizedBox(width: 8),
                            Text(
                              s.isTr ? 'Birleştirme Özeti' : 'Merge Impact Summary',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: AppFont.body),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        _buildImpactRow(
                          s.isTr ? 'Aktarılacak Kayıt Sayısı' : 'Entries Transferred',
                          '${impact.fromEntriesCount}',
                          Colors.orange,
                        ),
                        _buildImpactRow(
                          s.isTr ? 'Hedefin Mevcut Kayıtları' : 'Target Current Entries',
                          '${impact.intoEntriesCount}',
                          scheme.onSurfaceVariant,
                        ),
                        _buildImpactRow(
                          s.isTr ? 'Birleşim Sonrası Toplam' : 'Total Entries After',
                          '${impact.totalEntriesAfter}',
                          Colors.green,
                          isBold: true,
                        ),
                        if (impact.linkedGoalsCount > 0)
                          _buildImpactRow(
                            s.isTr ? 'Taşınacak Bağlı Hedefler' : 'Linked Goals Transferred',
                            '${impact.linkedGoalsCount}',
                            Colors.blue,
                          ),
                        if (impact.roadmapStepsCount > 0)
                          _buildImpactRow(
                            s.isTr ? 'Taşınacak Yol Haritası Adımları' : 'Roadmap Steps Transferred',
                            '${impact.roadmapStepsCount}',
                            Colors.purple,
                          ),
                        if (impact.activeTimersCount > 0)
                          _buildImpactRow(
                            s.isTr ? 'Taşınacak Aktif Sayaçlar' : 'Active Timers Transferred',
                            '${impact.activeTimersCount}',
                            Colors.amber.shade800,
                          ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: scheme.errorContainer.withValues(alpha: 0.35),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.warning_amber_rounded, size: 16, color: scheme.error),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  s.isTr
                                      ? '"${from!.name}" aktivitesi silinecek, kayıtları "${into!.name}" adı altında saklanacaktır.'
                                      : 'Activity "${from!.name}" will be deleted; records will be preserved under "${into!.name}".',
                                  style: TextStyle(fontSize: AppFont.micro, color: scheme.error, fontWeight: FontWeight.w600),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],

              const SizedBox(height: 24),
              FilledButton.icon(
                key: const Key('merge-confirm-button'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                icon: _isProcessing
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.call_merge_rounded),
                label: Text(s.isTr ? 'Aktiviteleri Birleştir' : 'Merge Activities'),
                onPressed: canMerge ? _executeMerge : null,
              ),
              const SizedBox(height: 24),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSelectionCard({
    required String title,
    required String subtitle,
    required Color color,
    required Activity? activity,
    required VoidCallback onTap,
    required bool isTr,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final count = activity != null ? (store.stats[activity.id]?.count ?? 0) : 0;

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: activity != null ? color.withValues(alpha: 0.5) : scheme.outlineVariant.withValues(alpha: 0.3),
          width: activity != null ? 1.5 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              if (activity != null)
                ActivityAvatar(activity.id, size: 42)
              else
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.touch_app_rounded, color: color, size: 22),
                ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: AppFont.micro,
                        fontWeight: FontWeight.bold,
                        color: color,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      activity?.name ?? (isTr ? 'Aktivite seçmek için dokunun' : 'Tap to select activity'),
                      style: TextStyle(
                        fontSize: AppFont.body,
                        fontWeight: FontWeight.w600,
                        color: activity != null ? scheme.onSurface : scheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (activity != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        '$count ${isTr ? "kayıt mevcut" : "entries exist"}',
                        style: TextStyle(fontSize: AppFont.micro, color: scheme.onSurfaceVariant),
                      ),
                    ] else ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(fontSize: AppFont.micro, color: scheme.outline),
                      ),
                    ],
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildImpactRow(String label, String value, Color color, {bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(label, style: TextStyle(fontSize: AppFont.small, fontWeight: isBold ? FontWeight.bold : FontWeight.normal)),
          ),
          const SizedBox(width: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: AppFont.small,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
