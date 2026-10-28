import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'design.dart';

/// Runs only after persistence succeeds. Does not request focus, haptics or sound.
Future<void> showKeptFeedback(
  BuildContext context, {
  required String text,
  required GlobalKey sourceKey,
  GlobalKey? destinationKey,
}) async {
  if (!context.mounted) return;
  final overlay = Overlay.of(context, rootOverlay: true);
  final root = overlay.context.findRenderObject() as RenderBox?;
  final source = sourceKey.currentContext?.findRenderObject() as RenderBox?;
  final target =
      destinationKey?.currentContext?.findRenderObject() as RenderBox?;
  final reduced = MediaQuery.disableAnimationsOf(context);
  if (!reduced &&
      root != null &&
      source != null &&
      source.hasSize &&
      target != null &&
      target.hasSize) {
    final from =
        source.localToGlobal(Offset.zero, ancestor: root) & source.size;
    final to = target.localToGlobal(
      target.size.center(Offset.zero),
      ancestor: root,
    );
    final done = Completer<void>();
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => KeptFlight(
        text: text,
        from: from,
        to: to,
        onDone: () {
          if (entry.mounted) entry.remove();
          if (!done.isCompleted) done.complete();
        },
      ),
    );
    overlay.insert(entry);
    await done.future;
  }
}

class KeptFlight extends StatefulWidget {
  final String text;
  final Rect from;
  final Offset to;
  final VoidCallback onDone;
  const KeptFlight({
    super.key,
    required this.text,
    required this.from,
    required this.to,
    required this.onDone,
  });
  @override
  State<KeptFlight> createState() => _KeptFlightState();
}

class _KeptFlightState extends State<KeptFlight>
    with SingleTickerProviderStateMixin {
  late final AnimationController animation;
  @override
  void initState() {
    super.initState();
    animation =
        AnimationController(
            vsync: this,
            duration: const Duration(milliseconds: 620),
          )
          ..addStatusListener((s) {
            if (s == AnimationStatus.completed) widget.onDone();
          })
          ..forward();
  }

  @override
  void dispose() {
    animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext c) => IgnorePointer(
    child: AnimatedBuilder(
      animation: animation,
      builder: (c, _) {
        final p = animation.value;
        final shrink = (p / .32).clamp(0.0, 1.0);
        final travel = Curves.easeInOutCubic.transform(
          ((p - .20) / .80).clamp(0.0, 1.0),
        );
        final a = widget.from.center;
        final b = widget.to;
        final control = Offset(
          (a.dx + b.dx) / 2 + 50,
          a.dy + (b.dy - a.dy) * .22,
        );
        final point =
            a * math.pow(1 - travel, 2).toDouble() +
            control * (2 * (1 - travel) * travel) +
            b * (travel * travel);
        final glow = p > .86 ? (1 - p) / .14 : 1.0;
        return Stack(
          children: [
            if (shrink < 1)
              Positioned.fromRect(
                rect: widget.from,
                child: Opacity(
                  opacity: 1 - shrink,
                  child: Transform.scale(
                    scale: 1 - shrink * .95,
                    alignment: Alignment.center,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        widget.text,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Paper.body,
                      ),
                    ),
                  ),
                ),
              ),
            if (p >= .20)
              Positioned(
                left: point.dx - 4,
                top: point.dy - 4,
                child: Opacity(
                  opacity: glow.clamp(0.0, 1.0),
                  child: Container(
                    key: const ValueKey('kept-light-point'),
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFFE5D8B6),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFE5D8B6).withValues(alpha: .5),
                          blurRadius: 9,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    ),
  );
}
