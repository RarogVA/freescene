import 'package:flutter/material.dart';

import '../widgets/catalog_style.dart';
import '../catalog/catalog_models.dart';
import '../catalog/poster_cache.dart';
import 'remote_focus.dart';

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
  Widget build(BuildContext context) => PillSurface(
    child: RemoteButton(
      id: id,
      focus: focus,
      selected: selected,
      onPressed: onPressed,
      flat: true,
      radius: 24,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Semantics(
        label: label,
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
                    duration: motionDuration(context, 220),
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

/// Move a laid-out toolbar behind a fixed rounded clip. The list of posters
/// and the search actions do not rebuild on animation ticks.
class TvSearchPill extends StatefulWidget {
  const TvSearchPill({
    required this.keepOpen,
    required this.content,
    super.key,
  });

  final bool Function() keepOpen;
  final Widget Function(bool expanded, double width) content;

  @override
  State<TvSearchPill> createState() => _TvSearchPillState();
}

class _TvSearchPillState extends State<TvSearchPill> {
  bool expanded = false;

  @override
  Widget build(BuildContext context) => Focus(
    canRequestFocus: false,
    skipTraversal: true,
    onFocusChange: (value) {
      if (expanded != value && (value || !widget.keepOpen())) {
        setState(() => expanded = value);
      }
    },
    child: LayoutBuilder(
      builder: (context, bounds) => RepaintBoundary(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(30),
          child: TweenAnimationBuilder<double>(
            tween: Tween(end: expanded ? 0.0 : 1.0),
            duration: motionDuration(context, 180),
            curve: Curves.easeOutCubic,
            child: RepaintBoundary(
              child: PillSurface(
                child: widget.content(expanded, bounds.maxWidth),
              ),
            ),
            builder: (_, fraction, bar) => Transform.translate(
              offset: Offset(
                (bounds.maxWidth - 58).clamp(0.0, double.infinity) * fraction,
                0,
              ),
              child: bar,
            ),
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
    duration: motionDuration(context, 240),
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
              child: PosterArtwork(title: title, cache: cache),
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
                          duration: motionDuration(context, 240),
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
                        if (trailer != null || overflow)
                          Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Wrap(
                              spacing: 12,
                              runSpacing: 8,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                ?trailer,
                                if (overflow)
                                  RemoteButton(
                                    id: 'detail-description',
                                    focus: widget.focus,
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
                              ],
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
