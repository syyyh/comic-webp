import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panelly/app_controller.dart';
import 'package:panelly/models/comic_book.dart';
import 'package:panelly/models/library_folder.dart';
import 'package:panelly/screens/reader_screen.dart';
import 'package:panelly/services/library_repository.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

void main() {
  testWidgets('continuous reader keeps the saved page during initial layout', (
    tester,
  ) async {
    final root = Directory('build/test_tmp/reader_initial_page')
      ..createSync(recursive: true);
    addTearDown(() {
      if (root.existsSync()) root.deleteSync(recursive: true);
    });
    final pageDirectory = Directory(
      '${root.path}${Platform.pathSeparator}comic_reader_test${Platform.pathSeparator}pages',
    )..createSync(recursive: true);
    final pageBytes = File('test/goldens/empty_library.png').readAsBytesSync();
    for (var index = 0; index < 8; index++) {
      File(
        '${pageDirectory.path}${Platform.pathSeparator}${index.toString().padLeft(5, '0')}.png',
      ).writeAsBytesSync(pageBytes);
    }
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final book = ComicBook(
      id: 'reader-test',
      title: '测试漫画',
      directoryName: 'comic_reader_test',
      importedAt: DateTime(2026),
      chapters: <ComicChapter>[
        ComicChapter(
          title: '正文',
          pages: List<String>.generate(
            8,
            (index) => 'pages/${index.toString().padLeft(5, '0')}.png',
          ),
        ),
      ],
      totalBytes: 8,
      currentPage: 3,
    );
    final controller = AppController(
      repository: _FakeLibraryRepository(root, book),
    );
    await controller.initialize();

    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(controller: controller, book: book, initialPage: 3),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(controller.latestVersionOf(book).currentPage, 3);
    final reader = tester.widget<ScrollablePositionedList>(
      find.byType(ScrollablePositionedList),
    );
    expect(reader.initialScrollIndex, 3);
  });
}

class _FakeLibraryRepository extends LibraryRepository {
  _FakeLibraryRepository(this.root, ComicBook book)
    : _books = <ComicBook>[book];

  final Directory root;
  List<ComicBook> _books;

  @override
  Future<Directory> libraryDirectory() async {
    return root;
  }

  @override
  Future<List<ComicBook>> loadBooks() async {
    return List<ComicBook>.of(_books);
  }

  @override
  Future<List<LibraryFolder>> loadFolders() async {
    return <LibraryFolder>[];
  }

  @override
  Future<bool> loadDarkMode() async {
    return false;
  }

  @override
  Future<void> saveBooks(List<ComicBook> books) async {
    _books = List<ComicBook>.of(books);
  }
}
