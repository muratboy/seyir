import 'package:flutter/material.dart';

/// Aktivitenin son 30 gününü gösteren tek satırlık nokta şeridi.
///
/// Her nokta bir gündür (en soldaki 29 gün öncesi, en sağdaki bugündür).
/// Aktif olunan günler aktivitenin renginde dolgulu, diğer günler soluktur.
class ActivityDotStrip extends StatelessWidget {
  final List<bool> dots;
  final Color color;

  const ActivityDotStrip({
    super.key,
    required this.dots,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final inactiveColor = scheme.outlineVariant.withValues(alpha: 0.35);

    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < dots.length; i++) ...[
            if (i > 0) const SizedBox(width: 2.5),
            Container(
              width: 4,
              height: 4,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: dots[i] ? color : inactiveColor,
                // Bugün için hafif çerçeve/vurgu
                border: i == dots.length - 1 && dots[i]
                    ? Border.all(color: color.withValues(alpha: 0.8), width: 0.8)
                    : null,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
