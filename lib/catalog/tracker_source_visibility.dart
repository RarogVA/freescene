import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'catalog_models.dart';
import 'tracker_updates.dart';

/// Cached sliver children and the off-screen rows of the TV column can both
/// be built before they are visible. Acknowledge only after layout and scroll.
class TrackerSourceVisibility extends StatefulWidget {
  const TrackerSourceVisibility({
    required this.child,
    required this.title,
    required this.events,
    required this.updates,
    super.key,
  });
  final Widget child;
  final CatalogTitle title;
  final Set<String> events;
  final TrackerUpdates updates;

  static Widget wrap(
    Widget child,
    TrackerUpdates? updates,
    CatalogTitle? title,
    CatalogSource source,
  ) {
    if (updates == null || title == null) return child;
    final events = updates.shownEvents(title, source);
    return events.isEmpty
        ? child
        : TrackerSourceVisibility(
            title: title,
            events: events,
            updates: updates,
            child: child,
          );
  }

  @override
  State<TrackerSourceVisibility> createState() =>
      _TrackerSourceVisibilityState();
}

class _TrackerSourceVisibilityState extends State<TrackerSourceVisibility> {
  ScrollPosition? _position;
  bool _scheduled = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _position?.removeListener(_check);
    _position = Scrollable.maybeOf(context)?.position;
    _position?.addListener(_check);
  }

  void _check() {
    if (_scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!mounted || ModalRoute.of(context)?.isCurrent == false) return;
      final box = context.findRenderObject();
      if (box is! RenderBox || !box.attached || !box.hasSize) return;
      final viewport = RenderAbstractViewport.maybeOf(box);
      if (viewport == null) return;
      final bounds = MatrixUtils.transformRect(
        box.getTransformTo(viewport),
        box.paintBounds,
      );
      if (viewport.paintBounds.overlaps(bounds)) {
        widget.updates.acknowledge(widget.title, widget.events);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    _check();
    return widget.child;
  }

  @override
  void dispose() {
    _position?.removeListener(_check);
    super.dispose();
  }
}
