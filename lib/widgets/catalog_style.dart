import 'package:flutter/material.dart';

import 'app_icons.dart';

import '../catalog/catalog_models.dart';
import '../catalog/cached_poster.dart';
import '../catalog/poster_cache.dart';
import '../catalog/watched.dart';

Duration motionDuration(BuildContext context, [int milliseconds = 180]) =>
    MediaQuery.disableAnimationsOf(context)
    ? Duration.zero
    : Duration(milliseconds: milliseconds);

double posterCaptionHeight(BuildContext context) =>
    MediaQuery.textScalerOf(context).scale(60) + 28;

class BrandIcon extends StatelessWidget {
  const BrandIcon({this.size = 52, super.key});
  final double size;
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      widthFactor: 1,
      heightFactor: 1,
      child: SizedBox.square(
        dimension: size,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(size * .21),
          clipBehavior: Clip.antiAlias,
          child: AnimatedSwitcher(
            duration: motionDuration(context),
            child: Transform.scale(
              key: ValueKey('tv-brand-${dark ? 'dark' : 'light'}'),
              scale: 1.18,
              child: Image.asset(
                dark
                    ? 'assets/branding/tv-preview-icon.png'
                    : 'assets/branding/tv-preview-icon-light.png',
                width: size,
                height: size,
                filterQuality: FilterQuality.high,
                cacheWidth: (size * MediaQuery.devicePixelRatioOf(context) * 2)
                    .ceil(),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Slide a fixed-size segment in the paint phase while labels stay in place.
class CatalogSelectionThumb extends StatelessWidget {
  const CatalogSelectionThumb({
    required this.index,
    required this.count,
    this.animate = true,
    super.key,
  });
  final int index, count;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    final offset = Offset(index.toDouble(), 0);
    final thumb = DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.onSurface,
        borderRadius: BorderRadius.circular(24),
      ),
    );
    return Align(
      alignment: Alignment.centerLeft,
      child: FractionallySizedBox(
        widthFactor: 1 / count,
        heightFactor: 1,
        child: animate && !MediaQuery.disableAnimationsOf(context)
            ? AnimatedSlide(
                offset: offset,
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                child: thumb,
              )
            : FractionalTranslation(translation: offset, child: thumb),
      ),
    );
  }
}

class PillSurface extends StatelessWidget {
  const PillSurface({required this.child, super.key});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [colors.surfaceContainerHigh, colors.surfaceContainerLow],
        ),
        border: Border.all(color: colors.outlineVariant.withValues(alpha: .65)),
      ),
      child: child,
    );
  }
}

/// Static surfaces keep the TV preview inexpensive on low-memory devices.
class PosterArtwork extends StatelessWidget {
  const PosterArtwork({
    required this.title,
    this.cache,
    this.decodeWidth = 240,
    super.key,
  });
  final CatalogTitle title;
  final PosterDiskCache? cache;
  final int decodeWidth;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final placeholder = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [colors.surfaceContainerHighest, colors.surfaceContainerLow],
        ),
      ),
      child: Center(
        child: Icon(
          switch (title.kind) {
            CatalogKind.series => Icons.live_tv_outlined,
            CatalogKind.games => Icons.sports_esports_outlined,
            CatalogKind.movies => Icons.local_movies_outlined,
          },
          size: 44,
          color: colors.onSurfaceVariant,
        ),
      ),
    );
    return title.poster == null
        ? placeholder
        : CachedPoster(
            uri: title.poster!,
            fallback: title.posterFallback,
            cache: cache,
            decodeWidth: decodeWidth,
            placeholder: placeholder,
          );
  }
}

class PosterCardContent extends StatelessWidget {
  const PosterCardContent({
    required this.title,
    required this.english,
    required this.favorite,
    required this.queued,
    this.updateLabel,
    this.cache,
    super.key,
  });
  final CatalogTitle title;
  final bool english, favorite, queued;
  final String? updateLabel;
  final PosterDiskCache? cache;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final marked = WatchedScope.of(context)?.titleWatched(title) == true;
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                PosterArtwork(title: title, cache: cache),
                if (title.poster != null)
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: [0, .45, 1],
                        colors: [
                          Color(0x33000000),
                          Colors.transparent,
                          Color(0x66000000),
                        ],
                      ),
                    ),
                  ),
                if (title.rating != null)
                  Positioned(
                    left: 10,
                    top: 10,
                    child: _PosterBadge(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.star_rounded,
                            size: 15,
                            color: Color(0xffefbd88),
                          ),
                          const SizedBox(width: 3),
                          Text(
                            title.rating!.toStringAsFixed(1),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (updateLabel case final label?)
                  Positioned(
                    top: 10,
                    right: 10,
                    child: Tooltip(
                      message: label,
                      child: _PosterBadge(
                        background: const Color(0xff703b1b),
                        child: const Icon(
                          AppIcons.trackerUpdate,
                          size: 18,
                          color: Color(0xffffc18a),
                        ),
                      ),
                    ),
                  ),
                if (favorite || queued || marked)
                  Positioned(
                    right: 10,
                    bottom: 10,
                    child: _PosterBadge(
                      accent: favorite || queued || marked,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (marked)
                            Icon(
                              Icons.visibility_outlined,
                              size: 16,
                              color: colors.primary,
                            ),
                          if (marked && (favorite || queued))
                            const SizedBox(width: 6),
                          if (favorite)
                            Icon(
                              Icons.favorite,
                              size: 16,
                              color: colors.primary,
                            ),
                          if (favorite && queued) const SizedBox(width: 6),
                          if (queued)
                            Icon(
                              Icons.playlist_play,
                              size: 18,
                              color: colors.primary,
                            ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          SizedBox(
            height: posterCaptionHeight(context),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Tooltip(
                    message: title.title(english),
                    child: Text(
                      title.title(english),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        height: 1.2,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    [
                      if (title.year != null) '${title.year}',
                      switch (title.kind) {
                        CatalogKind.series => english ? 'Series' : 'Сериал',
                        CatalogKind.games => english ? 'Game' : 'Игра',
                        CatalogKind.movies => english ? 'Film' : 'Фильм',
                      },
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PosterBadge extends StatelessWidget {
  const _PosterBadge({
    required this.child,
    this.accent = false,
    this.background,
  });
  final Widget child;
  final bool accent;
  final Color? background;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
    decoration: BoxDecoration(
      color:
          background ??
          (accent
              ? Theme.of(context).colorScheme.primaryContainer
              : const Color(0xd9101216)),
      borderRadius: BorderRadius.circular(7),
    ),
    child: child,
  );
}
