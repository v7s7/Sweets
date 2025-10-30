// lib/features/sweets/widgets/category_bar.dart
import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../categories/data/categories_repo.dart';
import '../../categories/data/category.dart';
import '../state/sweets_controller.dart';
import '../../sweets/data/sweets_repo.dart';
import '../../sweets/data/sweet.dart';

/// Frosted-glass segmented Category bar (top level + optional sub row).
/// Hides empty categories/subcategories until they have at least one active item.
/// Place below the hero and above the cart controls.
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
    final catsAsync   = ref.watch(categoriesStreamProvider);
    final sweetsAsync = ref.watch(sweetsStreamProvider);

    final scheme    = Theme.of(context).colorScheme;
    final onSurface = scheme.onSurface;

    return catsAsync.maybeWhen(
      orElse: () => const SizedBox.shrink(),
      data: (allCats) {
        if (allCats.isEmpty) return const SizedBox.shrink();

        // Current selections
        final String? selTop = ref.watch(selectedCategoryIdProvider);
        final String? selSub = ref.watch(selectedSubcategoryIdProvider);

        // Active items → set of used categoryIds (each product saves either sub or top into categoryId)
        final List<Sweet> items = sweetsAsync.value ?? const <Sweet>[];
        final Set<String> used = {
          for (final s in items)
            if ((s.categoryId ?? '').isNotEmpty) s.categoryId!,
        };

        // Compute visible tops (has own items OR any child with items)
        final List<Category> tops = allCats
            .where((c) => c.parentId == null)
            .where((top) {
              final hasDirect = used.contains(top.id);
              final hasChildWithItems = allCats.any(
                (x) => x.parentId == top.id && used.contains(x.id),
              );
              return hasDirect || hasChildWithItems;
            })
            .toList()
          ..sort((a, b) => a.sort.compareTo(b.sort));

        // Visible subs of selected top (only those that actually have items)
        final List<Category> subs = (selTop == null)
            ? const <Category>[]
            : (allCats
                .where((c) => c.parentId == selTop && used.contains(c.id))
                .toList()
              ..sort((a, b) => a.sort.compareTo(b.sort)));

        // ----- Guard: if selection points to hidden/empty, reset safely -----
        if (selTop != null && !tops.any((c) => c.id == selTop)) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            ref.read(selectedCategoryIdProvider.notifier).state = null;
            ref.read(selectedSubcategoryIdProvider.notifier).state = null;
          });
        } else if (selSub != null && !used.contains(selSub)) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            ref.read(selectedSubcategoryIdProvider.notifier).state = null;
          });
        }

        // ----- UI helpers -----
        Widget pill({
          required String? id,
          required String label,
          required bool selected,
          required VoidCallback onTap,
        }) {
          final bg     = selected ? onSurface.withOpacity(0.10) : onSurface.withOpacity(0.06);
          final border = onSurface.withOpacity(selected ? 0.25 : 0.15);
          final txt    = onSurface;

          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: InkWell(
              borderRadius: BorderRadius.circular(999),
              onTap: onTap,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
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
                  // Top row (All + visible tops only)
                  row(
                    controller: _topCtrl,
                    children: [
                      pill(
                        id: null,
                        label: 'All',
                        selected: selTop == null,
                        onTap: () {
                          ref.read(selectedCategoryIdProvider.notifier).state = null;
                          ref.read(selectedSubcategoryIdProvider.notifier).state = null;
                        },
                      ),
                      ...tops.map(
                        (c) => pill(
                          id: c.id,
                          label: c.name,
                          selected: selTop == c.id,
                          onTap: () {
                            ref.read(selectedCategoryIdProvider.notifier).state = c.id;
                            ref.read(selectedSubcategoryIdProvider.notifier).state = null;
                          },
                        ),
                      ),
                    ],
                  ),

                  // Hairline only if we have visible subs
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 160),
                    child: (selTop != null && subs.isNotEmpty)
                        ? Container(height: 1, color: onSurface.withOpacity(0.06))
                        : const SizedBox.shrink(),
                  ),

                  // Sub row (visible subs only)
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
                                    selected: ref.watch(selectedSubcategoryIdProvider) == s.id,
                                    onTap: () => ref
                                        .read(selectedSubcategoryIdProvider.notifier)
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

/// Backward-compatible wrapper so existing calls `const CategoryBar()` still work.
class CategoryBar extends StatelessWidget {
  const CategoryBar({super.key});
  @override
  Widget build(BuildContext context) => const GlassCategoryBar();
}
