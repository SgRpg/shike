import 'package:flutter/material.dart';
import '../refined/design.dart';

/// Presentation-only normalization of an immutable historical metadata snapshot.
class DiaryMetadataHeader extends StatelessWidget {
  final String snapshot;
  final DateTime created;
  final int? mood;
  final Widget? moodControl;
  const DiaryMetadataHeader({super.key, required this.snapshot, required this.created, required this.mood, this.moodControl});

  @override Widget build(BuildContext context) {
    final datePrefix = RegExp(r'^\s*(\d{4})[./-](\d{1,2})[./-](\d{1,2})\s*(?:[·•]\s*)?').firstMatch(snapshot);
    final date = datePrefix == null
        ? '${created.year}.${created.month.toString().padLeft(2, '0')}.${created.day.toString().padLeft(2, '0')}'
        : '${datePrefix.group(1)}.${datePrefix.group(2)!.padLeft(2, '0')}.${datePrefix.group(3)!.padLeft(2, '0')}';
    final environment = (datePrefix == null ? snapshot : snapshot.substring(datePrefix.end))
        .split(RegExp(r'\s*[·•]\s*'))
        .map((part) => part.trim().replaceAll('℃', '°')
            .replaceAll(RegExp(r'°\s*c', caseSensitive: false), '°')
            .replaceFirst(RegExp(r'市$'), ''))
        .where((part) => part.isNotEmpty).join(' · ');
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: Text(date, style: const TextStyle(fontSize: 19, height: 1.4,
          fontWeight: FontWeight.w500, color: Color(0xFF4C5056)))),
        if (moodControl != null) moodControl! else if (mood != null) ...[
          const SizedBox(width: 16),
          Semantics(label: '心情 $mood 分', child: Container(width: 18, height: 18,
            decoration: BoxDecoration(shape: BoxShape.circle, color: Paper.mood[mood!]))),
        ],
      ]),
      if (environment.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 5),
        child: Text(environment, style: const TextStyle(fontSize: 13, height: 1.5, color: Color(0xFF93999F)))),
    ]);
  }
}
