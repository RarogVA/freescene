import 'package:flutter/material.dart';

import 'catalog_models.dart';
import 'catalog_page.dart' show SourceTable, catalogError;

class SourceLinkDialog extends StatefulWidget {
  const SourceLinkDialog({
    required this.english,
    this.onUseSource,
    required this.catalog,
    super.key,
  });
  final bool english;
  final Future<void> Function(CatalogSource, bool)? onUseSource;
  final SourceLinkCatalog catalog;
  @override
  State<SourceLinkDialog> createState() => _SourceLinkDialogState();
}

class _SourceLinkDialogState extends State<SourceLinkDialog> {
  final input = TextEditingController();
  late final catalog = widget.catalog;
  List<CatalogSource> sources = [];
  String? error;
  String activeLink = '';
  int next = 0;
  bool busy = false, more = false, loaded = false;
  String tr(String ru, String en) => widget.english ? en : ru;
  Future<void> load({bool append = false}) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
      if (!append) {
        sources = [];
        more = false;
        activeLink = input.text.trim();
      }
    });
    try {
      final page = await catalog.fromLink(activeLink, start: append ? next : 0);
      if (!mounted) return;
      final seen = sources.map((s) => s.row.id).toSet();
      setState(() {
        sources = [...sources, ...page.items.where((s) => seen.add(s.row.id))];
        next = page.next;
        more = page.hasMore;
        loaded = true;
      });
    } catch (e) {
      if (mounted) setState(() => error = catalogError(e, widget.english));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    input.dispose();
    catalog.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(tr('Видео и плейлисты', 'Videos and playlists')),
    content: SizedBox(
      width: 1000,
      height: 500,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: input,
            maxLength: 512,
            enabled: !busy,
            decoration: const InputDecoration(hintText: 'https://…'),
            onSubmitted: (_) => load(),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: busy ? null : () => load(),
              icon: const Icon(Icons.search),
              label: Text(tr('Открыть список', 'Load videos')),
            ),
          ),
          if (busy) const LinearProgressIndicator(),
          if (error != null)
            SelectableText(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          if (loaded && sources.isEmpty && !busy)
            Text(
              tr(
                'Видео не найдены или недоступны',
                'No available videos found',
              ),
            ),
          Expanded(
            child: SingleChildScrollView(
              child: SourceTable(
                sources: sources,
                english: widget.english,
                game: false,
                series: true,
                onUseSource: widget.onUseSource,
              ),
            ),
          ),
          if (more)
            TextButton(
              onPressed: busy ? null : () => load(append: true),
              child: Text(tr('Загрузить ещё', 'Load more')),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(tr('Закрыть', 'Close')),
      ),
    ],
  );
}
