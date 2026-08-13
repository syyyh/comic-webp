import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:panelly/models/comic_book.dart';
import 'package:panelly/services/thumbnail_service.dart';

void main() {
  test('thumbnail path stays inside the comic directory', () {
    final bookDirectory = Directory('build/test_tmp/comic_42');
    final thumbnailPath = ThumbnailService.thumbnailPath(bookDirectory);
    expect(p.basename(thumbnailPath), 'cover.png');
    expect(p.basename(p.dirname(thumbnailPath)), 'comic_42');
  });

  test('empty books do not create a thumbnail', () async {
    final root = Directory('build/test_tmp/thumbnail_empty')
      ..createSync(recursive: true);
    final book = ComicBook(
      id: 'empty',
      title: '空',
      directoryName: 'comic_empty',
      importedAt: DateTime.now(),
      chapters: const <ComicChapter>[],
      totalBytes: 0,
    );
    await ThumbnailService.createForBook(book, root);
    expect(
      File(
        ThumbnailService.thumbnailPath(Directory('${root.path}/comic_empty')),
      ).existsSync(),
      isFalse,
    );
  });
}
