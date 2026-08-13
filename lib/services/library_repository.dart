import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/comic_book.dart';
import '../models/library_folder.dart';

class LibraryRepository {
  static const _libraryKey = 'comic_library_v1';
  static const _themeKey = 'theme_mode_v1';
  static const _foldersKey = 'library_folders_v1';

  Future<Directory> libraryDirectory() async {
    final documents = await getApplicationDocumentsDirectory();
    final directory = Directory(p.join(documents.path, 'comic_library'));
    await directory.create(recursive: true);
    return directory;
  }

  Future<List<ComicBook>> loadBooks() async {
    final preferences = await SharedPreferences.getInstance();
    final encoded = preferences.getString(_libraryKey);
    if (encoded == null) return <ComicBook>[];

    try {
      final values = jsonDecode(encoded) as List<dynamic>;
      final books = values
          .map((value) => ComicBook.fromJson(value as Map<String, dynamic>))
          .toList();
      final root = await libraryDirectory();
      return books
          .where(
            (book) =>
                Directory(p.join(root.path, book.directoryName)).existsSync(),
          )
          .toList();
    } on FormatException {
      return <ComicBook>[];
    }
  }

  Future<void> saveBooks(List<ComicBook> books) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      _libraryKey,
      jsonEncode(books.map((book) => book.toJson()).toList()),
    );
  }

  Future<List<LibraryFolder>> loadFolders() async {
    final preferences = await SharedPreferences.getInstance();
    final encoded = preferences.getString(_foldersKey);
    if (encoded == null) return <LibraryFolder>[];
    try {
      return (jsonDecode(encoded) as List<dynamic>)
          .map((value) => LibraryFolder.fromJson(value as Map<String, dynamic>))
          .toList();
    } on FormatException {
      return <LibraryFolder>[];
    }
  }

  Future<void> saveFolders(List<LibraryFolder> folders) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      _foldersKey,
      jsonEncode(folders.map((folder) => folder.toJson()).toList()),
    );
  }

  Future<void> deleteBook(ComicBook book) async {
    final root = await libraryDirectory();
    final directory = Directory(p.join(root.path, book.directoryName));
    if (directory.existsSync()) {
      await directory.delete(recursive: true);
    }
  }

  Future<String> resolvePage(ComicBook book, String relativePath) async {
    final root = await libraryDirectory();
    return p.join(root.path, book.directoryName, relativePath);
  }

  Future<bool> loadDarkMode() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getBool(_themeKey) ?? false;
  }

  Future<void> saveDarkMode(bool value) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_themeKey, value);
  }
}
