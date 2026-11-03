import 'package:flutter/material.dart';
import '../refined/design.dart';
class HomeMoodChoices extends StatelessWidget {
  final int? value;
  final ValueChanged<int> onChanged;
  const HomeMoodChoices({super.key, required this.value, required this.onChanged});
  @override Widget build(BuildContext context) => MoodChoices(value: value, onChanged: onChanged);
}
