import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'mood_wave.dart';

abstract final class Paper {
  static const bg = Color(0xFFFFFDFA);
  static const ink = Color(0xFF24262C);
  static const secondary = Color(0xFF64728A);
  static const faint = Color(0xFFA0A8B4);
  static const line = Color(0xFFEAE8E4);
  static const soft = Color(0xFFF5F1EA);
  static const mood = <Color>[
    Color(0xFF94ABBF),
    Color(0xFFA8C5E8),
    Color(0xFFD6DEE5),
    Color(0xFFDDC8B7),
    Color(0xFFFFC4A6),
    Color(0xFFF1A787),
  ];
  static const body = TextStyle(fontSize: 17, height: 1.6, color: ink);
  static const meta = TextStyle(fontSize: 14, height: 1.5, color: secondary);
  static TextStyle title([double size = 30]) => TextStyle(
    fontFamily: 'ShikeSerif',
    fontFamilyFallback: const ['Songti SC', 'SimSun'],
    fontSize: size,
    fontWeight: FontWeight.w700,
    color: ink,
    height: 1.25,
  );
  static ThemeData theme() => ThemeData(
    useMaterial3: true,
    scaffoldBackgroundColor: bg,
    canvasColor: bg,
    colorScheme: const ColorScheme.light(
      primary: ink,
      onPrimary: Colors.white,
      surface: bg,
      onSurface: ink,
    ),
    fontFamilyFallback: const [
      'PingFang SC',
      'Microsoft YaHei',
      'Noto Sans SC',
    ],
    textTheme: const TextTheme(
      bodyMedium: body,
      bodyLarge: body,
      titleMedium: body,
    ),
    dividerTheme: const DividerThemeData(color: line, thickness: 0.7, space: 1),
    splashFactory: NoSplash.splashFactory,
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: ink,
        disabledForegroundColor: faint,
        textStyle: const TextStyle(fontSize: 15),
        minimumSize: const Size(44, 44),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: bg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    snackBarTheme: const SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: ink,
    ),
  );
}

enum Mark {
  home,
  journal,
  heart,
  person,
  pen,
  envelope,
  search,
  back,
  next,
  plus,
  check,
  focus,
  unfocus,
  image,
  mic,
  stop,
  play,
  close,
  card,
  cloud,
  shield,
  info,
  download,
  more,
  trash,
  quote,
  leaf,
}

class LineMark extends StatelessWidget {
  final Mark mark;
  final double size;
  final Color color;
  final bool filled;
  const LineMark(
    this.mark, {
    super.key,
    this.size = 24,
    this.color = Paper.ink,
    this.filled = false,
  });
  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _MarkPainter(mark, color, filled)),
    ),
  );
}

class _MarkPainter extends CustomPainter {
  final Mark mark;
  final Color color;
  final bool filled;
  _MarkPainter(this.mark, this.color, this.filled);
  @override
  void paint(Canvas c, Size size) {
    c.scale(size.width / 24, size.height / 24);
    final pen = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.35
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final fill = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    void path(List<Offset> points, {bool close = false, bool solid = false}) {
      final p = Path()..moveTo(points.first.dx, points.first.dy);
      for (final x in points.skip(1)) {
        p.lineTo(x.dx, x.dy);
      }
      if (close) p.close();
      c.drawPath(p, solid ? fill : pen);
    }

    void line(double x, double y, double a, double b) =>
        c.drawLine(Offset(x, y), Offset(a, b), pen);
    switch (mark) {
      case Mark.home:
        final p = Path()
          ..moveTo(3, 10)
          ..lineTo(12, 2.7)
          ..lineTo(21, 10)
          ..lineTo(21, 21)
          ..lineTo(14.5, 21)
          ..lineTo(14.5, 14)
          ..lineTo(9.5, 14)
          ..lineTo(9.5, 21)
          ..lineTo(3, 21)
          ..close();
        c.drawPath(p, filled ? fill : pen);
      case Mark.journal:
        c.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(5, 2.5, 14, 19),
            const Radius.circular(2),
          ),
          filled ? fill : pen,
        );
        final p = Paint()
          ..color = filled ? Paper.bg : color
          ..strokeWidth = 1.1
          ..strokeCap = StrokeCap.round;
        c.drawLine(const Offset(8.5, 7), const Offset(15.5, 7), p);
        c.drawLine(const Offset(8.5, 11), const Offset(15.5, 11), p);
        c.drawLine(const Offset(8.5, 15), const Offset(12, 15), p);
      case Mark.heart:
        final p = Path()
          ..moveTo(12, 21)
          ..cubicTo(9, 18, 2, 13, 2, 7.7)
          ..cubicTo(2, 2, 9, .7, 12, 6)
          ..cubicTo(15, .7, 22, 2, 22, 7.7)
          ..cubicTo(22, 13, 15, 18, 12, 21)
          ..close();
        c.drawPath(p, filled ? fill : pen);
      case Mark.person:
        c.drawCircle(const Offset(12, 6.8), 4, filled ? fill : pen);
        final p = Path()
          ..moveTo(3, 21)
          ..lineTo(3, 18.5)
          ..cubicTo(3, 12, 21, 12, 21, 18.5)
          ..lineTo(21, 21)
          ..close();
        c.drawPath(p, filled ? fill : pen);
      case Mark.pen:
        path(const [
          Offset(3, 21),
          Offset(4.8, 14.9),
          Offset(16.2, 3.5),
          Offset(20.6, 7.9),
          Offset(9.2, 19.3),
        ], close: true);
        line(14.6, 5.1, 19, 9.5);
        line(4.8, 14.9, 9.2, 19.3);
      case Mark.envelope:
        c.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(2, 4, 20, 16),
            const Radius.circular(1.6),
          ),
          pen,
        );
        path(const [Offset(3, 5), Offset(12, 13), Offset(21, 5)]);
      case Mark.search:
        c.drawCircle(const Offset(10, 10), 7, pen);
        line(15, 15, 22, 22);
      case Mark.back:
        path(const [Offset(15, 4), Offset(7, 12), Offset(15, 20)]);
      case Mark.next:
        path(const [Offset(9, 5), Offset(16, 12), Offset(9, 19)]);
      case Mark.plus:
        line(12, 3, 12, 21);
        line(3, 12, 21, 12);
      case Mark.check:
        path(const [Offset(3, 12), Offset(9, 18), Offset(21, 5)]);
      case Mark.focus:
      case Mark.unfocus:
        if (mark == Mark.focus) {
          path(const [Offset(3, 8), Offset(3, 3), Offset(8, 3)]);
          path(const [Offset(16, 3), Offset(21, 3), Offset(21, 8)]);
          path(const [Offset(21, 16), Offset(21, 21), Offset(16, 21)]);
          path(const [Offset(8, 21), Offset(3, 21), Offset(3, 16)]);
        } else {
          path(const [Offset(3, 8), Offset(8, 8), Offset(8, 3)]);
          path(const [Offset(16, 3), Offset(16, 8), Offset(21, 8)]);
          path(const [Offset(21, 16), Offset(16, 16), Offset(16, 21)]);
          path(const [Offset(8, 21), Offset(8, 16), Offset(3, 16)]);
        }
      case Mark.image:
        c.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(2, 3, 20, 18),
            const Radius.circular(2),
          ),
          pen,
        );
        c.drawCircle(const Offset(8, 8), 1.8, pen);
        path(const [
          Offset(2, 18),
          Offset(8, 12),
          Offset(12, 16),
          Offset(16, 11),
          Offset(22, 17),
        ]);
      case Mark.mic:
        c.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(8, 2, 8, 13),
            const Radius.circular(4),
          ),
          pen,
        );
        c.drawArc(const Rect.fromLTWH(4, 4, 16, 15), 0, math.pi, false, pen);
        line(4, 11, 4, 12);
        line(20, 11, 20, 12);
        line(12, 19, 12, 23);
      case Mark.stop:
        c.drawCircle(const Offset(12, 12), 10, pen);
        c.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(8, 8, 8, 8),
            const Radius.circular(1),
          ),
          fill,
        );
      case Mark.play:
        path(
          const [Offset(7, 4), Offset(20, 12), Offset(7, 20)],
          close: true,
          solid: true,
        );
      case Mark.close:
        line(5, 5, 19, 19);
        line(19, 5, 5, 19);
      case Mark.card:
        c.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(2, 4, 20, 16),
            const Radius.circular(2),
          ),
          pen,
        );
        line(2, 9, 22, 9);
        line(6, 15, 10, 15);
      case Mark.cloud:
        final p = Path()
          ..moveTo(6, 20)
          ..cubicTo(-1, 20, -1, 10, 6, 10)
          ..cubicTo(6, 0, 20, 0, 20, 10)
          ..cubicTo(26, 11, 25, 20, 19, 20)
          ..close();
        c.drawPath(p, pen);
      case Mark.shield:
        path(const [
          Offset(12, 2),
          Offset(21, 6),
          Offset(20, 16),
          Offset(16, 20),
          Offset(12, 23),
          Offset(8, 20),
          Offset(4, 16),
          Offset(3, 6),
        ], close: true);
        line(12, 6, 12, 18);
      case Mark.info:
        c.drawCircle(const Offset(12, 12), 10, pen);
        c.drawCircle(const Offset(12, 7), .7, fill);
        line(12, 11, 12, 17);
      case Mark.download:
        line(12, 2, 12, 15);
        path(const [Offset(7, 10), Offset(12, 15), Offset(17, 10)]);
        path(const [
          Offset(3, 15),
          Offset(3, 21),
          Offset(21, 21),
          Offset(21, 15),
        ]);
      case Mark.more:
        for (final x in [5.0, 12.0, 19.0]) {
          c.drawCircle(Offset(x, 12), 1.3, fill);
        }
      case Mark.trash:
        line(4, 6, 20, 6);
        path(const [
          Offset(6, 6),
          Offset(7, 22),
          Offset(17, 22),
          Offset(18, 6),
        ]);
        path(const [Offset(8, 6), Offset(8, 2), Offset(16, 2), Offset(16, 6)]);
        line(10, 10, 10, 18);
        line(14, 10, 14, 18);
      case Mark.quote:
        c.drawCircle(const Offset(7, 9), 3, pen);
        c.drawCircle(const Offset(17, 9), 3, pen);
        c.drawArc(const Rect.fromLTWH(4, 8, 7, 11), 0, math.pi / 2, false, pen);
        c.drawArc(
          const Rect.fromLTWH(14, 8, 7, 11),
          0,
          math.pi / 2,
          false,
          pen,
        );
      case Mark.leaf:
        final p = Path()
          ..moveTo(4, 22)
          ..cubicTo(9, 18, 18, 13, 20, 3)
          ..cubicTo(7, 3, 4, 10, 10, 14);
        c.drawPath(p, pen);
        line(4, 22, 17, 7);
    }
  }

  @override
  bool shouldRepaint(_MarkPainter old) =>
      old.mark != mark || old.color != color || old.filled != filled;
}

class IconAction extends StatelessWidget {
  final Mark mark;
  final String label;
  final VoidCallback? onTap;
  final double size;
  final Color? color;
  const IconAction(
    this.mark, {
    super.key,
    required this.label,
    required this.onTap,
    this.size = 22,
    this.color,
  });
  @override
  Widget build(BuildContext c) => Semantics(
    button: true,
    enabled: onTap != null,
    label: label,
    child: Tooltip(
      message: label,
      excludeFromSemantics: true,
      child: InkResponse(
        onTap: onTap,
        radius: 24,
        hoverColor: Colors.transparent,
        highlightColor: Paper.ink.withValues(alpha: .04),
        child: SizedBox(
          width: 48,
          height: 48,
          child: Center(
            child: LineMark(
              mark,
              size: size,
              color: color ?? (onTap == null ? Paper.faint : Paper.ink),
            ),
          ),
        ),
      ),
    ),
  );
}

class PaperHeader extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final Widget? leading;
  final List<Widget> actions;
  const PaperHeader(
    this.title, {
    super.key,
    this.leading,
    this.actions = const [],
  });
  @override
  Size get preferredSize => const Size.fromHeight(60);
  @override
  Widget build(BuildContext c) => SafeArea(
    bottom: false,
    child: SizedBox(
      height: 60,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 80),
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Paper.title(21),
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.only(left: 8),
              child:
                  leading ??
                  IconAction(
                    Mark.back,
                    label: '返回',
                    onTap: () => Navigator.maybePop(c),
                  ),
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Row(mainAxisSize: MainAxisSize.min, children: actions),
            ),
          ),
        ],
      ),
    ),
  );
}

class MoodChoices extends StatelessWidget {
  final int? value;
  final ValueChanged<int> onChanged;
  final bool compact;
  const MoodChoices({
    super.key,
    required this.value,
    required this.onChanged,
    this.compact = false,
  });
  @override
  Widget build(BuildContext c) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: List.generate(
      6,
      (i) => MoodWaveDot(
        index: i,
        child: Semantics(
          label: '心情 $i 分',
          button: true,
          selected: value == i,
          child: InkResponse(
            onTap: () => onChanged(i),
            radius: 24,
            child: SizedBox(
              width: 44,
              height: 48,
              child: Center(
                child: AnimatedContainer(
                  duration: MediaQuery.disableAnimationsOf(c)
                      ? Duration.zero
                      : const Duration(milliseconds: 140),
                  width: compact ? 23 : 23 + i * 2.0,
                  height: compact ? 23 : 23 + i * 2.0,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Paper.mood[i],
                    border: value == i
                        ? Border.all(color: Paper.bg, width: 3)
                        : null,
                    boxShadow: value == i
                        ? [
                            BoxShadow(
                              color: Paper.ink.withValues(alpha: .1),
                              blurRadius: 4,
                              spreadRadius: 1,
                            ),
                          ]
                        : null,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class EmptyNote extends StatelessWidget {
  final String text;
  const EmptyNote(this.text, {super.key});
  @override
  Widget build(BuildContext c) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Text(text, textAlign: TextAlign.center, style: Paper.meta),
    ),
  );
}

void tell(BuildContext c, String message) {
  ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(message)));
}

Future<bool> confirm(
  BuildContext c,
  String message, {
  String yes = '完成',
  String no = '再想想',
}) async =>
    await showDialog<bool>(
      context: c,
      builder: (c) => AlertDialog(
        content: Text(message, style: Paper.body),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(no)),
          TextButton(onPressed: () => Navigator.pop(c, true), child: Text(yes)),
        ],
      ),
    ) ??
    false;
