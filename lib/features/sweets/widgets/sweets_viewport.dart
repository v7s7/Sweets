import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../cart/widgets/cart_sheet.dart';
import '../../sweets/data/sweets_repo.dart'; // exposes sweetsStreamProvider
import '../../sweets/data/sweet.dart';
import '../../sweets/state/sweets_controller.dart';
import '../../../core/utils/haptics.dart';
import '../../cart/state/cart_controller.dart';
import 'sweet_image.dart';
import 'nutrition_panel.dart';
import '../../cart/widgets/cart_badge.dart';

class SweetsViewport extends ConsumerStatefulWidget {
  const SweetsViewport({super.key});

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
  final GlobalKey _cartBadgeKey = GlobalKey();
  OverlayEntry? _flyEntry;

  ProviderSubscription<AsyncValue<List<Sweet>>>? _sweetsSub;

  void _openCartSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => const CartSheet(),
    );
  }

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

    return sweetsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Text(
          'Error loading menu:\n$e',
          textAlign: TextAlign.center,
        ),
      ),
      data: (sweets) {
        if (sweets.isEmpty) {
          return const Center(child: Text('No products yet.'));
        }

        final state = ref.watch(sweetsControllerProvider);
        final current = sweets[state.index % sweets.length];

        final total = (current.price * _qty);
        final size = MediaQuery.of(context).size;
        final onSurface = Theme.of(context).colorScheme.onSurface;
        final surface = Theme.of(context).colorScheme.surface;

        // Enforce global text/icon color for this screen too.
        return DefaultTextStyle.merge(
          style: Theme.of(context).textTheme.bodyMedium!.copyWith(color: onSurface),
          child: IconTheme(
            data: IconThemeData(color: onSurface),
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
                        .setIndex((i % sweets.length).toInt());
                    setState(() => _qty = 1);
                  },
                  itemBuilder: (ctx, i) {
                    final sweet = sweets[i % sweets.length];
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
                            // Name (bold, centered) — explicitly use onSurface
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 180),
                              transitionBuilder: (c, a) => FadeTransition(
                                opacity: a,
                                child: ScaleTransition(scale: a, child: c),
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
                                  onDec: () => setState(
                                      () => _qty = (_qty > 1) ? _qty - 1 : 1),
                                  onInc: () => setState(
                                      () => _qty = (_qty < 99) ? _qty + 1 : 99),
                                ),
                                const SizedBox(width: 10),
                                _AddIconButton(
                                  onSurface: onSurface,
                                  onTap: () =>
                                      _handleAddToCart(current, qty: _qty),
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

                // 5) Cart badge (TOPMOST so it receives taps)
                Positioned(
                  top: 10,
                  right: 12,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _openCartSheet,
                    child: CartBadge(hostKey: _cartBadgeKey),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
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
            imageAsset: sweet.imageAsset!,
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
    final end = _centerOfKey(_cartBadgeKey);
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
          color: onSurface.withOpacity(0.06),
          borderRadius: BorderRadius.circular(24),
          boxShadow: const [
            BoxShadow(color: Color(0x14000000), blurRadius: 14, offset: Offset(0, 8)),
          ],
          border: Border.all(color: onSurface.withOpacity(0.12)),
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
    return DecoratedBox(
      decoration: BoxDecoration(
        color: onSurface.withOpacity(0.06),
        shape: BoxShape.circle,
        boxShadow: const [
          BoxShadow(color: Color(0x22000000), blurRadius: 14, offset: Offset(0, 8)),
        ],
        border: Border.all(color: onSurface.withOpacity(0.18)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: 44,
            height: 44,
            child: Icon(Icons.shopping_bag_outlined, size: 22, color: onSurface),
          ),
        ),
      ),
    );
  }
}
