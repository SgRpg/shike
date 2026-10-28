import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';

import 'controller.dart';
import '../refined/design.dart';
import 'reading.dart';
import '../refined/semicircle_filter.dart';
import '../refined/heart_tabs.dart';

class HeartPage extends StatefulWidget {
  final CompleteController controller;
  final bool active;
  const HeartPage({super.key, required this.controller, this.active = true});
  @override
  State<HeartPage> createState() => _HeartPageState();
}

class _HeartPageState extends State<HeartPage> {
  bool heat = false, monthly = false;
  DateTime shown = DateTime.now();
  DateTime? selected;
  Set<int> selectedMoods = {0, 1, 2, 3, 4, 5};
  String? feedback;
  @override
  void initState() {
    super.initState();
    if (widget.active) loadFeedback();
  }

  @override
  void didUpdateWidget(HeartPage old) {
    super.didUpdateWidget(old);
    if (!widget.active && old.active) {
      selectedMoods = {0, 1, 2, 3, 4, 5};
    }
    if (widget.active && !old.active) loadFeedback();
  }

  Future<void> loadFeedback() async {
    final value = await widget.controller.periodFeedback(
      month: monthly,
      now: DateTime.now(),
    );
    if (mounted) setState(() => feedback = value);
  }

  bool accepts(int? mood) => mood != null && selectedMoods.contains(mood);
  @override
  Widget build(BuildContext c) {
    final now = DateTime.now();
    final start = monthly
        ? DateTime(now.year, now.month, 1)
        : DateTime(now.year, now.month, now.day - now.weekday + 1);
    final count = monthly ? DateTime(now.year, now.month + 1, 0).day : 7;
    final days = widget.controller.period(start, count);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
          child: Text('心迹', style: Paper.title(31)),
        ),
        HeartTopTabs(
          heat: heat,
          onChanged: (v) {
            setState(() {
              heat = v;
              selectedMoods = {0, 1, 2, 3, 4, 5};
            });
            if (!heat) loadFeedback();
          },
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 24),
          child: Divider(),
        ),
        Expanded(
          child: heat
              ? calendar(c)
              : ListView(
                  padding: const EdgeInsets.fromLTRB(24, 25, 24, 30),
                  children: [
                    Center(
                      child: PeriodControl(
                        value: monthly,
                        onChanged: (v) {
                          setState(() {
                            monthly = v;
                            feedback = null;
                          });
                          loadFeedback();
                        },
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      '${DateFormat('M月d日').format(start)} — ${DateFormat('M月d日').format(DateTime(start.year, start.month, start.day + count - 1))}',
                      textAlign: TextAlign.center,
                      style: Paper.meta,
                    ),
                    const SizedBox(height: 32),
                    const Text('每日平均心情', style: TextStyle(fontSize: 18)),
                    const SizedBox(height: 26),
                    SizedBox(
                      height: 240,
                      child: days.every((d) => d.mean == null)
                          ? const EmptyNote('还没有心情记录')
                          : MoodTrend(
                              days: days,
                              monthly: monthly,
                              onTap: (d) => showDay(c, d),
                            ),
                    ),
                    if (feedback != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 20),
                        child: Text(
                          feedback!,
                          style: Paper.meta,
                          textAlign: TextAlign.center,
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }

  Widget calendar(BuildContext context) {
    final first = DateTime(shown.year, shown.month, 1);
    final offset = first.weekday - 1;
    final count = DateTime(shown.year, shown.month + 1, 0).day;
    final narrow = MediaQuery.sizeOf(context).width < 355;
    return ListView(
      padding: EdgeInsets.fromLTRB(narrow ? 4 : 24, 16, narrow ? 4 : 24, 24),
      children: [
        Row(
          children: [
            IconAction(
              Mark.back,
              label: '上个月',
              size: 18,
              onTap: () =>
                  setState(() => shown = DateTime(shown.year, shown.month - 1)),
            ),
            Expanded(
              child: Text(
                '${shown.year}年${shown.month}月',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 17),
              ),
            ),
            IconAction(
              Mark.next,
              label: '下个月',
              size: 18,
              onTap: () =>
                  setState(() => shown = DateTime(shown.year, shown.month + 1)),
            ),
            MoodSemicircleFilter(
              selected: selectedMoods,
              enabled: widget.active && heat,
              onChanged: (values) => setState(() => selectedMoods = values),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Row(
          children: ['一', '二', '三', '四', '五', '六', '日']
              .map(
                (t) => Expanded(
                  child: Text(
                    t,
                    textAlign: TextAlign.center,
                    style: Paper.meta,
                  ),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 14),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            mainAxisExtent: 49,
          ),
          itemCount: offset + count,
          itemBuilder: (c, i) {
            if (i < offset) return const SizedBox();
            final d = DateTime(shown.year, shown.month, i - offset + 1);
            final values = widget.controller.dayEntries(d);
            final mood = values.isEmpty ? null : values.first.mood;
            final colored = accepts(mood);
            final active = selected != null && onDay(selected!, d);
            return Semantics(
              button: true,
              label: '${d.month}月${d.day}日，${values.length}篇日记',
              selected: active,
              child: InkResponse(
                onTap: () {
                  setState(() => selected = d);
                  showDay(c, d);
                },
                radius: 23,
                child: Center(
                  child: Container(
                    width: 38,
                    height: 38,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: colored ? Paper.mood[mood!] : Colors.transparent,
                      border: active
                          ? Border.all(color: Colors.white, width: 4)
                          : null,
                      boxShadow: active
                          ? [
                              BoxShadow(
                                color: Paper.ink.withValues(alpha: .10),
                                blurRadius: 7,
                                offset: const Offset(0, 2),
                              ),
                            ]
                          : null,
                    ),
                    child: Text(
                      '${d.day}',
                      style: const TextStyle(color: Paper.ink, fontSize: 13),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  void showDay(BuildContext context, DateTime date) {
    final entries = widget.controller.dayEntries(date);
    final maxHeight = MediaQuery.sizeOf(context).height * .60;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Paper.bg,
      barrierColor: Colors.black.withValues(alpha: .08),
      constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (c) => SafeArea(
        top: false,
        child: SizedBox(
          width: double.infinity,
          height: math.min(
            maxHeight,
            math.max(195.0, 100 + entries.length * 72.0),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  child: Container(
                    width: 40,
                    height: 5,
                    decoration: BoxDecoration(
                      color: const Color(0xFFCCCBC8),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 10, 24, 12),
                child: Text(
                  '${DateFormat('M月d日').format(date)} · ${entries.length} 篇',
                  style: const TextStyle(fontSize: 18),
                ),
              ),
              Expanded(
                child: entries.isEmpty
                    ? const EmptyNote('这一天还没有记录。')
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        itemCount: entries.length,
                        separatorBuilder: (_, _) => const Divider(),
                        itemBuilder: (c, i) {
                          final e = entries[i];
                          return InkWell(
                            onTap: () {
                              Navigator.pop(c);
                              openReading(context, widget.controller, e);
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 18),
                              child: Row(
                                children: [
                                  Text(
                                    DateFormat('HH:mm').format(e.created),
                                    style: Paper.meta.copyWith(fontSize: 13),
                                  ),
                                  const SizedBox(width: 15),
                                  Container(
                                    width: 18,
                                    height: 18,
                                    decoration: BoxDecoration(
                                      color: Paper.mood[e.mood ?? 0],
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 15),
                                  Expanded(
                                    child: Text(
                                      e.text,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 15),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  const LineMark(Mark.next, size: 15),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class PeriodControl extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  const PeriodControl({
    super.key,
    required this.value,
    required this.onChanged,
  });
  @override
  Widget build(BuildContext c) => Container(
    width: 222,
    height: 44,
    padding: const EdgeInsets.all(2),
    decoration: BoxDecoration(
      color: const Color(0xFFF0F0EF),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Row(
      children: [
        for (final v in [false, true])
          Expanded(
            child: Semantics(
              button: true,
              selected: value == v,
              label: v ? '月' : '周',
              child: GestureDetector(
                onTap: () => onChanged(v),
                child: Container(
                  alignment: Alignment.center,
                  decoration: value == v
                      ? BoxDecoration(
                          color: Paper.bg,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: const Color(0xFFDEDEDB),
                            width: .7,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Paper.ink.withValues(alpha: .03),
                              blurRadius: 2,
                            ),
                          ],
                        )
                      : null,
                  child: Text(
                    v ? '月' : '周',
                    style: TextStyle(
                      color: value == v ? Paper.ink : Paper.secondary,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

class MoodTrend extends StatelessWidget {
  final List<MoodDay> days;
  final bool monthly;
  final ValueChanged<DateTime> onTap;
  const MoodTrend({
    super.key,
    required this.days,
    required this.onTap,
    this.monthly = false,
  });
  @override
  Widget build(BuildContext c) {
    final spots = <FlSpot>[];
    for (var i = 0; i < days.length; i++) {
      final value = days[i].mean;
      spots.add(value == null ? FlSpot.nullSpot : FlSpot(i.toDouble(), value));
    }
    return Semantics(
      label: '${days.length}天的每日平均心情图，可点日期查看日记',
      child: LineChart(
        LineChartData(
          minX: 0,
          maxX: (days.length - 1).toDouble(),
          minY: 0,
          maxY: 5,
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: 1,
            getDrawingHorizontalLine: (_) => const FlLine(
              color: Paper.line,
              strokeWidth: .7,
              dashArray: [3, 4],
            ),
          ),
          borderData: FlBorderData(
            show: true,
            border: const Border(
              left: BorderSide(color: Paper.faint, width: .8),
              bottom: BorderSide(color: Paper.faint, width: .8),
            ),
          ),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(),
            rightTitles: const AxisTitles(),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                interval: 1,
                reservedSize: 25,
                getTitlesWidget: (v, m) => Text(
                  '${v.toInt()}',
                  style: Paper.meta.copyWith(fontSize: 12),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                interval: 1,
                reservedSize: 32,
                getTitlesWidget: (v, m) {
                  final i = v.toInt();
                  if (i < 0 || i >= days.length || v != i.toDouble()) {
                    return const SizedBox();
                  }
                  final label = trendAxisLabel(
                    days[i].date,
                    monthly: monthly,
                    totalDays: days.length,
                  );
                  if (label == null) return const SizedBox();
                  return Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      label,
                      style: Paper.meta.copyWith(fontSize: 12),
                    ),
                  );
                },
              ),
            ),
          ),
          lineTouchData: LineTouchData(
            handleBuiltInTouches: false,
            touchCallback: (event, response) {
              if (event is FlTapUpEvent &&
                  response?.lineBarSpots?.isNotEmpty == true) {
                final x = response!.lineBarSpots!.first.x;
                if (x.isFinite && x >= 0 && x < days.length) {
                  onTap(days[x.toInt()].date);
                }
              }
            },
          ),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: false,
              color: const Color(0xFFEC967E),
              barWidth: 1.3,
              dotData: FlDotData(
                show: true,
                getDotPainter: (s, _, _, _) => FlDotCirclePainter(
                  radius: 4,
                  color: Paper.bg,
                  strokeWidth: 1.2,
                  strokeColor: const Color(0xFFEC967E),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String? trendAxisLabel(
  DateTime date, {
  required bool monthly,
  required int totalDays,
}) {
  if (!monthly) return ['一', '二', '三', '四', '五', '六', '日'][date.weekday - 1];
  if (date.day == totalDays) return '月末';
  return {1, 7, 14, 21, 28}.contains(date.day) ? '${date.day}日' : null;
}
