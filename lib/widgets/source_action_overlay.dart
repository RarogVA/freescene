import 'package:flutter/material.dart';

import 'catalog_style.dart';

/// Actions paint over a source row; their animation never participates in layout.
class SourceActionOverlay extends StatefulWidget {
  const SourceActionOverlay({
    required this.child,
    required this.actions,
    this.busy = false,
    super.key,
  });
  final Widget child, actions;
  final bool busy;

  @override
  State<SourceActionOverlay> createState() => _SourceActionOverlayState();
}

class _SourceActionOverlayState extends State<SourceActionOverlay> {
  bool hovered = false, focused = false;

  @override
  Widget build(BuildContext context) {
    final visible = hovered || focused || widget.busy;
    return MouseRegion(
      onEnter: (_) => setState(() => hovered = true),
      onExit: (_) => setState(() => hovered = false),
      child: Focus(
        canRequestFocus: false,
        onFocusChange: (value) => setState(() => focused = value),
        child: Stack(
          children: [
            widget.child,
            Positioned(
              left: 16,
              right: 64,
              top: 0,
              bottom: 0,
              child: IgnorePointer(
                ignoring: !visible,
                child: AnimatedOpacity(
                  opacity: visible ? 1 : 0,
                  alwaysIncludeSemantics: true,
                  duration: motionDuration(context, 180),
                  child: widget.actions,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
