import 'dart:io';
import 'dart:ui' as ui;

import 'package:path/path.dart' as p;

import '../models/comic_book.dart';

class ThumbnailService {
  const ThumbnailService._();

  static const _thumbnailName = 'cover.png';
  static const thumbnailWidth = 640;

  static String thumbnailPath(Directory bookDirectory) =>
      p.join(bookDirectory.path, _thumbnailName);

  static Future<void> createForBook(
    ComicBook book,
    Directory libraryRoot,
  ) async {
    if (book.pages.isEmpty) return;
    final bookDirectory = Directory(
      p.join(libraryRoot.path, book.directoryName),
    );
    if (File(thumbnailPath(bookDirectory)).existsSync()) return;
    final source = File(p.join(bookDirectory.path, book.pages.first));
    if (!source.existsSync()) return;

    ui.ImmutableBuffer? buffer;
    ui.Codec? codec;
    ui.Image? image;
    try {
      // Decode directly from the file so the full source image is not copied
      // into the Dart heap during large-library imports.
      buffer = await ui.ImmutableBuffer.fromFilePath(source.path);
      codec = await ui.instantiateImageCodecFromBuffer(
        buffer,
        targetWidth: thumbnailWidth,
        allowUpscaling: false,
      );
      // instantiateImageCodecFromBuffer takes ownership of the buffer.
      buffer = null;
      final frame = await codec.getNextFrame();
      image = frame.image;
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) return;
      await File(thumbnailPath(bookDirectory)).writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        flush: true,
      );
    } on Object {
      // A broken first page should not make an otherwise valid import fail.
    } finally {
      buffer?.dispose();
      image?.dispose();
      codec?.dispose();
    }
  }
}
