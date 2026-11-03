import 'package:flutter/material.dart';

import 'mood_wave.dart';

/// Keeps the page's existing nudge entry while each dot follows its wave phase.
class MoodNudge extends StatefulWidget {
  final Widget child;
  const MoodNudge({super.key, required this.child});
  @override
  MoodNudgeState createState() => MoodNudgeState();
}

class MoodNudgeState extends State<MoodNudge> {
  final wave = GlobalKey<MoodWaveState>();
  void nudge() => wave.currentState?.nudge();
  @override
  Widget build(BuildContext c) => MoodWave(key: wave, child: widget.child);
}
