import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

import '../models/comic_book.dart';

typedef ImportProgressCallback = void Function(ImportProgress progress);

class ImportProgress {
  const ImportProgress({
    required this.label,
    required this.value,
    required this.completedPages,
    required this.totalPages,
  });

  final String label;
  final double value;
  final int completedPages;
  final int totalPages;
}

class ArchiveImportException implements Exception {
  const ArchiveImportException(this.message);

  final String message;

  @override
  String toString() => message;
}

class ArchiveOrganizer {
  static const int _maximumPageBytes = 100 * 1024 * 1024;
  static const int _maximumArchiveBytes = 4 * 1024 * 1024 * 1024;

  Future<ComicBook> importArchive({
    required String sourcePath,
    required Directory libraryRoot,
    ImportProgressCallback? onProgress,
  }) async {
    final source = File(sourcePath);
    if (!source.existsSync()) {
      throw const ArchiveImportException('找不到所选压缩包');
    }

    final extension = p.extension(sourcePath).toLowerCase();
    if (extension != '.zip' && extension != '.cbz') {
      throw const ArchiveImportException('目前仅支持 ZIP 和 CBZ 压缩包');
    }

    onProgress?.call(
      const ImportProgress(
        label: '正在检查压缩包',
        value: 0.04,
        completedPages: 0,
        totalPages: 0,
      ),
    );

    final input = InputFileStream(sourcePath);
    late final Archive archive;
    try {
      archive = ZipDecoder().decodeStream(input);
    } on Object {
      input.closeSync();
      throw const ArchiveImportException('压缩包损坏、加密或格式不受支持');
    }

    final entries = archive.files
        .where((entry) => entry.isFile && isWebpPath(entry.name))
        .where((entry) => !isJunkPath(entry.name))
        .toList();

    if (entries.isEmpty) {
      input.closeSync();
      throw const ArchiveImportException('压缩包里没有找到 WebP 漫画页');
    }

    final totalBytes = entries.fold<int>(0, (sum, entry) => sum + entry.size);
    if (totalBytes > _maximumArchiveBytes ||
        entries.any((entry) => entry.size > _maximumPageBytes)) {
      input.closeSync();
      throw const ArchiveImportException('压缩包内容过大，已停止导入');
    }

    final normalized = entries
        .map((entry) => _ComicEntry(entry, normalizeArchivePath(entry.name)))
        .toList();
    final stripped = stripSharedRoot(
      normalized.map((item) => item.path).toList(),
    );
    final byOriginalPath = <String, String>{
      for (var index = 0; index < normalized.length; index++)
        normalized[index].path: stripped[index],
    };
    normalized.sort(
      (left, right) => compareOrganizedPaths(
        byOriginalPath[left.path]!,
        byOriginalPath[right.path]!,
      ),
    );

    final timestamp = DateTime.now();
    final id = timestamp.microsecondsSinceEpoch.toString();
    final title = cleanComicTitle(p.basenameWithoutExtension(sourcePath));
    final directoryName = 'comic_$id';
    final temporary = Directory(p.join(libraryRoot.path, '.import_$id'));
    final finalDirectory = Directory(p.join(libraryRoot.path, directoryName));
    await temporary.create(recursive: true);

    final chapterPages = <String, List<String>>{};
    try {
      for (var index = 0; index < normalized.length; index++) {
        final item = normalized[index];
        final relativeSource = byOriginalPath[item.path]!;
        final chapter = inferChapterName(relativeSource);
        final chapterIndex = chapterPages.keys.toList().indexOf(chapter);
        final stableChapterIndex = chapterIndex < 0
            ? chapterPages.length
            : chapterIndex;
        final pages = chapterPages.putIfAbsent(chapter, () => <String>[]);
        final relativeOutput = p.join(
          'pages',
          stableChapterIndex.toString().padLeft(3, '0'),
          '${pages.length.toString().padLeft(5, '0')}.webp',
        );
        final outputPath = p.join(temporary.path, relativeOutput);
        await Directory(p.dirname(outputPath)).create(recursive: true);
        final output = OutputFileStream(outputPath);
        try {
          item.entry.writeContent(output);
        } finally {
          output.closeSync();
        }
        pages.add(relativeOutput);

        onProgress?.call(
          ImportProgress(
            label: '正在整理 ${index + 1} / ${normalized.length}',
            value: 0.08 + ((index + 1) / normalized.length) * 0.88,
            completedPages: index + 1,
            totalPages: normalized.length,
          ),
        );
        await Future<void>.delayed(Duration.zero);
      }

      await temporary.rename(finalDirectory.path);
    } on Object {
      if (temporary.existsSync()) {
        await temporary.delete(recursive: true);
      }
      rethrow;
    } finally {
      input.closeSync();
    }

    onProgress?.call(
      ImportProgress(
        label: '整理完成',
        value: 1,
        completedPages: normalized.length,
        totalPages: normalized.length,
      ),
    );

    return ComicBook(
      id: id,
      title: title,
      directoryName: directoryName,
      importedAt: timestamp,
      totalBytes: totalBytes,
      chapters: chapterPages.entries
          .map((entry) => ComicChapter(title: entry.key, pages: entry.value))
          .toList(),
    );
  }

  Future<ComicBook> importDirectory({
    required String sourcePath,
    required Directory libraryRoot,
    ImportProgressCallback? onProgress,
  }) async {
    final source = Directory(sourcePath);
    if (!source.existsSync()) {
      throw const ArchiveImportException('找不到所选漫画文件夹');
    }
    onProgress?.call(
      const ImportProgress(
        label: '正在扫描漫画文件夹',
        value: 0.04,
        completedPages: 0,
        totalPages: 0,
      ),
    );

    final files = <_DirectoryComicEntry>[];
    await for (final entity in source.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is! File) continue;
      final relative = normalizeArchivePath(
        p.relative(entity.path, from: source.path),
      );
      if (!isWebpPath(relative) || isJunkPath(relative)) continue;
      final size = await entity.length();
      if (size > _maximumPageBytes) {
        throw const ArchiveImportException('漫画文件夹中存在过大的页面，已停止导入');
      }
      files.add(_DirectoryComicEntry(entity, relative, size));
    }
    if (files.isEmpty) {
      throw const ArchiveImportException('文件夹里没有找到 WebP 漫画页');
    }
    final totalBytes = files.fold<int>(0, (sum, item) => sum + item.size);
    if (totalBytes > _maximumArchiveBytes) {
      throw const ArchiveImportException('漫画文件夹内容过大，已停止导入');
    }
    files.sort((left, right) => compareOrganizedPaths(left.path, right.path));

    final timestamp = DateTime.now();
    final id = timestamp.microsecondsSinceEpoch.toString();
    final directoryName = 'comic_$id';
    final temporary = Directory(p.join(libraryRoot.path, '.import_$id'));
    final finalDirectory = Directory(p.join(libraryRoot.path, directoryName));
    await temporary.create(recursive: true);
    final chapterPages = <String, List<String>>{};

    try {
      for (var index = 0; index < files.length; index++) {
        final item = files[index];
        final chapter = inferChapterName(item.path);
        final chapterIndex = chapterPages.keys.toList().indexOf(chapter);
        final stableChapterIndex = chapterIndex < 0
            ? chapterPages.length
            : chapterIndex;
        final pages = chapterPages.putIfAbsent(chapter, () => <String>[]);
        final relativeOutput = p.join(
          'pages',
          stableChapterIndex.toString().padLeft(3, '0'),
          '${pages.length.toString().padLeft(5, '0')}.webp',
        );
        final output = File(p.join(temporary.path, relativeOutput));
        await output.parent.create(recursive: true);
        await item.file.copy(output.path);
        pages.add(relativeOutput);
        onProgress?.call(
          ImportProgress(
            label: '正在整理 ${index + 1} / ${files.length}',
            value: 0.08 + ((index + 1) / files.length) * 0.88,
            completedPages: index + 1,
            totalPages: files.length,
          ),
        );
        await Future<void>.delayed(Duration.zero);
      }
      await temporary.rename(finalDirectory.path);
    } on Object {
      if (temporary.existsSync()) await temporary.delete(recursive: true);
      rethrow;
    }

    onProgress?.call(
      ImportProgress(
        label: '整理完成',
        value: 1,
        completedPages: files.length,
        totalPages: files.length,
      ),
    );
    return ComicBook(
      id: id,
      title: cleanComicTitle(p.basename(p.normalize(source.path))),
      directoryName: directoryName,
      importedAt: timestamp,
      totalBytes: totalBytes,
      chapters: chapterPages.entries
          .map((entry) => ComicChapter(title: entry.key, pages: entry.value))
          .toList(),
    );
  }

  static bool isWebpPath(String path) =>
      p.extension(path.replaceAll('\\', '/')).toLowerCase() == '.webp';

  static bool isJunkPath(String path) {
    final segments = normalizeArchivePath(path).split('/');
    return segments.any(
          (segment) => segment == '__MACOSX' || segment.startsWith('.'),
        ) ||
        segments.last.toLowerCase() == 'thumbs.db';
  }

  static String normalizeArchivePath(String path) {
    final normalized = path.replaceAll('\\', '/');
    return normalized
        .split('/')
        .where((segment) => segment.isNotEmpty && segment != '.')
        .join('/');
  }

  static List<String> stripSharedRoot(List<String> paths) {
    if (paths.isEmpty) return <String>[];
    final splitPaths = paths.map((path) => path.split('/')).toList();
    final canStrip = splitPaths.every(
      (segments) =>
          segments.length > 1 && segments.first == splitPaths.first.first,
    );
    if (!canStrip) return paths;
    return splitPaths.map((segments) => segments.skip(1).join('/')).toList();
  }

  static String inferChapterName(String path) {
    final segments = normalizeArchivePath(path).split('/');
    if (segments.length < 2) return '正文';
    return cleanLabel(segments.first);
  }

  static String cleanComicTitle(String value) =>
      cleanLabel(value.replaceFirst(RegExp(r'^[\s._-]+'), ''));

  static String cleanLabel(String value) {
    final spaced = value
        .replaceAll(RegExp(r'[_]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return spaced.isEmpty ? '未命名漫画' : spaced;
  }

  static int naturalCompare(String left, String right) {
    final leftParts = _naturalParts(left);
    final rightParts = _naturalParts(right);
    final length = leftParts.length < rightParts.length
        ? leftParts.length
        : rightParts.length;
    for (var index = 0; index < length; index++) {
      final a = leftParts[index];
      final b = rightParts[index];
      final aNumber = int.tryParse(a);
      final bNumber = int.tryParse(b);
      final comparison = aNumber != null && bNumber != null
          ? aNumber.compareTo(bNumber)
          : a.toLowerCase().compareTo(b.toLowerCase());
      if (comparison != 0) return comparison;
    }
    return leftParts.length.compareTo(rightParts.length);
  }

  static int compareOrganizedPaths(String left, String right) {
    final leftChapter = inferChapterName(left);
    final rightChapter = inferChapterName(right);
    if (leftChapter == rightChapter) return naturalCompare(left, right);
    if (leftChapter == '正文') return -1;
    if (rightChapter == '正文') return 1;
    return naturalCompare(leftChapter, rightChapter);
  }

  static List<String> _naturalParts(String value) {
    return RegExp(
      r'\d+|\D+',
    ).allMatches(value).map((match) => match.group(0)!).toList();
  }
}

class _ComicEntry {
  const _ComicEntry(this.entry, this.path);

  final ArchiveFile entry;
  final String path;
}

class _DirectoryComicEntry {
  const _DirectoryComicEntry(this.file, this.path, this.size);

  final File file;
  final String path;
  final int size;
}
