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
  @override State<RefinedBackupPage> createState() => _RefinedBackupPageState();
}

class _RefinedBackupPageState extends State<RefinedBackupPage> with WidgetsBindingObserver {
  static const channel = MethodChannel('shike/private');
  late final Future<BackupService> service;
  bool busy = false, receiving = false;
  String? pairing;
  Uint8List? qr;
  Timer? expiry;
  @override void initState() {
    super.initState(); WidgetsBinding.instance.addObserver(this);
    service = openBackupFiles().then((f) => BackupService(widget.controller.repository.state, f));
    channel.setMethodCallHandler((call) async {
      if (call.method != 'receivedBackup') return;
      final api = await service;
      final path = call.arguments as String;
      try {
        // A receipt can arrive while the QR image is still being generated.
        while (mounted && busy) { await Future<void>.delayed(const Duration(milliseconds: 80)); }
        if (!mounted || pairing == null) return;
        expiry?.cancel();
        setState(() { receiving = true; qr = null; });
        await run(() async => importBytes(await api.files.read(path), automatic: true));
      } finally {
        await api.files.remove(path);
        if (mounted) setState(() { receiving = false; pairing = null; qr = null; });
      }
    });
  }
  @override void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      unawaited(stopReceiving());
    }
  }
  Future<void> stopReceiving() async {
    expiry?.cancel();
    if (mounted) setState(() { pairing = null; qr = null; });
    if (!kIsWeb) await channel.invokeMethod<void>('stopNearby').catchError((_) {});
  }
  @override void dispose() {
    expiry?.cancel(); WidgetsBinding.instance.removeObserver(this);
    channel.setMethodCallHandler(null);
    if (!kIsWeb) unawaited(channel.invokeMethod<void>('stopNearby').catchError((_) {}));
    super.dispose();
  }
  Future<void> run(Future<void> Function() action) async {
    if (busy) return;
    setState(() => busy = true);
    try { await action(); }
    on FormatException catch (e) { if (mounted) tell(context, e.message); }
    on PlatformException catch (e) { if (mounted) tell(context, e.message ?? '暂时无法连接，请让两部手机连接同一 Wi-Fi 后重试。'); }
    catch (_) { if (mounted) tell(context, '暂时未能完成，原有记录仍保留。'); }
    finally { if (mounted) setState(() => busy = false); }
  }
  Future<void> export() async {
    final api = await service;
    final output = await FilePicker.saveFile(dialogTitle: '保存拾刻备份', fileName: '拾刻备份.zip', mimeType: 'application/zip', bytes: await api.export());
    if (output != null && mounted) {
      await api.markExported(); if (!mounted) return;
      widget.controller.reload(); tell(context, '备份已导出。');
    }
  }
  Future<void> importBytes(Uint8List bytes, {bool automatic = false}) async {
    final api = await service;
    final plan = await api.prepareImport(bytes);
    if (!mounted) return;
    if (!automatic && !await confirm(context, '导入 ${plan.additions} 篇记录？${plan.conflicts == 0 ? '' : '其中 ${plan.conflicts} 篇冲突记录会另存一份。'}', yes: '导入', no: '取消')) return;
    if (!mounted) return;
    await api.applyImport(plan);
    widget.controller.reload();
    (widget.controller.store as CompleteStore).refresh();
    await widget.controller.reconcileNotifications().catchError((_) {});
    if (mounted) tell(context, automatic ? '记录已接收并带回来了。' : '记录已带回来了。');
  }
  Future<void> choose() async {
    final picked = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: ['json', 'zip']);
    if (picked != null) await importBytes(await picked.readAsBytes());
  }
  Future<void> receive() async {
    if (kIsWeb) { tell(context, '请在安卓手机上使用附近迁移。'); return; }
    final code = await channel.invokeMethod<String>('receive');
    if (code == null || !mounted) return;
    setState(() => pairing = code);
    try {
      final image = await channel.invokeMethod<Uint8List>('qrImage', {'text': code});
      if (image == null) throw StateError('二维码未生成');
      if (!mounted || pairing != code) return;
      setState(() => qr = image);
      expiry?.cancel();
      expiry = Timer(const Duration(minutes: 10), () async {
        await stopReceiving();
        if (mounted) tell(context, '配对码已过期，点一下重新生成。');
      });
    } catch (_) { await stopReceiving(); rethrow; }
  }
  Future<void> send() async {
    if (kIsWeb) { tell(context, '请在安卓手机上使用附近迁移。'); return; }
    final raw = await channel.invokeMethod<String>('scanQR');
    if (raw == null) return;
    final code = NearbyPairing.parse(raw, DateTime.now());
    final api = await service;
    await channel.invokeMethod<void>('send', {'pairing': code.encode(), 'bytes': NearbyFrame.encode(await api.export())});
    if (mounted) tell(context, '已传送，对方会自动合并收到的记录。');
  }
  Widget option(String title, VoidCallback? action, {String? subtitle}) => ListTile(
    contentPadding: EdgeInsets.zero, title: Text(title, style: Paper.body),
    subtitle: subtitle == null ? null : Text(subtitle, style: Paper.meta.copyWith(fontSize: 12, color: Paper.faint)),
    trailing: const LineMark(Mark.next, size: 17), onTap: action,
  );
  @override Widget build(BuildContext context) => PopScope(
    canPop: !receiving,
    child: Scaffold(appBar: const PaperHeader('备份与迁移'),
      body: ListView(padding: const EdgeInsets.all(24), children: [
        option('导出备份包', busy || pairing != null ? null : () => run(export)),
        option('导入备份包', busy || pairing != null ? null : () => run(choose)),
        const Divider(), const SizedBox(height: 16),
        option('发送到附近的安卓手机', busy || pairing != null ? null : () => run(send)),
        option('接收附近安卓手机的数据', busy || pairing != null ? null : () => run(receive)),
        if (qr != null) ...[
          const SizedBox(height: 24),
          Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 280),
            child: AspectRatio(aspectRatio: 1, child: Image.memory(qr!, filterQuality: FilterQuality.none, semanticLabel: '附近迁移配对二维码')))),
          const SizedBox(height: 16),
          Text('等待另一部手机扫码', textAlign: TextAlign.center, style: Paper.body.copyWith(fontSize: 15)),
          const SizedBox(height: 8),
          const Text('两部手机连接同一 Wi-Fi。在另一部拾刻中点击“发送到附近的安卓手机”扫描此码，记录会自动传送并合并到本机。配对码 10 分钟内有效。', textAlign: TextAlign.center, style: Paper.meta),
          Center(child: TextButton(onPressed: stopReceiving, child: const Text('取消接收'))),
        ],
        if (busy) Padding(padding: const EdgeInsets.all(24), child: Column(children: [
          const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 1.5, color: Paper.faint)),
          if (receiving) const Padding(padding: EdgeInsets.only(top: 12), child: Text('正在带回记录…', style: Paper.meta)),
        ])),
        const SizedBox(height: 24),
        Text('上次备份：${widget.controller.repository.snapshot.meta['lastBackup'] ?? '还没有备份'}', style: Paper.meta),
      ]),
    ),
  );
}
