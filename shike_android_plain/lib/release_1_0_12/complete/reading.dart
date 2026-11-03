import 'first_line_mood.dart';
import 'diary_metadata.dart';
import 'search_calendar.dart';
import 'tap_input_focus.dart';
import 'export_preview.dart';
import 'paper_press.dart';
import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';

import 'cards.dart' show showRewardBatch;

import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../src/store.dart';
import 'optimized_images.dart' show storedImage;
import 'controller.dart';
import '../refined/design.dart';
import '../refined/export.dart';

void openReading(
  BuildContext c,
  CompleteController controller,
  Diary entry, {
  Diary? from,
}) {
  if (!entry.visible) return;
  Navigator.push(
    c,
    PaperDiaryRoute(
      builder: (_) => ReadingPage(
        controller: controller,
        entry: entry,
        returnLabel: from == null
            ? null
            : referenceReturnLabel(from.created, entry.created),
      ),
    ),
  );
}

void showPhotoViewer(BuildContext c, List<String> paths, int initial) =>
    Navigator.push(
      c,
      MaterialPageRoute(
        builder: (_) => PhotoViewer(paths: List.of(paths), initial: initial),
      ),
    );

String referenceReturnLabel(DateTime source, DateTime target) =>
    '回到 ${source.year == target.year ? '' : '${source.year}年'}${source.month}月${source.day}日';

class ReadingPage extends StatefulWidget {
  final CompleteController controller;
  final Diary entry;
  final String? returnLabel;
  final bool selectReference;
  const ReadingPage({
    super.key,
    required this.controller,
    required this.entry,
    this.returnLabel,
    this.selectReference = false,
  });
  @override
  State<ReadingPage> createState() => _ReadingPageState();
}

class _ReadingPageState extends State<ReadingPage> {
  bool exporting = false;
  @override
  void initState() {
    super.initState();
    if (widget.entry.state == 'capsule') {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        try {
          final cards = await widget.controller.opened(widget.entry);
          if (mounted) showRewardBatch(context, widget.controller, cards);
        } catch (_) {
          /* A readable capsule remains readable even if feedback fails. */
        }
      });
    }
  }

  Future<void> export() async {
    if (exporting) return;
    setState(() => exporting = true);
    try {
      await previewDiaryExport(context, widget.entry,
        includeMood: widget.controller.settings['exportMood'] as bool,
        metadata: widget.controller.savedMetadata(widget.entry),
      );
    } catch (_) {
      if (mounted) tell(context, '无法保存图片，请检查相册权限或文件位置。');
    } finally {
      if (mounted) setState(() => exporting = false);
    }
  }

  void menu() => showModalBottomSheet<void>(
    context: context,
    backgroundColor: Paper.bg,
    showDragHandle: true,
    builder: (c) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const LineMark(Mark.download),
            title: Text(exporting ? '预览中' : '导出为图片'),
            enabled: !exporting,
            onTap: () {
              Navigator.pop(c);
              export();
            },
          ),
          ListTile(
            leading: const LineMark(Mark.quote),
            title: const Text('查看引用关系'),
            onTap: () {
              Navigator.pop(c);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ReferencePage(
                    controller: widget.controller,
                    entry: widget.entry,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    ),
  );
  @override
  Widget build(BuildContext c) {
    final e = widget.entry;
    if (!e.visible) return const Scaffold(body: EmptyNote('这封信还没有到可以打开的时候。'));
    return AnimatedScale(scale: exporting ? .985 : 1,
      duration: MediaQuery.disableAnimationsOf(c) ? Duration.zero : const Duration(milliseconds: 220),
      child: AnimatedOpacity(opacity: exporting ? 0 : 1,
      duration: MediaQuery.disableAnimationsOf(c) ? Duration.zero : const Duration(milliseconds: 220),
      child: Scaffold(
      appBar: PaperHeader(
        '',
        leading: widget.returnLabel == null
            ? null
            : TextButton(
                onPressed: () => Navigator.pop(c),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const LineMark(Mark.back, size: 18),
                    const SizedBox(width: 4),
                    Text(
                      widget.returnLabel!,
                      style: Paper.meta.copyWith(fontSize: 13),
                    ),
                  ],
                ),
              ),
        actions: [
          if (widget.selectReference)
            TextButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('引用这篇'),
            )
          else
            IconAction(Mark.more, label: '日记操作', onTap: menu),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 35),
        children: [
          if (e.state == 'capsule') ...[
            Center(
              child: Text(
                '来自 ${DateFormat('yyyy.MM.dd').format(e.created)} 的你',
                style: Paper.meta.copyWith(fontSize: 17),
              ),
            ),
            const SizedBox(height: 38),
          ],
          DiaryMetadataHeader(snapshot: widget.controller.savedMetadata(e), created: e.created, mood: e.mood),
          const SizedBox(height: 32),
          LinkedParagraph(controller: widget.controller, entry: e),
          if (e.photos.isNotEmpty) ...[
            const SizedBox(height: 24),
            LayoutBuilder(
              builder: (c, box) => Wrap(
                spacing: 8,
                runSpacing: 8,
                children: e.photos.indexed
                    .map(
                      (p) => GestureDetector(
                        onTap: () => showPhotoViewer(c, e.photos, p.$1),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(5),
                          child: SizedBox(
                            width: (box.maxWidth - 16) / 3,
                            height: (box.maxWidth - 16) / 3 * 1.2,
                            child: storedImage(p.$2),
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
          ],
          if (e.audio != null) ...[
            const SizedBox(height: 18),
            AudioStrip(file: e.audio!),
          ],

        ],
      ),
    )));
  }
}

class LinkedParagraph extends StatefulWidget {
  final CompleteController controller;
  final Diary entry;
  const LinkedParagraph({
    super.key,
    required this.controller,
    required this.entry,
  });
  @override
  State<LinkedParagraph> createState() => _LinkedParagraphState();
}

class _LinkedParagraphState extends State<LinkedParagraph> {
  final List<TapGestureRecognizer> taps = [];
  String? pressed;
  @override
  void dispose() {
    for (final t in taps) {
      t.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext c) {
    final text = widget.entry.text;
    final links =
        (widget.controller.references[widget.entry.id] ?? [])
            .where(
              (r) =>
                  r.fits(text) &&
                  widget.controller.visible.any((e) => e.id == r.target),
            )
            .toList()
          ..sort((a, b) => a.start.compareTo(b.start));
    final spans = <InlineSpan>[];
    var offset = 0;
    for (final r in links) {
      if (r.start < offset) continue;
      spans.add(TextSpan(text: text.substring(offset, r.start)));
      final index = links.indexOf(r);
      if (taps.length <= index) taps.add(TapGestureRecognizer());
      final tap = taps[index]
        ..onTapDown = (_) {
          setState(() => pressed = '${r.start}');
        }
        ..onTapCancel = () {
          setState(() => pressed = null);
        }
        ..onTapUp = (_) {
          setState(() => pressed = null);
        }
        ..onTap = () {
          openReading(
            c,
            widget.controller,
            widget.controller.visible.firstWhere((e) => e.id == r.target),
            from: widget.entry,
          );
        };
      spans.add(
        TextSpan(
          text: r.text,
          style: TextStyle(
            decoration: TextDecoration.underline,
            decorationStyle: TextDecorationStyle.dashed,
            decorationThickness: .6,
            decorationColor: pressed == '${r.start}'
                ? Paper.mood[4]
                : Paper.faint,
          ),
          recognizer: tap,
        ),
      );
      offset = r.end;
    }
    spans.add(TextSpan(text: text.substring(offset)));
    return SelectableText.rich(
      TextSpan(
        style: Paper.body.copyWith(fontSize: 18, height: 1.75),
        children: spans,
      ),
    );
  }
}

class AudioStrip extends StatefulWidget {
  final String file;
  const AudioStrip({super.key, required this.file});
  @override
  State<AudioStrip> createState() => _AudioStripState();
}

class _AudioStripState extends State<AudioStrip> {
  final player = AudioPlayer();
  StreamSubscription<PlayerState>? subscription;
  bool playing = false, loading = false;
  @override
  void initState() {
    super.initState();
    subscription = player.onPlayerStateChanged.listen((value) {
      if (mounted) setState(() => playing = value == PlayerState.playing);
    });
  }

  @override
  void dispose() {
    subscription?.cancel();
    player.dispose();
    super.dispose();
  }

  Future<void> toggle() async {
    if (loading) return;
    setState(() => loading = true);
    try {
      if (playing) {
        await player.pause();
      } else {
        await player.play(DeviceFileSource(widget.file));
      }
    } catch (_) {
      if (mounted) tell(context, '暂时无法播放这段语音。');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext c) => Align(
    alignment: Alignment.centerLeft,
    child: TextButton.icon(
      onPressed: loading ? null : toggle,
      icon: LineMark(playing ? Mark.stop : Mark.play, size: 18),
      label: Text(playing ? '暂停语音' : '播放语音', style: Paper.meta),
    ),
  );
}

class PhotoViewer extends StatelessWidget {
  final List<String> paths;
  final int initial;
  const PhotoViewer({super.key, required this.paths, required this.initial});
  @override
  Widget build(BuildContext c) => Scaffold(
    appBar: const PaperHeader(''),
    body: SafeArea(
      top: false,
      child: PageView.builder(
        controller: PageController(initialPage: initial),
        itemCount: paths.length,
        itemBuilder: (c, i) => InteractiveViewer(
          minScale: 1,
          maxScale: 5,
          child: Center(child: storedImage(paths[i], fit: BoxFit.contain)),
        ),
      ),
    ),
  );
}

class ReferencePage extends StatelessWidget {
  final CompleteController controller;
  final Diary entry;
  const ReferencePage({
    super.key,
    required this.controller,
    required this.entry,
  });
  @override
  Widget build(BuildContext c) {
    final out = (controller.references[entry.id] ?? [])
        .map((r) => r.target)
        .toSet();
    final incoming = controller.references.entries
        .where((e) => e.value.any((r) => r.target == entry.id))
        .map((e) => e.key)
        .toSet();
    return Scaffold(
      appBar: const PaperHeader('引用关系'),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          for (final group in [('这篇引用了', out), ('引用了这篇', incoming)]) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 18),
              child: Text(group.$1, style: Paper.title(20)),
            ),
            if (!controller.visible.any((e) => group.$2.contains(e.id)))
              const Padding(
                padding: EdgeInsets.only(bottom: 18),
                child: Text('暂无引用', style: Paper.meta),
              ),
            ...controller.visible
                .where((e) => group.$2.contains(e.id))
                .map(
                  (e) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      e.text,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      DateFormat('yyyy.MM.dd').format(e.created),
                      style: Paper.meta,
                    ),
                    trailing: const LineMark(Mark.next, size: 17),
                    onTap: () => openReading(c, controller, e),
                  ),
                ),
            const Divider(),
          ],
        ],
      ),
    );
  }
}

class SearchPage extends StatefulWidget {
  final CompleteController controller;
  const SearchPage({super.key, required this.controller});
  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> with TapInputFocusPolicy<SearchPage> {
  final input = TextEditingController();
  DateTimeRange? range;
  bool calendarShowing = false;
  @override void dispose() { input.dispose(); super.dispose(); }

  Future<void> chooseRange() async {
    if (calendarShowing) return;
    calendarShowing = true;
    releaseInput(suspend: true);
    try {
      final result = await showSearchCalendar(context, initial: range);
      if (mounted && result != null) setState(() => range = result);
    } finally {
      calendarShowing = false;
      if (mounted) releaseInput();
    }
  }

  String get rangeLabel {
    final value = range!;
    final includeYear = value.start.year != value.end.year || value.start.year != DateTime.now().year;
    final format = DateFormat(includeYear ? 'yyyy年MM月dd日' : 'MM月dd日');
    if (onDay(value.start, value.end)) return format.format(value.start);
    return '${format.format(value.start)} - ${format.format(value.end)}';
  }

  Widget dateChip(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
    const labelStyle = TextStyle(fontSize: 13, height: 1.5, color: Paper.ink);
    final label = TextPainter(text: TextSpan(text: rangeLabel, style: labelStyle),
      textDirection: Directionality.of(context), textScaler: MediaQuery.textScalerOf(context),
      maxLines: 2, ellipsis: '…')..layout(maxWidth: (box.maxWidth - 56).clamp(1.0, double.infinity));
    final height = label.height + 12 < 44 ? 44.0 : label.height + 12;
    label.dispose();
    return Align(alignment: Alignment.centerLeft, child: SizedBox(height: height,
      child: Stack(children: [
        Positioned.fill(top: 6, bottom: 6, child: DecoratedBox(decoration: BoxDecoration(
          color: const Color(0xFFF0EEEC), borderRadius: BorderRadius.circular(18)))),
        Padding(padding: const EdgeInsets.only(left: 12), child: Row(mainAxisSize: MainAxisSize.min, children: [
          Flexible(child: Text(rangeLabel, maxLines: 2, overflow: TextOverflow.ellipsis,
            style: labelStyle)),
          SizedBox(width: 44, height: height, child: IconButton(tooltip: '清除日期筛选',
            padding: EdgeInsets.zero, onPressed: () => setState(() => range = null),
            icon: const LineMark(Mark.close, size: 13, color: Paper.ink))),
        ])),
      ]),
    ));
    });
  }

  @override Widget build(BuildContext c) {
    final q = input.text.trim();
    final matches = widget.controller.visible.where((e) {
      final d = localDay(e.created);
      return (q.isEmpty || e.text.contains(q)) && (range == null ||
        (!d.isBefore(range!.start) && !d.isAfter(range!.end)));
    }).toList()..sort((a, b) => b.created.compareTo(a.created));
    final active = q.isNotEmpty || range != null;
    return Scaffold(
      appBar: const PaperHeader(''),
      body: Column(children: [
        Padding(padding: const EdgeInsets.fromLTRB(24, 14, 24, 10), child: TextField(
          controller: input, focusNode: inputFocus, autofocus: false,
          canRequestFocus: allowInputFocus, onTapOutside: (_) => releaseInput(),
          onChanged: (_) => setState(() {}), style: Paper.body,
          decoration: InputDecoration(hintText: '搜索日记', hintStyle: Paper.meta,
            prefixIcon: const Padding(padding: EdgeInsets.all(14), child: LineMark(Mark.search, size: 20)),
            suffixIcon: Row(mainAxisSize: MainAxisSize.min, children: [
              if (input.text.isNotEmpty) IconAction(Mark.close, label: '清空搜索', size: 16,
                onTap: () { input.clear(); setState(() {}); }),
              Semantics(button: true, label: '筛选日期', child: SoftPress(onTap: chooseRange,
                child: const SizedBox(width: 48, height: 48, child: Center(child: CalendarLineIcon())))),
            ]),
            filled: true, fillColor: const Color(0xFFF3F2F0),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(28), borderSide: BorderSide.none),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(28), borderSide: BorderSide.none),
          ),
        )),
        if (range != null) Padding(padding: const EdgeInsets.fromLTRB(24, 0, 24, 4), child: dateChip(c)),
        Expanded(child: !active ? const SizedBox.expand()
          : matches.isEmpty ? const EmptyNote('没有找到这段记录。')
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 24), itemCount: matches.length,
              separatorBuilder: (_, _) => const Divider(),
              itemBuilder: (context, i) {
                final entry = matches[i];
                return PaperPress(onTap: () => openReading(context, widget.controller, entry),
                  child: Padding(padding: const EdgeInsets.symmetric(vertical: 20),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(DateFormat('MM月dd日').format(entry.created), style: Paper.meta),
                      const SizedBox(height: 10),
                      FirstLineMoodSummary(mood: entry.mood, text: TextSpan(children: highlight(entry.text, q))),
                    ])),
                );
              },
            )),
      ]),
    );
  }

  List<InlineSpan> highlight(String text, String query) {
    if (query.isEmpty) return [TextSpan(text: text)];
    final result = <InlineSpan>[];
    var offset = 0;
    while (true) {
      final i = text.indexOf(query, offset);
      if (i < 0) break;
      result.add(TextSpan(text: text.substring(offset, i)));
      result.add(
        TextSpan(
          text: query,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            decoration: TextDecoration.underline,
          ),
        ),
      );
      offset = i + query.length;
    }
    result.add(TextSpan(text: text.substring(offset)));
    return result;
  }
}
