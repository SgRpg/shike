import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';

import '../refined/design.dart';
import 'controller.dart';
import 'backup_service.dart';
import 'platform_files.dart';
import 'nearby_protocol.dart';

class RefinedBackupPage extends StatefulWidget {
  final CompleteController controller;
  const RefinedBackupPage({super.key, required this.controller});
  @override
  State<RefinedBackupPage> createState() => _RefinedBackupPageState();
}

class _RefinedBackupPageState extends State<RefinedBackupPage>
    with WidgetsBindingObserver {
  static const channel = MethodChannel('shike/private');
  late final Future<BackupService> service;
  bool busy = false;
  String? pairing;
  Uint8List? qr;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    service = openBackupFiles().then(
      (f) => BackupService(widget.controller.repository.state, f),
    );
    channel.setMethodCallHandler((call) async {
      if (call.method == 'receivedBackup' && mounted) {
        final api = await service;
        try {
          await importBytes(await api.files.read(call.arguments as String));
        } finally {
          if (mounted) {
            setState(() {
              pairing = null;
              qr = null;
            });
          }
        }
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      unawaited(channel.invokeMethod('stopNearby').catchError((_) {}));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    channel.setMethodCallHandler(null);
    unawaited(channel.invokeMethod('stopNearby').catchError((_) {}));
    super.dispose();
  }

  Future<void> run(Future<void> Function() action) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await action();
    } catch (_) {
      if (mounted) tell(context, '暂时未能完成，原有记录仍保留。');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> export() async {
    final api = await service;
    final bytes = await api.export();
    final output = await FilePicker.saveFile(
      dialogTitle: '保存拾刻备份',
      fileName: '拾刻备份.zip',
      mimeType: 'application/zip',
      bytes: bytes,
    );
    if (output != null && mounted) {
      widget.controller.reload();
      tell(context, '备份已导出。');
    }
  }

  Future<void> importBytes(Uint8List bytes) async {
    final api = await service;
    final plan = await api.prepareImport(bytes);
    if (!mounted) return;
    final yes = await confirm(
      context,
      '导入 ${plan.additions} 篇记录？${plan.conflicts == 0 ? '' : '其中 ${plan.conflicts} 篇冲突记录会另存一份。'}',
      yes: '导入',
      no: '取消',
    );
    if (!yes) return;
    await api.applyImport(plan);
    widget.controller.reload();
    (widget.controller.store as CompleteStore).refresh();
    await widget.controller.reconcileNotifications();
    if (mounted) tell(context, '记录已带回来了。');
  }

  Future<void> choose() async {
    final picked = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['json', 'zip'],
    );
    if (picked == null) return;
    await importBytes(await picked.readAsBytes());
  }

  Future<void> receive() async {
    if (kIsWeb) {
      tell(context, '请在 iPhone 上使用附近迁移。');
      return;
    }
    final code = await channel.invokeMethod<String>('receive');
    if (code == null) return;
    final image = await channel.invokeMethod<Uint8List>('qrImage', {
      'text': code,
    });
    if (mounted) {
      setState(() {
        pairing = code;
        qr = image;
      });
    }
  }

  Future<void> send() async {
    if (kIsWeb) {
      tell(context, '请在 iPhone 上使用附近迁移。');
      return;
    }
    final raw = await channel.invokeMethod<String>('scanQR');
    if (raw == null) return;
    final code = NearbyPairing.parse(raw, DateTime.now());
    final api = await service;
    final bytes = NearbyFrame.encode(await api.export());
    await channel.invokeMethod('send', {
      'pairing': code.encode(),
      'bytes': bytes,
    });
    if (mounted) tell(context, '已发送，请在另一部 iPhone 确认导入。');
  }

  @override
  Widget build(BuildContext c) => Scaffold(
    appBar: const PaperHeader('备份与迁移'),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('导出备份包'),
          onTap: busy ? null : () => run(export),
          trailing: const LineMark(Mark.next, size: 17),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('导入备份包'),
          onTap: busy ? null : () => run(choose),
          trailing: const LineMark(Mark.next, size: 17),
        ),
        const Divider(),
        const SizedBox(height: 16),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('发送到附近的 iPhone'),
          onTap: busy ? null : () => run(send),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('接收记录'),
          onTap: busy ? null : () => run(receive),
        ),
        if (qr != null) ...[
          const SizedBox(height: 20),
          Center(child: Image.memory(qr!, width: 240, height: 240)),
          const SizedBox(height: 12),
          const Text('用另一部 iPhone 扫描。保持此页打开，配对码 10 分钟内有效。', style: Paper.meta),
          TextButton(
            onPressed: () async {
              await channel.invokeMethod('stopNearby');
              if (mounted) {
                setState(() {
                  pairing = null;
                  qr = null;
                });
              }
            },
            child: const Text('取消接收'),
          ),
        ],
        if (busy)
          const Padding(
            padding: EdgeInsets.all(20),
            child: Center(child: CircularProgressIndicator(strokeWidth: 1.5)),
          ),
        const SizedBox(height: 24),
        Text(
          '上次备份：${widget.controller.repository.snapshot.meta['lastBackup'] ?? '还没有备份'}',
          style: Paper.meta,
        ),
      ],
    ),
  );
}
