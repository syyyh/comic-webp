import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../app_controller.dart';
import '../models/comic_book.dart';

class ReaderScreen extends StatefulWidget {
  const ReaderScreen({
    super.key,
    required this.controller,
    required this.book,
    required this.initialPage,
  });

  final AppController controller;
  final ComicBook book;
  final int initialPage;

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  late final PageController _pageController;
  late final ItemScrollController _continuousController;
  late final ItemPositionsListener _continuousPositions;
  late int _currentPage;
  late ReadingMode _readingMode;
  bool _showControls = true;
  bool _didInitialContinuousScroll = false;
  int _preloadedCenter = -1;

  @override
  void initState() {
    super.initState();
    final lastPage = widget.book.pageCount - 1;
    _currentPage = widget.initialPage.clamp(0, lastPage < 0 ? 0 : lastPage);
    _readingMode = widget.book.readingMode;
    _pageController = PageController(initialPage: _currentPage);
    _continuousController = ItemScrollController();
    _continuousPositions = ItemPositionsListener.create();
    _continuousPositions.itemPositions.addListener(_onContinuousPositions);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    _continuousPositions.itemPositions.removeListener(_onContinuousPositions);
    widget.controller.updateReadingProgress(widget.book, _currentPage);
    _pageController.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final book = widget.controller.latestVersionOf(widget.book);
    final pages = book.pages;
    _preloadAround(book, pages);
    if (_readingMode == ReadingMode.continuous &&
        !_didInitialContinuousScroll) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _didInitialContinuousScroll || pages.isEmpty) return;
        if (_continuousController.isAttached && _currentPage > 0) {
          _continuousController.jumpTo(index: _currentPage);
        }
        _didInitialContinuousScroll = true;
      });
    }

    return PopScope(
      onPopInvokedWithResult: (didPop, result) {
        widget.controller.updateReadingProgress(book, _currentPage);
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() => _showControls = !_showControls),
          child: Stack(
            fit: StackFit.expand,
            children: [
              _buildReader(book, pages),
              IgnorePointer(
                ignoring: !_showControls,
                child: AnimatedOpacity(
                  opacity: _showControls ? 1 : 0,
                  duration: const Duration(milliseconds: 180),
                  child: _ReaderControls(
                    title: book.title,
                    currentPage: _currentPage,
                    pageCount: pages.length,
                    readingMode: _readingMode,
                    isBookmarked: book.bookmarks.contains(_currentPage),
                    bookmarkCount: book.bookmarks.length,
                    onBack: () => Navigator.of(context).pop(),
                    onChapterList: () => _showChapterList(context, book),
                    onBookmarkList: () => _showBookmarkList(context, book),
                    onReadingMode: () => _showReadingMode(context, book),
                    onToggleBookmark: () => _toggleBookmark(book),
                    onPageSelected: _goToPage,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildReader(ComicBook book, List<String> pages) {
    if (pages.isEmpty) {
      return const Center(
        child: Text('没有可阅读的页面', style: TextStyle(color: Colors.white70)),
      );
    }
    if (_readingMode == ReadingMode.continuous) {
      return ScrollablePositionedList.builder(
        key: const ValueKey('continuous-reader'),
        itemScrollController: _continuousController,
        itemPositionsListener: _continuousPositions,
        itemCount: pages.length,
        itemBuilder: (context, index) => _ReaderImage(
          path: widget.controller.pagePath(book, pages[index]),
          continuous: true,
        ),
      );
    }
    return PageView.builder(
      key: ValueKey(_readingMode),
      controller: _pageController,
      reverse: _readingMode == ReadingMode.swipeRight,
      scrollDirection: Axis.horizontal,
      itemCount: pages.length,
      onPageChanged: (value) {
        setState(() => _currentPage = value);
        widget.controller.updateReadingProgress(book, value);
        _preloadAround(book, pages);
      },
      itemBuilder: (context, index) =>
          _ReaderImage(path: widget.controller.pagePath(book, pages[index])),
    );
  }

  void _onContinuousPositions() {
    if (_readingMode != ReadingMode.continuous || !mounted) return;
    final visible =
        _continuousPositions.itemPositions.value
            .where(
              (position) =>
                  position.itemLeadingEdge < 1 && position.itemTrailingEdge > 0,
            )
            .toList()
          ..sort((a, b) => a.itemLeadingEdge.compareTo(b.itemLeadingEdge));
    if (visible.isEmpty || visible.first.index == _currentPage) return;
    setState(() => _currentPage = visible.first.index);
    widget.controller.updateReadingProgress(widget.book, _currentPage);
    _preloadAround(widget.book, widget.book.pages);
  }

  void _preloadAround(ComicBook book, List<String> pages) {
    if (!mounted || pages.isEmpty || _preloadedCenter == _currentPage) return;
    _preloadedCenter = _currentPage;
    final width =
        (MediaQuery.sizeOf(context).width *
                MediaQuery.devicePixelRatioOf(context))
            .round()
            .clamp(480, 1600);
    for (final index in <int>[
      _currentPage - 1,
      _currentPage,
      _currentPage + 1,
    ]) {
      if (index < 0 || index >= pages.length) continue;
      final provider = ResizeImage(
        FileImage(File(widget.controller.pagePath(book, pages[index]))),
        width: width,
      );
      precacheImage(provider, context);
    }
  }

  void _goToPage(int page) {
    final bounded = page.clamp(0, widget.book.pageCount - 1);
    if (_readingMode == ReadingMode.continuous) {
      if (_continuousController.isAttached) {
        _continuousController.scrollTo(
          index: bounded,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
        );
      }
    } else {
      _pageController.animateToPage(
        bounded,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
    }
  }

  Future<void> _showReadingMode(BuildContext context, ComicBook book) async {
    final mode = await showModalBottomSheet<ReadingMode>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text('阅读方式'),
              subtitle: const Text('连续拼接或左右翻页'),
              leading: const Icon(Icons.chrome_reader_mode_outlined),
            ),
            ...ReadingMode.values.map(
              (mode) => ListTile(
                onTap: () => Navigator.of(context).pop(mode),
                leading: Icon(_ReaderControls.modeIcon(mode)),
                title: Text(_modeLabel(mode)),
                subtitle: Text(_modeDescription(mode)),
                trailing: mode == _readingMode
                    ? const Icon(Icons.check_circle_rounded)
                    : null,
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
    if (mode == null || mode == _readingMode || !mounted) return;
    await widget.controller.updateReadingMode(book, mode);
    setState(() {
      _readingMode = mode;
      _didInitialContinuousScroll = false;
    });
    if (mode != ReadingMode.continuous) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _pageController.hasClients) {
          _pageController.jumpToPage(_currentPage);
        }
      });
    }
  }

  Future<void> _toggleBookmark(ComicBook book) async {
    await widget.controller.setBookmark(
      book,
      _currentPage,
      bookmarked: !book.bookmarks.contains(_currentPage),
    );
    if (mounted) setState(() {});
  }

  Future<void> _showBookmarkList(BuildContext context, ComicBook book) async {
    final page = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: book.bookmarks.isEmpty
            ? const Padding(
                padding: EdgeInsets.fromLTRB(24, 12, 24, 36),
                child: Text('还没有书签，点击阅读器右上角的书签图标添加。'),
              )
            : ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.only(bottom: 18),
                itemCount: book.bookmarks.length,
                separatorBuilder: (context, index) => const Divider(indent: 72),
                itemBuilder: (context, index) {
                  final pageIndex = book.bookmarks[index];
                  return ListTile(
                    leading: const CircleAvatar(
                      child: Icon(Icons.bookmark_rounded, size: 18),
                    ),
                    title: Text('第 ${pageIndex + 1} 页'),
                    subtitle: Text(_chapterForPage(book, pageIndex)),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => Navigator.of(context).pop(pageIndex),
                  );
                },
              ),
      ),
    );
    if (page != null) _goToPage(page);
  }

  Future<void> _showChapterList(BuildContext context, ComicBook book) async {
    var pageOffset = 0;
    final chapters = <({ComicChapter chapter, int page})>[];
    for (final chapter in book.chapters) {
      chapters.add((chapter: chapter, page: pageOffset));
      pageOffset += chapter.pages.length;
    }
    final page = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView.separated(
          shrinkWrap: true,
          padding: const EdgeInsets.only(bottom: 18),
          itemCount: chapters.length,
          separatorBuilder: (context, index) => const Divider(indent: 72),
          itemBuilder: (context, index) {
            final item = chapters[index];
            final selected =
                _currentPage >= item.page &&
                _currentPage < item.page + item.chapter.pages.length;
            return ListTile(
              leading: CircleAvatar(child: Text('${index + 1}')),
              title: Text(item.chapter.title),
              subtitle: Text('${item.chapter.pages.length} 页'),
              trailing: selected ? const Icon(Icons.check_rounded) : null,
              onTap: () => Navigator.of(context).pop(item.page),
            );
          },
        ),
      ),
    );
    if (page != null) _goToPage(page);
  }

  String _chapterForPage(ComicBook book, int page) {
    var offset = 0;
    for (final chapter in book.chapters) {
      if (page < offset + chapter.pages.length) return chapter.title;
      offset += chapter.pages.length;
    }
    return '正文';
  }

  static String _modeLabel(ReadingMode mode) {
    switch (mode) {
      case ReadingMode.continuous:
        return '连续拼接';
      case ReadingMode.swipeLeft:
        return '向左翻页';
      case ReadingMode.swipeRight:
        return '向右翻页';
    }
  }

  static String _modeDescription(ReadingMode mode) {
    switch (mode) {
      case ReadingMode.continuous:
        return '页面上下相连，滚动阅读整本漫画';
      case ReadingMode.swipeLeft:
        return '向左滑进入下一页';
      case ReadingMode.swipeRight:
        return '向右滑进入下一页';
    }
  }
}

class _ReaderImage extends StatelessWidget {
  const _ReaderImage({required this.path, this.continuous = false});

  final String path;
  final bool continuous;

  @override
  Widget build(BuildContext context) {
    if (continuous) {
      return Image.file(
        File(path),
        width: double.infinity,
        fit: BoxFit.fitWidth,
        cacheWidth:
            (MediaQuery.sizeOf(context).width *
                    MediaQuery.devicePixelRatioOf(context))
                .round()
                .clamp(480, 1600),
        filterQuality: FilterQuality.medium,
        gaplessPlayback: true,
        errorBuilder: (context, error, stackTrace) => const SizedBox(
          height: 180,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.broken_image_outlined, color: Colors.white70),
                SizedBox(height: 10),
                Text('这一页无法显示', style: TextStyle(color: Colors.white70)),
              ],
            ),
          ),
        ),
      );
    }
    return InteractiveViewer(
      minScale: 1,
      maxScale: 4,
      child: Center(
        child: Image.file(
          File(path),
          fit: BoxFit.contain,
          cacheWidth:
              (MediaQuery.sizeOf(context).width *
                      MediaQuery.devicePixelRatioOf(context))
                  .round()
                  .clamp(480, 1600),
          filterQuality: FilterQuality.medium,
          gaplessPlayback: true,
          errorBuilder: (context, error, stackTrace) => const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.broken_image_outlined, color: Colors.white70),
              SizedBox(height: 10),
              Text('这一页无法显示', style: TextStyle(color: Colors.white70)),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReaderControls extends StatelessWidget {
  const _ReaderControls({
    required this.title,
    required this.currentPage,
    required this.pageCount,
    required this.readingMode,
    required this.isBookmarked,
    required this.bookmarkCount,
    required this.onBack,
    required this.onChapterList,
    required this.onBookmarkList,
    required this.onReadingMode,
    required this.onToggleBookmark,
    required this.onPageSelected,
  });

  final String title;
  final int currentPage;
  final int pageCount;
  final ReadingMode readingMode;
  final bool isBookmarked;
  final int bookmarkCount;
  final VoidCallback onBack;
  final VoidCallback onChapterList;
  final VoidCallback onBookmarkList;
  final VoidCallback onReadingMode;
  final VoidCallback onToggleBookmark;
  final ValueChanged<int> onPageSelected;

  @override
  Widget build(BuildContext context) {
    final safePageCount = pageCount < 1 ? 1 : pageCount;
    return Column(
      children: [
        DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xE6000000), Color(0x00000000)],
            ),
          ),
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(6, 6, 8, 34),
              child: Row(
                children: [
                  IconButton(
                    onPressed: onBack,
                    tooltip: '返回',
                    color: Colors.white,
                    icon: const Icon(Icons.arrow_back_rounded),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: onReadingMode,
                    tooltip: '阅读方式',
                    color: Colors.white,
                    icon: Icon(modeIcon(readingMode)),
                  ),
                  IconButton(
                    onPressed: onToggleBookmark,
                    tooltip: isBookmarked ? '移除书签' : '添加书签',
                    color: Colors.white,
                    icon: Icon(
                      isBookmarked
                          ? Icons.bookmark_rounded
                          : Icons.bookmark_border_rounded,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const Spacer(),
        DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0x00000000), Color(0xE6000000)],
            ),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 40, 8, 10),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Slider(
                          value: currentPage
                              .clamp(0, safePageCount - 1)
                              .toDouble(),
                          min: 0,
                          max: (safePageCount - 1).toDouble(),
                          divisions: safePageCount > 1 ? safePageCount - 1 : 1,
                          label: '${currentPage + 1}',
                          onChanged: safePageCount > 1
                              ? (value) => onPageSelected(value.round())
                              : null,
                        ),
                      ),
                      SizedBox(
                        width: 58,
                        child: Text(
                          '${currentPage + 1} / $pageCount',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      IconButton(
                        onPressed: onChapterList,
                        tooltip: '章节',
                        color: Colors.white,
                        icon: const Icon(Icons.format_list_numbered_rounded),
                      ),
                      IconButton(
                        onPressed: onBookmarkList,
                        tooltip:
                            '书签${bookmarkCount > 0 ? ' ($bookmarkCount)' : ''}',
                        color: Colors.white,
                        icon: Badge(
                          isLabelVisible: bookmarkCount > 0,
                          label: Text('$bookmarkCount'),
                          child: const Icon(Icons.bookmarks_outlined),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  static IconData modeIcon(ReadingMode mode) {
    switch (mode) {
      case ReadingMode.continuous:
        return Icons.view_agenda_outlined;
      case ReadingMode.swipeLeft:
        return Icons.swipe_left_rounded;
      case ReadingMode.swipeRight:
        return Icons.swipe_right_rounded;
    }
  }
}
