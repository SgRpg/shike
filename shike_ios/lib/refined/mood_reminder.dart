import 'package:flutter/material.dart';

import 'design.dart';

class QuickSendHalo extends StatelessWidget {
  final Widget child;
  const QuickSendHalo({super.key, required this.child});
  @override
  Widget build(BuildContext c) => SizedBox.square(
    key: const ValueKey('quick-send-halo'),
    dimension: 30,
    child: DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Paper.secondary.withValues(alpha: .10),
      ),
      child: Center(child: child),
    ),
  );
}

Widget quickSendControl(
  BuildContext context, {
  required bool busy,
  required VoidCallback? onSend,
  VoidCallback? onMissingMood,
  required Widget arrow,
}) {
  final VoidCallback? action = busy
      ? null
      : () => (onSend ?? onMissingMood)?.call();
  return Semantics(
    excludeSemantics: true,
    label: '收好',
    hint: onSend == null && !busy ? '还未选择心情，点按提醒选择' : null,
    button: true,
    enabled: !busy,
    onTap: action,
    child: TextButton(
      key: const ValueKey('quick-submit'),
      onPressed: action,
      style: TextButton.styleFrom(
        padding: EdgeInsets.zero,
        minimumSize: const Size(44, 44),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        overlayColor: Colors.transparent,
        shape: const CircleBorder(),
      ),
      child: QuickSendHalo(
        child: busy
            ? const SizedBox.square(
                dimension: 12,
                child: CircularProgressIndicator(
                  strokeWidth: 1.1,
                  color: Paper.secondary,
                ),
              )
            : arrow,
      ),
    ),
  );
}
