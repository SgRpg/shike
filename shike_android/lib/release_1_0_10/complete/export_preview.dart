import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../src/store.dart';
import '../refined/design.dart';

const _album = MethodChannel('shike/album');

class _Piece {
  final String value;
  final double height;
  final bool photo;
  const _Piece(this.value, this.height, {this.photo = false});
}

TextPainter _text(String value, {double size = 34, Color color = Paper.ink}) =>
    TextPainter(
      text: TextSpan(text: value, style: TextStyle(fontSize: size, height: 1.7, color: color)),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: 772);

Future<ui.Image> _photo(String path) async {
  final bytes = path.startsWith('data:image;base64,')
      ? base64Decode(path.substring('data:image;base64,'.length))
      : await File(path).readAsBytes();
  final codec = await ui.instantiateImageCodec(bytes, targetWidth: 772);
  try { return (await codec.getNextFrame()).image; } finally { codec.dispose(); }
}

class _ExportBundle {
  final Directory directory;
  final List<File> files;
  final List<int> heights;
  const _ExportBundle(this.directory, this.files, this.heights);
  Future<void> dispose() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  }
}

/// Render one bounded canvas at a time; the preview and saver share these files.
Future<_ExportBundle> _generate(Diary diary, String metadata, bool includeMood) async {
  const bodyLimit = 7952.0;
  final pieces = <_Piece>[];
  for (final paragraph in diary.text.split('\n')) {
    if (paragraph.isEmpty) { pieces.add(const _Piece('', 30)); continue; }
    var chars = paragraph.characters.toList();
    while (chars.isNotEmpty) {
      var low = 1, high = chars.length, fit = 1;
      while (low <= high) {
        final mid = (low + high) ~/ 2;
        final painter = _text(chars.take(mid).join());
        final fits = painter.height + 20 <= bodyLimit;
        painter.dispose();
        if (fits) { fit = mid; low = mid + 1; } else { high = mid - 1; }
      }
      final value = chars.take(fit).join();
      final painter = _text(value);
      pieces.add(_Piece(value, painter.height + 20));
      painter.dispose();
      chars = chars.skip(fit).toList();
    }
  }
  for (final path in diary.photos) {
    final image = await _photo(path);
    pieces.add(_Piece(path, math.min(2200, 772 * image.height / image.width) + 28, photo: true));
    image.dispose();
  }
  final pages = <List<_Piece>>[];
  var current = <_Piece>[], height = 0.0;
  for (final piece in pieces) {
    if (current.isNotEmpty && height + piece.height > bodyLimit) {
      pages.add(current); current = []; height = 0;
    }
    current.add(piece); height += piece.height;
  }
  if (current.isNotEmpty || pages.isEmpty) pages.add(current);
  final directory = await (await getTemporaryDirectory()).createTemp('shike-export-');
  final files = <File>[], heights = <int>[];
  try {
    for (var index = 0; index < pages.length; index++) {
      final page = pages[index];
      final canvasHeight = math.max(420, 240 + page.fold<double>(0, (v, p) => v + p.height)).ceil();
      final recorder = ui.PictureRecorder();
      // The page recorder is local, so no previously rendered image remains decoded.
      final draw = Canvas(recorder);
      draw.drawColor(Colors.white, BlendMode.src);
      final head = _text(metadata, size: 26, color: Paper.secondary);
      head.paint(draw, const Offset(64, 52));
      if (includeMood && diary.mood != null) {
        draw.drawCircle(Offset(math.min(820, 64 + head.width + 25), 76), 12, Paint()..color = Paper.mood[diary.mood!]);
      }
      head.dispose();
      var y = 142.0;
      for (final piece in page) {
        if (piece.photo) {
          final image = await _photo(piece.value);
          final dest = Rect.fromLTWH(64, y, 772, piece.height - 28);
          final source = Size(image.width.toDouble(), image.height.toDouble());
          final fit = applyBoxFit(BoxFit.contain, source, dest.size);
          draw.drawImageRect(image, Offset.zero & source,
              Alignment.center.inscribe(fit.destination, dest), Paint()..filterQuality = FilterQuality.medium);
          image.dispose();
        } else if (piece.value.isNotEmpty) {
          final body = _text(piece.value); body.paint(draw, Offset(64, y)); body.dispose();
        }
        y += piece.height;
      }
      draw.drawLine(Offset(64, canvasHeight - 82), Offset(836, canvasHeight - 82), Paint()..color = Paper.line..strokeWidth = 1);
      final foot = _text(pages.length > 1 ? '拾刻 · ${index + 1}/${pages.length}' : '拾刻', size: 24, color: Paper.secondary);
      foot.paint(draw, Offset((900 - foot.width) / 2, canvasHeight - 67)); foot.dispose();
      final picture = recorder.endRecording();
      final image = await picture.toImage(900, canvasHeight); picture.dispose();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png); image.dispose();
      if (bytes == null) throw StateError('图片还没有准备好');
      final file = File('${directory.path}/${index + 1}.png');
      await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
      files.add(file); heights.add(canvasHeight);
    }
    return _ExportBundle(directory, files, heights);
  } catch (_) { await directory.delete(recursive: true); rethrow; }
}

Future<_ExportBundle> _generateCard(Uint8List bytes) async {
  final directory = await (await getTemporaryDirectory()).createTemp('shike-card-export-');
  try {
    final codec = await ui.instantiateImageCodec(bytes, targetWidth: 900);
    late final int height;
    try {
      final image = (await codec.getNextFrame()).image;
      height = (image.height * 900 / image.width).round();
      image.dispose();
    } finally { codec.dispose(); }
    final file = File('${directory.path}/1.png');
    await file.writeAsBytes(bytes, flush: true);
    return _ExportBundle(directory, [file], [height]);
  } catch (_) { await directory.delete(recursive: true); rethrow; }
}

Future<void> previewCardExport(BuildContext context, Uint8List bytes, {required String name}) =>
  _pushExportPreview(context, _ExportPreview(poster: bytes, filename: name));

Future<void> previewDiaryExport(BuildContext context, Diary diary, {
  required String metadata, required bool includeMood,
}) => _pushExportPreview(context, _ExportPreview(diary: diary, metadata: metadata, includeMood: includeMood));

Future<void> _pushExportPreview(BuildContext context, Widget page) async {
  await Navigator.of(context).push<void>(
    PageRouteBuilder<void>(
      transitionDuration: const Duration(milliseconds: 260),
      reverseTransitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (_, _, _) => page,
      transitionsBuilder: (context, animation, _, child) {
        if (MediaQuery.disableAnimationsOf(context)) return child;
        final curve = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
        return FadeTransition(opacity: curve, child: ScaleTransition(
          scale: Tween<double>(begin: .985, end: 1).animate(curve), child: child));
      },
    ),
  );
}

class _ExportPreview extends StatefulWidget {
  final Diary? diary;
  final String metadata;
  final bool includeMood;
  final Uint8List? poster;
  final String? filename;
  const _ExportPreview({this.diary, this.metadata = '', this.includeMood = false, this.poster, this.filename});
  @override State<_ExportPreview> createState() => _ExportPreviewState();
}

class _ExportPreviewState extends State<_ExportPreview> with WidgetsBindingObserver {
  _ExportBundle? bundle;
  String? error;
  bool saving = false, zoomed = false, completed = false, showSuccess = false, settingsRequired = false;
  final saved = <String>[];
  Timer? successTimer;
  @override void initState() {
    super.initState(); WidgetsBinding.instance.addObserver(this); generate();
  }
  @override void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && settingsRequired) checkPermission();
  }
  Future<void> checkPermission() async {
    try {
      if (await _album.invokeMethod<bool>('canSave') == true && mounted) {
        setState(() { settingsRequired = false; error = null; });
      }
    } catch (_) { /* Keep the settings action available. */ }
  }
  Future<void> generate() async {
    setState(() => error = null);
    try {
      final value = widget.poster == null
        ? await _generate(widget.diary!, widget.metadata, widget.includeMood)
        : await _generateCard(widget.poster!);
      if (!mounted) { await value.dispose(); return; }
      setState(() => bundle = value);
    } catch (_) { if (mounted) setState(() => error = '图片暂时没有准备好，点一下重试'); }
  }
  void close() { if (!saving) Navigator.pop(context); }
  Future<void> save() async {
    if (saving || completed || bundle == null) return;
    if (settingsRequired) {
      await _album.invokeMethod<void>('openSettings');
      return;
    }
    setState(() { saving = true; error = null; });
    try {
      for (var i = saved.length; i < bundle!.files.length; i++) {
        final uri = await _album.invokeMethod<String>('save', {
          'path': bundle!.files[i].path,
          'name': '${widget.filename ?? '拾刻-${widget.diary!.id}'}-${DateTime.now().millisecondsSinceEpoch}-${i + 1}.png',
        });
        if (uri == null) throw StateError('没有保存');
        saved.add(uri);
      }
      if (!mounted) return;
      final reduced = MediaQuery.disableAnimationsOf(context);
      setState(() { completed = true; showSuccess = false; settingsRequired = false; });
      if (!reduced) await Future<void>.delayed(const Duration(milliseconds: 450));
      if (!mounted) return;
      setState(() => showSuccess = true);
      successTimer = Timer(Duration(milliseconds: reduced ? 3000 : 3240), () {
        if (mounted) setState(() => showSuccess = false);
      });
    } catch (e) {
      debugPrint('Shike export save: $e');
      if (mounted) setState(() {
        final permission = e is PlatformException && e.code == 'PERMISSION';
        settingsRequired = permission && e.details is Map && e.details['settingsRequired'] == true;
        error = saved.isNotEmpty ? '已收好 ${saved.length} 张，点按钮继续保存剩余图片'
          : settingsRequired ? '需要在系统设置中允许保存图片'
          : permission ? '需要允许保存图片，再点一下重试'
          : '暂时没有收好，请再试一次';
      });
    } finally { if (mounted) setState(() => saving = false); }
  }
  Future<void> viewSaved() async {
    if (saved.isEmpty) return;
    successTimer?.cancel();
    try { await _album.invokeMethod<void>('view', {'uri': saved.first}); }
    catch (_) { if (mounted) setState(() => error = '图片已经收好，可以前往相册查看。'); }
    if (mounted) setState(() => showSuccess = false);
  }
  @override void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    successTimer?.cancel();
    final value = bundle;
    if (value != null) {
      for (final file in value.files) { FileImage(file).evict(); }
      unawaited(value.dispose());
    }
    super.dispose();
  }
  @override Widget build(BuildContext context) => PopScope(
    canPop: !saving,
    child: Scaffold(backgroundColor: Paper.bg,
      appBar: PaperHeader('', leading: IconButton(
        tooltip: '返回', onPressed: saving ? null : close,
        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
        icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 22, color: Color(0xFF333333)))),
      body: SafeArea(top: false, child: Column(children: [
        Expanded(child: bundle == null
          ? Center(child: error == null
              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 1.4, color: Paper.faint))
              : TextButton(onPressed: generate, child: Text(error!, style: Paper.meta)))
          : LayoutBuilder(builder: (context, box) {
              final w = box.maxWidth - 48;
              final total = bundle!.heights.fold<double>(0, (a, h) => a + h * w / 900) + (bundle!.files.length - 1) * 18;
              return ListView.builder(
                physics: zoomed ? const NeverScrollableScrollPhysics() : const ClampingScrollPhysics(),
                padding: EdgeInsets.fromLTRB(24, math.max(24, (box.maxHeight - total) / 2), 24, 24),
                itemCount: bundle!.files.length,
                itemBuilder: (context, index) => Padding(padding: const EdgeInsets.only(bottom: 18),
                  child: _ZoomPaper(
                    onZoomChanged: (z) { if (zoomed != z) setState(() => zoomed = z); },
                    child: Image.file(bundle!.files[index], width: w, fit: BoxFit.fitWidth,
                      cacheWidth: (w * MediaQuery.devicePixelRatioOf(context)).round().clamp(1, 900), excludeFromSemantics: true),
                  )),
              );
            })),
        if (bundle != null && bundle!.files.length > 1)
          Padding(padding: const EdgeInsets.only(bottom: 8), child: Text('共 ${bundle!.files.length} 张', style: Paper.meta.copyWith(fontSize: 12))),
        if (bundle != null && error != null)
          Padding(padding: const EdgeInsets.fromLTRB(24, 0, 24, 12), child: Text(error!, style: Paper.meta.copyWith(fontSize: 13))),
        Padding(padding: const EdgeInsets.fromLTRB(24, 8, 24, 30),
          child: SizedBox(
            height: math.max(48, MediaQuery.textScalerOf(context).scale(14) * 1.45 + 16),
            child: Center(child: AnimatedSwitcher(
              duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : const Duration(milliseconds: 240),
              reverseDuration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : const Duration(milliseconds: 450),
              child: completed
                ? (showSuccess ? ConstrainedBox(key: const ValueKey('saved'), constraints: const BoxConstraints(maxWidth: 300),
                    child: DecoratedBox(
                      decoration: const BoxDecoration(color: Color(0xEFF2F1EE), borderRadius: BorderRadius.all(Radius.circular(36))),
                      child: Padding(padding: const EdgeInsets.only(left: 18, right: 6),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          const Flexible(child: Text('收进相册啦', maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 13, color: Color(0xFF85898D)))),
                          const Padding(padding: EdgeInsets.symmetric(horizontal: 8),
                            child: Text('｜', style: TextStyle(fontSize: 13, color: Paper.faint))),
                          TextButton(onPressed: viewSaved,
                            style: TextButton.styleFrom(foregroundColor: const Color(0xFF333333), minimumSize: const Size(70, 48)),
                            child: const Row(mainAxisSize: MainAxisSize.min, children: [
                              Text('去看看', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                              SizedBox(width: 5), Icon(Icons.chevron_right_rounded, size: 18),
                            ])),
                        ]))))
                  : const SizedBox(key: ValueKey('finished')))
                : FilledButton(key: const ValueKey('save'),
                    style: FilledButton.styleFrom(backgroundColor: const Color(0xFF333333), foregroundColor: Colors.white,
                      minimumSize: Size(180, math.max(48, MediaQuery.textScalerOf(context).scale(14) * 1.45 + 16)),
                      shape: const StadiumBorder(), elevation: 0),
                    onPressed: bundle == null || saving ? null : save,
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text(saving ? '正在收好' : settingsRequired ? '开启相册权限' : '收进相册'),
                      const SizedBox(width: 14), const Icon(Icons.arrow_forward_rounded, size: 18),
                    ])),
            )),
          )),
      ])),
    ),
  );
}

class _ZoomPaper extends StatefulWidget {
  final Widget child;
  final ValueChanged<bool> onZoomChanged;
  const _ZoomPaper({required this.child, required this.onZoomChanged});
  @override State<_ZoomPaper> createState() => _ZoomPaperState();
}
class _ZoomPaperState extends State<_ZoomPaper> {
  final transform = TransformationController();
  @override void initState() {
    super.initState();
    transform.addListener(changed);
  }
  void changed() => widget.onZoomChanged(transform.value.getMaxScaleOnAxis() > 1.02);
  @override void dispose() { transform.removeListener(changed); transform.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) => InteractiveViewer(
    transformationController: transform, minScale: 1, maxScale: 3, child: widget.child);
}

