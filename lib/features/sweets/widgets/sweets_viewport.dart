// lib/features/sweets/widgets/sweets_viewport.dart
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../sweets/data/sweets_repo.dart'; // sweetsStreamProvider
import '../../sweets/data/sweet.dart';
import '../../sweets/state/sweets_controller.dart';
import '../../../core/utils/haptics.dart';
import '../../cart/state/cart_controller.dart';
import 'sweet_image.dart';
import 'nutrition_panel.dart';
import 'category_bar.dart';
import '../../categories/data/categories_repo.dart'; // categoriesStreamProvider
import '../../categories/data/category.dart'; // <-- ensure Category is in scope

class SweetsViewport extends ConsumerStatefulWidget {
  final GlobalKey cartBadgeKey; // AppBar cart button key for fly animation end
  const SweetsViewport({super.key, required this.cartBadgeKey});

  @override
  ConsumerState<SweetsViewport> createState() => _SweetsViewportState();
}

class _SweetsViewportState extends ConsumerState<SweetsViewport>
    with TickerProviderStateMixin {
  static const int _kInitialPage = 10000;

  // Home layout: 15% | 70% | 15% peeks
  late final PageController _pc =
      PageController(viewportFraction: 0.7, initialPage: _kInitialPage);

  double _page = _kInitialPage.toDouble();
  int _qty = 1;

  final GlobalKey _activeImageKey = GlobalKey();
  OverlayEntry? _flyEntry;

  ProviderSubscription<AsyncValue<List<Sweet>>>? _sweetsSub;

  @override
  void initState() {
    super.initState();
    _pc.addListener(_onPageTick);

    // If data already present on first frame, apply initial index.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final async = ref.read(sweetsStreamProvider);
      final sweets = async.value;
      if (sweets != null && sweets.isNotEmpty) {
        _applyInitialIndex(sweets);
      }
    });

    // Listen to stream provider; when it turns to non-empty data / length changes, apply index.
    _sweetsSub = ref.listenManual<AsyncValue<List<Sweet>>>(
      sweetsStreamProvider,
      (prev, next) {
        final prevLen =
            prev?.maybeWhen(data: (l) => l.length, orElse: () => null);
        final list = next.maybeWhen(data: (l) => l, orElse: () => null);
        if (list != null && list.isNotEmpty) {
          if (prevLen == null || prevLen != list.length) {
            _applyInitialIndex(list);
          }
        }
      },
    );
  }

  void _applyInitialIndex(List<Sweet> sweets) {
    final idx = (_kInitialPage % sweets.length).toInt();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(sweetsControllerProvider.notifier).setIndex(idx);
      if (_pc.hasClients) {
        try {
          _pc.jumpToPage(_kInitialPage);
        } catch (_) {}
      }
      setState(() => _qty = 1);
    });
  }

  void _onPageTick() => setState(() => _page = _pc.page ?? _page);

  @override
  void dispose() {
    _pc.removeListener(_onPageTick);
    _pc.dispose();
    _flyEntry?.remove();
    _sweetsSub?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sweetsAsync = ref.watch(sweetsStreamProvider);
    final catsAsync = ref.watch(categoriesStreamProvider);

    return sweetsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Text(
          'Error loading menu:\n$e',
          textAlign: TextAlign.center,
        ),
      ),
      data: (allSweets) {
        final onSurface = Theme.of(context).colorScheme.onSurface;

        // Strongly type to avoid nullable-element inference from `const []`.
        final List<Category> cats = catsAsync.value ?? <Category>[];
        final selCat = ref.watch(selectedCategoryIdProvider);
        final selSub = ref.watch(selectedSubcategoryIdProvider);

        final filtered = _filterByCategory(allSweets, cats, selCat, selSub);

        if (filtered.isEmpty) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CategoryBar(),
              const SizedBox(height: 24),
              Text('No products in this category.',
                  style: TextStyle(color: onSurface)),
            ],
          );
        }

        // Keep index in range after filtering
        final state = ref.watch(sweetsControllerProvider);
        final safeIndex = state.index % filtered.length;
        if (safeIndex != state.index) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              ref.read(sweetsControllerProvider.notifier).setIndex(safeIndex);
            }
          });
        }
        final current = filtered[safeIndex];

        final total = (current.price * _qty);
        final size = MediaQuery.of(context).size;
        final surface = Theme.of(context).colorScheme.surface;

        // Enforce global text/icon color for this screen too.
        return DefaultTextStyle.merge(
          style:
              Theme.of(context).textTheme.bodyMedium!.copyWith(color: onSurface),
          child: IconTheme(
            data: IconThemeData(color: onSurface),
            child: Column(
              children: [
                const CategoryBar(),
                Expanded(
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      // 1) Carousel with 15/70/15 peeks; disable scroll while detail open
                      PageView.builder(
                        controller: _pc,
                        padEnds: true,
                        clipBehavior: Clip.none,
                        pageSnapping: true,
                        physics: state.isDetailOpen
                            ? const NeverScrollableScrollPhysics()
                            : const BouncingScrollPhysics(),
                        onPageChanged: (i) {
                          ref
                              .read(sweetsControllerProvider.notifier)
                              .setIndex((i % filtered.length).toInt());
                          setState(() => _qty = 1);
                        },
                        itemBuilder: (ctx, i) {
                          final sweet = filtered[i % filtered.length];
                          return _buildPageItem(context, sweet, i, state);
                        },
                      ),

                      // 2) Mask RIGHT HALF when detail is open so the next item doesn't peek
                      if (state.isDetailOpen)
                        Positioned(
                          top: 0,
                          bottom: 0,
                          right: 0,
                          width: size.width * 0.5,
                          child: IgnorePointer(
                            child: DecoratedBox(
                              decoration: BoxDecoration(color: surface),
                            ),
                          ),
                        ),

                      // 3) Name, price, counter, and add button — right under the hero
                      Align(
                        alignment: const Alignment(0, 0.78),
                        child: IgnorePointer(
                          ignoring: state.isDetailOpen,
                          child: AnimatedOpacity(
                            opacity: state.isDetailOpen ? 0 : 1,
                            duration: const Duration(milliseconds: 180),
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 520),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // Name (bold, centered)
                                  AnimatedSwitcher(
                                    duration:
                                        const Duration(milliseconds: 180),
                                    transitionBuilder: (c, a) => FadeTransition(
                                      opacity: a,
                                      child: ScaleTransition(
                                          scale: a, child: c),
                                    ),
                                    child: Text(
                                      current.name,
                                      key: ValueKey(current.id),
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 16,
                                            color: onSurface,
                                          ),
                                    ),
                                  ),
                                  const SizedBox(height: 6),

                                  // Price (updates with qty) + counter + compact add button
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        total.toStringAsFixed(3),
                                        style: TextStyle(
                                          color: onSurface,
                                          fontWeight: FontWeight.w800,
                                          fontSize: 18,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      _QtyStepper(
                                        onSurface: onSurface,
                                        qty: _qty,
                                        onDec: () => setState(() =>
                                            _qty = (_qty > 1) ? _qty - 1 : 1),
                                        onInc: () => setState(() =>
                                            _qty = (_qty < 99) ? _qty + 1 : 99),
                                      ),
                                      const SizedBox(width: 10),
                                      _AddIconButton(
                                        onSurface: onSurface,
                                        onTap: () => _handleAddToCart(current,
                                            qty: _qty),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),

                      // 4) Nutrition panel on the RIGHT when detail is open
                      Align(
                        alignment: Alignment.centerRight,
                        child: Padding(
                          padding: const EdgeInsets.only(right: 12.0),
                          child: NutritionPanel(
                            sweet: current,
                            visible: state.isDetailOpen,
                            onClose: () => ref
                                .read(sweetsControllerProvider.notifier)
                                .closeDetail(),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Filter sweets by selected category/subcategory.
  List<Sweet> _filterByCategory(
    List<Sweet> sweets,
    List<Category> cats,
    String? selCat,
    String? selSub,
  ) {
    if (selSub != null) {
      return sweets.where((s) => s.categoryId == selSub).toList();
    }
    if (selCat != null) {
      // `parentId` is nullable, but `c` itself is not; compare safely.
      final childIds = cats
          .where((c) => (c.parentId ?? '') == selCat)
          .map((c) => c.id);

      final allowed = <String>{selCat, ...childIds};
      return sweets
          .where((s) => s.categoryId != null && allowed.contains(s.categoryId))
          .toList();
    }
    return sweets;
  }

  Widget _buildPageItem(
    BuildContext context,
    Sweet sweet,
    int i,
    SweetsState state,
  ) {
    // Offset from the center [-1..1]
    final t = (_page - i).clamp(-1.0, 1.0);
    // Emphasis: center bigger, neighbors smaller
    final scale = 1 - (0.18 * t.abs());
    final y = 18 * t.abs();
    final rot = 0.02 * -t;

    final isActive = (_page - i).abs() < 0.5;

    return Transform.translate(
      offset: Offset(0, y),
      child: Transform.scale(
        scale: scale,
        child: Transform.rotate(
          angle: rot,
          child: SweetImage(
            imageAsset: (sweet.imageAsset ?? ''), // safe
            isActive: isActive,
            isDetailOpen: state.isDetailOpen,
            hostKey: isActive ? _activeImageKey : null,
            onTap: () =>
                ref.read(sweetsControllerProvider.notifier).toggleDetail(),
          ),
        ),
      ),
    );
  }

  Future<void> _handleAddToCart(Sweet sweet, {int qty = 1}) async {
    ref.read(cartControllerProvider.notifier).add(sweet, qty: qty);

    final overlay = Overlay.maybeOf(context);
    await Haptics.light();
    if (overlay == null || !mounted) return;

    final start = _centerOfKey(_activeImageKey);
    final end = _centerOfKey(widget.cartBadgeKey); // <- AppBar button key
    if (start == null || end == null) return;

    // Remove any existing entry before starting a new animation
    _flyEntry?.remove();
    _flyEntry = null;

    final controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    final curve =
        CurvedAnimation(parent: controller, curve: Curves.easeInOutCubic);

    final tweenX = Tween<double>(begin: start.dx, end: end.dx);
    final tweenY = Tween<double>(begin: start.dy, end: end.dy - 8);
    final sizeTween = Tween<double>(begin: 48, end: 16);

    final entry = OverlayEntry(builder: (ctx) {
      final onSurface = Theme.of(ctx).colorScheme.onSurface;
      return AnimatedBuilder(
        animation: curve,
        builder: (ctx, _) {
          final x = tweenX.evaluate(curve);
          final y = tweenY.evaluate(curve) - 120 * _arc(curve.value);
          final s = sizeTween.evaluate(curve);
          return Positioned(
            left: x - s / 2,
            top: y - s / 2,
            child: IgnorePointer(
              child: Opacity(
                opacity: (1 - curve.value * 0.4),
                child: ClipOval(
                  child: Container(
                    width: s,
                    height: s,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: onSurface.withOpacity(0.12),
                    ),
                    child: FittedBox(
                      fit: BoxFit.cover,
                      child: _thumbFor(sweet),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      );
    });

    overlay.insert(entry);
    _flyEntry = entry;

    controller.addStatusListener((st) {
      if (st == AnimationStatus.completed || st == AnimationStatus.dismissed) {
        if (entry.mounted) {
          try {
            entry.remove();
          } catch (_) {}
        }
        if (identical(_flyEntry, entry)) {
          _flyEntry = null;
        }
        controller.dispose();
      }
    });

    controller.forward();
  }

  Widget _thumbFor(Sweet s) {
    if (s.imageUrl != null && s.imageUrl!.isNotEmpty) {
      return Image.network(
        s.imageUrl!,
        errorBuilder: (_, __, ___) => const Icon(Icons.circle, size: 12),
      );
    }
    if (s.imageAsset != null && s.imageAsset!.isNotEmpty) {
      return Image.asset(
        s.imageAsset!,
        errorBuilder: (_, __, ___) => const Icon(Icons.circle, size: 12),
      );
    }
    return const Icon(Icons.circle, size: 12);
  }

  double _arc(double t) => math.sin(t * math.pi);

  Offset? _centerOfKey(GlobalKey key) {
    final ctx = key.currentContext;
    if (ctx == null) return null;
    final box = ctx.findRenderObject() as RenderBox?;
    if (box == null || !box.attached) return null;
    final pos = box.localToGlobal(Offset.zero);
    return pos + box.size.center(Offset.zero);
  }
}

/* ---------- UI pieces ---------- */

class _QtyStepper extends StatelessWidget {
  final int qty;
  final VoidCallback onDec;
  final VoidCallback onInc;
  final Color onSurface;

  const _QtyStepper({
    required this.qty,
    required this.onDec,
    required this.onInc,
    required this.onSurface,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.30), // neutral dark overlay (no brand color)
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.black.withOpacity(0.15)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _step(icon: Icons.remove_rounded, onTap: onDec, onSurface: onSurface),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Text(
                qty.toString().padLeft(2, '0'),
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: onSurface),
              ),
            ),
            _step(icon: Icons.add_rounded, onTap: onInc, onSurface: onSurface),
          ],
        ),
      ),
    );
  }

  Widget _step({required IconData icon, required VoidCallback onTap, required Color onSurface}) {
    return InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Icon(icon, size: 22, color: onSurface),
      ),
    );
  }
}

class _AddIconButton extends StatelessWidget {
  final VoidCallback onTap;
  final Color onSurface;
  const _AddIconButton({required this.onTap, required this.onSurface});

  @override
  Widget build(BuildContext context) {
    // Outline-only circular button; icon + border use the same color (secondary/onSurface)
    return Semantics(
      button: true,
      label: 'Add to cart',
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          shape: const CircleBorder(),
          side: BorderSide(color: onSurface),
          minimumSize: const Size(48, 48),
          padding: EdgeInsets.zero,
          foregroundColor: onSurface, // icon color
        ),
        onPressed: onTap,
        child: const Icon(Icons.shopping_bag_outlined, size: 22),
      ),
    );
  }
}
