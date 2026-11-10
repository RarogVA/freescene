import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'catalog_models.dart';
import 'source_format.dart';
import 'availability_indicator.dart';
import '../domain/availability.dart';

String? compactQuality(String? value) {
  if (value == null || value.trim().isEmpty) return null;
  final text = value.toUpperCase();
  double? height;
  final dimensions = RegExp(r'(\d{3,5})\s*[X×Х]\s*(\d{3,5})').firstMatch(text);
  if (dimensions != null) {
    final w = double.parse(dimensions[1]!), h = double.parse(dimensions[2]!);
    // Wide theatrical crops retain the resolution class of their encoded width.
    height = math.max(math.min(w, h), math.max(w, h) * 9 / 16);
  } else {
    final resolution = RegExp(r'(\d{3,4})\s*[PIР]').firstMatch(text);
    height = resolution == null ? null : double.parse(resolution[1]!);
    height ??= RegExp(r'\b[48][KК]\b|\bUHD\b').hasMatch(text)
        ? 2160
        : RegExp(r'\b2[KК]\b|\bQHD\b').hasMatch(text)
        ? 1440
        : RegExp(r'\bFHD\b|FULL\s*HD').hasMatch(text)
        ? 1080
        : RegExp(r'\bHD\b').hasMatch(text)
        ? 720
        : RegExp(r'\bSD\b|DVD').hasMatch(text)
        ? 480
        : double.tryParse(text.trim());
  }
  if (height == null || height <= 0) return null;
  const classes = {
    360: '360p',
    480: '480p',
    720: '720p',
    1080: '1080p',
    1440: '2К',
    2160: '4К',
  };
  final nearest = classes.keys.reduce(
    (a, b) => (height! - a).abs() <= (height - b).abs() ? a : b,
  );
  return classes[nearest];
}

/// Metadata can form one fitted row for remote/mouse use or a scrollable phone row.
class SourceMetadata extends StatelessWidget {
  const SourceMetadata({
    required this.source,
    required this.english,
    this.singleLine = false,
    this.scrollable = true,
    super.key,
  });
  final CatalogSource source;
  final bool english, singleLine, scrollable;
  @override
  Widget build(BuildContext context) {
    final row = source.row;
    final dark = Theme.of(context).brightness == Brightness.dark;
    Widget bubble(String type, Widget child, Color tint) => Container(
      key: ValueKey('bubble-$type'),
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: dark ? .13 : .08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tint.withValues(alpha: .28)),
      ),
      child: DefaultTextStyle.merge(
        style: TextStyle(fontSize: 12, color: tint),
        child: child,
      ),
    );
    Widget line(List<Widget> items) => Align(
      alignment: Alignment.centerLeft,
      widthFactor: 1,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0) const SizedBox(width: 6),
              items[i],
            ],
          ],
        ),
      ),
    );
    final quality = row.provider.descriptor?.qualityInPlayer == true
        ? null
        : compactQuality(row.quality);
    final details = [
      if ((row.sizeBytes ?? 0) > 0)
        bubble(
          'size',
          Text(catalogBytes(row.sizeBytes)),
          dark ? const Color(0xffc1addb) : const Color(0xff70508c),
        ),
      if ((row.durationSeconds ?? 0) > 0)
        bubble(
          'duration',
          Text(sourceDuration(row.durationSeconds)),
          dark ? const Color(0xffd8b876) : const Color(0xff86651c),
        ),
      if (row.isTorrent && TorrentAvailability(row.visibleCounts).bars != null)
        bubble(
          'availability',
          AvailabilityIndicator(source: row, english: english),
          dark ? const Color(0xff91ba9b) : const Color(0xff3f7250),
        ),
    ];
    final format = [
      if (row.provider.label.trim().isNotEmpty)
        bubble(
          'provider',
          Text(row.provider.label),
          dark ? const Color(0xff9cb8d6) : const Color(0xff42698e),
        ),
      if (quality != null)
        bubble('quality', Text(quality), Theme.of(context).colorScheme.primary),
    ];
    if (singleLine) {
      final items = [...format, ...details];
      if (!scrollable) return line(items);
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0) const SizedBox(width: 6),
              items[i],
            ],
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        line(format),
        if (details.isNotEmpty) ...[const SizedBox(height: 6), line(details)],
      ],
    );
  }
}
