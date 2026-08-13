import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../models/comic_book.dart';
import '../services/thumbnail_service.dart';

class ComicCover extends StatelessWidget {
  const ComicCover({
    super.key,
    required this.controller,
    required this.book,
    this.borderRadius = 6,
    this.respectPrivacy = true,
  });

  final AppController controller;
  final ComicBook book;
  final double borderRadius;
  final bool respectPrivacy;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final pages = book.pages;
    final thumbnail = File(
      ThumbnailService.thumbnailPath(Directory(controller.pagePath(book, ''))),
    );
    final source = thumbnail.existsSync()
        ? thumbnail
        : (pages.isEmpty ? null : File(controller.pagePath(book, pages.first)));
    final cover = ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: DecoratedBox(
        decoration: BoxDecoration(color: colors.surfaceContainerHighest),
        child: source == null
            ? _FallbackCover(
                title: respectPrivacy ? book.displayTitle : book.title,
              )
            : Image.file(
                source,
                fit: BoxFit.cover,
                cacheWidth: 640,
                errorBuilder: (context, error, stackTrace) => _FallbackCover(
                  title: respectPrivacy ? book.displayTitle : book.title,
                ),
              ),
      ),
    );
    if (!respectPrivacy || !book.blurCover) return cover;
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: cover,
      ),
    );
  }
}

class _FallbackCover extends StatelessWidget {
  const _FallbackCover({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ColoredBox(
      color: colors.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.auto_stories_rounded, color: colors.onPrimaryContainer),
            const SizedBox(height: 10),
            Text(
              title,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: colors.onPrimaryContainer,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
