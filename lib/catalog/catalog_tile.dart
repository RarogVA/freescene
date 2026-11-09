import 'package:flutter/material.dart';

/// The foreground border and actions follow the entire card, including controls.
class CatalogTile extends StatefulWidget {
  const CatalogTile({
    required this.onTap,
    required this.child,
    this.focusNode,
    super.key,
  });
  final VoidCallback onTap;
  final Widget child;
  final FocusNode? focusNode;

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
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              width: 1.5,
              color: hovered || focused
                  ? Theme.of(context).colorScheme.primary
                  : Colors.transparent,
            ),
          ),
          child: InkWell(
            focusNode: widget.focusNode,
            onTap: widget.onTap,
            child: widget.child,
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
