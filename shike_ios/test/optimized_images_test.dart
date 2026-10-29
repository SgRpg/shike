import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shike/complete/optimized_images.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'cover keeps enough pixels without stretching a landscape thumbnail',
    () {
      final size = photoDecodeSize(4000, 2000, 300, 450, BoxFit.cover);
      expect((size.width, size.height), (900, 450));
    },
  );

  test('contain uses the viewport and never upscales a small photo', () {
    final size = photoDecodeSize(4000, 2000, 300, 450, BoxFit.contain);
    expect((size.width, size.height), (300, 150));
    final small = photoDecodeSize(120, 80, 1200, 800, BoxFit.cover);
    expect((small.width, small.height), (120, 80));
  });

  test('full camera photos have a bounded decoded allocation', () {
    final size = photoDecodeSize(3456, 4608, 4096, 4096, BoxFit.cover);
    expect((size.width, size.height), (1536, 2048));
    expect(size.width! * size.height! * 4, 12 * 1024 * 1024);
  });

  test('cache is capped without widening an existing tighter limit', () {
    final cache = PaintingBinding.instance.imageCache;
    final bytes = cache.maximumSizeBytes;
    final count = cache.maximumSize;
    addTearDown(() {
      cache.maximumSizeBytes = bytes;
      cache.maximumSize = count;
    });
    cache.maximumSizeBytes = 80 * 1024 * 1024;
    configurePhotoMemoryCache();
    expect(cache.maximumSizeBytes, 48 * 1024 * 1024);
    cache.maximumSizeBytes = 16 * 1024 * 1024;
    configurePhotoMemoryCache();
    expect(cache.maximumSizeBytes, 16 * 1024 * 1024);
  });

  test(
    'actual image codec decodes a thumbnail instead of full pixels',
    () async {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawColor(Colors.blue, BlendMode.src);
      final picture = recorder.endRecording();
      final source = await picture.toImage(800, 400);
      final png = await source.toByteData(format: ui.ImageByteFormat.png);
      source.dispose();
      picture.dispose();
      final data =
          'data:image/png;base64,${base64Encode(png!.buffer.asUint8List())}';
      final stream = BoundedPhotoProvider(
        data,
        80,
        80,
        BoxFit.contain,
      ).resolve(ImageConfiguration.empty);
      final result = Completer<ImageInfo>();
      final listener = ImageStreamListener(
        (image, _) => result.complete(image),
        onError: result.completeError,
      );
      stream.addListener(listener);
      final decoded = await result.future.timeout(const Duration(seconds: 10));
      expect((decoded.image.width, decoded.image.height), (80, 40));
      stream.removeListener(listener);
      decoded.dispose();
    },
  );
}
