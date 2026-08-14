import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panelly/app_controller.dart';
import 'package:panelly/models/comic_book.dart';
import 'package:panelly/models/library_folder.dart';
import 'package:panelly/screens/home_shell.dart';
import 'package:panelly/services/archive_organizer.dart';
import 'package:panelly/services/incoming_archive_service.dart';
import 'package:panelly/services/library_repository.dart';

void main() {
  testWidgets('an incoming archive is imported and its cache copy is deleted', (
    tester,
  ) async {
    final root = Directory('build/test_tmp/incoming_archive_import')
      ..createSync(recursive: true);
    addTearDown(() {
      if (root.existsSync()) root.deleteSync(recursive: true);
    });
    final incoming = File('${root.path}${Platform.pathSeparator}shared.cbz')
      ..writeAsBytesSync(<int>[1, 2, 3]);
    final source = _FakeIncomingArchiveSource();
    final controller = AppController(
      repository: _FakeLibraryRepository(root),
      organizer: _FakeArchiveOrganizer(),
    );
    await controller.initialize();

    await tester.pumpWidget(
      MaterialApp(
        home: HomeShell(controller: controller, incomingArchiveSource: source),
      ),
    );
    source.add(IncomingArchiveReady(incoming.path));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(controller.books, hasLength(1));
    expect(controller.books.single.title, 'QQ 测试漫画');
    expect(incoming.existsSync(), isFalse);
    expect(find.textContaining('已整理《QQ 测试漫画》'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await source.dispose();
  });
}

class _FakeIncomingArchiveSource implements IncomingArchiveSource {
  final _events = StreamController<IncomingArchiveEvent>.broadcast();

  @override
  Stream<IncomingArchiveEvent> get events => _events.stream;

  void add(IncomingArchiveEvent event) => _events.add(event);

  @override
  Future<void> start() async {}

  @override
  Future<void> dispose() => _events.close();
}

class _FakeArchiveOrganizer extends ArchiveOrganizer {
  @override
  Future<ComicBook> importArchive({
    required String sourcePath,
    required Directory libraryRoot,
    ImportProgressCallback? onProgress,
  }) async {
    onProgress?.call(
      const ImportProgress(
        label: '整理完成',
        value: 1,
        completedPages: 0,
        totalPages: 0,
      ),
    );
    return ComicBook(
      id: 'incoming-test',
      title: 'QQ 测试漫画',
      directoryName: 'comic_incoming_test',
      importedAt: DateTime(2026, 8, 14),
      chapters: const <ComicChapter>[],
      totalBytes: 3,
    );
  }
}

class _FakeLibraryRepository extends LibraryRepository {
  _FakeLibraryRepository(this.root);

  final Directory root;
  List<ComicBook> books = <ComicBook>[];

  @override
  Future<Directory> libraryDirectory() async => root;

  @override
  Future<List<ComicBook>> loadBooks() async => List<ComicBook>.of(books);

  @override
  Future<List<LibraryFolder>> loadFolders() async => <LibraryFolder>[];

  @override
  Future<bool> loadDarkMode() async => false;

  @override
  Future<void> saveBooks(List<ComicBook> value) async {
    books = List<ComicBook>.of(value);
  }
}
