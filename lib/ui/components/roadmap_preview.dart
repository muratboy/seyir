import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../../data/store.dart';
import '../../logic/format.dart';
import '../../logic/l10n.dart';
import '../app_font.dart';

/// İçe aktarılacak yol haritasının, kaydedilmeden önceki önizlemesi. Yapay zekâ yanıtından da bağlantıdan da
/// gelse eklenen şey burada görünenin aynısıdır. [source] verilirse içeriğin nereden geldiği de yazılır.
class RoadmapPreview extends StatelessWidget {
  final Roadmap roadmap;
  final String? source;

  const RoadmapPreview({super.key, required this.roadmap, this.source});

  @override
  Widget build(BuildContext context) {
    final r = roadmap;
    final isTr = strings.value.isTr;
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.green.withValues(alpha: 0.4)),
      ),
      child: ListView(
        children: [
          Row(
            children: [
              Text(r.emoji, style: const TextStyle(fontSize: AppFont.display)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      r.title,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: AppFont.subtitle),
                    ),
                    Text(
                      '${r.category} • ${r.steps.length} ${isTr ? "Adım" : "Steps"}',
                      style: TextStyle(fontSize: AppFont.caption, color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (source != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.link_rounded, size: 14, color: scheme.onSurfaceVariant),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    '${isTr ? 'Kaynak' : 'Source'}: $source',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: AppFont.caption, color: scheme.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          ],
          if (r.description.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(r.description, style: TextStyle(fontSize: AppFont.small, color: scheme.onSurfaceVariant)),
          ],
          const Divider(height: 20),
          Text(
            isTr ? 'Adımlar / Duraklar:' : 'Steps / Waypoints:',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: AppFont.small),
          ),
          const SizedBox(height: 8),
          for (final st in r.steps)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${st.order}. ', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: AppFont.small)),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(st.title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: AppFont.small)),
                        if (st.description.isNotEmpty)
                          Text(st.description, style: TextStyle(fontSize: AppFont.caption, color: scheme.onSurfaceVariant)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  // Uzun bir birim satırı taşırmasın.
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 120),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: st.isGoal ? scheme.primaryContainer : scheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        st.isGoal
                            ? (st.target != null
                                ? '${fmtNum(st.target!)} ${st.unit ?? ""}'.trim()
                                : (isTr ? "Hedef" : "Goal"))
                            : (isTr ? "Görev" : "Task"),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: AppFont.micro,
                          fontWeight: FontWeight.bold,
                          color: st.isGoal ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

bool _isSavingRoadmap = false;

/// Önizlenen yol haritasını kaydeder, içe aktarma penceresini kapatır ve sonucu bildirir.
Future<void> saveImportedRoadmap(BuildContext context, Roadmap roadmap) async {
  if (_isSavingRoadmap) return;
  _isSavingRoadmap = true;
  try {
    final isTr = strings.value.isTr;
    final messenger = ScaffoldMessenger.of(context);
    await store.createRoadmap(roadmap);
    if (!context.mounted) return;
    Navigator.pop(context);
    messenger.showSnackBar(
      SnackBar(
        content: Text(isTr
            ? '🎉 "${roadmap.title}" yol haritalarına eklendi!'
            : '🎉 "${roadmap.title}" added to roadmaps!'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  } finally {
    _isSavingRoadmap = false;
  }
}
