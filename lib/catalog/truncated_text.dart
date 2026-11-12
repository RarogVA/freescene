import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Groups overflowing labels into one remote-focus tooltip for a source row.
class OverflowTooltip extends StatefulWidget {
  const OverflowTooltip({required this.child, super.key});
  final Widget child;
  @override
  State<OverflowTooltip> createState() => _OverflowTooltipState();
}

class _OverflowTooltipState extends State<OverflowTooltip> {
  final entries = <_TruncatedTextState, String>{};
  final tooltip = GlobalKey<TooltipState>();
  bool focused = false, visible = false;
  String message = '';

  void update(_TruncatedTextState id, String? text) {
    if (!mounted || entries[id] == text) return;
    if (text == null) {
      entries.remove(id);
    } else {
      entries[id] = text;
    }
    refresh();
  }

  void refresh() {
    if (!mounted) return;
    if (visible) {
      Tooltip.dismissAllToolTips();
      visible = false;
    }
    setState(() {
      final ordered = entries.entries.toList()
        ..sort(
          (a, b) =>
              a.key.widget.tooltipOrder.compareTo(b.key.widget.tooltipOrder),
        );
      message = ordered.map((entry) => entry.value).join('\n');
    });
    if (focused && message.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && focused) {
          visible = tooltip.currentState?.ensureTooltipVisible() ?? false;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) => Focus(
    canRequestFocus: false,
    skipTraversal: true,
    onFocusChange: (value) {
      focused = value;
      refresh();
    },
    child: Tooltip(
      key: tooltip,
      // Keep Tooltip's child tree stable when focus or overflow changes.
      message: message.isEmpty ? ' ' : message,
      triggerMode: TooltipTriggerMode.manual,
      showDuration: const Duration(days: 1),
      constraints: BoxConstraints(
        maxWidth: math.min(560, MediaQuery.sizeOf(context).width - 32),
      ),
      child: _OverflowScope(owner: this, child: widget.child),
    ),
  );
}

class _OverflowScope extends InheritedWidget {
  const _OverflowScope({required this.owner, required super.child});
  final _OverflowTooltipState owner;
  @override
  bool updateShouldNotify(_OverflowScope oldWidget) => owner != oldWidget.owner;
}

/// Hover hints only appear when the actual rendered label is truncated.
class TruncatedText extends StatefulWidget {
  const TruncatedText(
    this.text, {
    this.maxLines = 1,
    this.tooltipOrder = 0,
    this.style,
    this.textKey,
    super.key,
  });
  final String text;
  final int maxLines, tooltipOrder;
  final TextStyle? style;
  final Key? textKey;
  @override
  State<TruncatedText> createState() => _TruncatedTextState();
}

class _TruncatedTextState extends State<TruncatedText> {
  _OverflowTooltipState? owner;
  @override
  void dispose() {
    final previous = owner;
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => previous?.update(this, null),
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final next = context
        .dependOnInheritedWidgetOfExactType<_OverflowScope>()
        ?.owner;
    if (owner != next) {
      final previous = owner;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => previous?.update(this, null),
      );
      owner = next;
    }
    return LayoutBuilder(
      builder: (context, box) {
        final style = DefaultTextStyle.of(context).style.merge(widget.style);
        final painter = TextPainter(
          text: TextSpan(text: widget.text, style: style),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
          maxLines: widget.maxLines,
          ellipsis: '…',
        )..layout(maxWidth: box.maxWidth);
        final truncated = painter.didExceedMaxLines;
        painter.dispose();
        final text = Text(
          widget.text,
          key: widget.textKey,
          maxLines: widget.maxLines,
          overflow: TextOverflow.ellipsis,
          style: widget.style,
        );
        if (owner != null) {
          final value = truncated ? widget.text : null;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) owner?.update(this, value);
          });
          return text;
        }
        return truncated ? Tooltip(message: widget.text, child: text) : text;
      },
    );
  }
}
