import 'package:flutter/material.dart';

import 'design.dart';

/// Each option owns half the available width; the rule follows the label width.
class HeartTopTabs extends StatelessWidget {
  final bool heat;
  final ValueChanged<bool> onChanged;
  const HeartTopTabs({super.key, required this.heat, required this.onChanged});

  @override
  Widget build(BuildContext c) => Row(
    key: const ValueKey('heart-top-tabs'),
    children: [
      for (final item in [(false, '趋势'), (true, '热力图')])
        Expanded(
          child: Semantics(
            button: true,
            selected: heat == item.$1,
            child: InkWell(
              key: ValueKey('heart-top-option-${item.$1}'),
              onTap: () => onChanged(item.$1),
              hoverColor: Colors.transparent,
              highlightColor: Paper.ink.withValues(alpha: .025),
              child: Center(
                child: IntrinsicWidth(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                        child: Text(
                          item.$2,
                          key: ValueKey('heart-top-label-${item.$1}'),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 16,
                            height: 1.4,
                            fontWeight: heat == item.$1
                                ? FontWeight.w600
                                : FontWeight.w400,
                            color: heat == item.$1
                                ? Paper.ink
                                : Paper.secondary,
                          ),
                        ),
                      ),
                      SizedBox(
                        key: ValueKey('heart-top-line-${item.$1}'),
                        height: 1.3,
                        child: ColoredBox(
                          color: heat == item.$1
                              ? const Color(0xFFED967B)
                              : Colors.transparent,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
    ],
  );
}
