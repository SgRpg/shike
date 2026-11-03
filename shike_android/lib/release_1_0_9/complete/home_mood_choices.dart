import 'package:flutter/material.dart';
import '../refined/design.dart';
import '../refined/mood_wave.dart';

/// Keep the colored core fixed; the selection halo is painted outside its bounds.
class HomeMoodChoices extends StatelessWidget {
  final int? value;
  final ValueChanged<int> onChanged;
  const HomeMoodChoices({super.key, required this.value, required this.onChanged});
  @override Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: List.generate(6, (i) {
      final diameter = 23 + i * 2.0;
      final selected = value == i;
      return MoodWaveDot(index: i, child: Semantics(label: '心情 $i 分', button: true, selected: selected,
        child: InkResponse(onTap: () => onChanged(i), radius: 24,
          child: SizedBox(width: 44, height: 48, child: Center(
            child: SizedBox(width: diameter, height: diameter,
              child: Stack(clipBehavior: Clip.none, children: [
                Positioned(left: -3, top: -3, right: -3, bottom: -3,
                  child: IgnorePointer(child: AnimatedOpacity(opacity: selected ? 1 : 0,
                    duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : const Duration(milliseconds: 140),
                    child: DecoratedBox(decoration: BoxDecoration(shape: BoxShape.circle, color: Paper.bg,
                      boxShadow: [BoxShadow(color: Paper.ink.withValues(alpha: .1), blurRadius: 4, spreadRadius: 1)])),
                  ))),
                Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(shape: BoxShape.circle, color: Paper.mood[i]))),
              ]),
            ),
          )),
        ),
      ));
    }),
  );
}
