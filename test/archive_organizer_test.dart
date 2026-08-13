import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panelly/services/archive_organizer.dart';

void main() {
  group('ArchiveOrganizer', () {
    test('sorts numeric page names naturally', () {
      final pages = <String>[
        'chapter/10.webp',
        'chapter/2.webp',
        'chapter/1.webp',
      ]..sort(ArchiveOrganizer.naturalCompare);

      expect(pages, <String>[
        'chapter/1.webp',
        'chapter/2.webp',
        'chapter/10.webp',
      ]);
    });

    test('strips a shared archive root folder', () {
      expect(
        ArchiveOrganizer.stripSharedRoot(<String>[
          'My Comic/Chapter 01/001.webp',
          'My Comic/Chapter 02/001.webp',
        ]),
        <String>['Chapter 01/001.webp', 'Chapter 02/001.webp'],
      );
    });

    test('keeps paths when they do not share a root folder', () {
      expect(
        ArchiveOrganizer.stripSharedRoot(<String>[
          'Chapter 01/001.webp',
          'Chapter 02/001.webp',
          'cover.webp',
        ]),
        <String>['Chapter 01/001.webp', 'Chapter 02/001.webp', 'cover.webp'],
      );
    });

    test('infers chapter from first folder and body for loose pages', () {
      expect(ArchiveOrganizer.inferChapterName('第 01 话/001.webp'), '第 01 话');
      expect(ArchiveOrganizer.inferChapterName('001.webp'), '正文');
    });

    test('detects WebP case-insensitively and ignores junk paths', () {
      expect(ArchiveOrganizer.isWebpPath('Chapter/001.WEBP'), isTrue);
      expect(ArchiveOrganizer.isWebpPath('Chapter/001.jpg'), isFalse);
      expect(ArchiveOrganizer.isJunkPath('__MACOSX/001.webp'), isTrue);
      expect(ArchiveOrganizer.isJunkPath('Chapter/.cover.webp'), isTrue);
    });

    test('imports and reorganizes a real ZIP archive', () async {
      final temporaryRoot = Directory('build/test_tmp')
        ..createSync(recursive: true);
      final temporary = await temporaryRoot.createTemp('panelly_import_test_');
      addTearDown(() => temporary.delete(recursive: true));
      final archive = Archive()
        ..addFile(ArchiveFile.bytes('Comic/Chapter 01/10.webp', <int>[10]))
        ..addFile(ArchiveFile.bytes('Comic/Chapter 01/2.webp', <int>[2]))
        ..addFile(ArchiveFile.bytes('Comic/cover.webp', <int>[0]))
        ..addFile(ArchiveFile.bytes('Comic/Chapter 02/1.webp', <int>[20]))
        ..addFile(ArchiveFile.bytes('Comic/Chapter 01/note.jpg', <int>[99]))
        ..addFile(ArchiveFile.bytes('__MACOSX/ghost.webp', <int>[88]));
      final source = File('${temporary.path}/Demo Comic.cbz');
      await source.writeAsBytes(ZipEncoder().encodeBytes(archive));
      final library = Directory('${temporary.path}/library')..createSync();

      final book = await ArchiveOrganizer().importArchive(
        sourcePath: source.path,
        libraryRoot: library,
      );

      expect(book.title, 'Demo Comic');
      expect(book.pageCount, 4);
      expect(book.chapters.map((chapter) => chapter.title), <String>[
        '正文',
        'Chapter 01',
        'Chapter 02',
      ]);
      expect(
        await File(
          '${library.path}/${book.directoryName}/${book.pages[1]}',
        ).readAsBytes(),
        <int>[2],
      );
      expect(
        await File(
          '${library.path}/${book.directoryName}/${book.pages[2]}',
        ).readAsBytes(),
        <int>[10],
      );
    });

    test('imports and reorganizes a real comic directory', () async {
      final temporaryRoot = Directory('build/test_tmp')
        ..createSync(recursive: true);
      final temporary = await temporaryRoot.createTemp('panelly_folder_test_');
      addTearDown(() => temporary.delete(recursive: true));
      final source = Directory('${temporary.path}/Folder Comic')..createSync();
      final chapter = Directory('${source.path}/Chapter 01')..createSync();
      await File('${chapter.path}/10.webp').writeAsBytes(<int>[10]);
      await File('${chapter.path}/2.webp').writeAsBytes(<int>[2]);
      await File('${source.path}/cover.webp').writeAsBytes(<int>[0]);
      await File('${source.path}/notes.jpg').writeAsBytes(<int>[99]);
      final library = Directory('${temporary.path}/library')..createSync();

      final book = await ArchiveOrganizer().importDirectory(
        sourcePath: source.path,
        libraryRoot: library,
      );

      expect(book.title, 'Folder Comic');
      expect(book.pageCount, 3);
      expect(book.chapters.map((chapter) => chapter.title), <String>[
        '正文',
        'Chapter 01',
      ]);
      expect(
        await File(
          '${library.path}/${book.directoryName}/${book.pages[1]}',
        ).readAsBytes(),
        <int>[2],
      );
      expect(
        await File(
          '${library.path}/${book.directoryName}/${book.pages[2]}',
        ).readAsBytes(),
        <int>[10],
      );
    });
  });
}
