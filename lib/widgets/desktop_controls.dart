import 'package:flutter/material.dart';

import 'catalog_style.dart';

/// A circular action that reveals its caption for both pointer and keyboard use.
class DesktopActionButton extends StatefulWidget {
  const DesktopActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.selected = false,
    this.alwaysExpanded = false,
    this.revealLabel = true,
    this.size = 44,
    this.glyph,
    super.key,
  });
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool selected, alwaysExpanded, revealLabel;
  final double size;
  final Widget? glyph;

  @override
  State<DesktopActionButton> createState() => _DesktopActionButtonState();
}

class _DesktopActionButtonState extends State<DesktopActionButton> {
  bool hovered = false, focused = false;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final expanded =
        widget.alwaysExpanded || (widget.revealLabel && (hovered || focused));
    return Semantics(
      label: widget.label,
      button: true,
      selected: widget.selected,
      enabled: widget.onPressed != null,
      focusable: widget.onPressed != null,
      focused: focused,
      onTap: widget.onPressed,
      excludeSemantics: true,
      child: Tooltip(
        message: widget.label,
        child: FilledButton(
          onPressed: widget.onPressed,
          onHover: (value) => setState(() => hovered = value),
          onFocusChange: (value) => setState(() => focused = value),
          style: FilledButton.styleFrom(
            minimumSize: Size.square(widget.size),
            maximumSize: Size(double.infinity, widget.size),
            padding: EdgeInsets.symmetric(horizontal: (widget.size - 20) / 2),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.standard,
            shape: const StadiumBorder(),
            backgroundColor: widget.selected
                ? colors.primaryContainer
                : colors.surfaceContainerHigh,
            foregroundColor: widget.selected
                ? colors.onPrimaryContainer
                : colors.onSurface,
            side: BorderSide(
              color: colors.outlineVariant.withValues(alpha: .65),
            ),
          ),
          child: ExcludeSemantics(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                widget.glyph ?? Icon(widget.icon, size: 20),
                Flexible(
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(end: expanded ? 1 : 0),
                    duration: motionDuration(context, 220),
                    curve: Curves.easeOutCubic,
                    builder: (context, value, child) => ClipRect(
                      child: Align(
                        widthFactor: value,
                        alignment: AlignmentDirectional.centerStart,
                        child: child,
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsetsDirectional.only(start: 8),
                      child: Text(
                        widget.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The field keeps its controller and focus while its pill opens and closes.
class DesktopSearchField extends StatefulWidget {
  const DesktopSearchField({
    required this.controller,
    required this.label,
    required this.onChanged,
    required this.clearLabel,
    this.onSubmitted,
    this.onCleared,
    this.trailing = const [],
    this.expandedWidth = 360,
    this.alignment = AlignmentDirectional.centerEnd,
    this.shrinkWrap = false,
    this.fieldKey,
    this.clearKey,
    super.key,
  });
  final TextEditingController controller;
  final String label, clearLabel;
  final ValueChanged<String> onChanged;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onCleared;
  final List<Widget> trailing;
  final double expandedWidth;
  final AlignmentGeometry alignment;
  final bool shrinkWrap;
  final Key? fieldKey, clearKey;

  @override
  State<DesktopSearchField> createState() => _DesktopSearchFieldState();
}

class _DesktopSearchFieldState extends State<DesktopSearchField> {
  final focus = FocusNode();
  bool hovered = false;
  @override
  void initState() {
    super.initState();
    focus.addListener(changed);
    widget.controller.addListener(changed);
  }

  void changed() => setState(() {});
  @override
  void didUpdateWidget(DesktopSearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(changed);
      widget.controller.addListener(changed);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(changed);
    focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.shrinkWrap
      ? field(context, widget.expandedWidth)
      : LayoutBuilder(
          builder: (context, bounds) =>
              field(context, bounds.maxWidth.clamp(44.0, widget.expandedWidth)),
        );

  Widget field(BuildContext context, double width) {
    final open = hovered || focus.hasFocus || widget.controller.text.isNotEmpty;
    final colors = Theme.of(context).colorScheme;
    return Align(
      alignment: widget.alignment,
      widthFactor: widget.shrinkWrap ? 1 : null,
      child: MouseRegion(
        onEnter: (_) => setState(() => hovered = true),
        onExit: (_) => setState(() => hovered = false),
        child: AnimatedContainer(
          duration: motionDuration(context, 220),
          curve: Curves.easeOutCubic,
          width: open ? width : 44,
          height: 44,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            color: colors.surfaceContainerHigh,
            border: Border.all(
              color: focus.hasFocus ? colors.primary : colors.outlineVariant,
            ),
          ),
          child: OverflowBox(
            alignment: AlignmentDirectional.centerStart,
            minWidth: width,
            maxWidth: width,
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    key: widget.fieldKey,
                    focusNode: focus,
                    controller: widget.controller,
                    onChanged: widget.onChanged,
                    onSubmitted: widget.onSubmitted,
                    textAlignVertical: TextAlignVertical.center,
                    decoration: InputDecoration(
                      hintText: widget.label,
                      isDense: true,
                      filled: false,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                      prefixIconConstraints: const BoxConstraints.tightFor(
                        width: 42,
                        height: 42,
                      ),
                      prefixIcon: IconButton(
                        tooltip: widget.label,
                        onPressed: focus.requestFocus,
                        icon: const Icon(Icons.search_rounded, size: 20),
                      ),
                      suffixIcon: widget.controller.text.isEmpty
                          ? null
                          : IconButton(
                              key: widget.clearKey,
                              tooltip: widget.clearLabel,
                              onPressed: () {
                                widget.controller.clear();
                                if (widget.onCleared != null) {
                                  widget.onCleared!();
                                } else {
                                  widget.onChanged('');
                                }
                                focus.requestFocus();
                              },
                              icon: const Icon(Icons.close_rounded, size: 18),
                            ),
                    ),
                  ),
                ),
                if (open) ...[
                  for (final action in widget.trailing) ...[
                    const SizedBox(width: 4),
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: ((width - 100) / 2).clamp(44.0, 130.0),
                      ),
                      child: action,
                    ),
                  ],
                  if (widget.trailing.isNotEmpty) const SizedBox(width: 4),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class DesktopPicker extends StatelessWidget {
  const DesktopPicker({required this.icon, required this.child, super.key});
  final IconData icon;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHigh,
        border: Border.all(color: colors.outlineVariant.withValues(alpha: .65)),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: colors.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(child: DropdownButtonHideUnderline(child: child)),
        ],
      ),
    );
  }
}
