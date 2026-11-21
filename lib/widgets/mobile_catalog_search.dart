import 'package:flutter/material.dart';

import 'catalog_style.dart';
import 'desktop_controls.dart';

/// The search pill opens over the section switch without moving the catalogue.
class MobileCatalogSearch extends StatefulWidget {
  const MobileCatalogSearch({
    required this.kindSwitch,
    required this.query,
    required this.english,
    required this.onSearch,
    required this.onVoice,
    required this.onFilter,
    required this.onRefresh,
    required this.filterActive,
    super.key,
  });
  final Widget kindSwitch;
  final String query;
  final bool english, filterActive;
  final ValueChanged<String> onSearch;
  final VoidCallback onVoice, onFilter, onRefresh;
  @override
  State<MobileCatalogSearch> createState() => _MobileCatalogSearchState();
}

class _MobileCatalogSearchState extends State<MobileCatalogSearch> {
  late final controller = TextEditingController(text: widget.query);
  final focus = FocusNode();
  bool expanded = false;
  String tr(String ru, String en) => widget.english ? en : ru;
  @override
  void didUpdateWidget(MobileCatalogSearch oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.query != widget.query && controller.text != widget.query) {
      controller.text = widget.query;
    }
  }

  @override
  void dispose() {
    controller.dispose();
    focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) => SizedBox(
      height: 58,
      child: Stack(
        children: [
          Positioned.fill(
            right: 66,
            child: ExcludeFocus(excluding: expanded, child: widget.kindSwitch),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TapRegion(
              onTapOutside: (_) {
                if (expanded && ModalRoute.of(context)?.isCurrent == true) {
                  focus.unfocus();
                  setState(() => expanded = false);
                }
              },
              child: AnimatedContainer(
                key: const ValueKey('mobile-search-pill'),
                width: expanded ? bounds.maxWidth : 58,
                height: 58,
                duration: motionDuration(context, 180),
                curve: Curves.easeOutCubic,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(30),
                ),
                child: OverflowBox(
                  alignment: Alignment.centerLeft,
                  minWidth: bounds.maxWidth,
                  maxWidth: bounds.maxWidth,
                  child: PillSurface(
                    child: Row(
                      children: [
                        SizedBox(
                          width: 48,
                          child: DesktopSearchAction(
                            key: const ValueKey('mobile-search-open'),
                            icon: Icons.search,
                            label: tr('Поиск', 'Search'),
                            selected: widget.query.isNotEmpty,
                            onPressed: () {
                              if (!expanded) {
                                setState(() => expanded = true);
                                focus.requestFocus();
                              } else {
                                widget.onSearch(controller.text.trim());
                                focus.unfocus();
                              }
                            },
                          ),
                        ),
                        Expanded(
                          child: TextField(
                            key: const ValueKey('mobile-search-input'),
                            controller: controller,
                            focusNode: focus,
                            enabled: expanded,
                            textInputAction: TextInputAction.search,
                            decoration: InputDecoration(
                              hintText: tr('Поиск', 'Search'),
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              disabledBorder: InputBorder.none,
                              filled: false,
                              isDense: true,
                              contentPadding: EdgeInsets.zero,
                            ),
                            onSubmitted: (value) {
                              widget.onSearch(value.trim());
                              focus.unfocus();
                            },
                          ),
                        ),
                        ValueListenableBuilder<TextEditingValue>(
                          valueListenable: controller,
                          builder: (context, value, _) => value.text.isEmpty
                              ? const SizedBox.shrink()
                              : DesktopSearchAction(
                                  icon: Icons.close,
                                  label: tr('Очистить поиск', 'Clear search'),
                                  onPressed: !expanded
                                      ? null
                                      : () {
                                          controller.clear();
                                          widget.onSearch('');
                                          focus.requestFocus();
                                        },
                                ),
                        ),
                        for (final action in [
                          (
                            id: 'voice',
                            icon: Icons.mic,
                            label: tr('Голосовой поиск', 'Voice search'),
                            run: widget.onVoice,
                          ),
                          (
                            id: 'filter',
                            icon: Icons.filter_alt_outlined,
                            label: tr('Фильтры', 'Filters'),
                            run: widget.onFilter,
                          ),
                          (
                            id: 'refresh',
                            icon: Icons.refresh,
                            label: tr('Обновить', 'Refresh'),
                            run: widget.onRefresh,
                          ),
                        ])
                          DesktopSearchAction(
                            key: ValueKey('mobile-search-${action.id}'),
                            icon: action.icon,
                            label: action.label,
                            selected:
                                action.id == 'filter' && widget.filterActive,
                            onPressed: !expanded
                                ? null
                                : () {
                                    focus.unfocus();
                                    action.run();
                                  },
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
