import '../catalog/watched.dart';

import 'package:flutter/material.dart';

import '../catalog/cached_poster.dart';
import '../catalog/catalog_models.dart';
import '../catalog/poster_cache.dart';
import 'remote_focus.dart';

Duration tvMotionDuration(BuildContext context, [int milliseconds = 180]) =>
    MediaQuery.disableAnimationsOf(context)
    ? Duration.zero
    : Duration(milliseconds: milliseconds);

double tvPosterCaptionHeight(BuildContext context) =>
    MediaQuery.textScalerOf(context).scale(60) + 28;

class TvBrandIcon extends StatelessWidget {
  const TvBrandIcon({this.size = 52, super.key});
  final double size;
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: SizedBox.square(
        dimension: size,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(size * .21),
          clipBehavior: Clip.antiAlias,
          child: AnimatedSwitcher(
            duration: tvMotionDuration(context),
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

class TvBackButton extends StatelessWidget {
  const TvBackButton({
    required this.id,
    required this.focus,
    required this.label,
    required this.onPressed,
    super.key,
  });
  final String id, label;
  final RemoteFocus focus;
  final VoidCallback? onPressed;
  @override
  Widget build(BuildContext context) => RemoteButton(
    id: id,
    focus: focus,
    onPressed: onPressed,
    flat: true,
    radius: 24,
    child: Tooltip(
      message: label,
      child: const Icon(Icons.arrow_back_rounded, size: 21),
    ),
  );
}

class TvSurface extends StatelessWidget {
  const TvSurface({required this.child, super.key});
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

/// The same remote button stays focused while its caption appears or disappears.
class TvCollectionButton extends StatelessWidget {
  const TvCollectionButton({
    required this.id,
    required this.focus,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onPressed,
    super.key,
  });

  final String id, label;
  final RemoteFocus focus;
  final IconData icon;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => TvSurface(
    child: RemoteButton(
      id: id,
      focus: focus,
      selected: selected,
      onPressed: onPressed,
      flat: true,
      radius: 24,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Tooltip(
        message: label,
        child: ExcludeSemantics(
          child: Builder(
            builder: (context) {
              final focused = Focus.of(context).hasFocus;
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 21),
                  TweenAnimationBuilder<double>(
                    tween: Tween(end: focused ? 1.0 : 0.0),
                    duration: tvMotionDuration(context, 220),
                    curve: Curves.easeOutCubic,
                    child: Padding(
                      padding: const EdgeInsetsDirectional.only(start: 8),
                      child: Text(label, maxLines: 1),
                    ),
                    builder: (context, amount, caption) => ClipRect(
                      child: Align(
                        alignment: AlignmentDirectional.centerStart,
                        widthFactor: amount,
                        child: caption,
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    ),
  );
}

class TvAnimatedSize extends StatelessWidget {
  const TvAnimatedSize({
    required this.duration,
    required this.alignment,
    required this.curve,
    required this.child,
    super.key,
  });
  final Duration duration;
  final AlignmentGeometry alignment;
  final Curve curve;
  final Widget child;
  @override
  Widget build(BuildContext context) => duration == Duration.zero
      ? child
      : AnimatedSize(
          duration: duration,
          alignment: alignment,
          curve: curve,
          child: child,
        );
}

class TvEntrance extends StatelessWidget {
  const TvEntrance({required this.child, super.key});
  final Widget child;
  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0, end: 1),
    duration: tvMotionDuration(context, 240),
    curve: Curves.easeOutCubic,
    child: child,
    builder: (context, value, child) => Opacity(
      opacity: value,
      child: Transform.translate(
        offset: Offset(0, (1 - value) * 10),
        child: child,
      ),
    ),
  );
}

/// Static surfaces keep the TV preview inexpensive on low-memory devices.
class TvPosterArtwork extends StatelessWidget {
  const TvPosterArtwork({
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
          title.kind == CatalogKind.series
              ? Icons.live_tv_outlined
              : Icons.local_movies_outlined,
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

class TvPosterContent extends StatelessWidget {
  const TvPosterContent({
    required this.title,
    required this.english,
    required this.favorite,
    required this.queued,
    this.cache,
    super.key,
  });
  final CatalogTitle title;
  final bool english, favorite, queued;
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
                TvPosterArtwork(title: title, cache: cache),
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
                if (favorite || queued || marked)
                  Positioned(
                    right: 10,
                    bottom: 10,
                    child: _PosterBadge(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (WatchedScope.of(context)?.titleWatched(title) ==
                              true)
                            const Icon(
                              Icons.visibility_outlined,
                              size: 16,
                              color: Colors.white,
                            ),
                          if (favorite)
                            const Icon(
                              Icons.favorite,
                              size: 16,
                              color: Colors.white,
                            ),
                          if (favorite && queued) const SizedBox(width: 6),
                          if (queued)
                            const Icon(
                              Icons.playlist_play,
                              size: 18,
                              color: Colors.white,
                            ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          SizedBox(
            height: tvPosterCaptionHeight(context),
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
                      title.kind == CatalogKind.series
                          ? (english ? 'Series' : 'Сериал')
                          : (english ? 'Film' : 'Фильм'),
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
  const _PosterBadge({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
    decoration: BoxDecoration(
      color: const Color(0xd9101216),
      borderRadius: BorderRadius.circular(7),
    ),
    child: child,
  );
}

class TvDetailHero extends StatefulWidget {
  const TvDetailHero({
    required this.title,
    required this.english,
    required this.focus,
    this.cache,
    this.trailer,
    super.key,
  });
  final CatalogTitle title;
  final bool english;
  final RemoteFocus focus;
  final PosterDiskCache? cache;
  final Widget? trailer;

  @override
  State<TvDetailHero> createState() => _TvDetailHeroState();
}

class _TvDetailHeroState extends State<TvDetailHero> {
  bool expanded = false;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final title = widget.title;
    final english = widget.english;
    final cache = widget.cache;
    final trailer = widget.trailer;
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [colors.surfaceContainerHigh, colors.surfaceContainerLow],
        ),
        border: Border.all(color: colors.outlineVariant.withValues(alpha: .5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: 136,
              height: 204,
              child: TvPosterArtwork(title: title, cache: cache),
            ),
          ),
          const SizedBox(width: 28),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title.kind == CatalogKind.series
                      ? (english ? 'SERIES' : 'СЕРИАЛ')
                      : (english ? 'FILM' : 'ФИЛЬМ'),
                  style: TextStyle(
                    fontSize: 11,
                    letterSpacing: 2,
                    color: colors.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  title.title(english),
                  style: const TextStyle(
                    fontSize: 30,
                    height: 1.15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  [
                    if (title.rating != null)
                      '★ ${title.rating!.toStringAsFixed(1)}',
                    if (title.year != null) '${title.year}',
                    if (title.genres != null) title.genres!,
                  ].join('   ·   '),
                  style: TextStyle(color: colors.primary, fontSize: 14),
                ),
                const SizedBox(height: 16),
                LayoutBuilder(
                  builder: (context, bounds) {
                    final text = title.synopsis(english);
                    final style = TextStyle(
                      color: colors.onSurfaceVariant,
                      height: 1.5,
                    );
                    final painter = TextPainter(
                      text: TextSpan(
                        text: text,
                        style: DefaultTextStyle.of(context).style.merge(style),
                      ),
                      maxLines: 3,
                      textDirection: Directionality.of(context),
                      textScaler: MediaQuery.textScalerOf(context),
                    )..layout(maxWidth: bounds.maxWidth);
                    final overflow = painter.didExceedMaxLines;
                    painter.dispose();
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TvAnimatedSize(
                          duration: tvMotionDuration(context, 240),
                          alignment: Alignment.topLeft,
                          curve: Curves.easeInOutCubic,
                          child: Text(
                            text,
                            maxLines: expanded ? null : 3,
                            overflow: expanded
                                ? TextOverflow.visible
                                : TextOverflow.ellipsis,
                            style: style,
                          ),
                        ),
                        if (overflow)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: RemoteButton(
                              id: 'detail-description',
                              focus: widget.focus,
                              flat: true,
                              radius: 24,
                              onPressed: () =>
                                  setState(() => expanded = !expanded),
                              child: Text(
                                expanded
                                    ? (english ? 'Show less' : 'Свернуть')
                                    : (english
                                          ? 'Full description'
                                          : 'Полное описание'),
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
                if (trailer != null) ...[const SizedBox(height: 16), trailer],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
