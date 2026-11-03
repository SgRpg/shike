import 'package:flutter/material.dart';

import 'design.dart';
import 'mood_reminder.dart';

InputDecoration quickEntryDecoration({
  required bool hasText,
  required bool busy,
  required VoidCallback? onSend,
  VoidCallback? onMissingMood,
}) => InputDecoration(
  hintText: '这一刻，有什么想留下的？',
  hintStyle: const TextStyle(color: Paper.secondary, fontSize: 17),
  contentPadding: const EdgeInsets.symmetric(vertical: 12),
  enabledBorder: const UnderlineInputBorder(
    borderSide: BorderSide(color: Color(0xFFD4DFE8), width: .8),
  ),
  focusedBorder: const UnderlineInputBorder(
    borderSide: BorderSide(color: Paper.secondary, width: 1),
  ),
  disabledBorder: const UnderlineInputBorder(
    borderSide: BorderSide(color: Paper.line),
  ),
  suffixIconConstraints: const BoxConstraints.tightFor(width: 44, height: 44),
  suffixIcon: hasText
      ? QuickSendArrow(busy: busy, onSend: onSend, onMissingMood: onMissingMood)
      : null,
);

class QuickSendArrow extends StatelessWidget {
  final bool busy;
  final VoidCallback? onSend;
  final VoidCallback? onMissingMood;
  const QuickSendArrow({
    super.key,
    required this.busy,
    required this.onSend,
    this.onMissingMood,
  });

  @override
  Widget build(BuildContext c) => quickSendControl(
    c,
    busy: busy,
    onSend: onSend,
    onMissingMood: onMissingMood,
    arrow: SizedBox.square(
      key: const ValueKey('quick-send-glyph'),
      dimension: 14,
      child: CustomPaint(
        painter: _SendArrowPainter(
          (onSend == null ? Paper.secondary : Paper.ink).withValues(alpha: .68),
        ),
      ),
    ),
  );
}

class _SendArrowPainter extends CustomPainter {
  final Color color;
  const _SendArrowPainter(this.color);
  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 14, size.height / 14);
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.25
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawLine(const Offset(7, 12), const Offset(7, 2), stroke);
    canvas.drawPath(
      Path()
        ..moveTo(3, 6)
        ..lineTo(7, 2)
        ..lineTo(11, 6),
      stroke,
    );
  }

  @override
  bool shouldRepaint(_SendArrowPainter old) => old.color != color;
}
