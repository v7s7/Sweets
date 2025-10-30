// lib/features/sweets/widgets/category_bar.dart
import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../categories/data/categories_repo.dart';
import '../../categories/data/category.dart';
import '../state/sweets_controller.dart';

/// Frosted-glass segmented Category bar (top level + optional sub row).
/// Designed to sit over content, like iOS.
/// Use from SweetsViewport: GlassCategoryBar().
class GlassCategoryBar extends ConsumerStatefulWidget {
  const GlassCategoryBar({super.key});

  @override
  ConsumerState<GlassCategoryBar> createState() => _GlassCategoryBarState();
}

class _GlassCategoryBarState extends ConsumerState<GlassCategoryBar> {
  final _topCtrl = ScrollController();
  final _subCtrl = ScrollController();

  @override
  void dispose() {
    _topCtrl.dispose();
    _subCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final catsAsync = ref.watch(categoriesStreamProvider);
    final scheme = Theme.of(context).colorScheme;
    final onSurface = scheme.onSurface;

    return catsAsync.maybeWhen(
      orElse: () => const SizedBox.shrink(),
      data: (all) {
        if (all.isEmpty) return const SizedBox.shrink();

        final String? selTop = ref.watch(selectedCategoryIdProvider);
        final String? selSub = ref.watch(selectedSubcategoryIdProvider);

        final tops = all.where((c) => c.parentId == null).toList()
          ..sort((a, b) => a.sort.compareTo(b.sort));
        final subs = selTop == null
            ? const <Category>[]
            : (all.where((c) => c.parentId == selTop).toList()
              ..sort((a, b) => a.sort.compareTo(b.sort)));

        Widget pill({
          required String? id,
          required String label,
          required bool selected,
          required VoidCallback onTap,
        }) {
          // iOS glass look: translucent base + subtle border + rounded 999
          final bg = selected
              ? onSurface.withOpacity(0.10)
              : onSurface.withOpacity(0.06);
          final border = onSurface.withOpacity(selected ? 0.25 : 0.15);
          final txt = onSurface;

          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: InkWell(
              borderRadius: BorderRadius.circular(999),
              onTap: onTap,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: border),
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                    color: txt,
                  ),
                ),
              ),
            ),
          );
        }

        Widget row({
          required List<Widget> children,
          required ScrollController controller,
        }) {
          return SingleChildScrollView(
            controller: controller,
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(children: children),
          );
        }

        // Glass container with blur + subtle gradient + hairline
        final glass = ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: scheme.surface.withOpacity(0.40),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: onSurface.withOpacity(0.08)),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    scheme.surface.withOpacity(0.42),
                    scheme.surface.withOpacity(0.32),
                  ],
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Top row
                  row(
                    controller: _topCtrl,
                    children: [
                      pill(
                        id: null,
                        label: 'All',
                        selected: selTop == null,
                        onTap: () {
                          ref.read(selectedCategoryIdProvider.notifier).state =
                              null;
                          ref
                              .read(selectedSubcategoryIdProvider.notifier)
                              .state = null;
                        },
                      ),
                      ...tops.map(
                        (c) => pill(
                          id: c.id,
                          label: c.name,
                          selected: selTop == c.id,
                          onTap: () {
                            ref
                                .read(selectedCategoryIdProvider.notifier)
                                .state = c.id;
                            ref
                                .read(selectedSubcategoryIdProvider.notifier)
                                .state = null;
                          },
                        ),
                      ),
                    ],
                  ),

                  // Divider hairline only when subs are present
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 160),
                    child: (selTop != null && subs.isNotEmpty)
                        ? Container(
                            height: 1,
                            color: onSurface.withOpacity(0.06),
                          )
                        : const SizedBox.shrink(),
                  ),

                  // Sub row
                  AnimatedSize(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOutCubic,
                    child: (selTop != null && subs.isNotEmpty)
                        ? row(
                            controller: _subCtrl,
                            children: subs
                                .map(
                                  (s) => pill(
                                    id: s.id,
                                    label: s.name,
                                    selected: selSub == s.id,
                                    onTap: () => ref
                                        .read(selectedSubcategoryIdProvider
                                            .notifier)
                                        .state = s.id,
                                  ),
                                )
                                .toList(),
                          )
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
          ),
        );

        // Constrain width so it feels like a floating control
        return ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: glass,
          ),
        );
      },
    );
  }
}
