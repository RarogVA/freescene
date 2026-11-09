import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Keeps a horizontal content gesture from also becoming page navigation.
/// Bounds are evaluated when the native gesture ends, including UI scaling.
class BackSwipeGuard extends StatefulWidget {
  const BackSwipeGuard({required this.child, this.enabled, super.key});

  final Widget child;
  final bool Function()? enabled;

  static final _regions = <_BackSwipeGuardState>{};

  static bool blocks(Offset rootPoint) {
    for (final region in _regions) {
      if (!region.mounted || !(region.widget.enabled?.call() ?? true)) continue;
      final render = region.context.findRenderObject();
      if (render is! RenderBox || !render.attached || !render.hasSize) continue;
      var visible = true;
      for (
        RenderObject? parent = render;
        parent != null;
        parent = parent.parent
      ) {
        if (parent is RenderOffstage && parent.offstage) {
          visible = false;
          break;
        }
        if (parent is RenderAbstractViewport && parent is RenderBox) {
          final viewportBox = parent as RenderBox;
          final viewportPoint = viewportBox.globalToLocal(rootPoint);
          if (!viewportBox.hasSize ||
              !viewportPoint.dx.isFinite ||
              !viewportPoint.dy.isFinite ||
              !(Offset.zero & viewportBox.size).contains(viewportPoint)) {
            visible = false;
            break;
          }
        }
      }
      if (!visible) continue;
      final local = render.globalToLocal(rootPoint);
      if (local.dx.isFinite &&
          local.dy.isFinite &&
          (Offset.zero & render.size).contains(local)) {
        return true;
      }
    }
    return false;
  }

  @override
  State<BackSwipeGuard> createState() => _BackSwipeGuardState();
}

class _BackSwipeGuardState extends State<BackSwipeGuard> {
  @override
  void initState() {
    super.initState();
    BackSwipeGuard._regions.add(this);
  }

  @override
  void dispose() {
    BackSwipeGuard._regions.remove(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
