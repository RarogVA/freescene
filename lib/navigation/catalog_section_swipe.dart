import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../catalog/catalog_models.dart';
import 'back_swipe_guard.dart';

/// A swipe commits one adjacent section on release. The catalogue body owns
/// the gesture; search fields, dialogs and detail tables stay outside it.
class CatalogSectionSwipe extends StatefulWidget {
  const CatalogSectionSwipe({
    required this.value,
    required this.kinds,
    required this.onChanged,
    required this.child,
    super.key,
  });
  final CatalogKind value;
  final List<CatalogKind> kinds;
  final ValueChanged<CatalogKind>? onChanged;
  final Widget child;
  static final _regions = <_CatalogSectionSwipeState>{};

  /// AppKit supplies physical direction and a point before application scaling.
  static bool handleNative(Offset point, int direction) {
    if (BackSwipeGuard.blocks(point)) return false;
    for (final region in _regions) {
      if (!region.mounted ||
          region.widget.onChanged == null ||
          ModalRoute.of(region.context)?.isCurrent != true) {
        continue;
      }
      final box = region.context.findRenderObject();
      if (box is RenderBox &&
          box.attached &&
          box.hasSize &&
          (Offset.zero & box.size).contains(box.globalToLocal(point))) {
        region.move(direction);
        return true;
      }
    }
    return false;
  }

  @override
  State<CatalogSectionSwipe> createState() => _CatalogSectionSwipeState();
}

class _CatalogSectionSwipeState extends State<CatalogSectionSwipe> {
  double distance = 0;
  @override
  void initState() {
    super.initState();
    CatalogSectionSwipe._regions.add(this);
  }

  @override
  void dispose() {
    CatalogSectionSwipe._regions.remove(this);
    super.dispose();
  }

  void move(int direction) {
    if (direction != -1 && direction != 1) return;
    final index = widget.kinds.indexOf(widget.value) + direction;
    if (index >= 0 && index < widget.kinds.length) {
      widget.onChanged?.call(widget.kinds[index]);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.onChanged == null) return widget.child;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      // AppKit already handles precise trackpad phases on macOS, including
      // natural scrolling and momentum. Do not also consume its pan events.
      supportedDevices: defaultTargetPlatform == TargetPlatform.macOS
          ? const {
              PointerDeviceKind.touch,
              PointerDeviceKind.mouse,
              PointerDeviceKind.stylus,
              PointerDeviceKind.invertedStylus,
              PointerDeviceKind.unknown,
            }
          : null,
      onHorizontalDragStart: (_) => distance = 0,
      onHorizontalDragUpdate: (event) => distance += event.primaryDelta ?? 0,
      onHorizontalDragCancel: () => distance = 0,
      onHorizontalDragEnd: (event) {
        final velocity = event.primaryVelocity ?? 0;
        if (distance.abs() >= 64 ||
            (distance.abs() >= 24 &&
                velocity.abs() >= 500 &&
                velocity.sign == distance.sign)) {
          move(distance < 0 ? 1 : -1);
        }
        distance = 0;
      },
      child: widget.child,
    );
  }
}
