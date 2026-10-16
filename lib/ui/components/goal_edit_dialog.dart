import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../../data/store.dart';
import '../../logic/format.dart';
import '../../logic/l10n.dart';
import '../../logic/text_match.dart';
import '../common.dart';
import '../app_font.dart';

class GoalEditDialog {
  static Future<void> show(BuildContext context, {Goal? existing}) async {
    final s = strings.value;
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final targetCtrl = TextEditingController(text: existing != null ? fmtNum(existing.target) : '2.5');
    var type = existing?.type ?? 'target'; // target or limit
    var mode = existing?.mode ?? 'amount'; // amount or count
    var unitId = existing?.unitId ?? (mode == 'amount' ? 'l' : 'adet');
    var period = existing?.period ?? GoalPeriod.day;
    var hasEndDate = existing?.endDate != null;
    DateTime? endDate = existing?.endDate != null
        ? DateTime.fromMillisecondsSinceEpoch(existing!.endDate!)
        : DateTime.now().add(const Duration(days: 30));

    final links = existing != null
        ? List<GoalLink>.from(existing.links.map((l) => GoalLink(
            activityId: l.activityId,
            pct: l.pct,
            propertyId: l.propertyId,
            customRate: l.customRate,
          )))
        : <GoalLink>[];

    await showDialog<void>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setS) => AlertDialog(
          title: Text(existing == null ? s.newGoal : s.editGoal),
          content: SingleChildScrollView(
            padding: const EdgeInsets.only(top: 12, bottom: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: nameCtrl,
                  autofocus: existing == null,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    labelText: s.goalName,
                    hintText: s.isTr ? 'örn: Günlük Sıvı Alımı veya Kafein Limiti' : 'e.g. Daily Fluid Intake or Caffeine Limit',
                  ),
                ),
                const SizedBox(height: 12),

                // Goal Kind: Target vs Limit
                Text(
                  s.goalKind,
                  style: TextStyle(
                    fontSize: AppFont.caption,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(c).colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 4),
                SegmentedButton<String>(
                  showSelectedIcon: false,
                  segments: [
                    ButtonSegment(
                      value: 'target',
                      label: Text(s.goalKindTarget),
                      icon: const Icon(Icons.track_changes, size: 18),
                    ),
                    ButtonSegment(
                      value: 'limit',
                      label: Text(s.goalKindLimit),
                      icon: const Icon(Icons.shield_outlined, size: 18),
                    ),
                  ],
                  selected: {type},
                  onSelectionChanged: (set) => setS(() {
                    type = set.first;
                  }),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 10, left: 4),
                  child: Text(
                    type == 'limit' ? s.goalKindLimitDesc : s.goalKindTargetDesc,
                    style: TextStyle(
                      fontSize: AppFont.micro,
                      color: Theme.of(c).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),

                // Goal Mode: Amount vs Count
                Text(
                  s.goalType,
                  style: TextStyle(
                    fontSize: AppFont.caption,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(c).colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 4),
                SegmentedButton<String>(
                  showSelectedIcon: false,
                  segments: [
                    ButtonSegment(
                      value: 'amount',
                      label: Text(s.isTr ? 'Miktar' : 'Amount'),
                      icon: const Icon(Icons.scale_outlined, size: 18),
                    ),
                    ButtonSegment(
                      value: 'count',
                      label: Text(s.isTr ? 'Adet' : 'Count'),
                      icon: const Icon(Icons.numbers_outlined, size: 18),
                    ),
                  ],
                  selected: {mode},
                  onSelectionChanged: (set) => setS(() {
                    mode = set.first;
                    if (mode == 'count') unitId = 'adet';
                  }),
                ),

                const SizedBox(height: 12),

                // Target & Unit
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: targetCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(
                          labelText: type == 'limit' ? s.limitTarget : s.goalTarget,
                          hintText: type == 'limit' ? '400' : '2.5',
                        ),
                      ),
                    ),
                    if (mode == 'amount') ...[
                      const SizedBox(width: 8),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: unitId,
                          isExpanded: true,
                          decoration: InputDecoration(labelText: s.unit),
                          // Kapalıyken yalnızca kısaltma: "Litre (L)" dar ekranda "Litr…" diye kesiliyordu.
                          selectedItemBuilder: (context) => [
                            for (final u in store.allUnits) Align(alignment: Alignment.centerLeft, child: Text(u.symbol)),
                          ],
                          items: [
                            for (final u in store.allUnits)
                              DropdownMenuItem(
                                value: u.id,
                                child: Text('${u.name} (${u.symbol})', overflow: TextOverflow.ellipsis),
                              ),
                          ],
                          onChanged: (val) {
                            if (val != null) setS(() => unitId = val);
                          },
                        ),
                      ),
                    ],
                  ],
                ),

                const SizedBox(height: 12),

                // Period
                DropdownButtonFormField<GoalPeriod>(
                  initialValue: period,
                  isExpanded: true,
                  decoration: InputDecoration(labelText: s.period),
                  items: [
                    DropdownMenuItem(
                      value: GoalPeriod.day,
                      child: Text(s.periodDaily, overflow: TextOverflow.ellipsis),
                    ),
                    DropdownMenuItem(
                      value: GoalPeriod.week,
                      child: Text(s.periodWeekly, overflow: TextOverflow.ellipsis),
                    ),
                    DropdownMenuItem(
                      value: GoalPeriod.month,
                      child: Text(s.periodMonthly, overflow: TextOverflow.ellipsis),
                    ),
                    DropdownMenuItem(
                      value: GoalPeriod.total,
                      child: Text(s.periodTotal, overflow: TextOverflow.ellipsis),
                    ),
                  ],
                  onChanged: (val) {
                    if (val != null) setS(() => period = val);
                  },
                ),

                const SizedBox(height: 10),

                // End Date Switch
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(s.hasEndDate),
                  value: hasEndDate,
                  onChanged: (v) => setS(() => hasEndDate = v),
                ),

                if (hasEndDate && endDate != null) ...[
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.calendar_month),
                    title: Text(fmtDate(endDate!, isTr: s.isTr)),
                    subtitle: Text(fmtDaysLeft(daysBetween(DateTime.now(), endDate!), isTr: s.isTr)),
                    trailing: const Icon(Icons.edit),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: c,
                        initialDate: endDate,
                        firstDate: DateTime.now(),
                        lastDate: DateTime.now().add(const Duration(days: 3650)),
                      );
                      if (picked != null) setS(() => endDate = picked);
                    },
                  ),
                ],

                const Divider(height: 24),

                // Connected Activities: başlık ve düğme yan yana sığmazsa düğme alt satıra geçer (başlık dar
                // ekranda üç satıra bölünüyordu).
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      s.linkedActivities,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Theme.of(c).colorScheme.primary,
                      ),
                    ),
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                      icon: const Icon(Icons.add, size: 18),
                      label: Text(s.addActivityToGoal),
                      onPressed: () async {
                        final act = await showActivityPicker(
                          c,
                          title: s.addActivityToGoal,
                          exclude: {for (final l in links) l.activityId},
                        );
                        if (act != null) {
                          final props = store.activityProperties(act.id);
                          int? matchedPropId;
                          if (mode == 'amount') {
                            final gu = store.unit(unitId);
                            final matchingProp = props.where((p) => store.unit(p.unitId).dim == gu.dim).firstOrNull;
                            if (matchingProp != null) {
                              matchedPropId = matchingProp.id;
                            }
                          }
                          setS(() => links.add(GoalLink(activityId: act.id, pct: 100, propertyId: matchedPropId)));
                        }
                      },
                    ),
                  ],
                ),

                if (links.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      s.isTr
                          ? 'Henüz aktivite bağlanmadı. Yukarıdan ekleyin (örn: Çay, Su, Yoğurt).'
                          : 'No activities linked yet. Add above.',
                      style: TextStyle(color: Theme.of(c).colorScheme.onSurfaceVariant, fontSize: AppFont.small),
                    ),
                  )
                else
                  for (var i = 0; i < links.length; i++) ...[
                    Builder(builder: (c) {
                      final link = links[i];
                      final act = store.activity(link.activityId);
                      final props = store.activityProperties(link.activityId);
                      return Card(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        color: Theme.of(c).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(act.emoji ?? '🔹', style: const TextStyle(fontSize: AppFont.subtitle)),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      act.name,
                                      style: const TextStyle(fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                  Text(
                                    fmtPercent(link.pct.round()),
                                    style: const TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.close, size: 18),
                                    onPressed: () => setS(() => links.removeAt(i)),
                                  ),
                                ],
                              ),
                              Slider(
                                value: link.pct.clamp(1.0, 100.0),
                                min: 5,
                                max: 100,
                                divisions: 19,
                                label: fmtPercent(link.pct.round()),
                                onChanged: (val) => setS(() => link.pct = val),
                              ),
                              if (props.isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(
                                  s.isTr ? 'Ölçü Alınacak Özellik:' : 'Property to Measure:',
                                  style: TextStyle(
                                    fontSize: AppFont.micro,
                                    fontWeight: FontWeight.bold,
                                    color: Theme.of(c).colorScheme.primary,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                DropdownButtonFormField<int?>(
                                  initialValue: props.any((p) => p.id == link.propertyId) ? link.propertyId : null,
                                  isExpanded: true,
                                  decoration: InputDecoration(
                                    isDense: true,
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                  ),
                                  items: [
                                    DropdownMenuItem<int?>(
                                      value: null,
                                      child: Text(
                                        s.isTr ? 'Otomatik / Doğrudan Değer' : 'Automatic / Direct Value',
                                        style: const TextStyle(fontSize: AppFont.small),
                                      ),
                                    ),
                                    for (final p in props)
                                      DropdownMenuItem<int?>(
                                        value: p.id,
                                        child: Text(
                                          '${p.name}: ${fmtNum(p.value)} ${store.unit(p.unitId).symbol} (${fmtNum(p.perQty)} adet)',
                                          style: const TextStyle(fontSize: AppFont.small),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                  ],
                                  onChanged: (val) => setS(() => link.propertyId = val),
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    }),
                  ],
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: Text(s.cancel)),
            FilledButton(
              onPressed: () async {
                final name = nameCtrl.text.trim();
                final targetVal = parseNum(targetCtrl.text);
                if (name.isEmpty || targetVal == null || targetVal <= 0) return;

                final goal = existing ??
                    Goal(
                      id: 0,
                      name: name,
                      type: type,
                      mode: mode,
                      unitId: mode == 'amount' ? unitId : null,
                      target: targetVal,
                      period: period,
                      startDate: DateTime.now().millisecondsSinceEpoch,
                      endDate: hasEndDate && endDate != null ? endDate!.millisecondsSinceEpoch : null,
                      createdAt: DateTime.now().millisecondsSinceEpoch,
                      links: links,
                    );

                goal.name = name;
                goal.type = type;
                goal.mode = mode;
                goal.unitId = mode == 'amount' ? unitId : null;
                goal.target = targetVal;
                goal.period = period;
                goal.endDate = hasEndDate && endDate != null ? endDate!.millisecondsSinceEpoch : null;
                goal.links = links;

                await store.saveGoal(goal);
                if (c.mounted) Navigator.pop(c);
              },
              child: Text(s.save),
            ),
          ],
        ),
      ),
    );
  }
}
