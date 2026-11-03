import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A press begins on pointer down; scrolling or cancelling never selects.
class SoftPress extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final bool selection;
  final bool overshoot;
  const SoftPress({super.key, required this.child, required this.onTap, this.selection = false, this.overshoot = false});
  @override State<SoftPress> createState() => _SoftPressState();
}
class _SoftPressState extends State<SoftPress> with SingleTickerProviderStateMixin {
  late final motion = AnimationController.unbounded(vsync: this, value: 1);
  Offset? origin;
  int? pointer;
  bool cancelled = false;
  Timer? settle;
  bool get reduced => MediaQuery.disableAnimationsOf(context);
  void down(PointerDownEvent e) {
    if (widget.onTap == null || pointer != null) return;
    pointer = e.pointer; origin = e.position; cancelled = false; settle?.cancel();
    unawaited((widget.selection ? HapticFeedback.selectionClick() : HapticFeedback.lightImpact()).catchError((_) {}));
    if (!reduced) motion.animateTo(.9, duration: const Duration(milliseconds: 75), curve: Curves.easeOutCubic);
  }
  void release({bool cancel = false}) {
    if (pointer == null) return;
    pointer = null; cancelled |= cancel;
    if (reduced) { motion.value = 1; return; }
    motion.animateTo(widget.overshoot && !cancelled ? 1.05 : 1, duration: const Duration(milliseconds: 130), curve: Curves.easeOutCubic);
    if (widget.overshoot && !cancelled) settle = Timer(const Duration(milliseconds: 130), () {
      if (mounted) motion.animateTo(1, duration: const Duration(milliseconds: 160), curve: Curves.easeOutCubic);
    });
  }
  @override void didUpdateWidget(SoftPress old) { super.didUpdateWidget(old); if (widget.onTap == null) release(cancel: true); }
  @override void dispose() { settle?.cancel(); motion.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) => Listener(
    onPointerDown: down,
    onPointerMove: (e) { if (e.pointer == pointer && origin != null && (e.position - origin!).distance > 12) release(cancel: true); },
    onPointerUp: (e) { if (pointer == e.pointer) release(); },
    onPointerCancel: (e) { if (pointer == e.pointer) release(cancel: true); },
    child: GestureDetector(behavior: HitTestBehavior.opaque,
      onTapCancel: () => release(cancel: true),
      onTap: widget.onTap == null ? null : () { if (!cancelled) widget.onTap!(); },
      child: ScaleTransition(scale: motion, child: widget.child)),
  );
}

/// Keeps the foreground interactive, while taps outside softly dismiss it.
class FeedbackDismissLayer extends StatefulWidget {
  final Widget child;
  final VoidCallback onDismiss;
  const FeedbackDismissLayer({super.key, required this.child, required this.onDismiss});
  @override State<FeedbackDismissLayer> createState() => _FeedbackDismissLayerState();
}
class _FeedbackDismissLayerState extends State<FeedbackDismissLayer> {
  bool closing = false;
  Timer? timer;
  void dismiss() {
    if (closing) return;
    setState(() => closing = true);
    timer = Timer(MediaQuery.disableAnimationsOf(context) ? Duration.zero : const Duration(milliseconds: 160), widget.onDismiss);
  }
  @override void dispose() { timer?.cancel(); super.dispose(); }
  @override Widget build(BuildContext context) => AnimatedOpacity(
    opacity: closing ? 0 : 1,
    duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : const Duration(milliseconds: 160),
    child: Stack(fit: StackFit.expand, children: [
      Positioned.fill(child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: dismiss, child: const SizedBox.expand())),
      widget.child,
    ]),
  );
}
