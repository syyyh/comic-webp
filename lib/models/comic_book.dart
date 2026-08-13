class ComicChapter {
  const ComicChapter({required this.title, required this.pages});

  final String title;
  final List<String> pages;

  Map<String, Object?> toJson() => <String, Object?>{
    'title': title,
    'pages': pages,
  };

  factory ComicChapter.fromJson(Map<String, dynamic> json) {
    return ComicChapter(
      title: json['title'] as String,
      pages: (json['pages'] as List<dynamic>).cast<String>(),
    );
  }
}

enum ReadingMode { continuous, swipeLeft, swipeRight }

const _unchangedFolder = Object();

class ComicBook {
  const ComicBook({
    required this.id,
    required this.title,
    required this.directoryName,
    required this.importedAt,
    required this.chapters,
    required this.totalBytes,
    this.currentPage = 0,
    this.readingMode = ReadingMode.continuous,
    this.bookmarks = const <int>[],
    this.folderId,
    this.blurCover = false,
    this.hideTitle = false,
  });

  final String id;
  final String title;
  final String directoryName;
  final DateTime importedAt;
  final List<ComicChapter> chapters;
  final int totalBytes;
  final int currentPage;
  final ReadingMode readingMode;
  final List<int> bookmarks;
  final String? folderId;
  final bool blurCover;
  final bool hideTitle;

  String get displayTitle => hideTitle ? '已隐藏名称' : title;

  List<String> get pages => <String>[
    for (final chapter in chapters) ...chapter.pages,
  ];

  int get pageCount => pages.length;

  double get progress {
    if (pageCount == 0) return 0;
    return ((currentPage + 1) / pageCount).clamp(0, 1);
  }

  ComicBook copyWith({
    int? currentPage,
    ReadingMode? readingMode,
    List<int>? bookmarks,
    Object? folderId = _unchangedFolder,
    bool? blurCover,
    bool? hideTitle,
  }) {
    return ComicBook(
      id: id,
      title: title,
      directoryName: directoryName,
      importedAt: importedAt,
      chapters: chapters,
      totalBytes: totalBytes,
      currentPage: currentPage ?? this.currentPage,
      readingMode: readingMode ?? this.readingMode,
      bookmarks: bookmarks ?? this.bookmarks,
      folderId: identical(folderId, _unchangedFolder)
          ? this.folderId
          : folderId as String?,
      blurCover: blurCover ?? this.blurCover,
      hideTitle: hideTitle ?? this.hideTitle,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'title': title,
    'directoryName': directoryName,
    'importedAt': importedAt.toIso8601String(),
    'chapters': chapters.map((chapter) => chapter.toJson()).toList(),
    'totalBytes': totalBytes,
    'currentPage': currentPage,
    'readingMode': readingMode.name,
    'bookmarks': bookmarks,
    'folderId': folderId,
    'blurCover': blurCover,
    'hideTitle': hideTitle,
  };

  factory ComicBook.fromJson(Map<String, dynamic> json) {
    final chapters = (json['chapters'] as List<dynamic>)
        .map(
          (chapter) => ComicChapter.fromJson(chapter as Map<String, dynamic>),
        )
        .toList();
    final pageCount = chapters.fold<int>(
      0,
      (sum, chapter) => sum + chapter.pages.length,
    );
    final savedMode = json['readingMode'] as String?;
    final readingMode = ReadingMode.values.firstWhere(
      (mode) => mode.name == savedMode,
      orElse: () => ReadingMode.continuous,
    );
    final bookmarks =
        (json['bookmarks'] as List<dynamic>? ?? <dynamic>[])
            .whereType<int>()
            .where((page) => page >= 0 && page < pageCount)
            .toSet()
            .toList()
          ..sort();

    return ComicBook(
      id: json['id'] as String,
      title: json['title'] as String,
      directoryName: json['directoryName'] as String,
      importedAt: DateTime.parse(json['importedAt'] as String),
      chapters: chapters,
      totalBytes: json['totalBytes'] as int? ?? 0,
      currentPage: json['currentPage'] as int? ?? 0,
      readingMode: readingMode,
      bookmarks: bookmarks,
      folderId: json['folderId'] as String?,
      blurCover: json['blurCover'] as bool? ?? false,
      hideTitle: json['hideTitle'] as bool? ?? false,
    );
  }
}
