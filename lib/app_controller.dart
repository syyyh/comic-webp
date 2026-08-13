import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'models/comic_book.dart';
import 'models/library_folder.dart';
import 'services/archive_organizer.dart';
import 'services/library_repository.dart';
import 'services/thumbnail_service.dart';

class AppController extends ChangeNotifier {
  AppController({LibraryRepository? repository, ArchiveOrganizer? organizer})
    : repository = repository ?? LibraryRepository(),
      organizer = organizer ?? ArchiveOrganizer();

  final LibraryRepository repository;
  final ArchiveOrganizer organizer;

  List<ComicBook> _books = <ComicBook>[];
  List<LibraryFolder> _folders = <LibraryFolder>[];
  Directory? _libraryDirectory;
  bool _isReady = false;
  bool _isDarkMode = false;
  bool _isImporting = false;
  ImportProgress? _importProgress;

  List<ComicBook> get books => List.unmodifiable(_books);
  List<LibraryFolder> get folders => List.unmodifiable(_folders);
  Directory? get libraryDirectory => _libraryDirectory;
  bool get isReady => _isReady;
  bool get isDarkMode => _isDarkMode;
  bool get isImporting => _isImporting;
  ImportProgress? get importProgress => _importProgress;

  int get totalPages =>
      _books.fold<int>(0, (sum, book) => sum + book.pageCount);
  int get totalBytes =>
      _books.fold<int>(0, (sum, book) => sum + book.totalBytes);

  Future<void> initialize() async {
    _libraryDirectory = await repository.libraryDirectory();
    final results = await Future.wait<Object>(<Future<Object>>[
      repository.loadBooks(),
      repository.loadFolders(),
      repository.loadDarkMode(),
    ]);
    _books = results[0] as List<ComicBook>;
    _folders = results[1] as List<LibraryFolder>;
    _isDarkMode = results[2] as bool;
    final folderIds = _folders.map((folder) => folder.id).toSet();
    final needsFolderRepair = _books.any(
      (book) => book.folderId != null && !folderIds.contains(book.folderId),
    );
    _books = _books
        .map(
          (book) => book.folderId == null || folderIds.contains(book.folderId)
              ? book
              : book.copyWith(folderId: null),
        )
        .toList();
    if (needsFolderRepair) await repository.saveBooks(_books);
    _sortBooks();
    _isReady = true;
    notifyListeners();
    unawaited(_generateMissingThumbnails());
  }

  Future<void> _generateMissingThumbnails() async {
    final root = _libraryDirectory;
    if (root == null) return;
    var generated = false;
    for (final book in _books) {
      final thumbnail = File(
        ThumbnailService.thumbnailPath(
          Directory(p.join(root.path, book.directoryName)),
        ),
      );
      if (thumbnail.existsSync()) continue;
      await ThumbnailService.createForBook(book, root);
      generated = generated || thumbnail.existsSync();
      await Future<void>.delayed(Duration.zero);
    }
    if (generated) notifyListeners();
  }

  String pagePath(ComicBook book, String relativePath) {
    final root = _libraryDirectory;
    if (root == null) return '';
    return p.join(root.path, book.directoryName, relativePath);
  }

  Future<ComicBook> importArchive(String sourcePath) async {
    final root = _libraryDirectory ?? await repository.libraryDirectory();
    _libraryDirectory = root;
    _isImporting = true;
    _importProgress = const ImportProgress(
      label: '准备导入',
      value: 0,
      completedPages: 0,
      totalPages: 0,
    );
    notifyListeners();

    final progressThrottle = _ImportProgressThrottle();
    try {
      final book = await organizer.importArchive(
        sourcePath: sourcePath,
        libraryRoot: root,
        onProgress: (progress) {
          _importProgress = progress;
          if (progressThrottle.shouldNotify(progress)) notifyListeners();
        },
      );
      await ThumbnailService.createForBook(book, root);
      _books = <ComicBook>[book, ..._books];
      _sortBooks();
      await repository.saveBooks(_books);
      return book;
    } finally {
      _isImporting = false;
      notifyListeners();
    }
  }

  Future<ComicBook> importDirectory(String sourcePath) async {
    final root = _libraryDirectory ?? await repository.libraryDirectory();
    _libraryDirectory = root;
    _isImporting = true;
    _importProgress = const ImportProgress(
      label: '准备导入文件夹',
      value: 0,
      completedPages: 0,
      totalPages: 0,
    );
    notifyListeners();
    final progressThrottle = _ImportProgressThrottle();
    try {
      final book = await organizer.importDirectory(
        sourcePath: sourcePath,
        libraryRoot: root,
        onProgress: (progress) {
          _importProgress = progress;
          if (progressThrottle.shouldNotify(progress)) notifyListeners();
        },
      );
      await ThumbnailService.createForBook(book, root);
      _books = <ComicBook>[book, ..._books];
      _sortBooks();
      await repository.saveBooks(_books);
      return book;
    } finally {
      _isImporting = false;
      notifyListeners();
    }
  }

  Future<void> updateReadingProgress(ComicBook book, int pageIndex) async {
    final index = _books.indexWhere((candidate) => candidate.id == book.id);
    if (index < 0 || _books[index].currentPage == pageIndex) return;
    _books[index] = _books[index].copyWith(currentPage: pageIndex);
    await repository.saveBooks(_books);
    notifyListeners();
  }

  Future<void> updateReadingMode(ComicBook book, ReadingMode mode) async {
    final index = _books.indexWhere((candidate) => candidate.id == book.id);
    if (index < 0 || _books[index].readingMode == mode) return;
    _books[index] = _books[index].copyWith(readingMode: mode);
    await repository.saveBooks(_books);
    notifyListeners();
  }

  Future<void> setBookmark(
    ComicBook book,
    int pageIndex, {
    required bool bookmarked,
  }) async {
    final index = _books.indexWhere((candidate) => candidate.id == book.id);
    if (index < 0 || pageIndex < 0 || pageIndex >= _books[index].pageCount) {
      return;
    }
    final bookmarks = _books[index].bookmarks.toSet();
    bookmarked ? bookmarks.add(pageIndex) : bookmarks.remove(pageIndex);
    final sorted = bookmarks.toList()..sort();
    _books[index] = _books[index].copyWith(bookmarks: sorted);
    await repository.saveBooks(_books);
    notifyListeners();
  }

  ComicBook latestVersionOf(ComicBook book) {
    return _books.firstWhere(
      (candidate) => candidate.id == book.id,
      orElse: () => book,
    );
  }

  List<ComicBook> booksInFolder(String? folderId) {
    return _books.where((book) => book.folderId == folderId).toList();
  }

  LibraryFolder? folderById(String id) {
    for (final folder in _folders) {
      if (folder.id == id) return folder;
    }
    return null;
  }

  Future<LibraryFolder> createFolder(String name) async {
    final cleanName = name.trim();
    if (cleanName.isEmpty) throw ArgumentError('文件夹名称不能为空');
    final timestamp = DateTime.now();
    final folder = LibraryFolder(
      id: timestamp.microsecondsSinceEpoch.toString(),
      name: cleanName,
      createdAt: timestamp,
    );
    _folders = <LibraryFolder>[..._folders, folder];
    await repository.saveFolders(_folders);
    notifyListeners();
    return folder;
  }

  Future<void> renameFolder(LibraryFolder folder, String name) async {
    final cleanName = name.trim();
    if (cleanName.isEmpty) return;
    final index = _folders.indexWhere((candidate) => candidate.id == folder.id);
    if (index < 0) return;
    _folders[index] = _folders[index].copyWith(name: cleanName);
    await repository.saveFolders(_folders);
    notifyListeners();
  }

  Future<void> deleteFolder(LibraryFolder folder) async {
    _folders.removeWhere((candidate) => candidate.id == folder.id);
    _books = _books
        .map(
          (book) =>
              book.folderId == folder.id ? book.copyWith(folderId: null) : book,
        )
        .toList();
    await Future.wait<void>(<Future<void>>[
      repository.saveFolders(_folders),
      repository.saveBooks(_books),
    ]);
    notifyListeners();
  }

  Future<void> moveBooks(Set<String> bookIds, String? folderId) async {
    if (folderId != null && folderById(folderId) == null) return;
    _books = _books
        .map(
          (book) => bookIds.contains(book.id)
              ? book.copyWith(folderId: folderId)
              : book,
        )
        .toList();
    await repository.saveBooks(_books);
    notifyListeners();
  }

  Future<void> updatePrivacy(
    Set<String> bookIds, {
    bool? blurCover,
    bool? hideTitle,
  }) async {
    _books = _books
        .map(
          (book) => bookIds.contains(book.id)
              ? book.copyWith(blurCover: blurCover, hideTitle: hideTitle)
              : book,
        )
        .toList();
    await repository.saveBooks(_books);
    notifyListeners();
  }

  Future<void> deleteBook(ComicBook book) async {
    await repository.deleteBook(book);
    _books.removeWhere((candidate) => candidate.id == book.id);
    await repository.saveBooks(_books);
    notifyListeners();
  }

  Future<void> setDarkMode(bool value) async {
    if (_isDarkMode == value) return;
    _isDarkMode = value;
    notifyListeners();
    await repository.saveDarkMode(value);
  }

  void _sortBooks() {
    _books.sort((left, right) => right.importedAt.compareTo(left.importedAt));
  }
}

class _ImportProgressThrottle {
  final Stopwatch _clock = Stopwatch()..start();
  String? _lastLabel;

  bool shouldNotify(ImportProgress progress) {
    final stageChanged =
        progress.label != _lastLabel && !progress.label.startsWith('正在整理');
    final boundary =
        progress.completedPages <= 1 ||
        progress.completedPages == progress.totalPages;
    if (!stageChanged && !boundary && _clock.elapsedMilliseconds < 50) {
      return false;
    }
    _lastLabel = progress.label;
    _clock.reset();
    return true;
  }
}
