import 'package:flutter_test/flutter_test.dart';
import 'package:panelly/models/comic_book.dart';

void main() {
  test('ComicBook JSON round-trip keeps chapters and progress', () {
    final book = ComicBook(
      id: '42',
      title: '测试漫画',
      directoryName: 'comic_42',
      importedAt: DateTime.utc(2026, 8, 13),
      chapters: const <ComicChapter>[
        ComicChapter(
          title: '第一话',
          pages: <String>['pages/000/00000.webp', 'pages/000/00001.webp'],
        ),
      ],
      totalBytes: 2048,
      currentPage: 1,
      readingMode: ReadingMode.swipeRight,
      bookmarks: const <int>[0, 1],
      folderId: 'folder-1',
      blurCover: true,
      hideTitle: true,
    );

    final restored = ComicBook.fromJson(book.toJson());

    expect(restored.title, book.title);
    expect(restored.pageCount, 2);
    expect(restored.currentPage, 1);
    expect(restored.progress, 1);
    expect(restored.chapters.single.title, '第一话');
    expect(restored.readingMode, ReadingMode.swipeRight);
    expect(restored.bookmarks, <int>[0, 1]);
    expect(restored.folderId, 'folder-1');
    expect(restored.blurCover, isTrue);
    expect(restored.hideTitle, isTrue);
    expect(restored.displayTitle, '已隐藏名称');
  });

  test('old ComicBook JSON defaults to continuous mode and no bookmarks', () {
    final restored = ComicBook.fromJson(<String, dynamic>{
      'id': 'old',
      'title': '旧漫画',
      'directoryName': 'comic_old',
      'importedAt': '2026-08-13T00:00:00.000Z',
      'chapters': <Map<String, dynamic>>[
        <String, dynamic>{
          'title': '正文',
          'pages': <String>['pages/000/00000.webp'],
        },
      ],
      'totalBytes': 100,
      'currentPage': 0,
    });

    expect(restored.readingMode, ReadingMode.continuous);
    expect(restored.bookmarks, isEmpty);
    expect(restored.folderId, isNull);
    expect(restored.blurCover, isFalse);
    expect(restored.hideTitle, isFalse);
  });
}
