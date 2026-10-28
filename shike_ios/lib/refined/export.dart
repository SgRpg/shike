import 'dart:ui' as ui;
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:file_picker/file_picker.dart';
import 'package:gal/gal.dart';

import '../src/store.dart';
import 'design.dart';

Future<bool> savePng(Uint8List bytes, String filename) async {
  if (kIsWeb) {
    return await FilePicker.saveFile(
          fileName: filename,
          bytes: bytes,
          mimeType: 'image/png',
        ) !=
        null;
  } else {
    await Gal.putImageBytes(bytes, name: filename.replaceAll('.png', ''));
    return true;
  }
}

Future<Uint8List> captureBoundary(GlobalKey key) async {
  await WidgetsBinding.instance.endOfFrame;
  final boundary =
      key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
  if (boundary == null) throw StateError('卡片还没有准备好');
  final image = await boundary.toImage(pixelRatio: 2.5);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  if (data == null) throw StateError('无法生成图片');
  return data.buffer.asUint8List();
}

/// Paginated text export. Each PNG has a bounded canvas and no voice content.
Future<int> exportDiary(
  Diary diary, {
  required bool includeMood,
  String? metadata,
  Future<bool> Function(Uint8List, String)? saver,
}) async {
  final save = saver ?? savePng;
  const width = 900.0, height = 1450.0, pad = 64.0;
  final paragraphs = diary.text.split('\n');
  final chunks = <String>[];
  var current = '';
  for (final p in paragraphs) {
    // Split long paragraphs at grapheme boundaries to avoid a huge canvas.
    var rest = p.characters.toList();
    while (rest.isNotEmpty) {
      final take = rest.take(280).join();
      rest = rest.skip(280).toList();
      final candidate = current.isEmpty ? take : '$current\n$take';
      final layout = TextPainter(
        text: TextSpan(
          text: candidate,
          style: const TextStyle(color: Paper.ink, fontSize: 34, height: 1.7),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: width - pad * 2);
      if (layout.height > height - 360 && current.isNotEmpty) {
        chunks.add(current);
        current = take;
      } else {
        current = candidate;
      }
    }
    current = '$current\n';
  }
  if (current.trim().isNotEmpty) chunks.add(current.trimRight());
  if (chunks.isEmpty) chunks.add('');
  var page = 0;
  final total = chunks.length + (diary.photos.length / 4).ceil();
  for (final text in chunks) {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawColor(Paper.bg, BlendMode.src);
    final date =
        '${diary.created.year}.${diary.created.month.toString().padLeft(2, '0')}.${diary.created.day.toString().padLeft(2, '0')}';
    final head = TextPainter(
      text: TextSpan(
        text: metadata ?? date,
        style: const TextStyle(color: Paper.secondary, fontSize: 26),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: width - pad * 2);
    head.paint(canvas, const Offset(pad, 70));
    if (includeMood && diary.mood != null) {
      canvas.drawCircle(
        Offset((pad + head.width + 28).clamp(pad, width - pad), 85),
        14,
        Paint()..color = Paper.mood[diary.mood!],
      );
    }
    final body = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(color: Paper.ink, fontSize: 34, height: 1.7),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: width - pad * 2);
    body.paint(canvas, const Offset(pad, 155));
    final foot = TextPainter(
      text: TextSpan(
        text:
            '拾刻 · ${DateTime.now().year}.${DateTime.now().month}.${DateTime.now().day}  ${page + 1}/$total',
        style: const TextStyle(color: Paper.secondary, fontSize: 22),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: width - pad * 2);
    foot.paint(canvas, Offset(pad, height - 80));
    final picture = recorder.endRecording();
    final image = await picture.toImage(width.toInt(), height.toInt());
    picture.dispose();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    if (bytes == null) throw StateError('图片生成失败');
    if (!await save(
      bytes.buffer.asUint8List(),
      '拾刻-${diary.id}-${page + 1}.png',
    )) {
      return page;
    }
    page++;
  }
  for (var offset = 0; offset < diary.photos.length; offset += 4) {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawColor(Paper.bg, BlendMode.src);
    final head = TextPainter(
      text: TextSpan(
        text:
            metadata ??
            '${diary.created.year}.${diary.created.month}.${diary.created.day}',
        style: const TextStyle(color: Paper.secondary, fontSize: 26),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: width - pad * 2);
    head.paint(canvas, const Offset(pad, 70));
    final group = diary.photos.skip(offset).take(4).toList();
    for (var i = 0; i < group.length; i++) {
      final file = group[i];
      const prefix = 'data:image;base64,';
      final data = file.startsWith(prefix)
          ? base64Decode(file.substring(prefix.length))
          : await File(file).readAsBytes();
      final codec = await ui.instantiateImageCodec(data, targetWidth: 800);
      final frame = await codec.getNextFrame();
      codec.dispose();
      final source = Size(
        frame.image.width.toDouble(),
        frame.image.height.toDouble(),
      );
      final destination = Rect.fromLTWH(
        pad + (i % 2) * 394,
        155 + (i ~/ 2) * 520,
        378,
        500,
      );
      final fit = applyBoxFit(BoxFit.cover, source, destination.size);
      canvas.drawImageRect(
        frame.image,
        Alignment.center.inscribe(fit.source, Offset.zero & source),
        Alignment.center.inscribe(fit.destination, destination),
        Paint()..filterQuality = FilterQuality.medium,
      );
      frame.image.dispose();
    }
    final foot = TextPainter(
      text: TextSpan(
        text: '拾刻 · ${page + 1}/$total',
        style: const TextStyle(color: Paper.secondary, fontSize: 22),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: width - pad * 2);
    foot.paint(canvas, Offset(pad, height - 80));
    final picture = recorder.endRecording();
    final image = await picture.toImage(width.toInt(), height.toInt());
    picture.dispose();
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    if (data == null) throw StateError('图片生成失败');
    if (!await save(
      data.buffer.asUint8List(),
      '拾刻-${diary.id}-${page + 1}.png',
    )) {
      return page;
    }
    page++;
  }
  return page;
}
