import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../../data/store.dart';
import '../../logic/format.dart';
import '../../logic/l10n.dart';
import '../app_font.dart';

/// "45 / 100 dk": adımın bağlı aktiviteden gelen ilerlemesi.
String stepProgressText(StepProgress p) => '${fmtNum1(p.done)} / ${fmtNum(p.target)} ${p.unit}'.trim();

/// Bir aktiviteye bağlı adımın ilerlemesi: miktarı olan hedefte sayı ve çubuk, miktarı olmayan görevde ne
/// zaman tamamlanacağını söyleyen kısa bir not. Adım bağlı değilse hiçbir şey çizmez.
///
/// Adımlar bağlı aktivitenin kayıtlarıyla kendiliğinden ilerler ve tamamlanır; kullanıcı bunu ancak burada
/// görür. O yüzden ilerlemenin beklenmedik göründüğü durumların nedeni de yazılır: yolculuk henüz
/// başlamamıştır ya da hedefi dolan adımın işaretini kullanıcı kendisi kaldırmıştır.
class StepProgressLine extends StatelessWidget {
  final Roadmap roadmap;
  final RoadmapStep step;

  const StepProgressLine({super.key, required this.roadmap, required this.step});

  @override
  Widget build(BuildContext context) {
    if (!store.activities.containsKey(step.linkedActivityId)) return const SizedBox.shrink();
    final s = strings.value;
    final scheme = Theme.of(context).colorScheme;
    final progress = store.stepProgress(roadmap, step);
    final note = TextStyle(fontSize: AppFont.micro, color: scheme.onSurfaceVariant);

    if (progress == null) {
      return Text(
        s.isTr ? 'Yolculuk başlayınca aktivitenin kayıtları sayılır' : 'Entries count once the journey starts',
        style: note,
      );
    }

    final keptOpen = step.keptOpen && !step.isCompleted && progress.reached;
    final keptOpenNote = Text(
      s.isTr ? 'Adımı sen açık bıraktın; işaretleyince tamamlanır' : 'You reopened this step; tick it to finish',
      style: note,
    );

    if ((step.target ?? 0) <= 0) {
      if (keptOpen) return keptOpenNote;
      if (progress.reached) return Text(s.isTr ? 'Aktivite kaydedildi' : 'The activity was logged', style: note);
      // Kayıt olmadan elle tamamlanmış görev için söylenecek bir şey yoktur.
      if (step.isCompleted) return const SizedBox.shrink();
      return Text(
        s.isTr ? 'Aktivite kaydedilince tamamlanır' : 'Completes when the activity is logged',
        style: note,
      );
    }

    // Hedefler sayfasındaki kartlarla aynı düzen: çubuk, altında miktar ve yüzde. Sayı çubuğun yanına
    // konmaz; dar ekranda ya da büyük yazıda oraya sığmıyor.
    final color = progress.reached ? Colors.green : scheme.primary;
    final numbers = TextStyle(fontSize: AppFont.micro, fontWeight: FontWeight.w700, color: color);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: progress.ratio,
            minHeight: 5,
            backgroundColor: scheme.surfaceContainerHighest,
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
        const SizedBox(height: 4),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: Text(stepProgressText(progress), style: numbers)),
            const SizedBox(width: 8),
            Text(fmtPercent((progress.ratio * 100).floor()), style: numbers),
          ],
        ),
        if (keptOpen) ...[const SizedBox(height: 4), keptOpenNote],
      ],
    );
  }
}
