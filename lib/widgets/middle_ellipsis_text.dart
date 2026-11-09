import 'package:flutter/material.dart';

/// Retains both the identifying prefix and file/release suffix in bounded space.
class MiddleEllipsisText extends StatelessWidget {
  const MiddleEllipsisText(this.text, {this.maxLines = 2, super.key});
  final String text;
  final int maxLines;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final style = DefaultTextStyle.of(context).style;
      final scaler = MediaQuery.textScalerOf(context);
      final direction = Directionality.of(context);
      final painter = TextPainter(
        textDirection: direction,
        textScaler: scaler,
        maxLines: maxLines,
      );
      final normalized = text.replaceAll(RegExp(r'\s+'), ' ');
      bool fits(String value) {
        painter.text = TextSpan(text: value, style: style);
        painter.layout(maxWidth: constraints.maxWidth);
        return !painter.didExceedMaxLines &&
            painter.width <= constraints.maxWidth;
      }

      var visible = normalized;
      if (constraints.maxWidth.isFinite && !fits(visible)) {
        final chars = normalized.characters.toList();
        String shortened(int length) =>
            '${chars.take((length + 1) ~/ 2).join()}…${chars.skip(chars.length - length ~/ 2).join()}';
        var low = 0, high = chars.length - 1;
        while (low < high) {
          final mid = (low + high + 1) ~/ 2;
          fits(shortened(mid)) ? low = mid : high = mid - 1;
        }
        visible = shortened(low);
      }
      painter.dispose();
      return Semantics(
        label: text,
        child: ExcludeSemantics(
          child: Tooltip(
            message: text,
            excludeFromSemantics: true,
            child: Text(
              visible,
              style: style,
              textScaler: scaler,
              maxLines: maxLines,
              overflow: TextOverflow.clip,
            ),
          ),
        ),
      );
    },
  );
}
