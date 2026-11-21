import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The foreground border and actions follow the entire card, including controls.
class CatalogTile extends StatefulWidget {
  const CatalogTile({
    required this.onTap,
    required this.child,
    this.focusNode,
    this.onContextMenu,
    super.key,
  });
  final VoidCallback onTap;
  final Widget child;
  final FocusNode? focusNode;
  final Future<void> Function()? onContextMenu;

  static bool actionsRevealedOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<_CatalogTileInteraction>()
          ?.active ??
      true;

  @override
  State<CatalogTile> createState() => _CatalogTileState();
}

class _CatalogTileState extends State<CatalogTile> {
  bool hovered = false, focused = false;
  bool menuOpen = false, controlClick = false;
  int? pointer;
  static const contextMenuChannel = MethodChannel('freescene/context_menu');
  static final tiles = <_CatalogTileState>{};

  @override
  void initState() {
    super.initState();
    if (tiles.isEmpty) {
      contextMenuChannel.setMethodCallHandler((call) async {
        if (call.method != 'forceClick' || call.arguments is! Map) return;
        final args = call.arguments as Map;
        if (args['x'] is! num || args['y'] is! num) return;
        final position = Offset(
          (args['x'] as num).toDouble(),
          (args['y'] as num).toDouble(),
        );
        for (final tile in tiles.toList()) {
          final box = tile.context.findRenderObject();
          if (tile.mounted &&
              ModalRoute.of(tile.context)?.isCurrent == true &&
              box is RenderBox &&
              box.attached &&
              (Offset.zero & box.size).contains(box.globalToLocal(position))) {
            if (tile.pointer case final pointer?) {
              GestureBinding.instance.cancelPointer(pointer);
            }
            unawaited(tile.openMenu());
            break;
          }
        }
      });
    }
    tiles.add(this);
  }

  @override
  void dispose() {
    tiles.remove(this);
    if (tiles.isEmpty) contextMenuChannel.setMethodCallHandler(null);
    super.dispose();
  }

  Future<void> openMenu() async {
    if (menuOpen || widget.onContextMenu == null) return;
    menuOpen = true;
    try {
      await widget.onContextMenu!();
    } finally {
      menuOpen = false;
    }
  }

  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) => setState(() => hovered = true),
    onExit: (_) => setState(() => hovered = false),
    child: Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (value) => setState(() => focused = value),
      child: _CatalogTileInteraction(
        active: hovered || focused,
        child: Card(
          clipBehavior: Clip.antiAlias,
          borderOnForeground: true,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(
              width: 1.5,
              color: hovered || focused
                  ? Theme.of(context).colorScheme.primary
                  : Colors.transparent,
            ),
          ),
          child: Listener(
            onPointerDown: (event) => pointer = event.pointer,
            onPointerUp: (_) => pointer = null,
            onPointerCancel: (_) => pointer = null,
            child: InkWell(
              focusNode: widget.focusNode,
              onTapDown: (_) =>
                  controlClick = HardwareKeyboard.instance.isControlPressed,
              onTap: () => controlClick && widget.onContextMenu != null
                  ? openMenu()
                  : widget.onTap(),
              onLongPress: widget.onContextMenu == null ? null : openMenu,
              onSecondaryTap: widget.onContextMenu == null ? null : openMenu,
              child: widget.child,
            ),
          ),
        ),
      ),
    ),
  );
}

class _CatalogTileInteraction extends InheritedWidget {
  const _CatalogTileInteraction({required this.active, required super.child});
  final bool active;
  @override
  bool updateShouldNotify(_CatalogTileInteraction oldWidget) =>
      active != oldWidget.active;
}

/// Hidden actions keep their geometry; they cannot intercept a card click or Tab.
class CatalogTileAction extends StatelessWidget {
  const CatalogTileAction({
    required this.selected,
    required this.child,
    super.key,
  });
  final bool selected;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final visible = selected || CatalogTile.actionsRevealedOf(context);
    return IgnorePointer(
      ignoring: !visible,
      child: ExcludeFocus(
        excluding: !visible,
        child: ExcludeSemantics(
          excluding: !visible,
          child: Opacity(opacity: visible ? 1 : 0, child: child),
        ),
      ),
    );
  }
}
