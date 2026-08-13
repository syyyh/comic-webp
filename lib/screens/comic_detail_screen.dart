import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../models/comic_book.dart';
import '../widgets/comic_cover.dart';
import 'reader_screen.dart';

class ComicDetailScreen extends StatelessWidget {
  const ComicDetailScreen({
    super.key,
    required this.controller,
    required this.book,
  });

  final AppController controller;
  final ComicBook book;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final currentBook = controller.latestVersionOf(book);
        return Scaffold(
          body: CustomScrollView(
            slivers: [
              SliverAppBar(
                pinned: true,
                title: Text(
                  currentBook.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                actions: [
                  IconButton(
                    onPressed: () => _confirmDelete(context, currentBook),
                    tooltip: '删除漫画',
                    icon: const Icon(Icons.delete_outline_rounded),
                  ),
                ],
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 28),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 132,
                            child: AspectRatio(
                              aspectRatio: .68,
                              child: Hero(
                                tag: 'cover-${currentBook.id}',
                                child: ComicCover(
                                  controller: controller,
                                  book: currentBook,
                                  respectPrivacy: false,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 20),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    currentBook.title,
                                    maxLines: 4,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.headlineSmall,
                                  ),
                                  const SizedBox(height: 14),
                                  _MetadataLine(
                                    icon: Icons.photo_library_outlined,
                                    label: '${currentBook.pageCount} 页',
                                  ),
                                  const SizedBox(height: 8),
                                  _MetadataLine(
                                    icon: Icons.segment_rounded,
                                    label: '${currentBook.chapters.length} 章',
                                  ),
                                  if (currentBook.bookmarks.isNotEmpty) ...[
                                    const SizedBox(height: 8),
                                    _MetadataLine(
                                      icon: Icons.bookmarks_outlined,
                                      label:
                                          '${currentBook.bookmarks.length} 个书签',
                                    ),
                                  ],
                                  const SizedBox(height: 8),
                                  _MetadataLine(
                                    icon: Icons.event_outlined,
                                    label: _formatDate(currentBook.importedAt),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 26),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: () => _openReader(
                            context,
                            currentBook,
                            currentBook.currentPage,
                          ),
                          icon: Icon(
                            currentBook.currentPage > 0
                                ? Icons.play_arrow_rounded
                                : Icons.menu_book_rounded,
                          ),
                          label: Text(
                            currentBook.currentPage > 0
                                ? '继续阅读 · 第 ${currentBook.currentPage + 1} 页'
                                : '开始阅读',
                          ),
                        ),
                      ),
                      if (currentBook.currentPage > 0) ...[
                        const SizedBox(height: 12),
                        LinearProgressIndicator(
                          minHeight: 6,
                          value: currentBook.progress,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ],
                      const SizedBox(height: 34),
                      Row(
                        children: [
                          Text(
                            '章节',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const Spacer(),
                          Text(
                            '${currentBook.chapters.length}',
                            style: Theme.of(context).textTheme.labelLarge
                                ?.copyWith(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              SliverList.separated(
                itemCount: currentBook.chapters.length,
                separatorBuilder: (context, index) =>
                    const Divider(indent: 72, endIndent: 20),
                itemBuilder: (context, index) {
                  final chapter = currentBook.chapters[index];
                  final firstPage = _firstPageOfChapter(currentBook, index);
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 5,
                    ),
                    leading: CircleAvatar(
                      backgroundColor: Theme.of(
                        context,
                      ).colorScheme.secondaryContainer,
                      foregroundColor: Theme.of(
                        context,
                      ).colorScheme.onSecondaryContainer,
                      child: Text('${index + 1}'),
                    ),
                    title: Text(chapter.title),
                    subtitle: Text('${chapter.pages.length} 页'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => _openReader(context, currentBook, firstPage),
                  );
                },
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 40)),
            ],
          ),
        );
      },
    );
  }

  int _firstPageOfChapter(ComicBook book, int chapterIndex) {
    return book.chapters
        .take(chapterIndex)
        .fold<int>(0, (sum, chapter) => sum + chapter.pages.length);
  }

  Future<void> _openReader(
    BuildContext context,
    ComicBook book,
    int initialPage,
  ) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => ReaderScreen(
          controller: controller,
          book: book,
          initialPage: initialPage,
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, ComicBook book) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.delete_outline_rounded),
        title: const Text('删除这本漫画？'),
        content: Text('《${book.title}》的全部本地页面会被移除，此操作无法撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await controller.deleteBook(book);
    if (context.mounted) Navigator.of(context).pop();
  }

  static String _formatDate(DateTime value) {
    return '${value.year}.${value.month.toString().padLeft(2, '0')}.${value.day.toString().padLeft(2, '0')}';
  }
}

class _MetadataLine extends StatelessWidget {
  const _MetadataLine({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          icon,
          size: 18,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}
