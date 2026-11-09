import 'package:flutter/material.dart';

import 'android_theme.dart';

/// Unlike FocusNode.debugLabel, this identity survives release compilation.
class RemoteFocusNode extends FocusNode {
  RemoteFocusNode(this.id) : super(debugLabel: id);
  String id;
}

/// Dialog controls use the same visual axes, without inheriting the catalogue
/// registry or leaving the active route. Left/right never changes rows.
class RemoteDialogTraversalPolicy extends FocusTraversalPolicy {
  final readingOrder = ReadingOrderTraversalPolicy();
  @override
  Iterable<FocusNode> sortDescendants(
    Iterable<FocusNode> descendants,
    FocusNode currentNode,
  ) => readingOrder.sortDescendants(descendants, currentNode);
  @override
  FocusNode? findFirstFocusInDirection(
    FocusNode currentNode,
    TraversalDirection direction,
  ) => findFirstFocus(currentNode, ignoreCurrentFocus: true);
  @override
  bool inDirection(FocusNode currentNode, TraversalDirection direction) {
    final horizontal =
        direction == TraversalDirection.left ||
        direction == TraversalDirection.right;
    final sign =
        direction == TraversalDirection.left ||
            direction == TraversalDirection.up
        ? -1
        : 1;
    final rect = currentNode.rect;
    final candidates =
        <({FocusNode node, double main, double cross, bool aligned})>[];
    for (final node in currentNode.nearestScope!.traversalDescendants) {
      if (node == currentNode ||
          node is FocusScopeNode ||
          node.context == null) {
        continue;
      }
      final other = node.rect;
      final delta = other.center - rect.center;
      final main = (horizontal ? delta.dx : delta.dy) * sign;
      if (main < 1) continue;
      final aligned = horizontal
          ? other.top < rect.bottom - 1 && other.bottom > rect.top + 1
          : other.left < rect.right - 1 && other.right > rect.left + 1;
      candidates.add((
        node: node,
        main: main,
        cross: (horizontal ? delta.dy : delta.dx).abs(),
        aligned: aligned,
      ));
    }
    if (horizontal || candidates.any((c) => c.aligned)) {
      candidates.removeWhere((c) => !c.aligned);
    }
    candidates.sort((a, b) {
      final main = a.main.compareTo(b.main);
      return main == 0 ? a.cross.compareTo(b.cross) : main;
    });
    if (candidates.isNotEmpty) {
      final next = candidates.first.node;
      next.requestFocus();
      Scrollable.ensureVisible(next.context!, alignment: 0.5);
    }
    return true;
  }
}

/// Stable identities survive page rebuilds; disposed controls are never focused.
/// The view owns nodes, while this registry owns only references to live nodes.
class RemoteFocus {
  RemoteFocus({this.enabled = true});

  /// Phones use normal touch/keyboard focus, without TV restoration or scrolling.
  final bool enabled;
  final Map<String, FocusNode> _nodes = {};
  String? last;
  bool _disposed = false;
  bool _scheduled = false;
  int _generation = 0;
  void register(String id, FocusNode node) => _nodes[id] = node;
  void unregister(String id, FocusNode node) {
    if (_nodes[id] == node) _nodes.remove(id);
  }

  void selected(String id) => last = id;
  void restore(String? id, {String fallback = 'home'}) {
    if (!enabled) return;
    final generation = ++_generation;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_disposed || generation != _generation) return;
      final candidates = [_nodes[id], _nodes[fallback], ..._nodes.values];
      for (final node in candidates) {
        if (node != null && node.context != null && node.canRequestFocus) {
          node.requestFocus();
          Scrollable.ensureVisible(node.context!, alignment: 0.5);
          Future.microtask(() {
            if (generation == _generation) _scheduled = false;
          });
          return;
        }
      }
      _scheduled = false;
    });
  }

  void repair() {
    if (!enabled) return;
    if (_scheduled) return;
    if (_nodes.values.any(
      (node) => node.hasPrimaryFocus && node.canRequestFocus,
    )) {
      return;
    }
    restore(last);
  }

  void dispose() {
    _disposed = true;
    ++_generation;
    _nodes.clear();
  }
}

/// Remote navigation has no history-dependent reversal cache. Only mounted,
/// enabled controls participate; requesting focus also scrolls them into view.
class RemoteTraversalPolicy extends FocusTraversalPolicy {
  const RemoteTraversalPolicy(
    this.registry, {
    this.horizontalGroups = const [],
    this.verticalGroups = const [],
  });
  final RemoteFocus registry;
  final List<List<String>> horizontalGroups, verticalGroups;
  @override
  Iterable<FocusNode> sortDescendants(
    Iterable<FocusNode> descendants,
    FocusNode currentNode,
  ) => descendants;

  @override
  FocusNode? findFirstFocusInDirection(
    FocusNode currentNode,
    TraversalDirection direction,
  ) => findFirstFocus(currentNode, ignoreCurrentFocus: true);

  @override
  bool inDirection(FocusNode currentNode, TraversalDirection direction) {
    final rect = currentNode.rect;
    final origin = rect.center;
    final id = currentNode is RemoteFocusNode ? currentNode.id : null;
    bool tile(FocusNode node) =>
        node is RemoteFocusNode && node.id.startsWith('title-');
    bool rail(FocusNode node) =>
        node is RemoteFocusNode &&
        verticalGroups.any((group) => group.contains(node.id));
    bool overlaps(Rect other, bool horizontal) => horizontal
        ? other.top < rect.bottom - 1 && other.bottom > rect.top + 1
        : other.left < rect.right - 1 && other.right > rect.left + 1;
    final horizontal =
        direction == TraversalDirection.left ||
        direction == TraversalDirection.right;
    final sign =
        direction == TraversalDirection.left ||
            direction == TraversalDirection.up
        ? -1
        : 1;
    // Distant controls in the rail and adjacent toolbar controls retain their
    // visual order even when geometric distance favours another part of the UI.
    for (final group in horizontal ? horizontalGroups : verticalGroups) {
      final index = group.indexOf(id ?? '');
      if (index < 0) continue;
      for (var i = index + sign; i >= 0 && i < group.length; i += sign) {
        final next = registry._nodes[group[i]];
        if (next == null ||
            next.context == null ||
            !next.canRequestFocus ||
            next.skipTraversal) {
          continue;
        }
        // A toolbar can wrap on a phone: never jump to another visual row.
        if (horizontal && !overlaps(next.rect, true)) continue;
        next.requestFocus();
        Scrollable.ensureVisible(next.context!, alignment: 0.5);
        return true;
      }
      if (!horizontal) return true;
    }
    final candidates =
        <({FocusNode node, double main, double cross, bool aligned})>[];
    for (final node in registry._nodes.values) {
      if (node == currentNode ||
          node.context == null ||
          !node.canRequestFocus ||
          node.skipTraversal) {
        continue;
      }
      // Up/down in content must never jump sideways into the distant rail.
      if (!horizontal && rail(node)) continue;
      final delta = node.rect.center - origin;
      final main = horizontal ? delta.dx : delta.dy;
      if (main * sign < 1) continue;
      final cross = horizontal ? delta.dy : delta.dx;
      candidates.add((
        node: node,
        main: main.abs(),
        cross: cross.abs(),
        aligned: overlaps(node.rect, horizontal),
      ));
    }
    // A poster row/column never wraps diagonally to the next row/column.
    // The left edge is the route to the navigation rail; up from row one
    // returns to the toolbar. At the bottom/right edge focus stays put.
    if (tile(currentNode)) {
      final adjacent = candidates
          .where((c) => tile(c.node) && c.aligned)
          .toList();
      if (adjacent.isNotEmpty) {
        candidates
          ..clear()
          ..addAll(adjacent);
      } else if (direction == TraversalDirection.down ||
          direction == TraversalDirection.right) {
        return true;
      } else {
        candidates.removeWhere((c) => tile(c.node));
      }
    }
    if (candidates.any((c) => c.aligned)) {
      candidates.removeWhere((c) => !c.aligned);
    } else if (horizontal && !rail(currentNode)) {
      // Leaving a row is explicit: only its left edge may enter the rail.
      candidates.removeWhere(
        (c) => direction != TraversalDirection.left || !rail(c.node),
      );
    }
    if (candidates.isEmpty) return true;
    candidates.sort((a, b) {
      if (a.aligned && b.aligned) {
        final distance = a.main.compareTo(b.main);
        return distance != 0 ? distance : a.cross.compareTo(b.cross);
      }
      return (a.main * a.main + 4 * a.cross * a.cross).compareTo(
        b.main * b.main + 4 * b.cross * b.cross,
      );
    });
    final next = candidates.first.node;
    next.requestFocus();
    Scrollable.ensureVisible(next.context!, alignment: 0.5);
    return true;
  }
}

class RemoteButton extends StatefulWidget {
  const RemoteButton({
    required this.id,
    required this.focus,
    required this.onPressed,
    required this.child,
    this.selected = false,
    this.selectedBackground,
    this.selectedForeground,
    this.padding = const EdgeInsets.all(12),
    this.radius = 12,
    this.flat = false,
    this.tile = false,
    this.segment = false,
    this.alignment = Alignment.center,
    super.key,
  });
  final String id;
  final RemoteFocus focus;
  final VoidCallback? onPressed;
  final Widget child;
  final bool selected;
  final Color? selectedBackground, selectedForeground;
  final EdgeInsetsGeometry padding;
  final double radius;
  final bool flat, tile, segment;
  final AlignmentGeometry alignment;
  @override
  State<RemoteButton> createState() => _RemoteButtonState();
}

class _RemoteButtonState extends State<RemoteButton> {
  late final node = RemoteFocusNode(widget.id);
  bool focused = false;
  @override
  void initState() {
    super.initState();
    widget.focus.register(widget.id, node);
  }

  @override
  void didUpdateWidget(RemoteButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.id != widget.id || oldWidget.focus != widget.focus) {
      oldWidget.focus.unregister(oldWidget.id, node);
      node.id = widget.id;
      node.debugLabel = widget.id;
      widget.focus.register(widget.id, node);
    }
  }

  @override
  void dispose() {
    widget.focus.unregister(widget.id, node);
    node.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final outlineOnly =
        Theme.of(context).extension<RemoteFocusStyle>()?.outlineOnly ?? false;
    return OutlinedButton(
      key: ValueKey('remote-${widget.id}'),
      focusNode: node,
      onPressed: widget.onPressed,
      onFocusChange: (value) {
        if (!widget.focus.enabled) return;
        setState(() => focused = value);
        if (value) {
          widget.focus.selected(widget.id);
          Scrollable.ensureVisible(context, alignment: 0.5);
        }
      },
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 48),
        padding: widget.padding,
        alignment: widget.alignment,
        overlayColor: outlineOnly ? Colors.transparent : null,
        backgroundColor: focused && !widget.tile && !outlineOnly
            ? colors.primary
            : widget.selected
            ? widget.selectedBackground ??
                  (widget.segment
                      ? colors.primary.withValues(alpha: 0.9)
                      : colors.secondaryContainer)
            : widget.tile
            ? colors.surfaceContainer
            : null,
        foregroundColor: focused && !widget.tile && !outlineOnly
            ? colors.onPrimary
            : widget.selected
            ? widget.selectedForeground ??
                  (widget.segment ? colors.onPrimary : colors.onSurface)
            : colors.onSurface,
        side: BorderSide(
          color: focused
              ? colors.primary
              : widget.flat || widget.tile
              ? Colors.transparent
              : colors.outlineVariant,
          width: focused ? 3 : 1,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(widget.radius),
        ),
        animationDuration: widget.focus.enabled ? Duration.zero : null,
      ),
      child: widget.tile
          ? DecoratedBox(
              position: DecorationPosition.foreground,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(widget.radius),
                border: Border.all(
                  color: focused ? colors.primary : Colors.transparent,
                  width: 3,
                ),
              ),
              child: widget.child,
            )
          : widget.child,
    );
  }
}
