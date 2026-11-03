import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

/// Pointer feedback precedes tap recognition; scrolling still wins the gesture.
class PaperPress extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  final String? label;
  const PaperPress({super.key, required this.child, required this.onTap, this.label});
  @override State<PaperPress> createState() => _PaperPressState();
}
class _PaperPressState extends State<PaperPress> {
  bool pressed = false, cancelled = false, locked = false;
  Offset? origin;
  void release() { if (mounted) setState(() => pressed = false); }
  @override Widget build(BuildContext context) => Semantics(button: true, label: widget.label,
    child: Listener(
      onPointerDown: (event) {
        if (locked) return;
        origin = event.position; cancelled = false;
        setState(() => pressed = true);
        HapticFeedback.lightImpact();
      },
      onPointerMove: (event) {
        if (origin != null && (event.position - origin!).distance > 12) {
          cancelled = true; release();
        }
      },
      onPointerUp: (_) => release(),
      onPointerCancel: (_) { cancelled = true; release(); },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapCancel: release,
        onTap: () async {
          if (cancelled || locked) return;
          locked = true; release();
          widget.onTap();
          await Future<void>.delayed(const Duration(milliseconds: 300));
          if (mounted) locked = false;
        },
        child: AnimatedScale(scale: pressed ? .97 : 1,
          duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : Duration(milliseconds: pressed ? 80 : 160),
          curve: Curves.easeOutCubic, child: widget.child),
      ),
    ),
  );
}

class PaperDiaryRoute<T> extends CupertinoPageRoute<T> {
  PaperDiaryRoute({required super.builder});
  @override Duration get transitionDuration => const Duration(milliseconds: 280);
  @override Duration get reverseTransitionDuration => const Duration(milliseconds: 280);
}
