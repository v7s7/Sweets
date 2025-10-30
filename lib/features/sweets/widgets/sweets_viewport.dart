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
import '../../categories/data/category.dart';

// NEW: branding (for logo + nutrition note)
import '../../../core/branding/branding_providers.dart';
import '../../../core/branding/branding.dart';

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

  final GlobalKey _activeImageKey = GlobalKey(); // used by fly-to-cart
  OverlayEntry? _flyEntry;

  ProviderSubscription<AsyncValue<List<Sweet>>>? _sweetsSub;

  @override
  void initState() {
    super.initState();
    _pc.addListener(_onPageTick);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final async = ref.read(sweetsStreamProvider);
      final sweets = async.value;
      if (sweets != null && sweets.isNotEmpty) {
        _applyInitialIndex(sweets);
      }
    });

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

    // Branding (logo + nutrition note) — safe trims
    final Branding? branding = ref.watch(brandingProvider).maybeWhen(
      data: (b) => b,
      orElse: () => null,
    );
    final String? logoUrl = (() {
      final s = branding?.logoUrl?.trim();
      return (s != null && s.isNotEmpty) ? s : null;
    })();
    final String? nutritionNote = (() {
      final s = branding?.nutritionNote?.trim();
      return (s != null && s.isNotEmpty) ? s : null;
    })();

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
        final typography = Theme.of(context).textTheme;
        final String? secondaryFamily = typography.titleSmall?.fontFamily;
        final List<Category> cats = catsAsync.value ?? <Category>[];
        final selCat = ref.watch(selectedCategoryIdProvider);
        final selSub = ref.watch(selectedSubcategoryIdProvider);

        final filtered = _filterByCategory(allSweets, cats, selCat, selSub);

        if (filtered.isEmpty) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              const CategoryBar(),
              if (nutritionNote != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6.0),
                  child: Text(
                    nutritionNote,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: (typography.titleSmall ?? const TextStyle())
                        .copyWith(
                      fontFamily: secondaryFamily,
                      fontSize:
                          (typography.titleSmall?.fontSize ?? 14) + 1.5,
                      height: 1.28,
                      fontWeight: FontWeight.w600,
                      color: onSurface.withOpacity(0.78),
                    ),
                  ),
                ),
              const SizedBox(height: 24),
              Text('No products in this category.',
                  style: TextStyle(color: onSurface)),
            ],
          );
        }

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

        return DefaultTextStyle.merge(
          style: Theme.of(context)
              .textTheme
              .bodyMedium!
              .copyWith(color: onSurface),
          child: IconTheme(
            data: IconThemeData(color: onSurface),
            child: Column(
              children: [
                Expanded(
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      // 1) Carousel
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

                      // 2) Mask right half when detail is open
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

                      // 3) Centered brand logo
                      if (logoUrl case final url?)
                        Align(
                          alignment: Alignment.topCenter,
                          child: IgnorePointer(
                            ignoring: true,
                            child: Padding(
                              padding: EdgeInsets.only(
                                top: MediaQuery.of(context).padding.top +
                                    kToolbarHeight +
                                    8,
                              ),
                              child: AnimatedOpacity(
                                duration:
                                    const Duration(milliseconds: 180),
                                opacity: state.isDetailOpen ? 0 : 1,
                                child: _LogoCard(
                                  url: url,
                                  box: 120,
                                  icon: 100,
                                  borderOpacity: 0.10,
                                  fillOpacity: 0.06,
                                ),
                              ),
                            ),
                          ),
                        ),

                      // 4) Dots + Category bar
                      Align(
                        alignment: const Alignment(0, 0.48),
                        child: IgnorePointer(
                          ignoring: state.isDetailOpen,
                          child: AnimatedOpacity(
                            opacity: state.isDetailOpen ? 0 : 1,
                            duration: const Duration(milliseconds: 160),
                            child: ConstrainedBox(
                              constraints:
                                  const BoxConstraints(maxWidth: 560),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (filtered.length > 1)
                                    Padding(
                                      padding:
                                          const EdgeInsets.only(bottom: 8.0),
                                      child: _DotsIndicator(
                                        count: filtered.length,
                                        active: safeIndex,
                                        color: onSurface,
                                      ),
                                    ),
                                  const CategoryBar(),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),

                      // 5) Name + price/qty/add
                      Align(
                        alignment: const Alignment(0, 0.78),
                        child: IgnorePointer(
                          ignoring: state.isDetailOpen,
                          child: AnimatedOpacity(
                            opacity: state.isDetailOpen ? 0 : 1,
                            duration:
                                const Duration(milliseconds: 180),
                            child: ConstrainedBox(
                              constraints:
                                  const BoxConstraints(maxWidth: 520),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  AnimatedSwitcher(
                                    duration:
                                        const Duration(milliseconds: 180),
                                    transitionBuilder: (c, a) =>
                                        FadeTransition(
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
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.center,
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
                                            _qty =
                                                (_qty > 1) ? _qty - 1 : 1),
                                        onInc: () => setState(() =>
                                            _qty =
                                                (_qty < 99) ? _qty + 1 : 99),
                                      ),
                                      const SizedBox(width: 10),
                                      _AddIconButton(
                                        onSurface: onSurface,
                                        onTap: () =>
                                            _handleAddToCart(current,
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

                      // 6) Nutrition panel (right) – no text here now
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

                      // 7) Center nutrition note (big, single)
                      if (nutritionNote != null &&
                          nutritionNote.isNotEmpty)
                        Align(
                          alignment:
                              const Alignment(0, 0.9), // between item & bottom
                          child: AnimatedOpacity(
                            duration:
                                const Duration(milliseconds: 160),
                            opacity: state.isDetailOpen ? 1 : 0,
                            child: ConstrainedBox(
                              constraints:
                                  const BoxConstraints(maxWidth: 420),
                              child: Text(
                                nutritionNote,
                                textAlign: TextAlign.center,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(
                                          fontSize: 18,
                                          fontWeight: FontWeight.w700,
                                          color: onSurface
                                              .withOpacity(0.9),
                                          fontFamily: secondaryFamily,
                                          height: 1.25,
                                        ) ??
                                    TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w700,
                                      color: onSurface.withOpacity(0.9),
                                      fontFamily: secondaryFamily,
                                      height: 1.25,
                                    ),
                              ),
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
      final childIds =
          cats.where((c) => (c.parentId ?? '') == selCat).map((c) => c.id);
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
    final t = (_page - i).clamp(-1.0, 1.0);
    final scale = 1 - (0.18 * t.abs());
    final y = 18 * t.abs();
    final rot = 0.02 * -t;

    final int activeHost =
        _pc.hasClients ? (_pc.page?.round() ?? _kInitialPage) : _kInitialPage;
    final bool isHost = (i == activeHost);

    return Transform.translate(
      offset: Offset(0, y),
      child: Transform.scale(
        scale: scale,
        child: Transform.rotate(
          angle: rot,
          child: SweetImage(
            imageAsset: (sweet.imageAsset ?? ''),
            isActive: (_page - i).abs() < 0.5,
            isDetailOpen: state.isDetailOpen,
            hostKey: isHost ? _activeImageKey : null,
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
    final end = _centerOfKey(widget.cartBadgeKey);
    if (start == null || end == null) return;

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
      if (st == AnimationStatus.completed ||
          st == AnimationStatus.dismissed) {
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
          color: Colors.black.withOpacity(0.30),
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
                style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                    color: onSurface),
              ),
            ),
            _step(icon: Icons.add_rounded, onTap: onInc, onSurface: onSurface),
          ],
        ),
      ),
    );
  }

  Widget _step(
      {required IconData icon,
      required VoidCallback onTap,
      required Color onSurface}) {
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
    return Semantics(
      button: true,
      label: 'Add to cart',
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          shape: const CircleBorder(),
          side: BorderSide(color: onSurface),
          minimumSize: const Size(48, 48),
          padding: EdgeInsets.zero,
          foregroundColor: onSurface,
        ),
        onPressed: onTap,
        child: const Icon(Icons.shopping_bag_outlined, size: 22),
      ),
    );
  }
}

/// Instagram-like dots indicator (windowed for large lists)
class _DotsIndicator extends StatelessWidget {
  final int count;
  final int active;
  final Color color;

  const _DotsIndicator({
    required this.count,
    required this.active,
    required this.color,
  });

  static const int _kMaxDots = 12;

  @override
  Widget build(BuildContext context) {
    if (count <= 1) return const SizedBox.shrink();
    final visible = _visibleIndices(count, active, _kMaxDots);

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (int i = 0; i < visible.length; i++)
          _dot(
            isActive: visible[i] == active,
            isEdgeTruncator: (i == 0 && visible.first > 0) ||
                (i == visible.length - 1 && visible.last < count - 1),
          ),
      ],
    );
  }

  Widget _dot({required bool isActive, required bool isEdgeTruncator}) {
    if (isEdgeTruncator) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: Container(
          width: 4,
          height: 4,
          decoration: BoxDecoration(
            color: color.withOpacity(0.20),
            shape: BoxShape.circle,
          ),
        ),
      );
    }
    final double size = isActive ? 8 : 6;
    final double opacity = isActive ? 0.95 : 0.35;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      margin: const EdgeInsets.symmetric(horizontal: 3),
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withOpacity(opacity),
        shape: BoxShape.circle,
      ),
    );
  }

  List<int> _visibleIndices(int count, int active, int max) {
    if (count <= max) return List<int>.generate(count, (i) => i);
    final int half = (max / 2).floor();
    int start = active - half;
    int end = active + half;
    if (max.isEven) end -= 1;
    if (start < 0) {
      end += -start;
      start = 0;
    }
    if (end > count - 1) {
      start -= (end - (count - 1));
      end = count - 1;
    }
    if (start < 0) start = 0;
    final len = end - start + 1;
    if (len > max) end -= (len - max);
    return List<int>.generate(end - start + 1, (i) => start + i);
  }
}

/// Center logo card used on the home viewport.
class _LogoCard extends StatelessWidget {
  final String url;
  final double box; // outer square size
  final double icon; // image size inside
  final double borderOpacity;
  final double fillOpacity;
  const _LogoCard({
    super.key,
    required this.url,
    required this.box,
    required this.icon,
    required this.borderOpacity,
    required this.fillOpacity,
  });

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Container(
      width: box,
      height: box,
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(fillOpacity),
        borderRadius: BorderRadius.circular(box * 0.23),
        border: Border.all(color: onSurface.withOpacity(borderOpacity)),
      ),
      child: Center(
        child: Image.network(
          url,
          width: icon,
          height: icon,
          fit: BoxFit.contain,
          alignment: Alignment.center,
          errorBuilder: (_, __, ___) => const SizedBox.shrink(),
        ),
      ),
    );
  }
}
