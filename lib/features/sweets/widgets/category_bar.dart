// lib/features/sweets/widgets/category_bar.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../categories/data/categories_repo.dart';
import '../state/sweets_controller.dart';

class CategoryBar extends ConsumerStatefulWidget {
  const CategoryBar({super.key});

  @override
  ConsumerState<CategoryBar> createState() => _CategoryBarState();
}

class _CategoryBarState extends ConsumerState<CategoryBar> {
  // increase/decrease this to move the bar further from the AppBar
  static const double _kTopGap = 20; // was 8

  final _topCtrl = ScrollController();
  final _subCtrl = ScrollController();
  bool _topHasLeft = false, _topHasRight = false;
  bool _subHasLeft = false, _subHasRight = false;

  @override
  void initState() {
    super.initState();
    _topCtrl.addListener(_updateTopFades);
    _subCtrl.addListener(_updateSubFades);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _updateTopFades();
      _updateSubFades();
    });
  }

  @override
  void dispose() {
    _topCtrl.removeListener(_updateTopFades);
    _subCtrl.removeListener(_updateSubFades);
    _topCtrl.dispose();
    _subCtrl.dispose();
    super.dispose();
  }

  void _updateTopFades() {
    if (!_topCtrl.hasClients) return;
    final atStart = _topCtrl.position.pixels <= 0.5;
    final atEnd =
        _topCtrl.position.maxScrollExtent - _topCtrl.position.pixels <= 0.5;
    final hasLeft = !atStart, hasRight = !atEnd;
    if (hasLeft != _topHasLeft || hasRight != _topHasRight) {
      setState(() {
        _topHasLeft = hasLeft;
        _topHasRight = hasRight;
      });
    }
  }

  void _updateSubFades() {
    if (!_subCtrl.hasClients) return;
    final atStart = _subCtrl.position.pixels <= 0.5;
    final atEnd =
        _subCtrl.position.maxScrollExtent - _subCtrl.position.pixels <= 0.5;
    final hasLeft = !atStart, hasRight = !atEnd;
    if (hasLeft != _subHasLeft || hasRight != _subHasRight) {
      setState(() {
        _subHasLeft = hasLeft;
        _subHasRight = hasRight;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final catsAsync = ref.watch(categoriesStreamProvider);
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final surface = Theme.of(context).colorScheme.surface;

    return catsAsync.maybeWhen(
      data: (cats) {
        final top = cats.where((c) => c.parentId == null).toList();
        final selCat = ref.watch(selectedCategoryIdProvider);
        final subs = cats.where((c) => c.parentId == selCat).toList();

        ChoiceChip chip({
          required String? id,
          required String label,
          required bool selected,
          VoidCallback? onTap,
        }) =>
            ChoiceChip(
              label: Text(label, style: TextStyle(color: onSurface)),
              selected: selected,
              onSelected: (_) => onTap?.call(),
              backgroundColor: Colors.black.withOpacity(0.20),
              selectedColor: Colors.black.withOpacity(0.28),
              side: BorderSide(color: onSurface.withOpacity(0.6)),
              shape: const StadiumBorder(),
              visualDensity: VisualDensity.compact,
            );

        Widget fadedRow({
          required ScrollController controller,
          required List<Widget> children,
          required bool showLeft,
          required bool showRight,
          EdgeInsets padding = const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 8,
          ),
        }) {
          const fadeWidth = 28.0;
          return Stack(
            children: [
              SingleChildScrollView(
                controller: controller,
                scrollDirection: Axis.horizontal,
                padding: padding,
                physics: const BouncingScrollPhysics(),
                child: Row(children: children),
              ),
              Positioned.fill(
                left: 0,
                child: IgnorePointer(
                  child: AnimatedOpacity(
                    opacity: showLeft ? 1 : 0,
                    duration: const Duration(milliseconds: 160),
                    curve: Curves.easeOut,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        width: fadeWidth,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                            colors: [surface, surface.withOpacity(0)],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned.fill(
                right: 0,
                child: IgnorePointer(
                  child: AnimatedOpacity(
                    opacity: showRight ? 1 : 0,
                    duration: const Duration(milliseconds: 160),
                    curve: Curves.easeOut,
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Container(
                        width: fadeWidth,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.centerRight,
                            end: Alignment.centerLeft,
                            colors: [surface, surface.withOpacity(0)],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        }

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(height: _kTopGap), // extra spacing below the AppBar
            fadedRow(
              controller: _topCtrl,
              showLeft: _topHasLeft,
              showRight: _topHasRight,
              children: [
                chip(
                  id: null,
                  label: 'All',
                  selected: selCat == null,
                  onTap: () {
                    ref.read(selectedCategoryIdProvider.notifier).state = null;
                    ref
                        .read(selectedSubcategoryIdProvider.notifier)
                        .state = null;
                    WidgetsBinding.instance
                        .addPostFrameCallback((_) => _updateSubFades());
                  },
                ),
                const SizedBox(width: 8),
                ...top.map(
                  (c) => Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: chip(
                      id: c.id,
                      label: c.name,
                      selected: selCat == c.id,
                      onTap: () {
                        ref
                            .read(selectedCategoryIdProvider.notifier)
                            .state = c.id;
                        ref
                            .read(selectedSubcategoryIdProvider.notifier)
                            .state = null;
                        WidgetsBinding.instance
                            .addPostFrameCallback((_) => _updateSubFades());
                      },
                    ),
                  ),
                ),
              ],
            ),
            if (selCat != null && subs.isNotEmpty)
              fadedRow(
                controller: _subCtrl,
                showLeft: _subHasLeft,
                showRight: _subHasRight,
                children: subs
                    .map(
                      (s) => Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: chip(
                          id: s.id,
                          label: s.name,
                          selected:
                              ref.watch(selectedSubcategoryIdProvider) == s.id,
                          onTap: () => ref
                              .read(selectedSubcategoryIdProvider.notifier)
                              .state = s.id,
                        ),
                      ),
                    )
                    .toList(),
              ),
          ],
        );
      },
      orElse: () => const SizedBox.shrink(),
    );
  }
}
