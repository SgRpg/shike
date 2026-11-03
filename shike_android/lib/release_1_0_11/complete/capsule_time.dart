import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../refined/design.dart';

Future<DateTime?> chooseCapsuleTime(BuildContext context, {DateTime? initial}) => showGeneralDialog<DateTime>(
  context: context, barrierDismissible: true, barrierLabel: '返回写信', barrierColor: Colors.transparent,
  transitionDuration: const Duration(milliseconds: 240),
  pageBuilder: (_, _, _) => _CapsuleTime(initial: initial),
  transitionBuilder: (context, animation, _, child) => MediaQuery.disableAnimationsOf(context) ? child
    : SlideTransition(position: Tween<Offset>(begin: const Offset(0, .08), end: Offset.zero)
      .animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)), child: FadeTransition(opacity: animation, child: child)),
);

class _CapsuleTime extends StatefulWidget {
  final DateTime? initial;
  const _CapsuleTime({this.initial});
  @override State<_CapsuleTime> createState() => _CapsuleTimeState();
}
class _CapsuleTimeState extends State<_CapsuleTime> {
  late final DateTime opened = DateTime.now();
  late final DateTime firstDay = DateTime(opened.year, opened.month, opened.day);
  late final DateTime maximum = DateTime(opened.year + 10, opened.month,
    math.min(opened.day, DateUtils.getDaysInMonth(opened.year + 10, opened.month)), opened.hour, opened.minute);
  late DateTime day;
  late int hour, minute;
  int stage = 0;
  double turns = 0;
  Timer? advance;
  DateTime get minimum {
    final v = DateTime.now().add(const Duration(hours: 1));
    return DateTime(v.year, v.month, v.day, v.hour, v.minute + 1);
  }
  DateTime get selected => DateTime(day.year, day.month, day.day, hour, minute);
  @override void initState() {
    super.initState();
    final initial = widget.initial;
    final v = initial != null && !initial.isBefore(opened) && !initial.isAfter(maximum) ? initial : opened;
    day = DateTime(v.year, v.month, v.day); hour = v.hour; minute = v.minute;
    turns = (hour % 12) / 12;
  }
  @override void dispose() { advance?.cancel(); super.dispose(); }
  void tick() { unawaited(HapticFeedback.selectionClick().catchError((_) {})); }
  List<int> between(int from, int to) => [for (var i = from; i <= to; i++) i];
  int get minMonth => day.year == firstDay.year ? firstDay.month : 1;
  int get maxMonth => day.year == maximum.year ? maximum.month : 12;
  int get minDay => day.year == firstDay.year && day.month == firstDay.month ? firstDay.day : 1;
  int get maxDay => day.year == maximum.year && day.month == maximum.month
    ? maximum.day : DateUtils.getDaysInMonth(day.year, day.month);
  void dateChanged({int? year, int? month, int? date}) {
    final y = year ?? day.year;
    final m = (month ?? day.month).clamp(y == firstDay.year ? firstDay.month : 1, y == maximum.year ? maximum.month : 12);
    final d = (date ?? day.day).clamp(y == firstDay.year && m == firstDay.month ? firstDay.day : 1,
      y == maximum.year && m == maximum.month ? maximum.day : DateUtils.getDaysInMonth(y, m));
    setState(() => day = DateTime(y, m, d));
  }
  void pointTo(double next) {
    var delta = (next - turns) % 1;
    if (delta > .5) delta -= 1;
    turns += delta;
  }
  bool enabledHour(int h) => !DateTime(day.year, day.month, day.day, h, 59).isBefore(minimum)
    && !DateTime(day.year, day.month, day.day, h).isAfter(maximum);
  bool enabledMinute(int m) {
    final value = DateTime(day.year, day.month, day.day, hour, m);
    return !value.isBefore(minimum) && !value.isAfter(maximum);
  }
  void enterHour() {
    advance?.cancel();
    if (!enabledHour(hour)) {
      final valid = between(0, 23).where(enabledHour).toList();
      if (valid.isEmpty) {
        final next = minimum;
        setState(() { day = DateTime(next.year, next.month, next.day); hour = next.hour; minute = next.minute; });
      } else { hour = valid.first; }
    }
    setState(() { stage = 1; pointTo((hour % 12) / 12); });
  }
  void enterMinute() {
    advance?.cancel();
    final valid = between(0, 59).where(enabledMinute).toList();
    if (valid.isEmpty) { enterHour(); return; }
    if (!enabledMinute(minute)) minute = valid.first;
    setState(() { stage = 2; pointTo(minute / 60); });
  }
  void dial(Offset local, double size) {
    advance?.cancel();
    final delta = local - Offset(size / 2, size / 2);
    if (delta.distance < 15) return;
    final angle = (math.atan2(delta.dy, delta.dx) + math.pi / 2) % (math.pi * 2);
    if (stage == 1) {
      final slot = (angle / (2 * math.pi) * 12).round() % 12;
      final outside = delta.distance > size * .35;
      final value = outside ? (slot == 0 ? 0 : slot + 12) : (slot == 0 ? 12 : slot);
      if (!enabledHour(value) || value == hour) return;
      tick(); setState(() { hour = value; pointTo(slot / 12); });
    } else {
      final value = (angle / (2 * math.pi) * 60).round() % 60;
      if (!enabledMinute(value) || value == minute) return;
      tick(); setState(() { minute = value; pointTo(value / 60); });
    }
  }
  void settleHour() {
    if (stage == 1) advance = Timer(const Duration(milliseconds: 500), () { if (mounted) enterMinute(); });
  }
  void finish() {
    if (selected.isBefore(minimum) || selected.isAfter(maximum)) {
      enterHour();
      return;
    }
    Navigator.pop(context, selected);
  }
  Widget dateWheel() => SizedBox(height: 218, child: Stack(children: [
    Positioned.fill(child: ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (rect) => const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter,
        colors: [Colors.transparent, Colors.black, Colors.black, Colors.transparent], stops: [0, .36, .64, 1]).createShader(rect),
      child: Row(children: [
        Expanded(child: _DateWheel(values: between(firstDay.year, maximum.year), value: day.year, unit: '年', onChanged: (v) => dateChanged(year: v))),
        Expanded(child: _DateWheel(values: between(1, maxMonth), value: day.month, unit: '月', onChanged: (v) => dateChanged(month: v))),
        Expanded(child: _DateWheel(values: between(1, maxDay), value: day.day, unit: '日', onChanged: (v) => dateChanged(date: v))),
      ]),
    )),
    for (final top in [87.0, 131.0]) Positioned(left: 0, right: 0, top: top,
      child: const IgnorePointer(child: Divider(height: .5, thickness: .5, color: Paper.line))),
  ]));
  Widget clock() => LayoutBuilder(builder: (context, box) {
    final size = math.min(310.0, math.min(box.maxWidth, box.maxHeight));
    final radius = stage == 1 && hour > 0 && hour <= 12 ? .28 : .42;
    Widget number(int value, double ring, int slot, String label, bool enabled) {
      final angle = slot * math.pi / 6;
      final center = Offset(size / 2 + size * ring * math.sin(angle), size / 2 - size * ring * math.cos(angle));
      final chosen = stage == 1 ? value == hour : value == minute;
      return Positioned(left: center.dx - 20, top: center.dy - 20, width: 40, height: 40,
        child: Center(child: Text(label, style: TextStyle(fontSize: ring < .4 ? 14 : 17,
          color: chosen ? Colors.white : enabled ? const Color(0xFFB0B0B0) : const Color(0xFFE5E2DE),
          fontFeatures: const [ui.FontFeature.tabularFigures()]))));
    }
    return Center(child: SizedBox.square(dimension: size,
      child: GestureDetector(behavior: HitTestBehavior.opaque,
        onTapDown: (e) => dial(e.localPosition, size), onTapUp: (_) => settleHour(),
        onPanStart: (e) => dial(e.localPosition, size),
        onPanUpdate: (e) => dial(e.localPosition, size), onPanEnd: (_) => settleHour(),
        onPanCancel: () => advance?.cancel(),
        child: Stack(children: [
          Positioned.fill(child: TweenAnimationBuilder<double>(tween: Tween(begin: turns, end: turns),
            duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            builder: (_, angle, _) => TweenAnimationBuilder<double>(tween: Tween(begin: radius, end: radius),
              duration: const Duration(milliseconds: 200),
              builder: (_, r, _) => CustomPaint(painter: _ClockHand(angle, r))))),
          Positioned.fill(child: AnimatedSwitcher(duration: const Duration(milliseconds: 260),
            child: Stack(key: ValueKey(stage), children: stage == 1 ? [
              for (var i = 0; i < 12; i++) number(i == 0 ? 0 : i + 12, .42, i, (i == 0 ? 0 : i + 12).toString().padLeft(2, '0'), enabledHour(i == 0 ? 0 : i + 12)),
              for (var i = 0; i < 12; i++) number(i == 0 ? 12 : i, .28, i, (i == 0 ? 12 : i).toString().padLeft(2, '0'), enabledHour(i == 0 ? 12 : i)),
            ] : [for (var i = 0; i < 12; i++) number(i * 5, .42, i, (i * 5).toString().padLeft(2, '0'), enabledMinute(i * 5))]),
          )),
        ]),
      ),
    ));
  });
  @override Widget build(BuildContext context) => Material(type: MaterialType.transparency,
    child: Stack(children: [
      if (stage > 0) Positioned.fill(child: GestureDetector(onTap: () => Navigator.pop(context),
        child: BackdropFilter(filter: ui.ImageFilter.blur(sigmaX: 5, sigmaY: 5),
          child: ColoredBox(color: Paper.bg.withValues(alpha: .60))))),
      Align(alignment: Alignment.bottomCenter, child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 620),
        child: Container(decoration: const BoxDecoration(color: Paper.bg,
          borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
          child: SafeArea(top: false, child: Padding(padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 36, height: 4, decoration: BoxDecoration(color: Paper.line, borderRadius: BorderRadius.circular(2))),
              Row(children: [
                if (stage == 0) const Expanded(child: Text('解锁日期', style: Paper.meta))
                else TextButton(onPressed: () { advance?.cancel(); setState(() => stage = stage == 1 ? 0 : 1); pointTo(stage == 1 ? (hour % 12) / 12 : minute / 60); },
                  child: Text(stage == 1 ? '返回日期' : '返回小时', style: Paper.meta)),
                if (stage > 0) const Spacer(),
                if (stage == 1) const Text('选择时间', style: Paper.meta),
                if (stage > 0) const Spacer(),
                TextButton(onPressed: stage == 0 ? enterHour : stage == 1 ? enterMinute : finish,
                  child: Text(stage == 0 ? '完成' : stage == 1 ? '下一步' : '确定', style: Paper.meta)),
              ]),
              if (stage == 0) dateWheel() else ...[
                AnimatedSwitcher(duration: const Duration(milliseconds: 240), child: Text.rich(key: ValueKey(stage),
                  TextSpan(children: [
                    TextSpan(text: stage == 1 ? '${hour.toString().padLeft(2, '0')} ' : '${hour.toString().padLeft(2, '0')}:',
                      style: const TextStyle(fontSize: 34, color: Paper.ink, fontWeight: FontWeight.w500)),
                    TextSpan(text: stage == 1 ? '时' : minute.toString().padLeft(2, '0'),
                      style: TextStyle(fontSize: stage == 1 ? 16 : 34, color: stage == 1 ? Paper.secondary : Paper.mood[5])),
                  ]))),
                SizedBox(height: math.min(310, MediaQuery.sizeOf(context).height * .43), child: clock()),
              ],
            ]),
          )),
        ),
      )),
    ]),
  );
}

class _DateWheel extends StatefulWidget {
  final List<int> values;
  final int value;
  final String unit;
  final ValueChanged<int> onChanged;
  const _DateWheel({required this.values, required this.value, required this.unit, required this.onChanged});
  @override State<_DateWheel> createState() => _DateWheelState();
}
class _DateWheelState extends State<_DateWheel> {
  late final scroll = FixedExtentScrollController(initialItem: widget.values.indexOf(widget.value));
  @override void didUpdateWidget(_DateWheel old) {
    super.didUpdateWidget(old);
    final index = widget.values.indexOf(widget.value);
    if (old.values.first != widget.values.first || old.values.last != widget.values.last || old.value != widget.value) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && scroll.hasClients && scroll.selectedItem != index) scroll.jumpToItem(index);
      });
    }
  }
  @override void dispose() { scroll.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) => ListWheelScrollView.useDelegate(
    controller: scroll, itemExtent: 44, diameterRatio: 2.8, perspective: .001,
    physics: const FixedExtentScrollPhysics(parent: BouncingScrollPhysics()),
    onSelectedItemChanged: (i) {
      if (i >= widget.values.length) return;
      final value = widget.values[i];
      if (value != widget.value) { HapticFeedback.selectionClick(); widget.onChanged(value); }
      // Past month/day rows remain visible like paper fading at the edges,
      // but bounce back to the earliest valid date if the user selects one.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !scroll.hasClients) return;
        final target = widget.values.indexOf(widget.value);
        if (scroll.selectedItem != target) {
          scroll.animateToItem(target, duration: const Duration(milliseconds: 160), curve: Curves.easeOutCubic);
        }
      });
    },
    childDelegate: ListWheelChildBuilderDelegate(childCount: widget.values.length,
      builder: (_, i) {
        final value = widget.values[i], selected = value == widget.value;
        return Center(child: Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic,
          children: [
            Text(value.toString().padLeft(2, '0'), style: TextStyle(fontSize: selected ? 22 : 18,
              fontWeight: selected ? FontWeight.w500 : FontWeight.normal,
              color: selected ? Paper.ink : Paper.faint.withValues(alpha: .3), fontFeatures: const [ui.FontFeature.tabularFigures()])),
            const SizedBox(width: 3), Text(widget.unit, style: TextStyle(fontSize: 11, color: selected ? Paper.secondary : Paper.faint.withValues(alpha: .3))),
          ]));
      }),
  );
}
class _ClockHand extends CustomPainter {
  final double turns, radius;
  _ClockHand(this.turns, this.radius);
  @override void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero), angle = turns * math.pi * 2;
    final end = center + Offset(math.sin(angle), -math.cos(angle)) * (size.width * radius);
    final color = Paper.mood[5];
    canvas.drawLine(center, end, Paint()..color = color..strokeWidth = 1.2..strokeCap = StrokeCap.round);
    canvas.drawCircle(center, 3.5, Paint()..color = color);
    canvas.drawCircle(end, 18, Paint()..color = color.withValues(alpha: .85));
  }
  @override bool shouldRepaint(_ClockHand old) => turns != old.turns || radius != old.radius;
}
