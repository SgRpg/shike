import 'package:flutter/material.dart';

const moodWaveHopMs = 320;
const moodWaveDelayMs = 60;
const moodWaveDurationMs = moodWaveHopMs + 5 * moodWaveDelayMs;

final _waveLift = TweenSequence<double>([
  TweenSequenceItem(
    tween: Tween(
      begin: 0.0,
      end: -5.0,
    ).chain(CurveTween(curve: Curves.easeOutCubic)),
    weight: 35,
  ),
  TweenSequenceItem(
    tween: Tween(
      begin: -5.0,
      end: 0.0,
    ).chain(CurveTween(curve: Curves.easeOutBack)),
    weight: 65,
  ),
]);

class MoodWave extends StatefulWidget {
  final Widget child;
  const MoodWave({super.key, required this.child});
  @override
  MoodWaveState createState() => MoodWaveState();
}

class MoodWaveState extends State<MoodWave>
    with SingleTickerProviderStateMixin {
  late final AnimationController animation;
  @override
  void initState() {
    super.initState();
    animation = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: moodWaveDurationMs),
    );
  }

  void nudge() {
    if (!mounted ||
        animation.isAnimating ||
        MediaQuery.disableAnimationsOf(context)) {
      return;
    }
    animation.forward(from: 0);
  }

  @override
  void dispose() {
    animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext c) =>
      _MoodWaveScope(animation: animation, child: widget.child);
}

class _MoodWaveScope extends InheritedNotifier<AnimationController> {
  const _MoodWaveScope({
    required AnimationController animation,
    required super.child,
  }) : super(notifier: animation);
}

/// Outside a wave scope this is stationary, so other mood pickers keep their UI.
class MoodWaveDot extends StatelessWidget {
  final int index;
  final Widget child;
  const MoodWaveDot({super.key, required this.index, required this.child})
    : assert(index >= 0 && index < 6);
  @override
  Widget build(BuildContext c) {
    final wave = c.dependOnInheritedWidgetOfExactType<_MoodWaveScope>();
    final elapsed = (wave?.notifier?.value ?? 0) * moodWaveDurationMs;
    final local = ((elapsed - index * moodWaveDelayMs) / moodWaveHopMs).clamp(
      0.0,
      1.0,
    );
    return Transform.translate(
      key: ValueKey('mood-wave-dot-$index'),
      offset: Offset(0, _waveLift.transform(local)),
      child: child,
    );
  }
}
