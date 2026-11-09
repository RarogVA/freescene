import 'dart:io';

import 'package:flutter/material.dart';

import 'poster_cache.dart';

class CachedPoster extends StatefulWidget {
  const CachedPoster({
    required this.uri,
    required this.placeholder,
    this.cache,
    this.fallback,
    this.decodeWidth = 400,
    super.key,
  });
  final Uri uri;
  final Uri? fallback;
  final Widget placeholder;
  final PosterDiskCache? cache;
  final int decodeWidth;
  @override
  State<CachedPoster> createState() => _CachedPosterState();
}

class _CachedPosterState extends State<CachedPoster> {
  late Future<({File file, Uri uri})?> image;
  int retries = 0;
  PosterDiskCache get cache => widget.cache ?? PosterDiskCache.shared;
  @override
  void initState() {
    super.initState();
    image = _load();
  }

  @override
  void didUpdateWidget(CachedPoster old) {
    super.didUpdateWidget(old);
    if (old.uri != widget.uri ||
        old.cache != widget.cache ||
        old.fallback != widget.fallback) {
      retries = 0;
      image = _load();
    }
  }

  Future<({File file, Uri uri})?> _load() async {
    final store = cache;
    final candidates = {
      widget.uri,
      if (widget.fallback != null) widget.fallback!,
    };
    for (final uri in candidates) {
      final file = await store.get(uri);
      if (file != null) return (file: file, uri: uri);
    }
    return null;
  }

  void _corrupt(File file, Uri uri) {
    if (retries++ > 0) return;
    final original = widget.uri;
    final store = cache;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await store.invalidate(uri, expected: file);
      if (mounted && widget.uri == original && cache == store) {
        setState(() {
          image = _load();
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<({File file, Uri uri})?>(
    future: image,
    builder: (context, snapshot) {
      final file = snapshot.data;
      return file == null
          ? widget.placeholder
          : Image.file(
              file.file,
              fit: BoxFit.cover,
              cacheWidth: widget.decodeWidth,
              excludeFromSemantics: true,
              gaplessPlayback: true,
              errorBuilder: (_, error, stack) {
                _corrupt(file.file, file.uri);
                return widget.placeholder;
              },
            );
    },
  );
}
