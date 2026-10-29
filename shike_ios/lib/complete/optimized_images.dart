import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Explicit opt-in: existing pages keep their current image helper until the
/// reviewed import changes are authorized.
void configurePhotoMemoryCache() {
  final cache = PaintingBinding.instance.imageCache;
  cache.maximumSizeBytes = math.min(cache.maximumSizeBytes, 48 * 1024 * 1024);
  cache.maximumSize = math.min(cache.maximumSize, 100);
}

/// Determines the codec's output dimensions before allocating decoded pixels.
/// Cover and contain keep the original aspect ratio; no image is upscaled.
ui.TargetImageSize photoDecodeSize(
  int sourceWidth,
  int sourceHeight,
  int boxWidth,
  int boxHeight,
  BoxFit fit,
) {
  final x = math.max(1, boxWidth) / sourceWidth;
  final y = math.max(1, boxHeight) / sourceHeight;
  final requested = switch (fit) {
    BoxFit.cover || BoxFit.fill => math.max(x, y),
    BoxFit.fitWidth => x,
    BoxFit.fitHeight => y,
    BoxFit.none => 1.0,
    BoxFit.contain || BoxFit.scaleDown => math.min(x, y),
  };
  final limit = 2048 / math.max(sourceWidth, sourceHeight);
  final scale = math.min(1.0, math.min(requested, limit));
  return ui.TargetImageSize(
    width: math.max(1, (sourceWidth * scale).floor()),
    height: math.max(1, (sourceHeight * scale).floor()),
  );
}

int _bucket(double value) => (value / 64).ceil().clamp(1, 32) * 64;

Widget storedImage(String path, {BoxFit fit = BoxFit.cover}) => LayoutBuilder(
  builder: (context, constraints) {
    final media = MediaQuery.maybeOf(context);
    final fallback = media?.size ?? const Size(402, 874);
    final ratio = media?.devicePixelRatio ?? 1;
    final width = constraints.hasBoundedWidth
        ? constraints.maxWidth
        : fallback.width;
    final height = constraints.hasBoundedHeight
        ? constraints.maxHeight
        : fallback.height;
    if (kIsWeb && !path.startsWith('data:image')) {
      return const SizedBox.shrink();
    }
    return Image(
      image: BoundedPhotoProvider(
        path,
        _bucket(width * ratio),
        _bucket(height * ratio),
        fit,
      ),
      fit: fit,
      errorBuilder: (_, _, _) => const Icon(Icons.broken_image_outlined),
    );
  },
);

/// Uses intrinsic metadata in the codec callback, rather than decoding a full
/// camera photo and subsequently resizing the resulting pixel buffer.
@immutable
class BoundedPhotoProvider extends ImageProvider<BoundedPhotoProvider> {
  final String path;
  final int boxWidth;
  final int boxHeight;
  final BoxFit fit;

  const BoundedPhotoProvider(
    this.path,
    this.boxWidth,
    this.boxHeight,
    this.fit,
  );

  @override
  Future<BoundedPhotoProvider> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(
    BoundedPhotoProvider key,
    ImageDecoderCallback decode,
  ) => MultiFrameImageStreamCompleter(codec: _load(decode), scale: 1);

  Future<ui.Codec> _load(ImageDecoderCallback decode) async {
    try {
      final ui.ImmutableBuffer buffer;
      if (path.startsWith('data:image')) {
        final uri = Uri.parse(path);
        if (uri.data == null || !uri.data!.isBase64) {
          throw const FormatException('照片数据无效');
        }
        buffer = await ui.ImmutableBuffer.fromUint8List(
          base64Decode(path.substring(path.indexOf(',') + 1)),
        );
      } else {
        buffer = await ui.ImmutableBuffer.fromFilePath(path);
      }
      return await decode(
        buffer,
        getTargetSize: (width, height) =>
            photoDecodeSize(width, height, boxWidth, boxHeight, fit),
      );
    } catch (_) {
      PaintingBinding.instance.imageCache.evict(this);
      rethrow;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is BoundedPhotoProvider &&
      other.path == path &&
      other.boxWidth == boxWidth &&
      other.boxHeight == boxHeight &&
      other.fit == fit;

  @override
  int get hashCode => Object.hash(path, boxWidth, boxHeight, fit);
}
