import 'dart:async';

import 'package:flutter/services.dart';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../src/store.dart';
import '../src/media.dart' show copyImage, storedImage;
import 'model.dart';
import 'reference_picker.dart';
import 'controller.dart';
import '../refined/design.dart';
import 'cards.dart';
import 'reading.dart';

class RefinedEditor extends StatefulWidget {
  final CompleteController controller;
  final Diary? draft;
  final bool capsule;
  const RefinedEditor({
    super.key,
    required this.controller,
    this.draft,
    this.capsule = false,
  });
  @override
  State<RefinedEditor> createState() => _RefinedEditorState();
}

class _RefinedEditorState extends State<RefinedEditor>
    with WidgetsBindingObserver {
  late final String id;
  late final DateTime created;
  late final LinkedTextController text;
  final recorder = AudioRecorder();
  final focusNode = FocusNode();
  final scroll = ScrollController();
  String previousText = '';
  TextSelection previousSelection = const TextSelection.collapsed(offset: 0);
  final List<String> photos = [];
  final List<JournalReference> links = [];
  int? mood;
  String? audio;
  bool choosing = false,
      focused = false,
      busy = false,
      committed = false,
      leaving = false,
      allowPop = false,
      recording = false,
      importing = false;
  Timer? autosave, recordLimit;
  Future<void> queue = Future.value();
  Future<void>? stopping;
  DateTime? unlock;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final d = widget.draft;
    id = d?.id ?? widget.controller.store.newId();
    created = d?.created ?? DateTime.now();
    mood = d?.mood;
    audio = d?.audio;
    photos.addAll(d?.photos ?? []);
    links.addAll(widget.controller.references[id] ?? []);
    text = LinkedTextController(links, text: d?.text ?? '');
    previousText = text.text;
    unlock = d?.unlockAt;
    final position = widget.controller.repository.snapshot.drafts[id];
    if (position != null) {
      final base = (position['base'] as int? ?? text.text.length).clamp(
        0,
        text.text.length,
      );
      final extent = (position['extent'] as int? ?? base).clamp(
        0,
        text.text.length,
      );
      text.selection = TextSelection(baseOffset: base, extentOffset: extent);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && scroll.hasClients) {
          scroll.jumpTo(
            (position['scroll'] as num? ?? 0).toDouble().clamp(
              0,
              scroll.position.maxScrollExtent,
            ),
          );
        }
      });
    }
    scroll.addListener(changed);
    previousSelection = text.selection;
    text.addListener(changed);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      unawaited(flush().catchError((_) {}));
    }
  }

  void changed() {
    if (!mounted || committed) return;
    if (previousText != text.text) {
      final old = [
        for (final r in links)
          SentenceLink(
            id: r is StableJournalReference
                ? r.id
                : widget.controller.store.newId(),
            source: id,
            target: r.target,
            quote: r.text,
            start: r.start,
            end: r.end,
          ),
      ];
      final next = LinkEditing.rebase(
        previousText,
        text.text,
        old,
        selectionStart: previousSelection.start,
        selectionEnd: previousSelection.end,
      );
      links
        ..clear()
        ..addAll(
          next.map(
            (r) => StableJournalReference(
              id: r.id,
              target: r.target,
              text: r.quote,
              start: r.start,
              end: r.end,
            ),
          ),
        );
      previousText = text.text;
    }
    previousSelection = text.selection;
    setState(() {});
    autosave?.cancel();
    autosave = Timer(
      const Duration(milliseconds: 600),
      () => unawaited(saveDraft().catchError((_) {})),
    );
  }

  Diary candidate(String state) => Diary(
    id: id,
    text: text.text,
    mood: mood,
    created: created,
    updated: DateTime.now(),
    state: state,
    unlockAt: unlock,
    photos: List.of(photos),
    audio: audio,
    capsuleDraft: widget.capsule,
  );
  Future<void> saveDraft() {
    if (committed ||
        (text.text.trim().isEmpty &&
            mood == null &&
            photos.isEmpty &&
            audio == null &&
            widget.draft == null)) {
      return queue;
    }
    final value = candidate('draft');
    final refs = links.toList();
    queue = queue.catchError((_) {}).then((_) async {
      await widget.controller.saveEditing(value, refs, {
        'base': text.selection.baseOffset,
        'extent': text.selection.extentOffset,
        'scroll': scroll.hasClients ? scroll.offset : 0,
      });
    });
    return queue;
  }

  Future<void> flush() async {
    autosave?.cancel();
    await stopRecording();
    await saveDraft();
  }

  Future<void> exit() async {
    if (leaving || busy) return;
    leaving = true;
    try {
      await flush();
      if (mounted) {
        setState(() => allowPop = true);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) Navigator.pop(context);
        });
      }
    } catch (_) {
      leaving = false;
      if (mounted) tell(context, '草稿暂时没能保存，请稍后重试。');
    }
  }

  Future<void> addImages() async {
    if (importing || busy) return;
    setState(() => importing = true);
    try {
      final files = await ImagePicker().pickMultiImage();
      for (final file in files) {
        photos.add(await copyImage(file));
      }
      await saveDraft();
    } catch (_) {
      if (mounted) tell(context, '无法导入照片，请检查相册权限。');
    } finally {
      if (mounted) setState(() => importing = false);
    }
  }

  Future<void> record() async {
    if (recording) {
      await stopRecording();
      return;
    }
    if (busy) return;
    if (kIsWeb) {
      tell(context, '录音需要在 iPhone 上验证，网页保留文字和照片功能。');
      return;
    }
    try {
      if (!await recorder.hasPermission()) {
        if (mounted) tell(context, '请在系统设置中允许麦克风权限。');
        return;
      }
      final folder = await getApplicationDocumentsDirectory();
      await recorder.start(
        const RecordConfig(encoder: AudioEncoder.aacLc),
        path: path.join(
          folder.path,
          'voice-$id-${DateTime.now().microsecondsSinceEpoch}.m4a',
        ),
      );
      recording = true;
      if (mounted) setState(() {});
      recordLimit = Timer(
        const Duration(seconds: 10),
        () => unawaited(stopRecording()),
      );
    } catch (_) {
      if (mounted) tell(context, '录音暂时无法开始，请稍后重试。');
    }
  }

  Future<void> stopRecording() {
    if (stopping != null) return stopping!;
    if (!recording) return Future.value();
    recording = false;
    recordLimit?.cancel();
    stopping = () async {
      try {
        final file = await recorder.stop();
        if (file != null) audio = file;
        await saveDraft();
      } finally {
        stopping = null;
        if (mounted) setState(() {});
      }
    }();
    return stopping!;
  }

  Future<DateTime?> chooseTime() async {
    final now = DateTime.now();
    final minimum = now.add(const Duration(hours: 1));
    final maximum = DateTime(
      now.year + 10,
      now.month,
      now.day,
      now.hour,
      now.minute,
    );
    var chosen =
        unlock ??
        DateTime(now.year, now.month, now.day + 1, now.hour, now.minute);
    if (chosen.isBefore(minimum)) {
      chosen = minimum.add(const Duration(minutes: 1));
    }
    if (chosen.isAfter(maximum)) {
      chosen = maximum;
    }
    return showModalBottomSheet<DateTime>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Paper.bg,
      builder: (c) => SafeArea(
        child: SizedBox(
          height: 330,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text('选择解锁时间', style: TextStyle(fontSize: 18)),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(c, chosen),
                      child: const Text('选好了'),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: CupertinoDatePicker(
                  mode: CupertinoDatePickerMode.dateAndTime,
                  initialDateTime: chosen,
                  minimumDate: minimum,
                  maximumDate: maximum,
                  use24hFormat: true,
                  onDateTimeChanged: (v) => chosen = v,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> finish() async {
    if (busy || importing || mood == null || text.text.trim().isEmpty) return;
    setState(() => busy = true);
    try {
      await flush();
      if (!mounted) return;
      if (widget.capsule) {
        final chosen = await chooseTime();
        if (chosen == null) return;
        unlock = chosen;
        await saveDraft();
      }
      if (!mounted) return;
      final confirmed = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => RefinedPreview(
            controller: widget.controller,
            entry: candidate(widget.capsule ? 'capsule' : 'done'),
          ),
        ),
      );
      if (confirmed != true) return;
      if (widget.capsule &&
          unlock!.difference(DateTime.now()) < const Duration(hours: 1)) {
        if (mounted) tell(context, '请选择至少 1 小时后的解锁时间。');
        return;
      }
      await queue;
      final value = candidate(widget.capsule ? 'capsule' : 'done');
      await widget.controller.store.save(value);
      committed = true;
      // The journal is already locked: optional feedback must never cause a second commit.
      if (widget.capsule) {
        unawaited(
          widget.controller.reconcileNotifications(requestPermission: true),
        );
      }
      if (mounted) {
        unawaited(completionFeedback(context, widget.controller, value));
      }
      if (mounted) {
        setState(() => allowPop = true);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) Navigator.pop(context);
        });
      }
    } catch (_) {
      if (mounted) tell(context, '暂时没能完成，内容仍保留在草稿中。');
    } finally {
      if (mounted && !committed) setState(() => busy = false);
    }
  }

  Future<void> addReference() async {
    final selection = text.selection;
    if (selection.isCollapsed || selection.start < 0) return;
    final selected = text.text.substring(selection.start, selection.end);
    final oldScroll = scroll.hasClients ? scroll.offset : 0.0;
    focusNode.unfocus();
    final target = await chooseReference(context, widget.controller, id);
    if (mounted) {
      focusNode.requestFocus();
      text.selection = selection;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && scroll.hasClients) {
          scroll.jumpTo(oldScroll.clamp(0, scroll.position.maxScrollExtent));
        }
      });
    }
    if (target != null && mounted) {
      links.removeWhere(
        (r) => r.start < selection.end && r.end > selection.start,
      );
      links.add(
        StableJournalReference(
          id: widget.controller.store.newId(),
          target: target.id,
          text: selected,
          start: selection.start,
          end: selection.end,
        ),
      );
      text.notifyLinksChanged();
      await saveDraft();
      setState(() {});
    }
  }

  Widget selectionToolbar(EditableTextState state) {
    final selection = text.selection;
    final touched = links.any(
      (r) => r.start < selection.end && r.end > selection.start,
    );
    Widget action(String label, VoidCallback run) => TextButton(
      style: TextButton.styleFrom(
        foregroundColor: Colors.white,
        minimumSize: const Size(52, 44),
        padding: const EdgeInsets.symmetric(horizontal: 12),
      ),
      onPressed: () {
        state.hideToolbar();
        run();
      },
      child: Text(label, style: const TextStyle(fontSize: 14)),
    );
    if (selection.isCollapsed) return const SizedBox.shrink();
    return TextSelectionToolbar(
      anchorAbove: state.contextMenuAnchors.primaryAnchor,
      anchorBelow:
          state.contextMenuAnchors.secondaryAnchor ??
          state.contextMenuAnchors.primaryAnchor,
      toolbarBuilder: (c, child) => Material(
        color: Paper.ink,
        borderRadius: BorderRadius.circular(10),
        child: child,
      ),
      children: [
        action(
          '复制',
          () => Clipboard.setData(
            ClipboardData(text: selection.textInside(text.text)),
          ),
        ),
        action('删除', () {
          text.value = TextEditingValue(
            text: text.text.replaceRange(selection.start, selection.end, ''),
            selection: TextSelection.collapsed(offset: selection.start),
          );
        }),
        action('引用', () => addReference()),
        if (touched)
          action('删除引用', () {
            links.removeWhere(
              (r) => r.start < selection.end && r.end > selection.start,
            );
            text.notifyLinksChanged();
            unawaited(saveDraft());
          }),
      ],
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    autosave?.cancel();
    recordLimit?.cancel();
    scroll.removeListener(changed);
    scroll.dispose();
    text.removeListener(changed);
    text.dispose();
    focusNode.dispose();
    recorder.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext c) {
    final keyboard = MediaQuery.viewInsetsOf(c).bottom > 0;
    return PopScope(
      canPop: allowPop,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) exit();
      },
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        appBar: focused
            ? null
            : PaperHeader(
                widget.capsule ? '时间胶囊' : '写日记',
                leading: IconAction(
                  Mark.back,
                  label: '保存草稿并返回',
                  onTap: busy ? null : exit,
                ),
                actions: [
                  IconAction(
                    Mark.focus,
                    label: '专注模式',
                    onTap: busy ? null : () => setState(() => focused = true),
                  ),
                  IconAction(
                    Mark.check,
                    label: '预览并完成',
                    onTap:
                        busy ||
                            mood == null ||
                            text.text.trim().isEmpty ||
                            importing
                        ? null
                        : finish,
                    size: 24,
                  ),
                ],
              ),
        body: SafeArea(
          top: focused,
          bottom: true,
          child: Column(
            children: [
              if (focused)
                Align(
                  alignment: Alignment.centerRight,
                  child: IconAction(
                    Mark.unfocus,
                    label: '退出专注模式',
                    onTap: () => setState(() => focused = false),
                  ),
                ),
              if (!focused)
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 2, 24, 0),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              widget.controller.snapshots[id] ??
                                  widget.controller.metadata(created),
                              style: Paper.meta,
                            ),
                          ),
                          Semantics(
                            button: true,
                            label: '选择心情',
                            value: mood == null ? '未选择' : '$mood 分',
                            expanded: choosing,
                            child: GestureDetector(
                              onTap: busy
                                  ? null
                                  : () => setState(() => choosing = !choosing),
                              behavior: HitTestBehavior.opaque,
                              child: SizedBox.square(
                                dimension: 44,
                                child: Center(
                                  child: Container(
                                    width: 20,
                                    height: 20,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: mood == null
                                          ? const Color(0xFFD4D9DF)
                                          : Paper.mood[mood!],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (choosing)
                        Align(
                          alignment: Alignment.centerRight,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 278),
                            child: MoodChoices(
                              compact: true,
                              value: mood,
                              onChanged: (v) {
                                setState(() {
                                  mood = v;
                                  choosing = false;
                                });
                                unawaited(saveDraft().catchError((_) {}));
                              },
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              Expanded(
                child: Stack(
                  children: [
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        24,
                        choosing ? 12 : 22,
                        24,
                        40,
                      ),
                      child: TextField(
                        key: const ValueKey('diary-body'),
                        controller: text,
                        focusNode: focusNode,
                        readOnly: busy,
                        expands: true,
                        maxLines: null,
                        minLines: null,
                        textAlignVertical: TextAlignVertical.top,
                        style: Paper.body.copyWith(fontSize: 18, height: 1.75),
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.zero,
                        ),
                        scrollController: scroll,
                        contextMenuBuilder: (c, state) =>
                            selectionToolbar(state),
                      ),
                    ),
                    if (!focused)
                      Positioned(
                        right: 24,
                        bottom: 10,
                        child: Text(
                          '${text.text.characters.length} 字',
                          style: const TextStyle(
                            color: Color(0x6664728A),
                            fontSize: 13,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (!focused && photos.isNotEmpty)
                SizedBox(
                  height: 88,
                  child: ReorderableListView.builder(
                    scrollDirection: Axis.horizontal,
                    buildDefaultDragHandles: false,
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    itemCount: photos.length,
                    onReorderItem: (from, to) {
                      setState(() {
                        photos.insert(to, photos.removeAt(from));
                      });
                      unawaited(saveDraft().catchError((_) {}));
                    },
                    itemBuilder: (c, i) => ReorderableDelayedDragStartListener(
                      key: ValueKey(photos[i]),
                      index: i,
                      child: Stack(
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 8,
                            ),
                            child: GestureDetector(
                              onTap: () => showPhotoViewer(c, photos, i),
                              child: SizedBox(
                                width: 70,
                                height: 70,
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(4),
                                  child: storedImage(photos[i]),
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            right: 0,
                            top: 0,
                            child: IconAction(
                              Mark.close,
                              size: 14,
                              label: '移除第${i + 1}张图片',
                              onTap: busy
                                  ? null
                                  : () {
                                      setState(() => photos.removeAt(i));
                                      unawaited(saveDraft().catchError((_) {}));
                                    },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              if (!focused && audio != null)
                Padding(
                  padding: const EdgeInsets.only(left: 20),
                  child: Row(
                    children: [
                      AudioStrip(file: audio!),
                      IconAction(
                        Mark.close,
                        label: '移除语音',
                        size: 16,
                        onTap: busy
                            ? null
                            : () {
                                setState(() => audio = null);
                                unawaited(saveDraft().catchError((_) {}));
                              },
                      ),
                    ],
                  ),
                ),
              if (!focused)
                DecoratedBox(
                  decoration: const BoxDecoration(
                    border: Border(
                      top: BorderSide(color: Paper.line, width: .7),
                    ),
                  ),
                  child: SizedBox(
                    height: 58,
                    child: Row(
                      mainAxisAlignment: keyboard
                          ? MainAxisAlignment.start
                          : MainAxisAlignment.spaceEvenly,
                      children: [
                        if (keyboard) const SizedBox(width: 15),
                        IconAction(
                          Mark.image,
                          label: '添加图片',
                          size: 23,
                          onTap: busy || importing ? null : addImages,
                        ),
                        if (keyboard) const SizedBox(width: 12),
                        IconAction(
                          recording ? Mark.stop : Mark.mic,
                          label: recording ? '停止录音' : '录制语音',
                          size: 23,
                          onTap: busy ? null : record,
                        ),
                        if (recording)
                          const Expanded(
                            child: Text(
                              '录音中 · 最长 10 秒',
                              textAlign: TextAlign.center,
                              style: Paper.meta,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class LinkedTextController extends TextEditingController {
  final List<JournalReference> links;
  LinkedTextController(this.links, {super.text});
  void notifyLinksChanged() => notifyListeners();
  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final valid = links.where((r) => r.fits(text)).toList()
      ..sort((a, b) => a.start.compareTo(b.start));
    final spans = <InlineSpan>[];
    var offset = 0;
    for (final r in valid) {
      if (r.start < offset) continue;
      spans.add(TextSpan(text: text.substring(offset, r.start)));
      spans.add(
        TextSpan(
          text: text.substring(r.start, r.end),
          style: const TextStyle(
            decoration: TextDecoration.underline,
            decorationStyle: TextDecorationStyle.dashed,
            decorationColor: Paper.faint,
            decorationThickness: .6,
          ),
        ),
      );
      offset = r.end;
    }
    spans.add(TextSpan(text: text.substring(offset)));
    return TextSpan(style: style, children: spans);
  }
}

class RefinedPreview extends StatefulWidget {
  final CompleteController controller;
  final Diary entry;
  const RefinedPreview({
    super.key,
    required this.controller,
    required this.entry,
  });
  @override
  State<RefinedPreview> createState() => _RefinedPreviewState();
}

class _RefinedPreviewState extends State<RefinedPreview> {
  bool confirming = false;
  Future<void> finish() async {
    if (confirming) return;
    setState(() => confirming = true);
    final capsule = widget.entry.state == 'capsule';
    final d = widget.entry.unlockAt;
    final yes = await confirm(
      context,
      capsule
          ? '这是给 ${d!.year}.${d.month}.${d.day} 后的你的信，检查好后就寄出去喽'
          : '完成后不可删除哦，还要检查一下吗？',
      yes: capsule ? '寄出去' : '完成',
      no: capsule ? '我还有想说的话' : '再想想',
    );
    if (!mounted) return;
    if (yes) {
      Navigator.pop(context, true);
    } else {
      setState(() => confirming = false);
    }
  }

  @override
  Widget build(BuildContext c) => Scaffold(
    appBar: PaperHeader(
      '预览',
      actions: [
        TextButton(
          onPressed: confirming ? null : () => Navigator.pop(c, false),
          child: const Text('修改'),
        ),
      ],
    ),
    body: SafeArea(
      top: false,
      child: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.controller.metadata(widget.entry.created),
                        style: Paper.meta,
                      ),
                    ),
                    Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Paper.mood[widget.entry.mood!],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 30),
                LinkedParagraph(
                  controller: widget.controller,
                  entry: widget.entry,
                ),
                const SizedBox(height: 24),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: widget.entry.photos.indexed
                      .map(
                        (x) => GestureDetector(
                          onTap: () =>
                              showPhotoViewer(c, widget.entry.photos, x.$1),
                          child: SizedBox(
                            width: 98,
                            height: 110,
                            child: storedImage(x.$2),
                          ),
                        ),
                      )
                      .toList(),
                ),
                if (widget.entry.audio != null)
                  AudioStrip(file: widget.entry.audio!),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
            child: SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: confirming ? null : finish,
                child: Text(widget.entry.state == 'capsule' ? '寄出去' : '完成'),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
