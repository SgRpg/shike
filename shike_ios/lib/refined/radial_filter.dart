import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'design.dart';

class MoodRadialFilter extends StatefulWidget {
  final Set<int> selected;
  final ValueChanged<Set<int>> onChanged;
  final bool enabled;
  const MoodRadialFilter({
    super.key,
    required this.selected,
    required this.onChanged,
    this.enabled = true,
  });
  @override
  State<MoodRadialFilter> createState() => _MoodRadialFilterState();
}

class _MoodRadialFilterState extends State<MoodRadialFilter>
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
  void didUpdateWidget(MoodRadialFilter old) {
    super.didUpdateWidget(old);
    selected = Set.of(widget.selected);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!widget.enabled && entry != null) {
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
    final safe = Offset(
      original.dx.clamp(96.0, root.size.width - 96.0),
      original.dy.clamp(100.0, root.size.height - 130.0),
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
                onTap: () => close(),
                child: const ColoredBox(color: Colors.transparent),
              ),
            ),
            Positioned(
              left: center.dx - 92,
              top: center.dy - 92,
              width: 184,
              height: 184,
              child: IgnorePointer(
                child: Opacity(
                  opacity: t,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Paper.bg.withValues(alpha: .97),
                      boxShadow: [
                        BoxShadow(
                          color: Paper.ink.withValues(alpha: .035),
                          blurRadius: 14,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            for (var i = 0; i < 6; i++)
              Positioned(
                left:
                    center.dx +
                    math.cos(-math.pi / 4 + i * math.pi / 3) * 70 * t -
                    22,
                top:
                    center.dy +
                    math.sin(-math.pi / 4 + i * math.pi / 3) * 70 * t -
                    22,
                width: 44,
                height: 44,
                child: Opacity(opacity: t, child: choice(i)),
              ),
            Positioned(
              left: center.dx - 22,
              top: center.dy - 22,
              width: 44,
              height: 44,
              child: Semantics(
                button: true,
                label: '收起心情筛选',
                child: GestureDetector(
                  onTap: () => close(),
                  behavior: HitTestBehavior.opaque,
                  child: Center(child: centerDot()),
                ),
              ),
            ),
            Positioned(
              left: center.dx - 64,
              top: center.dy + 94,
              width: 128,
              height: 44,
              child: Material(
                color: Paper.bg.withValues(alpha: .98),
                borderRadius: BorderRadius.circular(20),
                child: TextButton(
                  onPressed: () {
                    selected = {0, 1, 2, 3, 4, 5};
                    widget.onChanged(Set.of(selected));
                    entry?.markNeedsBuild();
                  },
                  child: Text('恢复全部', style: Paper.meta.copyWith(fontSize: 12)),
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

  Widget choice(int i) {
    final active = selected.contains(i);
    return Semantics(
      excludeSemantics: true,
      button: true,
      selected: active,
      label: '筛选心情 $i 分',
      onTap: () => toggle(i),
      child: Material(
        color: Colors.transparent,
        child: InkResponse(
          radius: 22,
          onTap: () => toggle(i),
          child: Center(
            child: Container(
              width: 31,
              height: 31,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: active
                    ? Paper.mood[i]
                    : Paper.faint.withValues(alpha: .10),
                border: Border.all(
                  color: Paper.secondary.withValues(alpha: active ? .22 : .10),
                  width: .6,
                ),
                boxShadow: active
                    ? [
                        BoxShadow(
                          color: Paper.ink.withValues(alpha: .035),
                          blurRadius: 3,
                          offset: const Offset(0, 1),
                        ),
                      ]
                    : null,
              ),
              child: Text(
                '$i',
                style: TextStyle(
                  fontSize: 12,
                  color: Paper.ink.withValues(alpha: active ? .58 : .20),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void toggle(int i) {
    final next = Set<int>.of(selected);
    if (!next.add(i)) next.remove(i);
    selected = next;
    widget.onChanged(Set.of(next));
    entry?.markNeedsBuild();
  }

  Widget centerDot() => Container(
    width: 20,
    height: 20,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: Paper.faint.withValues(alpha: .42),
      border: widget.selected.length == 6
          ? null
          : Border.all(color: Paper.secondary.withValues(alpha: .5), width: .6),
    ),
  );
  @override
  Widget build(BuildContext c) => Semantics(
    button: true,
    label: '心情筛选',
    value: widget.selected.length == 6
        ? '全部显示'
        : widget.selected.isEmpty
        ? '全部隐藏'
        : '已选择 ${widget.selected.toList()..sort()} 分',
    expanded: entry != null,
    child: Tooltip(
      message: '筛选心情',
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
