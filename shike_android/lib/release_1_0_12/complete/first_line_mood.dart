import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../refined/design.dart';

/// A leading marker anchored to the first line, never the full text block.
/// Measurement and display share the exact span, style, width, locale and scale.
class FirstLineMoodSummary extends StatelessWidget {
  final InlineSpan text;
  final int? mood;
  const FirstLineMoodSummary({super.key, required this.text, required this.mood});
  @override Widget build(BuildContext context) {
    final style = DefaultTextStyle.of(context).style.merge(Paper.body).copyWith(
      height: 1.0, leadingDistribution: TextLeadingDistribution.even);
    final scaler = MediaQuery.textScalerOf(context);
    final locale = Localizations.maybeLocaleOf(context);
    final direction = Directionality.of(context);
    const behavior = TextHeightBehavior(
      applyHeightToFirstAscent: true, applyHeightToLastDescent: true,
      leadingDistribution: TextLeadingDistribution.even);
    Widget label() => Text.rich(text, style: style, textScaler: scaler,
      locale: locale, textDirection: direction, textHeightBehavior: behavior,
      maxLines: 2, overflow: TextOverflow.ellipsis);
    if (mood == null || mood! < 0 || mood! >= Paper.mood.length) return label();
    return LayoutBuilder(builder: (context, box) {
      final font = scaler.scale(style.fontSize ?? 17);
      // Scale the marker with the user's font, rather than leaving a tiny
      // fixed-size dot beside large system text. This matches reference P2.
      final diameter = font * .92;
      final gap = scaler.scale(10);
      final width = math.max(1.0, box.maxWidth - diameter - gap);
      final painter = TextPainter(text: TextSpan(style: style, children: [text]),
        textScaler: scaler, locale: locale, textDirection: direction,
        textHeightBehavior: behavior, maxLines: 2, ellipsis: '…')..layout(maxWidth: width);
      final lines = painter.computeLineMetrics();
      final first = lines.isEmpty ? null : lines.first;
      final firstCenter = first == null ? font / 2
        : first.baseline - first.ascent + first.height / 2;
      // A small optical descent compensates for CJK ink and baseline whitespace.
      // Crucially, wrapping only changes later lines, never this first-line anchor.
      final top = math.max(0.0, firstCenter - diameter / 2 + font * .06);
      painter.dispose();
      return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(padding: EdgeInsets.only(top: top, right: gap),
          child: Semantics(label: '心情 $mood 分', child: Container(width: diameter, height: diameter,
            decoration: BoxDecoration(shape: BoxShape.circle, color: Paper.mood[mood!])))),
        Expanded(child: label()),
      ]);
    });
  }
}
