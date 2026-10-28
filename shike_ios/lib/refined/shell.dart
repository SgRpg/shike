import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../src/store.dart';
import 'backup_page.dart';
import 'controller.dart';
import 'design.dart';
import 'editor.dart';
import 'heart.dart';
import 'gallery.dart';
import 'cards.dart';
import 'reading.dart';
import 'keep_feedback.dart';
import 'quick_send.dart';
import 'mood_nudge.dart';

class RefinedApp extends StatelessWidget {
  final RefinedController controller;
  const RefinedApp({super.key, required this.controller});
  @override
  Widget build(BuildContext c) => MaterialApp(
    title: '拾刻',
    debugShowCheckedModeBanner: false,
    theme: Paper.theme().copyWith(platform: TargetPlatform.iOS),
    home: RefinedHome(controller: controller),
    builder: (c, child) => ColoredBox(
      color: Paper.bg,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: child,
        ),
      ),
    ),
  );
}

class RefinedHome extends StatefulWidget {
  final RefinedController controller;
  const RefinedHome({super.key, required this.controller});
  @override
  State<RefinedHome> createState() => _RefinedHomeState();
}

class _RefinedHomeState extends State<RefinedHome> with WidgetsBindingObserver {
  int tab = 0;
  final lightTarget = GlobalKey();
  Timer? refresh;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    refresh = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) setState(() {});
  }

  @override
  void dispose() {
    refresh?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext c) => AnimatedBuilder(
    animation: widget.controller,
    builder: (c, _) => Scaffold(
      body: SafeArea(
        bottom: false,
        child: IndexedStack(
          index: tab,
          children: [
            MomentPage(controller: widget.controller, lightTarget: lightTarget),
            LightPage(controller: widget.controller),
            HeartPage(controller: widget.controller, active: tab == 2),
            CornerPage(controller: widget.controller),
          ],
        ),
      ),
      bottomNavigationBar: PaperNavigation(
        index: tab,
        lightTarget: lightTarget,
        onChanged: (v) => setState(() => tab = v),
      ),
    ),
  );
}

class PaperNavigation extends StatelessWidget {
  final int index;
  final ValueChanged<int> onChanged;
  final GlobalKey? lightTarget;
  const PaperNavigation({
    super.key,
    required this.index,
    required this.onChanged,
    this.lightTarget,
  });
  @override
  Widget build(BuildContext c) => DecoratedBox(
    decoration: const BoxDecoration(
      color: Paper.bg,
      border: Border(top: BorderSide(color: Paper.line, width: .7)),
    ),
    child: SafeArea(
      top: false,
      child: SizedBox(
        height: 74,
        child: Row(
          children: List.generate(4, (i) {
            final names = ['此刻', '拾光', '心迹', '角落'];
            final icons = [Mark.home, Mark.journal, Mark.heart, Mark.person];
            final active = i == index;
            final color = active ? Paper.ink : const Color(0xFF8C9199);
            return Expanded(
              child: Semantics(
                excludeSemantics: true,
                selected: active,
                button: true,
                label: names[i],
                onTap: () => onChanged(i),
                child: InkResponse(
                  key: ValueKey('tab-$i'),
                  onTap: () => onChanged(i),
                  hoverColor: Colors.transparent,
                  highlightColor: Paper.ink.withValues(alpha: .03),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        key: i == 1 ? lightTarget : null,
                        width: 24,
                        height: 24,
                        child: LineMark(
                          icons[i],
                          color: color,
                          filled: active,
                          size: 24,
                        ),
                      ),
                      const SizedBox(height: 7),
                      Text(
                        names[i],
                        style: TextStyle(
                          color: color,
                          fontSize: 12,
                          height: 1.15,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    ),
  );
}

class PageTitle extends StatelessWidget {
  final String title;
  final Widget? action;
  const PageTitle(this.title, {super.key, this.action});
  @override
  Widget build(BuildContext c) => Padding(
    padding: const EdgeInsets.fromLTRB(24, 20, 16, 0),
    child: Row(
      children: [
        Expanded(child: Text(title, style: Paper.title(31))),
        ?action,
      ],
    ),
  );
}

class MomentPage extends StatefulWidget {
  final RefinedController controller;
  final GlobalKey? lightTarget;
  const MomentPage({super.key, required this.controller, this.lightTarget});
  @override
  State<MomentPage> createState() => _MomentPageState();
}

class _MomentPageState extends State<MomentPage> {
  final input = TextEditingController();
  final inputGeometry = GlobalKey();
  final moodNudge = GlobalKey<MoodNudgeState>();
  int? mood;
  bool busy = false;
  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (busy || mood == null || input.text.trim().isEmpty) return;
    setState(() => busy = true);
    final now = DateTime.now();
    final entry = Diary(
      id: widget.controller.store.newId(),
      text: input.text.trim(),
      mood: mood,
      created: now,
      updated: now,
      state: 'done',
    );
    try {
      await widget.controller.store.save(entry);
    } catch (_) {
      if (mounted) {
        setState(() => busy = false);
        tell(context, '暂时没能收好，文字已保留，请再试一次。');
      }
      return;
    }
    try {
      await widget.controller.snapshot(
        entry.id,
        widget.controller.metadata(now),
      );
    } catch (_) {
      /* A saved journal must not be submitted twice. */
    }
    if (!mounted) return;
    input.clear();
    setState(() {
      mood = null;
      busy = false;
    });
    await showKeptFeedback(
      context,
      text: entry.text,
      sourceKey: inputGeometry,
      destinationKey: widget.lightTarget,
    );
    if (mounted) await completionFeedback(context, widget.controller, entry);
  }

  @override
  Widget build(BuildContext c) {
    final controller = widget.controller;
    final drafts = controller.store.drafts;
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
      children: [
        Text('拾刻', style: Paper.title(31)),
        if (controller.settings['greeting'] == true)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(greeting(DateTime.now()), style: Paper.meta),
          ),
        const SizedBox(height: 48),
        KeyedSubtree(
          key: inputGeometry,
          child: TextField(
            key: const ValueKey('quick-text'),
            controller: input,
            maxLines: 2,
            minLines: 1,
            enabled: !busy,
            onChanged: (_) => setState(() {}),
            style: Paper.body,
            decoration: quickEntryDecoration(
              hasText: input.text.trim().isNotEmpty,
              onMissingMood: () => moodNudge.currentState?.nudge(),
              busy: busy,
              onSend: !busy && mood != null && input.text.trim().isNotEmpty
                  ? submit
                  : null,
            ),
          ),
        ),
        const SizedBox(height: 22),
        IgnorePointer(
          ignoring: busy,
          child: MoodNudge(
            key: moodNudge,
            child: MoodChoices(
              value: mood,
              onChanged: (v) => setState(() => mood = v),
            ),
          ),
        ),
        const SizedBox(height: 60),
        EntryAction(
          mark: Mark.pen,
          title: '写日记',
          subtitle: drafts.isEmpty ? null : '${drafts.length} 篇未完成',
          onTap: () => Navigator.push(
            c,
            MaterialPageRoute(
              builder: (_) => drafts.isEmpty
                  ? RefinedEditor(controller: controller)
                  : DraftList(controller: controller),
            ),
          ),
        ),
        const Divider(),
        EntryAction(
          mark: Mark.envelope,
          title: '时间胶囊',
          subtitle: '给未来写封信',
          onTap: () => Navigator.push(
            c,
            MaterialPageRoute(
              builder: (_) =>
                  RefinedEditor(controller: controller, capsule: true),
            ),
          ),
        ),
      ],
    );
  }
}

String greeting(DateTime now) => now.hour >= 5 && now.hour < 12
    ? '早呀，今天想拾起什么？'
    : now.hour < 18 && now.hour >= 12
    ? '这一刻，有什么想留下的？'
    : now.hour >= 18 && now.hour < 23
    ? '晚上好，拾一句再睡吧。'
    : '很晚了，拾完就休息吧。';

class EntryAction extends StatelessWidget {
  final Mark mark;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  const EntryAction({
    super.key,
    required this.mark,
    required this.title,
    this.subtitle,
    required this.onTap,
  });
  @override
  Widget build(BuildContext c) => InkWell(
    onTap: onTap,
    hoverColor: Colors.transparent,
    child: ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 106),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 22),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: LineMark(mark, size: 33),
            ),
            const SizedBox(width: 24),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 21,
                      height: 1.35,
                      color: Paper.ink,
                    ),
                  ),
                  if (subtitle != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 7),
                      child: Text(
                        subtitle!,
                        style: Paper.meta.copyWith(fontSize: 13),
                      ),
                    ),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.only(top: 5),
              child: LineMark(Mark.next, size: 17),
            ),
          ],
        ),
      ),
    ),
  );
}

class LightPage extends StatelessWidget {
  final RefinedController controller;
  const LightPage({super.key, required this.controller});
  @override
  Widget build(BuildContext c) {
    final entries = controller.timeline;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PageTitle(
          '拾光',
          action: IconAction(
            Mark.search,
            label: '搜索日记',
            onTap: () => Navigator.push(
              c,
              MaterialPageRoute(
                builder: (_) => SearchPage(controller: controller),
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),
        Expanded(
          child: entries.isEmpty
              ? const EmptyNote('还没有拾起什么。今天想留一句吗？')
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                  itemCount: entries.length,
                  separatorBuilder: (_, _) => const Padding(
                    padding: EdgeInsets.symmetric(vertical: 25),
                    child: Divider(),
                  ),
                  itemBuilder: (c, i) =>
                      TimelineEntry(entry: entries[i], controller: controller),
                ),
        ),
      ],
    );
  }
}

class TimelineEntry extends StatelessWidget {
  final Diary entry;
  final RefinedController controller;
  const TimelineEntry({
    super.key,
    required this.entry,
    required this.controller,
  });
  @override
  Widget build(BuildContext c) {
    final sealed = entry.lockedCapsule;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(DateFormat('M月d日').format(entry.created), style: Paper.meta),
            if (!sealed && entry.mood != null) ...[
              const SizedBox(width: 16),
              Semantics(
                label: '心情 ${entry.mood} 分',
                child: Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    color: Paper.mood[entry.mood!],
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 14),
        if (sealed)
          Semantics(
            label: '时间胶囊，尚未到期',
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 23),
              decoration: BoxDecoration(
                color: Paper.soft,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const LineMark(Mark.envelope, size: 34),
                  const SizedBox(width: 22),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '时间胶囊',
                          style: TextStyle(fontSize: 19, height: 1.4),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          countdown(entry.unlockAt!),
                          style: const TextStyle(
                            color: Color(0xFFABA49B),
                            fontSize: 13,
                            height: 1.45,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          InkWell(
            onTap: () => openReading(c, controller, entry),
            hoverColor: Colors.transparent,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      entry.text,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Paper.body,
                    ),
                  ),
                  const SizedBox(width: 16),
                  const LineMark(Mark.next, size: 17),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

String countdown(DateTime until) {
  final d = until.difference(DateTime.now());
  if (d.inDays >= 2) return '${d.inDays} 天后再来看看呀';
  if (d.inHours >= 24) return '明天再来看呀';
  if (d.inHours >= 1) return '${d.inHours} 小时后再来看看呀';
  return '快要可以打开喽';
}

class DraftList extends StatelessWidget {
  final RefinedController controller;
  const DraftList({super.key, required this.controller});
  @override
  Widget build(BuildContext c) => Scaffold(
    appBar: PaperHeader(
      '未完成',
      actions: [
        IconAction(
          Mark.plus,
          label: '新写一篇',
          onTap: () => Navigator.push(
            c,
            MaterialPageRoute(
              builder: (_) => RefinedEditor(controller: controller),
            ),
          ),
        ),
      ],
    ),
    body: AnimatedBuilder(
      animation: controller,
      builder: (c, _) {
        final drafts = controller.store.drafts;
        return drafts.isEmpty
            ? const EmptyNote('这里还没有未完成的日记。')
            : ListView.separated(
                padding: const EdgeInsets.all(24),
                itemCount: drafts.length,
                separatorBuilder: (_, _) => const Divider(),
                itemBuilder: (c, i) {
                  final d = drafts[i];
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      d.text.isEmpty ? '空白日记' : d.text,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      '${d.capsuleDraft ? '时间胶囊 · ' : ''}${DateFormat('yyyy.MM.dd').format(d.updated)}',
                      style: Paper.meta,
                    ),
                    onTap: () => Navigator.push(
                      c,
                      MaterialPageRoute(
                        builder: (_) => RefinedEditor(
                          controller: controller,
                          draft: d,
                          capsule: d.capsuleDraft,
                        ),
                      ),
                    ),
                    trailing: IconAction(
                      Mark.trash,
                      label: '丢弃草稿',
                      onTap: () async {
                        if (await confirm(c, '丢弃这篇草稿？', yes: '丢弃', no: '取消')) {
                          await controller.store.deleteDraft(d.id);
                        }
                      },
                    ),
                  );
                },
              );
      },
    ),
  );
}

class CornerPage extends StatelessWidget {
  final RefinedController controller;
  const CornerPage({super.key, required this.controller});
  @override
  Widget build(BuildContext c) => ListView(
    padding: const EdgeInsets.fromLTRB(24, 20, 24, 30),
    children: [
      Text('角落', style: Paper.title(31)),
      const SizedBox(height: 38),
      for (final item in [
        (Mark.image, '拾影'),
        (Mark.card, '卡包'),
        (Mark.cloud, '备份与迁移'),
        (Mark.shield, '显示与权限'),
        (Mark.info, '关于拾刻'),
      ]) ...[
        InkWell(
          onTap: () => Navigator.push(
            c,
            MaterialPageRoute(
              builder: (_) => switch (item.$2) {
                '拾影' => RefinedGallery(controller: controller),
                '卡包' => RefinedCardPack(controller: controller),
                '备份与迁移' =>
                  controller.demo
                      ? const PreviewNotice()
                      : RefinedBackupPage(controller: controller),
                '显示与权限' => SettingsPage(controller: controller),
                _ => const AboutPage(),
              },
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 25),
            child: Row(
              children: [
                LineMark(item.$1, size: 29),
                const SizedBox(width: 24),
                Expanded(
                  child: Text(
                    item.$2,
                    style: const TextStyle(fontSize: 19, height: 1.5),
                  ),
                ),
                const LineMark(Mark.next, size: 17),
              ],
            ),
          ),
        ),
        const Divider(),
      ],
    ],
  );
}

class SettingsPage extends StatelessWidget {
  final RefinedController controller;
  const SettingsPage({super.key, required this.controller});
  @override
  Widget build(BuildContext c) => Scaffold(
    appBar: const PaperHeader('显示与权限'),
    body: AnimatedBuilder(
      animation: controller,
      builder: (c, _) => ListView(
        padding: const EdgeInsets.all(20),
        children: [
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('开屏问候'),
            value: controller.settings['greeting'] as bool,
            onChanged: (v) => controller.setSetting('greeting', v),
          ),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('导出图片包含心情'),
            value: controller.settings['exportMood'] as bool,
            onChanged: (v) => controller.setSetting('exportMood', v),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('城市'),
            subtitle: Text(
              (controller.settings['city'] as String).isEmpty
                  ? '不显示城市'
                  : controller.settings['city'] as String,
              style: Paper.meta,
            ),
            trailing: const LineMark(Mark.next, size: 17),
            onTap: () async {
              final input = TextEditingController(
                text: controller.settings['city'] as String,
              );
              final value = await showDialog<String>(
                context: c,
                builder: (c) => AlertDialog(
                  title: const Text('城市'),
                  content: TextField(
                    controller: input,
                    decoration: const InputDecoration(hintText: '留空则不显示'),
                    maxLength: 30,
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(c),
                      child: const Text('取消'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(c, input.text.trim()),
                      child: const Text('保存'),
                    ),
                  ],
                ),
              );
              input.dispose();
              if (value != null) await controller.setSetting('city', value);
            },
          ),
          const Divider(),
          const SizedBox(height: 20),
          const Text(
            '照片、录音和通知权限在使用对应功能时申请。可以在 iPhone 的系统设置中调整。',
            style: Paper.meta,
          ),
          const SizedBox(height: 16),
          const Text('天气服务尚未配置，暂不显示天气。', style: Paper.meta),
        ],
      ),
    ),
  );
}

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});
  @override
  Widget build(BuildContext c) => Scaffold(
    appBar: const PaperHeader('关于拾刻'),
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('拾刻', style: Paper.title(36)),
            const SizedBox(height: 14),
            const Text('把此刻轻轻拾起', style: Paper.meta),
            const SizedBox(height: 52),
            const Text(
              '写下的都算数，完成的都留下。',
              textAlign: TextAlign.center,
              style: Paper.meta,
            ),
          ],
        ),
      ),
    ),
  );
}

class PreviewNotice extends StatelessWidget {
  const PreviewNotice({super.key});
  @override
  Widget build(BuildContext c) => const Scaffold(
    appBar: PaperHeader('备份与迁移'),
    body: EmptyNote('视觉样例不操作你的真实备份。'),
  );
}
