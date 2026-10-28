import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'design.dart';

const allMoodScores = <int>{0, 1, 2, 3, 4, 5};

/// All lit is the default overview; its first tap starts an explicit selection.
Set<int> selectMoodScore(Set<int> current, int score) {
  assert(score >= 0 && score <= 5);
  if (current.length == 6 || current.isEmpty) return {score};
  final next = Set<int>.of(current);
  if (!next.add(score)) next.remove(score);
  return next.isEmpty ? Set.of(allMoodScores) : next;
}

/// 5 starts directly above the anchor; 4–0 follow counterclockwise at 30°.
Offset moodFanOffset(int score, {double radius = 86}) {
  final angle = -math.pi / 2 - (5 - score) * math.pi / 6;
  return Offset(math.cos(angle) * radius, math.sin(angle) * radius);
}

class MoodSemicircleFilter extends StatefulWidget {
  final Set<int> selected;
  final ValueChanged<Set<int>> onChanged;
  final bool enabled;
  const MoodSemicircleFilter({
    super.key,
    required this.selected,
    required this.onChanged,
    this.enabled = true,
  });

  @override
  State<MoodSemicircleFilter> createState() => _MoodSemicircleFilterState();
}

class _MoodSemicircleFilterState extends State<MoodSemicircleFilter>
    with SingleTickerProviderStateMixin {
  final anchor = GlobalKey();
  OverlayEntry? entry;
  late final AnimationController motion;
  late Set<int> selected;

  @override
  void initState() {
    super.initState();
    selected = Set.of(widget.selected);
    motion = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    )..addListener(() => entry?.markNeedsBuild());
  }

  @override
  void didUpdateWidget(MoodSemicircleFilter old) {
    super.didUpdateWidget(old);
    selected = Set.of(widget.selected);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!widget.enabled) {
        close(animate: false);
      } else {
        entry?.markNeedsBuild();
      }
    });
  }

  @override
  void dispose() {
    entry?.remove();
    entry = null;
    motion.dispose();
    super.dispose();
  }

  Future<void> close({bool animate = true}) async {
    if (entry == null) return;
    if (animate && mounted && !MediaQuery.disableAnimationsOf(context)) {
      await motion.reverse();
    }
    entry?.remove();
    entry = null;
    if (mounted) setState(() {});
  }

  void open() {
    if (!widget.enabled) return;
    if (entry != null) {
      close();
      return;
    }
    final overlay = Overlay.of(context, rootOverlay: true);
    final root = overlay.context.findRenderObject() as RenderBox?;
    final box = anchor.currentContext?.findRenderObject() as RenderBox?;
    if (root == null || box == null) return;
    final original = box.localToGlobal(
      box.size.center(Offset.zero),
      ancestor: root,
    );
    const inset = 112.0;
    final safe = Offset(
      original.dx.clamp(inset, root.size.width - 24),
      original.dy.clamp(inset, root.size.height - inset),
    );
    selected = Set.of(widget.selected);
    entry = OverlayEntry(
      builder: (c) {
        final t = MediaQuery.disableAnimationsOf(c)
            ? 1.0
            : Curves.easeOutCubic.transform(motion.value);
        final center = Offset.lerp(original, safe, t)!;
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: close,
                child: const ColoredBox(color: Colors.transparent),
              ),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(painter: _FanSurface(center, t)),
              ),
            ),
            for (var score = 5; score >= 0; score--)
              Positioned(
                left: center.dx + moodFanOffset(score).dx * t - 22,
                top: center.dy + moodFanOffset(score).dy * t - 22,
                width: 44,
                height: 44,
                child: Opacity(opacity: t, child: choice(score)),
              ),
            Positioned(
              left: center.dx - 22,
              top: center.dy - 22,
              width: 44,
              height: 44,
              child: Semantics(
                excludeSemantics: true,
                button: true,
                label: '收起心情筛选',
                onTap: close,
                child: GestureDetector(
                  onTap: close,
                  behavior: HitTestBehavior.opaque,
                  child: Center(child: centerDot()),
                ),
              ),
            ),
          ],
        );
      },
    );
    overlay.insert(entry!);
    motion.forward(from: 0);
    setState(() {});
  }

  void toggle(int score) {
    selected = selectMoodScore(selected, score);
    widget.onChanged(Set.of(selected));
    entry?.markNeedsBuild();
  }

  Widget choice(int score) {
    final active = selected.contains(score);
    // Circular hit regions do not overlap at the 30° spacing, even though
    // their enclosing rectangles can intersect diagonally.
    return ClipOval(
      child: Semantics(
        excludeSemantics: true,
        button: true,
        selected: active,
        label: '筛选心情 $score 分',
        onTap: () => toggle(score),
        child: Material(
          color: Colors.transparent,
          child: InkResponse(
            onTap: () => toggle(score),
            radius: 22,
            child: Center(
              child: AnimatedContainer(
                key: ValueKey('fan-score-$score'),
                duration: const Duration(milliseconds: 140),
                width: 26,
                height: 26,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: active
                      ? Paper.mood[score]
                      : Paper.faint.withValues(alpha: .10),
                  border: Border.all(
                    color: Paper.secondary.withValues(
                      alpha: active ? .32 : .12,
                    ),
                    width: .6,
                  ),
                  boxShadow: active
                      ? [
                          BoxShadow(
                            color: Paper.ink.withValues(alpha: .035),
                            blurRadius: 3,
                          ),
                        ]
                      : null,
                ),
                child: Text(
                  '$score',
                  style: TextStyle(
                    fontSize: 11,
                    color: Paper.ink.withValues(alpha: active ? .58 : .20),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget centerDot() => Container(
    width: 20,
    height: 20,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: Paper.faint.withValues(alpha: .42),
      border: selected.length == 6
          ? null
          : Border.all(color: Paper.secondary.withValues(alpha: .5), width: .6),
    ),
  );

  @override
  Widget build(BuildContext c) => Semantics(
    excludeSemantics: true,
    button: true,
    label: '心情筛选',
    value: widget.selected.length == 6
        ? '全部显示'
        : '已选择 ${widget.selected.toList()..sort()} 分',
    expanded: entry != null,
    onTap: open,
    child: Tooltip(
      message: '筛选心情',
      excludeFromSemantics: true,
      child: GestureDetector(
        onTap: open,
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          key: anchor,
          width: 48,
          height: 48,
          child: Center(
            child: entry == null
                ? centerDot()
                : const SizedBox.square(dimension: 20),
          ),
        ),
      ),
    ),
  );
}

class _FanSurface extends CustomPainter {
  final Offset center;
  final double opacity;
  _FanSurface(this.center, this.opacity);
  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Rect.fromCircle(center: center, radius: 110);
    final path = Path()
      ..moveTo(center.dx + 22, center.dy - 110)
      ..lineTo(center.dx, center.dy - 110)
      ..arcTo(bounds, -math.pi / 2, -math.pi, false)
      ..lineTo(center.dx + 22, center.dy + 110)
      ..close();
    canvas.drawShadow(
      path,
      Paper.ink.withValues(alpha: .025 * opacity),
      4,
      false,
    );
    canvas.drawPath(
      path,
      Paint()..color = Paper.bg.withValues(alpha: .98 * opacity),
    );
  }

  @override
  bool shouldRepaint(_FanSurface old) =>
      old.center != center || old.opacity != opacity;
}
