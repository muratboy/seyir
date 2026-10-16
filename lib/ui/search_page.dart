import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/models.dart';
import '../data/store.dart';
import '../logic/format.dart';
import '../logic/l10n.dart';
import '../logic/text_match.dart';
import 'activity_page.dart';
import 'app_font.dart';
import 'components/today_timeline.dart';
import 'roadmap_detail_page.dart';

/// Tüm kayıtlar, notlar, aktiviteler ve yol haritaları arasında anlık arama delegesi.
class TakipSearchDelegate extends SearchDelegate<dynamic> {
  final AppStore store;

  TakipSearchDelegate({required this.store});

  @override
  String get searchFieldLabel => strings.value.isTr ? 'Kayıt, not veya aktivite ara...' : 'Search logs, notes, activities...';

  @override
  ThemeData appBarTheme(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return theme.copyWith(
      appBarTheme: theme.appBarTheme.copyWith(
        backgroundColor: scheme.surface,
        iconTheme: IconThemeData(color: scheme.onSurface),
        titleSpacing: 0,
        elevation: 0,
      ),
      inputDecorationTheme: InputDecorationTheme(
        hintStyle: TextStyle(color: scheme.onSurfaceVariant, fontSize: AppFont.body),
        border: InputBorder.none,
      ),
    );
  }

  @override
  List<Widget>? buildActions(BuildContext context) {
    return [
      if (query.isNotEmpty)
        IconButton(
          icon: const Icon(Icons.clear, size: 20),
          tooltip: strings.value.isTr ? 'Temizle' : 'Clear',
          onPressed: () {
            query = '';
            showSuggestions(context);
          },
        ),
    ];
  }

  @override
  Widget? buildLeading(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.arrow_back),
      tooltip: strings.value.isTr ? 'Geri' : 'Back',
      onPressed: () => close(context, null),
    );
  }

  @override
  Widget buildResults(BuildContext context) => _buildSearchResults(context);

  @override
  Widget buildSuggestions(BuildContext context) => _buildSearchResults(context);

  Widget _buildSearchResults(BuildContext context) {
    final s = strings.value;
    final isTr = s.isTr;
    final scheme = Theme.of(context).colorScheme;
    final q = query.trim();
    final normQ = normalizeTr(q);

    // Boş sorgu: Son notlar ve sık kullanılan aktiviteler
    if (normQ.isEmpty) {
      final recentNotesEntries = store.entries.reversed
          .where((e) => e.note != null && e.note!.trim().isNotEmpty)
          .take(10)
          .toList();

      final topActivities = store.activities.values
          .where((a) => !a.isArchived)
          .toList()
        ..sort((a, b) => (store.stats[b.id]?.count ?? 0).compareTo(store.stats[a.id]?.count ?? 0));

      return ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          if (topActivities.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                isTr ? 'Sık Yapılan Aktiviteler' : 'Frequent Activities',
                style: TextStyle(
                  fontSize: AppFont.small,
                  fontWeight: FontWeight.bold,
                  color: scheme.primary,
                ),
              ),
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final act in topActivities.take(8))
                  ActionChip(
                    avatar: Text(act.emoji ?? '⚡', style: const TextStyle(fontSize: AppFont.caption)),
                    label: Text(act.name),
                    onPressed: () => close(context, act),
                  ),
              ],
            ),
            const SizedBox(height: 20),
          ],
          if (recentNotesEntries.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                isTr ? 'Son Eklenen Notlar' : 'Recent Notes',
                style: TextStyle(
                  fontSize: AppFont.small,
                  fontWeight: FontWeight.bold,
                  color: scheme.primary,
                ),
              ),
            ),
            for (final e in recentNotesEntries) _buildEntryTile(context, e, normQ),
          ],
        ],
      );
    }

    // Arama eşleşmeleri:
    // 1. Aktiviteler
    final matchingActivities = store.activities.values
        .where((a) => normalizeTr(a.name).contains(normQ) || normalizeTr(a.categoryDef.name(isTr)).contains(normQ))
        .toList();

    // 2. Kayıtlar ve Notlar (En yeni en başta)
    final matchingEntries = store.entries.reversed.where((e) {
      final act = store.activities[e.activityId];
      final noteMatch = e.note != null && normalizeTr(e.note!).contains(normQ);
      final actMatch = act != null && normalizeTr(act.name).contains(normQ);
      return noteMatch || actMatch;
    }).take(50).toList();

    // 3. Yol Haritaları ve Adımlar
    final matchingRoadmapSteps = <({Roadmap roadmap, RoadmapStep step})>[];
    for (final r in store.roadmaps) {
      for (final st in r.steps) {
        if (normalizeTr(st.title).contains(normQ) ||
            normalizeTr(st.description).contains(normQ) ||
            normalizeTr(r.title).contains(normQ)) {
          matchingRoadmapSteps.add((roadmap: r, step: st));
        }
      }
    }

    if (matchingActivities.isEmpty && matchingEntries.isEmpty && matchingRoadmapSteps.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.search_off_rounded, size: 54, color: scheme.onSurfaceVariant.withValues(alpha: 0.6)),
              const SizedBox(height: 14),
              Text(
                isTr ? '"$query" ile eşleşen sonuç bulunamadı' : 'No results found for "$query"',
                style: const TextStyle(fontSize: AppFont.body, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              Text(
                isTr ? 'Farklı bir kelime deneyebilir veya yeni bir aktivite oluşturabilirsiniz.' : 'Try a different keyword or create a new activity.',
                style: TextStyle(fontSize: AppFont.small, color: scheme.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      children: [
        // 1. Eşleşen Aktiviteler
        if (matchingActivities.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                Icon(Icons.category_outlined, size: 16, color: scheme.primary),
                const SizedBox(width: 6),
                Text(
                  '${isTr ? "Aktiviteler" : "Activities"} (${matchingActivities.length})',
                  style: TextStyle(
                    fontSize: AppFont.small,
                    fontWeight: FontWeight.bold,
                    color: scheme.primary,
                  ),
                ),
              ],
            ),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final act in matchingActivities)
                ActionChip(
                  avatar: Text(act.emoji ?? '⚡', style: const TextStyle(fontSize: AppFont.caption)),
                  label: Text(act.name),
                  onPressed: () => close(context, act),
                ),
            ],
          ),
          const SizedBox(height: 16),
        ],

        // 2. Eşleşen Yol Haritası Adımları
        if (matchingRoadmapSteps.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                const Icon(Icons.alt_route_rounded, size: 16, color: Colors.blue),
                const SizedBox(width: 6),
                Text(
                  '${isTr ? "Yol Haritaları" : "Roadmaps"} (${matchingRoadmapSteps.length})',
                  style: const TextStyle(
                    fontSize: AppFont.small,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue,
                  ),
                ),
              ],
            ),
          ),
          for (final item in matchingRoadmapSteps.take(4))
            Card(
              elevation: 0,
              margin: const EdgeInsets.only(bottom: 6),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.3)),
              ),
              child: ListTile(
                dense: true,
                leading: Text(item.roadmap.emoji, style: const TextStyle(fontSize: AppFont.title)),
                title: Text('${item.roadmap.title} › ${item.step.title}', maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: item.step.description.isNotEmpty ? Text(item.step.description, maxLines: 1, overflow: TextOverflow.ellipsis) : null,
                trailing: const Icon(Icons.chevron_right, size: 18),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => RoadmapDetailPage(roadmapId: item.roadmap.id)),
                  );
                },
              ),
            ),
          const SizedBox(height: 16),
        ],

        // 3. Eşleşen Kayıtlar ve Notlar
        if (matchingEntries.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                Icon(Icons.notes_rounded, size: 16, color: scheme.secondary),
                const SizedBox(width: 6),
                Text(
                  '${isTr ? "Kayıtlar & Notlar" : "Logs & Notes"} (${matchingEntries.length})',
                  style: TextStyle(
                    fontSize: AppFont.small,
                    fontWeight: FontWeight.bold,
                    color: scheme.secondary,
                  ),
                ),
              ],
            ),
          ),
          for (final e in matchingEntries) _buildEntryTile(context, e, normQ),
        ],
      ],
    );
  }

  Widget _buildEntryTile(BuildContext context, Entry e, String normQ) {
    final s = strings.value;
    final isTr = s.isTr;
    final scheme = Theme.of(context).colorScheme;
    final act = store.activities[e.activityId];
    final dt = DateTime.fromMillisecondsSinceEpoch(e.ts);
    final dateStr = DateFormat('d MMM yyyy, HH:mm', isTr ? 'tr_TR' : 'en_US').format(dt);
    final m = store.measureById(e.measureId);
    final valStr = e.value != null ? fmtNum(e.value!) : fmtNum(e.qty);
    final unitSym = e.unitId != null ? store.unit(e.unitId!).symbol : (m?.name ?? '');
    final note = e.note ?? '';

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _showEntryActionSheet(context, e, dt),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    act?.emoji ?? '⚡',
                    style: const TextStyle(fontSize: AppFont.title),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      act?.name ?? (isTr ? 'Bilinmeyen Aktivite' : 'Unknown Activity'),
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: AppFont.small),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    dateStr,
                    style: TextStyle(fontSize: AppFont.micro, color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: scheme.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '$valStr $unitSym'.trim(),
                      style: TextStyle(fontSize: AppFont.caption, fontWeight: FontWeight.bold, color: scheme.primary),
                    ),
                  ),
                  if (note.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '📝 $note',
                        style: TextStyle(
                          fontSize: AppFont.caption,
                          color: scheme.onSurface,
                          fontWeight: normQ.isNotEmpty && normalizeTr(note).contains(normQ) ? FontWeight.bold : FontWeight.normal,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
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
  }

  void _showEntryActionSheet(BuildContext context, Entry e, DateTime dt) {
    final s = strings.value;
    final isTr = s.isTr;
    final act = store.activities[e.activityId];

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListTile(
              leading: Text(act?.emoji ?? '⚡', style: const TextStyle(fontSize: AppFont.headline)),
              title: Text(act?.name ?? '', style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text(DateFormat('d MMMM yyyy, HH:mm', isTr ? 'tr_TR' : 'en_US').format(dt)),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.today_rounded, color: Colors.blue),
              title: Text(isTr ? 'Bu Güne Git' : 'Jump to This Day'),
              subtitle: Text(isTr ? 'Günlük ekranında bu tarihi aç' : 'Open this date on Today screen'),
              onTap: () {
                Navigator.pop(ctx);
                close(context, dt);
              },
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: Text(isTr ? 'Kaydı Düzenle' : 'Edit Entry'),
              onTap: () {
                Navigator.pop(ctx);
                TodayTimeline.showEntryEditSheet(context, e);
              },
            ),
            if (act != null)
              ListTile(
                leading: const Icon(Icons.insights_rounded),
                title: Text(isTr ? 'Aktivite Detayını Gör' : 'View Activity Details'),
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => ActivityPage(activity: act)),
                  );
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
