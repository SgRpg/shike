import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';

import '../src/backup.dart';
import 'controller.dart';
import 'design.dart';

class RefinedBackupCodec {
  static Future<Uint8List> encode(RefinedController controller) async {
    final root = Map<String, dynamic>.from(
      jsonDecode(utf8.decode(await BackupService.export(controller.store))),
    );
    root['refined'] = {
      'settings': controller.settings,
      'snapshots': controller.snapshots,
      'references': controller.references.map(
        (key, value) => MapEntry(key, value.map((r) => r.toJson()).toList()),
      ),
    };
    return Uint8List.fromList(utf8.encode(jsonEncode(root)));
  }

  static Future<int> restore(
    RefinedController controller,
    Uint8List data,
  ) async {
    final root = BackupService.validate(data);
    final meta = Map<String, dynamic>.from(root['refined'] as Map? ?? {});
    final refs = Map<String, dynamic>.from(meta['references'] as Map? ?? {});
    final snapshots = Map<String, String>.from(meta['snapshots'] as Map? ?? {});
    final settings = Map<String, dynamic>.from(meta['settings'] as Map? ?? {});
    // Parse the extra metadata before importing any records.
    final parsed = refs.map(
      (key, value) => MapEntry(
        key,
        (value as List)
            .map((r) => JournalReference.fromJson(Map<String, dynamic>.from(r)))
            .toList(),
      ),
    );
    final ids = controller.store.entries.map((e) => e.id).toSet();
    final expected = <String>[];
    final mapping = <String, String>{};
    for (final raw in root['entries'] as List) {
      final j = Map<String, dynamic>.from(raw);
      final id = j['id'] as String;
      final old = controller.store.entries.where((e) => e.id == id).firstOrNull;
      if (old == null) {
        expected.add(id);
      } else if (jsonEncode(await BackupService.encodeDiary(old)) ==
          jsonEncode(j)) {
        mapping[id] = id;
      } else {
        expected.add(id);
      }
    }
    final added = <String>[];
    void recordAdds() {
      for (final entry in controller.store.entries) {
        if (ids.add(entry.id)) added.add(entry.id);
      }
    }

    controller.store.addListener(recordAdds);
    int count;
    try {
      count = await BackupService.restore(controller.store, data);
    } finally {
      controller.store.removeListener(recordAdds);
    }
    for (var i = 0; i < expected.length && i < added.length; i++) {
      mapping[expected[i]] = added[i];
    }
    for (final entry in snapshots.entries) {
      final id = mapping[entry.key];
      if (id != null) await controller.snapshot(id, entry.value);
    }
    for (final entry in parsed.entries) {
      final id = mapping[entry.key];
      if (id == null || controller.references.containsKey(id)) continue;
      await controller.saveLinks(
        id,
        entry.value
            .map(
              (r) => JournalReference(
                target: mapping[r.target] ?? r.target,
                text: r.text,
                start: r.start,
                end: r.end,
              ),
            )
            .toList(),
      );
    }
    // Preserve the receiving device's current preferences; import only missing keys.
    for (final entry in settings.entries) {
      if (!controller.settings.containsKey(entry.key)) {
        await controller.setSetting(entry.key, entry.value);
      }
    }
    await controller.reloadCollections();
    return count;
  }
}

class RefinedBackupPage extends StatefulWidget {
  final RefinedController controller;
  const RefinedBackupPage({super.key, required this.controller});
  @override
  State<RefinedBackupPage> createState() => _RefinedBackupPageState();
}

class _RefinedBackupPageState extends State<RefinedBackupPage> {
  bool busy = false;
  Future<void> export() async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final bytes = await RefinedBackupCodec.encode(widget.controller);
      final output = await FilePicker.saveFile(
        fileName: '拾刻备份.json',
        mimeType: 'application/json',
        bytes: bytes,
      );
      if (mounted && output != null) tell(context, '备份已导出。');
    } catch (_) {
      if (mounted) tell(context, '无法导出，请检查媒体文件及可用空间。');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> import() async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final data = await BackupService.choose();
      if (data == null) return;
      final root = BackupService.validate(data);
      if (!mounted) return;
      if (!await confirm(
        context,
        '包含 ${(root['entries'] as List).length} 篇日记和草稿，将与已有内容合并。',
        yes: '导入',
        no: '取消',
      )) {
        return;
      }
      final count = await RefinedBackupCodec.restore(widget.controller, data);
      if (mounted) tell(context, '已导入 $count 篇日记或草稿。');
    } catch (_) {
      if (mounted) tell(context, '导入未完成，请检查备份文件。已有日记不会被覆盖。');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext c) => Scaffold(
    appBar: const PaperHeader('备份与迁移'),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Text('把拾起的都带走。', style: Paper.meta),
        const SizedBox(height: 25),
        for (final item in [
          (Mark.download, '导出备份包', export),
          (Mark.journal, '导入备份包', import),
        ]) ...[
          ListTile(
            contentPadding: const EdgeInsets.symmetric(vertical: 10),
            leading: LineMark(item.$1),
            title: Text(item.$2),
            subtitle: item.$2 == '导出备份包'
                ? Text(
                    '包含 ${widget.controller.store.entries.length} 篇日记和草稿',
                    style: Paper.meta,
                  )
                : null,
            trailing: const LineMark(Mark.next, size: 16),
            enabled: !busy,
            onTap: busy ? null : item.$3,
          ),
          const Divider(),
        ],
        if (busy)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 25),
            child: Center(
              child: SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 1.3),
              ),
            ),
          ),
        const SizedBox(height: 24),
        const Text('附近迁移需要在 iPhone 上完成连接验证，当前可先通过备份包迁移。', style: Paper.meta),
      ],
    ),
  );
}
