import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../refined/design.dart';

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);
bool _same(DateTime? a, DateTime? b) => a != null && b != null && _day(a) == _day(b);
DateTimeRange _ordered(DateTime a, DateTime b) => a.isAfter(b)
    ? DateTimeRange(start: _day(b), end: _day(a))
    : DateTimeRange(start: _day(a), end: _day(b));

Future<DateTimeRange?> showSearchCalendar(BuildContext context, {DateTimeRange? initial}) =>
    showModalBottomSheet<DateTimeRange>(
      context: context, isScrollControlled: true, useSafeArea: true,
      requestFocus: false, backgroundColor: Paper.bg,
      barrierColor: Colors.black.withValues(alpha: .06),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
      clipBehavior: Clip.antiAlias,
      constraints: const BoxConstraints(maxWidth: 620),
      builder: (context) => SizedBox(
        height: math.min(MediaQuery.sizeOf(context).height * .76,
            math.max(420, MediaQuery.sizeOf(context).height * .55)),
        child: _MiniCalendar(initial: initial),
      ),
    );

class CalendarLineIcon extends StatelessWidget {
  const CalendarLineIcon({super.key});
  @override Widget build(BuildContext context) => const SizedBox(width: 21, height: 21,
    child: CustomPaint(painter: _CalendarIconPainter()));
}
class _CalendarIconPainter extends CustomPainter {
  const _CalendarIconPainter();
  @override void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24, size.height / 24);
    final p = Paint()..color = Paper.ink.withValues(alpha: .65)
      ..style = PaintingStyle.stroke..strokeWidth = 1.35..strokeCap = StrokeCap.round;
    canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(3, 5, 18, 16), const Radius.circular(2)), p);
    canvas.drawLine(const Offset(3, 10), const Offset(21, 10), p);
    canvas.drawLine(const Offset(8, 3), const Offset(8, 7), p);
    canvas.drawLine(const Offset(16, 3), const Offset(16, 7), p);
  }
  @override bool shouldRepaint(covariant _CalendarIconPainter oldDelegate) => false;
}

class _MiniCalendar extends StatefulWidget {
  final DateTimeRange? initial;
  const _MiniCalendar({this.initial});
  @override State<_MiniCalendar> createState() => _MiniCalendarState();
}

class _MiniCalendarState extends State<_MiniCalendar> {
  late DateTime shown;
  DateTime? start, end, preview;
  Timer? commitTimer;
  double cellWidth = 48, rowHeight = 48;
  @override void initState() {
    super.initState();
    final date = widget.initial?.end ?? DateTime.now();
    shown = DateTime(date.year, date.month);
    start = widget.initial?.start; end = widget.initial?.end;
  }
  @override void dispose() { commitTimer?.cancel(); super.dispose(); }

  int get offset => DateTime(shown.year, shown.month).weekday - 1;
  int get days => DateTime(shown.year, shown.month + 1, 0).day;
  int get rows => (offset + days + 6) ~/ 7;
  DateTime? at(Offset position) {
    if (position.dx < 0 || position.dy < 0 || position.dx >= cellWidth * 7 || position.dy >= rows * rowHeight) return null;
    final index = (position.dy / rowHeight).floor() * 7 + (position.dx / cellWidth).floor();
    final number = index - offset + 1;
    return number < 1 || number > days ? null : DateTime(shown.year, shown.month, number);
  }

  void finish(DateTime a, DateTime b) {
    commitTimer?.cancel();
    final value = _ordered(a, b);
    setState(() { start = a; end = b; preview = null; });
    // One brief selected frame before dismissal; a new tap may still reset it.
    commitTimer = Timer(const Duration(milliseconds: 140), () {
      if (mounted) Navigator.pop(context, value);
    });
  }
  void choose(DateTime date) {
    commitTimer?.cancel();
    if (start == null || end != null) {
      setState(() { start = date; end = null; preview = null; });
    } else if (_same(start, date)) {
      setState(() { start = null; preview = null; });
    } else { finish(start!, date); }
  }
  void moveMonth(int amount) {
    commitTimer?.cancel();
    final next = DateTime(shown.year, shown.month + amount);
    if (next.year < 1 || next.year > 9999) return;
    setState(() { shown = next; preview = null; });
  }
  void dragStart(DragStartDetails details) {
    commitTimer?.cancel();
    final date = at(details.localPosition);
    if (date == null) return;
    setState(() {
      if (start == null || end != null) { start = date; end = null; }
      preview = date;
    });
  }
  void dragUpdate(DragUpdateDetails details) {
    final date = at(details.localPosition);
    if (date != null && start != null && !_same(date, preview)) setState(() => preview = date);
  }
  void dragEnd(DragEndDetails _) {
    if (start != null && preview != null && !_same(start, preview)) {
      finish(start!, preview!);
    } else { setState(() => preview = null); }
  }

  @override Widget build(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context);
    final headerHeight = math.max(52.0, scale.scale(17) * 1.4 + 8);
    return SafeArea(top: false, child: Column(children: [
      Padding(padding: const EdgeInsets.only(top: 12, bottom: 10), child: Container(
        width: 38, height: 4, decoration: BoxDecoration(color: const Color(0xFFDEDDDA), borderRadius: BorderRadius.circular(3)))),
      SizedBox(height: headerHeight, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Row(children: [
        IconAction(Mark.back, label: '上个月', size: 18, onTap: shown.year == 1 && shown.month == 1 ? null : () => moveMonth(-1)),
        Expanded(child: Text('${shown.year}年${shown.month}月', textAlign: TextAlign.center,
          maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w500, color: Paper.ink))),
        IconAction(Mark.next, label: '下个月', size: 18, onTap: shown.year == 9999 && shown.month == 12 ? null : () => moveMonth(1)),
      ]))),
      Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: SizedBox(
        height: math.max(28, scale.scale(11) * 1.4 + 4), child: Row(children: [
          for (final label in ['一','二','三','四','五','六','日'])
            Expanded(child: Center(child: Text(label, style: const TextStyle(fontSize: 11, color: Color(0xFF9C9FA3))))),
        ]))),
      Expanded(child: Padding(padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
        child: LayoutBuilder(builder: (context, box) {
          cellWidth = box.maxWidth / 7;
          rowHeight = math.max(32, math.min(50, box.maxHeight / rows));
          final tail = end ?? preview;
          final selected = start != null && tail != null ? _ordered(start!, tail) : null;
          return Align(alignment: Alignment.topCenter, child: GestureDetector(
            behavior: HitTestBehavior.opaque, dragStartBehavior: DragStartBehavior.down,
            onPanStart: dragStart, onPanUpdate: dragUpdate, onPanEnd: dragEnd,
            onPanCancel: () { if (mounted) setState(() => preview = null); },
            child: MouseRegion(onHover: (event) {
              if (start == null || end != null) return;
              final date = at(event.localPosition);
              if (date != null && !_same(preview, date)) setState(() => preview = date);
            }, child: SizedBox(height: rowHeight * rows, child: Column(children: [
              for (var row = 0; row < rows; row++)
                SizedBox(height: rowHeight, child: Row(children: [
                  for (var col = 0; col < 7; col++)
                    Expanded(child: _cell(row * 7 + col, col, selected)),
                ])),
            ]))),
          ));
        }),
      )),
    ]));
  }

  Widget _cell(int index, int col, DateTimeRange? selected) {
    final number = index - offset + 1;
    if (number < 1 || number > days) return const SizedBox();
    final date = DateTime(shown.year, shown.month, number);
    final inRange = selected != null && !date.isBefore(selected.start) && !date.isAfter(selected.end);
    final endpoint = _same(date, start) || _same(date, end);
    final diameter = math.min(36.0, rowHeight - 6);
    return Semantics(button: true, selected: endpoint || inRange,
      label: '${date.year}年${date.month}月${date.day}日',
      hint: '点按选择范围，长按筛选这一天',
      child: GestureDetector(behavior: HitTestBehavior.opaque,
        onTap: () => choose(date), onLongPress: () => finish(date, date),
        child: CustomPaint(painter: _RangeBand(
          selected: inRange, leftHalf: selected != null && _same(date, selected.start),
          rightHalf: selected != null && _same(date, selected.end),
          roundLeft: col == 0 || number == 1, roundRight: col == 6 || number == days,
          bandHeight: diameter,
        ), child: Center(child: Container(
          width: diameter, height: diameter, alignment: Alignment.center,
          decoration: BoxDecoration(shape: BoxShape.circle, color: endpoint ? const Color(0xFF555556) : Colors.transparent),
          child: Padding(padding: const EdgeInsets.symmetric(horizontal: 2), child: FittedBox(fit: BoxFit.scaleDown,
            child: Text('$number', style: TextStyle(fontSize: 13, color: endpoint ? Colors.white : Paper.ink)))),
        ))),
      ));
  }
}

class _RangeBand extends CustomPainter {
  final bool selected, leftHalf, rightHalf, roundLeft, roundRight;
  final double bandHeight;
  const _RangeBand({required this.selected, required this.leftHalf, required this.rightHalf,
    required this.roundLeft, required this.roundRight, required this.bandHeight});
  @override void paint(Canvas canvas, Size size) {
    if (!selected || (leftHalf && rightHalf)) return;
    final rect = Rect.fromLTRB(leftHalf ? size.width / 2 : 0, (size.height - bandHeight) / 2,
      rightHalf ? size.width / 2 : size.width, (size.height + bandHeight) / 2);
    final radius = Radius.circular(bandHeight / 2);
    canvas.drawRRect(RRect.fromRectAndCorners(rect,
      topLeft: roundLeft ? radius : Radius.zero, bottomLeft: roundLeft ? radius : Radius.zero,
      topRight: roundRight ? radius : Radius.zero, bottomRight: roundRight ? radius : Radius.zero),
      Paint()..color = const Color(0xFFF0EEEC));
  }
  @override bool shouldRepaint(covariant _RangeBand old) => selected != old.selected || leftHalf != old.leftHalf ||
    rightHalf != old.rightHalf || roundLeft != old.roundLeft || roundRight != old.roundRight || bandHeight != old.bandHeight;
}
