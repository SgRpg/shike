import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import '../refined/design.dart';
import '../refined/export.dart' show captureBoundary;

class CardAlbumCapsule extends StatefulWidget {
  final GlobalKey captureKey;
  final String filename;
  const CardAlbumCapsule({super.key, required this.captureKey, required this.filename});
  @override State<CardAlbumCapsule> createState() => _CardAlbumCapsuleState();
}
class _CardAlbumCapsuleState extends State<CardAlbumCapsule> with WidgetsBindingObserver {
  static const album = MethodChannel('shike/album');
  bool saving = false, completed = false, showSuccess = false, settingsRequired = false;
  String? uri;
  Timer? timer;
  @override void initState() { super.initState(); WidgetsBinding.instance.addObserver(this); }
  @override void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && settingsRequired) unawaited(checkPermission());
  }
  Future<void> checkPermission() async {
    try { if (await album.invokeMethod<bool>('canSave') == true && mounted) setState(() => settingsRequired = false); }
    catch (_) { /* User can try the settings action again. */ }
  }
  Future<void> save() async {
    if (saving || completed) return;
    if (settingsRequired) { await album.invokeMethod<void>('openSettings'); return; }
    setState(() => saving = true);
    Directory? temporary;
    try {
      final bytes = await captureBoundary(widget.captureKey);
      temporary = await (await getTemporaryDirectory()).createTemp('shike-card-');
      final file = File('${temporary.path}/card.png');
      await file.writeAsBytes(bytes, flush: true);
      final saved = await album.invokeMethod<String>('save', {
        'path': file.path, 'name': '${widget.filename}-${DateTime.now().millisecondsSinceEpoch}.png',
      });
      if (saved == null) throw StateError('未保存');
      if (!mounted) return;
      setState(() { uri = saved; completed = true; showSuccess = true; });
      timer = Timer(const Duration(seconds: 3), () { if (mounted) setState(() => showSuccess = false); });
    } catch (e) {
      if (mounted) {
        settingsRequired = e is PlatformException && e.code == 'PERMISSION' && e.details is Map && e.details['settingsRequired'] == true;
        tell(context, settingsRequired ? '需要在系统设置中允许保存图片。' : '暂时没有收好，请再试一次。');
      }
    } finally {
      if (temporary != null) await temporary.delete(recursive: true).catchError((_) => temporary!);
      if (mounted) setState(() => saving = false);
    }
  }
  Future<void> view() async {
    if (uri == null) return;
    timer?.cancel();
    try { await album.invokeMethod<void>('view', {'uri': uri}); }
    catch (_) { if (mounted) tell(context, '图片已经收好，可以前往相册查看。'); }
    if (mounted) setState(() => showSuccess = false);
  }
  @override void dispose() { WidgetsBinding.instance.removeObserver(this); timer?.cancel(); super.dispose(); }
  @override Widget build(BuildContext context) => SizedBox(height: 56,
    child: AnimatedSwitcher(duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : const Duration(milliseconds: 220),
      child: completed ? (showSuccess ? Container(key: const ValueKey('success'),
        padding: const EdgeInsets.only(left: 18, right: 4),
        decoration: BoxDecoration(color: const Color(0xEEF3F2EF), borderRadius: BorderRadius.circular(30)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Flexible(child: Text('收进相册啦', style: TextStyle(fontSize: 13, color: Color(0xFF85898D)))),
          const Text(' ｜ ', style: TextStyle(fontSize: 13, color: Paper.faint)),
          TextButton(onPressed: view, child: const Text('去看看 ›', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Paper.ink))),
        ])) : const SizedBox(key: ValueKey('finished')))
        : FilledButton(key: const ValueKey('save'), onPressed: saving ? null : save,
          style: FilledButton.styleFrom(backgroundColor: const Color(0xFF333333), foregroundColor: Colors.white,
            minimumSize: const Size(220, 48), shape: const StadiumBorder(), elevation: 0),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(saving ? '正在收好' : settingsRequired ? '开启相册权限' : '收进相册'),
            const SizedBox(width: 14), const Icon(Icons.arrow_forward_rounded, size: 18),
          ])),
    ),
  );
}
