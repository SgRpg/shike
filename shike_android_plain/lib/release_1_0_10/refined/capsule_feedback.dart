import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';

OverlayEntry? _currentFeedback;

/// App feedback only: compact, non-blocking, and automatically dismissed.
void showCapsuleFeedback(BuildContext context, String message, {
  String? actionLabel, VoidCallback? onAction,
}) {
  if (!context.mounted) return;
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  _currentFeedback?.remove();
  late OverlayEntry entry;
  void remove() {
    if (_currentFeedback == entry) {
      _currentFeedback = null;
      entry.remove();
    }
  }
  entry = OverlayEntry(builder: (_) => _FeedbackCapsule(
    message: message, actionLabel: actionLabel,
    onAction: onAction == null ? null : () { remove(); if (context.mounted) onAction(); },
    onDismiss: remove,
  ));
  _currentFeedback = entry;
  overlay.insert(entry);
}

class _FeedbackCapsule extends StatefulWidget {
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final VoidCallback onDismiss;
  const _FeedbackCapsule({required this.message, this.actionLabel, this.onAction, required this.onDismiss});
  @override State<_FeedbackCapsule> createState() => _FeedbackCapsuleState();
}

class _FeedbackCapsuleState extends State<_FeedbackCapsule> with SingleTickerProviderStateMixin {
  late final motion = AnimationController(vsync: this, duration: const Duration(milliseconds: 220), reverseDuration: const Duration(milliseconds: 400));
  Timer? timer;
  @override void initState() {
    super.initState();
    motion.forward();
    timer = Timer(const Duration(seconds: 3), () async {
      await motion.reverse();
      if (mounted) widget.onDismiss();
    });
  }
  @override void dispose() { timer?.cancel(); motion.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final reduced = media.disableAnimations;
    return Positioned(left: 24, right: 24,
      bottom: math.max(media.padding.bottom + 88, media.viewInsets.bottom + 16),
      child: IgnorePointer(ignoring: widget.onAction == null,
        child: FadeTransition(opacity: reduced ? const AlwaysStoppedAnimation(1) : motion,
          child: SlideTransition(position: reduced ? const AlwaysStoppedAnimation(Offset.zero)
            : Tween<Offset>(begin: const Offset(0, .15), end: Offset.zero).animate(CurvedAnimation(parent: motion, curve: Curves.easeOutCubic)),
            child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 360),
              child: Semantics(liveRegion: true, child: DecoratedBox(
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(30), boxShadow: [
                  BoxShadow(color: const Color(0xFF66615A).withValues(alpha: .06), blurRadius: 18, offset: const Offset(0, 3)),
                ]),
                child: ClipRRect(borderRadius: BorderRadius.circular(30),
                  child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                    child: Material(color: const Color(0xEEF3F2EF),
                      child: Padding(padding: EdgeInsets.fromLTRB(20, widget.onAction == null ? 13 : 4, widget.onAction == null ? 20 : 6, widget.onAction == null ? 13 : 4),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Flexible(child: Text(widget.message, textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 13, height: 1.5, color: Color(0xFF7F858B)))),
                          if (widget.onAction != null) ...[
                            const SizedBox(width: 8),
                            TextButton(onPressed: widget.onAction,
                              style: TextButton.styleFrom(foregroundColor: const Color(0xFF3D4146), minimumSize: const Size(54, 44)),
                              child: Text(widget.actionLabel ?? '看看', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700))),
                          ],
                        ]),
                      ),
                    ),
                  ),
                ),
              )),
            )),
          ),
        ),
      ),
    );
  }
}
