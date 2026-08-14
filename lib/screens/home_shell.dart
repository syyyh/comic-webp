import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../app_controller.dart';
import '../models/comic_book.dart';
import '../models/library_folder.dart';
import '../services/archive_organizer.dart';
import '../services/incoming_archive_service.dart';
import '../widgets/comic_cover.dart';
import 'comic_detail_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({
    super.key,
    required this.controller,
    this.incomingArchiveSource,
  });

  final AppController controller;
  final IncomingArchiveSource? incomingArchiveSource;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _selectedIndex = 0;
  final _selectedBooks = <String>{};
  final _incomingEvents = Queue<IncomingArchiveEvent>();
  late final IncomingArchiveSource _incomingArchiveSource;
  late final bool _ownsIncomingArchiveSource;
  StreamSubscription<IncomingArchiveEvent>? _incomingSubscription;
  bool _processingIncomingEvents = false;

  bool get _isSelecting => _selectedBooks.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _ownsIncomingArchiveSource = widget.incomingArchiveSource == null;
    _incomingArchiveSource =
        widget.incomingArchiveSource ?? IncomingArchiveService();
    _incomingSubscription = _incomingArchiveSource.events.listen(
      _enqueueIncomingEvent,
    );
    unawaited(_incomingArchiveSource.start());
  }

  @override
  void dispose() {
    unawaited(_incomingSubscription?.cancel());
    if (_ownsIncomingArchiveSource) {
      unawaited(_incomingArchiveSource.dispose());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: IndexedStack(
          index: _selectedIndex,
          children: [
            _LibraryPage(
              controller: widget.controller,
              selectedBooks: _selectedBooks,
              isSelecting: _isSelecting,
              onImport: _chooseImportSource,
              onToggleSelected: _toggleSelected,
              onOpenFolder: _openFolder,
              onCreateFolder: _createFolder,
            ),
            _SettingsPage(controller: widget.controller),
          ],
        ),
      ),
      bottomNavigationBar: _isSelecting
          ? _SelectionBar(
              count: _selectedBooks.length,
              onClose: () => setState(_selectedBooks.clear),
              onActions: _showSelectionActions,
            )
          : NavigationBar(
              selectedIndex: _selectedIndex,
              onDestinationSelected: (value) =>
                  setState(() => _selectedIndex = value),
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.collections_bookmark_outlined),
                  selectedIcon: Icon(Icons.collections_bookmark_rounded),
                  label: '书库',
                ),
                NavigationDestination(
                  icon: Icon(Icons.tune_outlined),
                  selectedIcon: Icon(Icons.tune_rounded),
                  label: '设置',
                ),
              ],
            ),
    );
  }

  void _toggleSelected(ComicBook book) {
    setState(() {
      if (!_selectedBooks.add(book.id)) _selectedBooks.remove(book.id);
    });
  }

  Future<void> _showSelectionActions() async {
    final selected = Set<String>.from(_selectedBooks);
    final selectedBooks = widget.controller.books
        .where((book) => selected.contains(book.id))
        .toList();
    final allTitlesHidden = selectedBooks.every((book) => book.hideTitle);
    final allCoversBlurred = selectedBooks.every((book) => book.blurCover);
    final action = await showModalBottomSheet<_SelectionAction>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(
                allTitlesHidden
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
              ),
              title: Text(allTitlesHidden ? '恢复名称' : '隐藏名称'),
              subtitle: Text(allTitlesHidden ? '重新在书架显示原名称' : '书架上显示为已隐藏名称'),
              onTap: () => Navigator.pop(context, _SelectionAction.toggleTitle),
            ),
            ListTile(
              leading: Icon(
                allCoversBlurred
                    ? Icons.blur_off_outlined
                    : Icons.blur_on_outlined,
              ),
              title: Text(allCoversBlurred ? '恢复封面' : '模糊封面'),
              subtitle: Text(allCoversBlurred ? '重新显示清晰封面' : '书架封面保持可辨识但降低细节'),
              onTap: () => Navigator.pop(context, _SelectionAction.toggleCover),
            ),
            ListTile(
              leading: const Icon(Icons.folder_outlined),
              title: const Text('移动到文件夹'),
              onTap: () => Navigator.pop(context, _SelectionAction.move),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case _SelectionAction.toggleTitle:
        await widget.controller.updatePrivacy(
          selected,
          hideTitle: !allTitlesHidden,
        );
      case _SelectionAction.toggleCover:
        await widget.controller.updatePrivacy(
          selected,
          blurCover: !allCoversBlurred,
        );
      case _SelectionAction.move:
        await _moveBooks(selected);
    }
    if (mounted) setState(_selectedBooks.clear);
  }

  Future<void> _moveBooks(Set<String> ids) async {
    final target = await showModalBottomSheet<String?>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.only(bottom: 18),
          children: [
            const ListTile(title: Text('选择目标文件夹')),
            ListTile(
              leading: const Icon(Icons.collections_bookmark_outlined),
              title: const Text('全部书库'),
              onTap: () => Navigator.pop(context, ''),
            ),
            ...widget.controller.folders.map(
              (folder) => ListTile(
                leading: const Icon(Icons.folder_outlined),
                title: Text(folder.name),
                onTap: () => Navigator.pop(context, folder.id),
              ),
            ),
          ],
        ),
      ),
    );
    if (!mounted || target == null) return;
    await widget.controller.moveBooks(ids, target.isEmpty ? null : target);
  }

  Future<void> _createFolder() async {
    final name = await _folderNameDialog('新建文件夹');
    if (name != null) await widget.controller.createFolder(name);
  }

  Future<void> _openFolder(String? id) async {
    if (id == null) return;
    final folder = widget.controller.folderById(id);
    if (folder == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) =>
            FolderScreen(controller: widget.controller, folder: folder),
      ),
    );
  }

  Future<String?> _folderNameDialog(String title) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 40,
          decoration: const InputDecoration(labelText: '文件夹名称'),
          onSubmitted: (value) => Navigator.pop(context, value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();
    return result?.isEmpty == true ? null : result;
  }

  Future<void> _chooseImportSource() async {
    if (widget.controller.isImporting) return;
    final source = await showModalBottomSheet<_ImportSource>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.folder_zip_outlined),
              title: const Text('漫画压缩包'),
              subtitle: const Text('ZIP 或 CBZ，自动解压并整理 WebP'),
              onTap: () => Navigator.pop(context, _ImportSource.archive),
            ),
            ListTile(
              leading: const Icon(Icons.folder_copy_outlined),
              title: const Text('漫画文件夹'),
              subtitle: const Text('递归查找 WebP，并按子文件夹分章'),
              onTap: () => Navigator.pop(context, _ImportSource.directory),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;
    if (source == _ImportSource.archive) {
      await _pickArchive();
    } else {
      await _pickDirectory();
    }
  }

  Future<void> _pickArchive() async {
    if (widget.controller.isImporting) return;
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const <String>['zip', 'cbz'],
      allowMultiple: false,
      withData: false,
    );
    final path = result?.files.single.path;
    if (path == null || !mounted) return;
    await _runImport(() => widget.controller.importArchive(path));
  }

  Future<void> _pickDirectory() async {
    if (widget.controller.isImporting) return;
    final path = await FilePicker.platform.getDirectoryPath(
      dialogTitle: '选择漫画文件夹',
      lockParentWindow: true,
    );
    if (path == null || !mounted) return;
    await _runImport(() => widget.controller.importDirectory(path));
  }

  Future<void> _runImport(Future<ComicBook> Function() import) async {
    showModalBottomSheet<void>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      builder: (context) => _ImportProgressSheet(controller: widget.controller),
    );
    try {
      final book = await import();
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已整理《${book.title}》，共 ${book.pageCount} 页')),
      );
    } on ArchiveImportException catch (error) {
      if (!mounted) return;
      Navigator.of(context).pop();
      _showError(error.message);
    } on Object {
      if (!mounted) return;
      Navigator.of(context).pop();
      _showError('导入没有完成，请确认压缩包未损坏且空间充足');
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  void _enqueueIncomingEvent(IncomingArchiveEvent event) {
    _incomingEvents.add(event);
    _scheduleIncomingProcessing();
  }

  void _scheduleIncomingProcessing() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_processIncomingEvents());
    });
  }

  Future<void> _processIncomingEvents() async {
    if (_processingIncomingEvents || !mounted) return;
    _processingIncomingEvents = true;
    try {
      while (_incomingEvents.isNotEmpty && mounted) {
        final event = _incomingEvents.removeFirst();
        if (event is IncomingArchiveFailure) {
          _showError(event.message);
          continue;
        }
        if (event is! IncomingArchiveReady) continue;

        while (widget.controller.isImporting && mounted) {
          await Future<void>.delayed(const Duration(milliseconds: 150));
        }
        if (!mounted) return;

        try {
          await _runImport(() => widget.controller.importArchive(event.path));
        } finally {
          final temporary = File(event.path);
          try {
            if (temporary.existsSync()) temporary.deleteSync();
            final parent = temporary.parent;
            if (p.basename(parent.parent.path) == 'incoming_archives' &&
                parent.existsSync()) {
              parent.deleteSync();
            }
          } on FileSystemException {
            // The cache directory can safely clean up a locked file later.
          }
        }
      }
    } finally {
      _processingIncomingEvents = false;
      if (_incomingEvents.isNotEmpty && mounted) {
        _scheduleIncomingProcessing();
      }
    }
  }
}

enum _SelectionAction { toggleTitle, toggleCover, move }

enum _ImportSource { archive, directory }

class _LibraryPage extends StatelessWidget {
  const _LibraryPage({
    required this.controller,
    required this.selectedBooks,
    required this.isSelecting,
    required this.onImport,
    required this.onToggleSelected,
    required this.onOpenFolder,
    required this.onCreateFolder,
  });

  final AppController controller;
  final Set<String> selectedBooks;
  final bool isSelecting;
  final VoidCallback onImport;
  final ValueChanged<ComicBook> onToggleSelected;
  final ValueChanged<String?> onOpenFolder;
  final VoidCallback onCreateFolder;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final books = controller.booksInFolder(null);
        return CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
              sliver: SliverToBoxAdapter(
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '漫匣',
                            style: Theme.of(context).textTheme.displaySmall,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            books.isEmpty
                                ? '你的离线漫画书架'
                                : '${books.length} 本漫画 · ${books.fold<int>(0, (sum, book) => sum + book.pageCount)} 页',
                            style: Theme.of(context).textTheme.bodyLarge
                                ?.copyWith(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: onCreateFolder,
                      tooltip: '新建文件夹',
                      icon: const Icon(Icons.create_new_folder_outlined),
                    ),
                    IconButton.filled(
                      onPressed: onImport,
                      tooltip: '导入压缩包',
                      icon: const Icon(Icons.add_rounded),
                    ),
                  ],
                ),
              ),
            ),
            if (controller.folders.isNotEmpty)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 28, 20, 0),
                sliver: SliverToBoxAdapter(
                  child: _FolderStrip(
                    controller: controller,
                    onOpenFolder: onOpenFolder,
                  ),
                ),
              ),
            if (books.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _EmptyLibrary(onImport: onImport),
              )
            else ...[
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 30, 20, 12),
                sliver: SliverToBoxAdapter(
                  child: Text(
                    '最近整理',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
                sliver: SliverGrid.builder(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 24,
                    crossAxisSpacing: 16,
                    childAspectRatio: .56,
                  ),
                  itemCount: books.length,
                  itemBuilder: (context, index) => _ComicTile(
                    controller: controller,
                    book: books[index],
                    selected: selectedBooks.contains(books[index].id),
                    isSelecting: isSelecting,
                    onToggleSelected: onToggleSelected,
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _FolderStrip extends StatelessWidget {
  const _FolderStrip({required this.controller, required this.onOpenFolder});
  final AppController controller;
  final ValueChanged<String?> onOpenFolder;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 88,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: controller.folders.length,
        separatorBuilder: (context, index) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final folder = controller.folders[index];
          final books = controller.booksInFolder(folder.id);
          return Hero(
            tag: 'folder-${folder.id}',
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => onOpenFolder(folder.id),
                child: Container(
                  width: 180,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.folder_rounded,
                        color: Theme.of(
                          context,
                        ).colorScheme.onSecondaryContainer,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              folder.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSecondaryContainer,
                                  ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${books.length} 本',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSecondaryContainer,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class FolderScreen extends StatefulWidget {
  const FolderScreen({
    super.key,
    required this.controller,
    required this.folder,
  });

  final AppController controller;
  final LibraryFolder folder;

  @override
  State<FolderScreen> createState() => _FolderScreenState();
}

class _FolderScreenState extends State<FolderScreen> {
  final _selectedBooks = <String>{};

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final folder = widget.controller.folderById(widget.folder.id);
        if (folder == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && Navigator.of(context).canPop()) {
              Navigator.pop(context);
            }
          });
          return const Scaffold();
        }
        final books = widget.controller.booksInFolder(folder.id);
        return Scaffold(
          appBar: AppBar(
            title: Text(folder.name),
            actions: [
              PopupMenuButton<String>(
                onSelected: (value) => _handleFolderMenu(folder, value),
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 'rename', child: Text('重命名')),
                  PopupMenuItem(value: 'delete', child: Text('删除文件夹')),
                ],
              ),
            ],
          ),
          body: CustomScrollView(
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                sliver: SliverToBoxAdapter(
                  child: Hero(
                    tag: 'folder-${folder.id}',
                    child: Material(
                      color: Colors.transparent,
                      child: Container(
                        height: 112,
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Theme.of(
                            context,
                          ).colorScheme.secondaryContainer,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.folder_rounded,
                              size: 46,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSecondaryContainer,
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    folder.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context)
                                        .textTheme
                                        .headlineSmall
                                        ?.copyWith(
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.onSecondaryContainer,
                                        ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${books.length} 本漫画',
                                    style: TextStyle(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSecondaryContainer,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (books.isEmpty)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(child: Text('这个文件夹还是空的')),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                  sliver: SliverGrid.builder(
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          mainAxisSpacing: 24,
                          crossAxisSpacing: 16,
                          childAspectRatio: .56,
                        ),
                    itemCount: books.length,
                    itemBuilder: (context, index) => _ComicTile(
                      controller: widget.controller,
                      book: books[index],
                      selected: _selectedBooks.contains(books[index].id),
                      isSelecting: _selectedBooks.isNotEmpty,
                      onToggleSelected: _toggleSelected,
                    ),
                  ),
                ),
            ],
          ),
          bottomNavigationBar: _selectedBooks.isEmpty
              ? null
              : _SelectionBar(
                  count: _selectedBooks.length,
                  onClose: () => setState(_selectedBooks.clear),
                  onActions: _showActions,
                ),
        );
      },
    );
  }

  void _toggleSelected(ComicBook book) {
    setState(() {
      if (!_selectedBooks.add(book.id)) _selectedBooks.remove(book.id);
    });
  }

  Future<void> _showActions() async {
    final ids = Set<String>.from(_selectedBooks);
    final books = widget.controller.books
        .where((book) => ids.contains(book.id))
        .toList();
    final allTitlesHidden = books.every((book) => book.hideTitle);
    final allCoversBlurred = books.every((book) => book.blurCover);
    final action = await showModalBottomSheet<_SelectionAction>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(
                allTitlesHidden
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
              ),
              title: Text(allTitlesHidden ? '恢复名称' : '隐藏名称'),
              onTap: () => Navigator.pop(context, _SelectionAction.toggleTitle),
            ),
            ListTile(
              leading: Icon(
                allCoversBlurred
                    ? Icons.blur_off_outlined
                    : Icons.blur_on_outlined,
              ),
              title: Text(allCoversBlurred ? '恢复封面' : '模糊封面'),
              onTap: () => Navigator.pop(context, _SelectionAction.toggleCover),
            ),
            ListTile(
              leading: const Icon(Icons.drive_file_move_outline),
              title: const Text('移出或移动'),
              onTap: () => Navigator.pop(context, _SelectionAction.move),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;
    switch (action) {
      case _SelectionAction.toggleTitle:
        await widget.controller.updatePrivacy(ids, hideTitle: !allTitlesHidden);
      case _SelectionAction.toggleCover:
        await widget.controller.updatePrivacy(
          ids,
          blurCover: !allCoversBlurred,
        );
      case _SelectionAction.move:
        await _moveSelected(ids);
    }
    if (mounted) setState(_selectedBooks.clear);
  }

  Future<void> _moveSelected(Set<String> ids) async {
    final target = await showModalBottomSheet<String?>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.only(bottom: 18),
          children: [
            const ListTile(title: Text('选择目标位置')),
            ListTile(
              leading: const Icon(Icons.collections_bookmark_outlined),
              title: const Text('全部书库'),
              onTap: () => Navigator.pop(context, ''),
            ),
            ...widget.controller.folders
                .where((folder) => folder.id != widget.folder.id)
                .map(
                  (folder) => ListTile(
                    leading: const Icon(Icons.folder_outlined),
                    title: Text(folder.name),
                    onTap: () => Navigator.pop(context, folder.id),
                  ),
                ),
          ],
        ),
      ),
    );
    if (target == null || !mounted) return;
    await widget.controller.moveBooks(ids, target.isEmpty ? null : target);
  }

  Future<void> _handleFolderMenu(LibraryFolder folder, String action) async {
    if (action == 'rename') {
      final controller = TextEditingController(text: folder.name);
      final name = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('重命名文件夹'),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLength: 40,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, controller.text.trim()),
              child: const Text('保存'),
            ),
          ],
        ),
      );
      controller.dispose();
      if (name != null && name.isNotEmpty) {
        await widget.controller.renameFolder(folder, name);
      }
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除文件夹？'),
        content: const Text('漫画不会被删除，只会回到全部书库。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed == true) await widget.controller.deleteFolder(folder);
  }
}

class _ComicTile extends StatelessWidget {
  const _ComicTile({
    required this.controller,
    required this.book,
    required this.selected,
    required this.isSelecting,
    required this.onToggleSelected,
  });
  final AppController controller;
  final ComicBook book;
  final bool selected;
  final bool isSelecting;
  final ValueChanged<ComicBook> onToggleSelected;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: '打开漫画 ${book.displayTitle}',
      child: GestureDetector(
        onLongPress: () => onToggleSelected(book),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () {
            if (isSelecting) return onToggleSelected(book);
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (context) =>
                    ComicDetailScreen(controller: controller, book: book),
              ),
            );
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Hero(
                      tag: 'cover-${book.id}',
                      child: ComicCover(controller: controller, book: book),
                    ),
                    if (book.currentPage > 0)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: LinearProgressIndicator(
                          minHeight: 4,
                          value: book.progress,
                          color: colors.primary,
                          backgroundColor: colors.surfaceContainerHighest,
                        ),
                      ),
                    if (selected)
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: colors.primary.withValues(alpha: .25),
                            border: Border.all(color: colors.primary, width: 3),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Center(
                            child: CircleAvatar(
                              backgroundColor: colors.primary,
                              foregroundColor: colors.onPrimary,
                              child: const Icon(Icons.check_rounded),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Text(
                book.displayTitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 3),
              Text(
                '${book.chapters.length} 章 · ${book.pageCount} 页',
                maxLines: 1,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SelectionBar extends StatelessWidget {
  const _SelectionBar({
    required this.count,
    required this.onClose,
    required this.onActions,
  });
  final int count;
  final VoidCallback onClose;
  final VoidCallback onActions;

  @override
  Widget build(BuildContext context) {
    return BottomAppBar(
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            IconButton(
              onPressed: onClose,
              tooltip: '取消选择',
              icon: const Icon(Icons.close_rounded),
            ),
            Expanded(
              child: Text(
                '已选 $count 本',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            FilledButton.icon(
              onPressed: onActions,
              icon: const Icon(Icons.tune_rounded),
              label: const Text('操作'),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary({required this.onImport});
  final VoidCallback onImport;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 36, 28, 100),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 138,
            height: 174,
            decoration: BoxDecoration(
              color: colors.primaryContainer,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: colors.primary.withValues(alpha: .22)),
            ),
            child: Icon(
              Icons.collections_bookmark_rounded,
              size: 54,
              color: colors.onPrimaryContainer,
            ),
          ),
          const SizedBox(height: 30),
          Text('把漫画交给漫匣', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 10),
          Text(
            '导入 ZIP、CBZ 或漫画文件夹，WebP 页面会自动分章并排序。',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: colors.onSurfaceVariant,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 26),
          FilledButton.icon(
            onPressed: onImport,
            icon: const Icon(Icons.add_rounded),
            label: const Text('导入漫画'),
          ),
        ],
      ),
    );
  }
}

class _ImportProgressSheet extends StatelessWidget {
  const _ImportProgressSheet({required this.controller});
  final AppController controller;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final progress = controller.importProgress;
      return PopScope(
        canPop: !controller.isImporting,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 36),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    controller.isImporting
                        ? Icons.auto_awesome_rounded
                        : Icons.check_circle_rounded,
                  ),
                  const SizedBox(width: 12),
                  Text('自动整理中', style: Theme.of(context).textTheme.titleLarge),
                ],
              ),
              const SizedBox(height: 26),
              LinearProgressIndicator(
                value: progress?.value,
                minHeight: 8,
                borderRadius: BorderRadius.circular(4),
              ),
              const SizedBox(height: 16),
              Text(progress?.label ?? '正在准备'),
              if ((progress?.totalPages ?? 0) > 0) ...[
                const SizedBox(height: 6),
                Text(
                  '已处理 ${progress!.completedPages} / ${progress.totalPages} 页',
                ),
              ],
            ],
          ),
        ),
      );
    },
  );
}

class _SettingsPage extends StatelessWidget {
  const _SettingsPage({required this.controller});
  final AppController controller;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) => ListView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
      children: [
        Text('设置', style: Theme.of(context).textTheme.displaySmall),
        const SizedBox(height: 6),
        Text(
          '阅读外观与本地存储',
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 34),
        Text('外观', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 10),
        Card(
          child: SwitchListTile(
            secondary: const Icon(Icons.dark_mode_outlined),
            title: const Text('深色模式'),
            subtitle: const Text('降低夜间阅读时的界面亮度'),
            value: controller.isDarkMode,
            onChanged: controller.setDarkMode,
          ),
        ),
        const SizedBox(height: 30),
        Text('本地书库', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 10),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.collections_bookmark_outlined),
                title: const Text('已整理'),
                trailing: Text('${controller.books.length} 本'),
              ),
              const Divider(indent: 56),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('漫画页面'),
                trailing: Text('${controller.totalPages} 页'),
              ),
              const Divider(indent: 56),
              ListTile(
                leading: const Icon(Icons.folder_outlined),
                title: const Text('文件夹'),
                trailing: Text('${controller.folders.length} 个'),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
