import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../sweets/data/sweets_repo.dart';
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

  @override
  void initState() {
    super.initState();
    _pc.addListener(_onPageTick);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final sweets = ref.read(sweetsRepoProvider);
      if (sweets.isNotEmpty) {
        ref.read(sweetsControllerProvider.notifier)
            .setIndex(_kInitialPage % sweets.length);
      }
    });
  }

  void _onPageTick() => setState(() => _page = _pc.page ?? _page);

  @override
  void dispose() {
    _pc.removeListener(_onPageTick);
    _pc.dispose();
    _flyEntry?.remove();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sweets = ref.watch(sweetsRepoProvider);
    final state = ref.watch(sweetsControllerProvider);
    final current = sweets[state.index % sweets.length];

    // total is unit price * qty; shown in pink next to the counter
    final total = (current.price * _qty);
    final size = MediaQuery.of(context).size;
    final pink = Theme.of(context).colorScheme.primary; // #FF6FA3 from theme

    return Stack(
      clipBehavior: Clip.none,
      children: [
        // Cart badge (top-right, keep for fly-to-cart target)
        Positioned(
          top: 10,
          right: 12,
          child: CartBadge(hostKey: _cartBadgeKey),
        ),

        // Carousel with 15/70/15 peeks; disable scroll while detail open
        PageView.builder(
          controller: _pc,
          padEnds: true,
          clipBehavior: Clip.none,
          pageSnapping: true,
          physics: state.isDetailOpen
              ? const NeverScrollableScrollPhysics()
              : const BouncingScrollPhysics(),
          onPageChanged: (i) {
            ref.read(sweetsControllerProvider.notifier)
               .setIndex(i % sweets.length);
            setState(() => _qty = 1);
          },
          itemBuilder: (ctx, i) {
            final sweet = sweets[i % sweets.length];
            return _buildPageItem(context, sweet, i, state);
          },
        ),

        // Mask RIGHT HALF when detail is open so the next item doesn't peek
        if (state.isDetailOpen)
          Positioned(
            top: 0,
            bottom: 0,
            right: 0,
            width: size.width * 0.5,
            child: IgnorePointer(
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter, end: Alignment.bottomCenter,
                    colors: [ Color(0xFFF9EFF3), Color(0xFFFFF5F8) ],
                  ),
                ),
              ),
            ),
          ),

        // ===== Name, pink price (total), counter, and add button — right under the hero =====
        Align(
          alignment: const Alignment(0, 0.78), // near bottom of hero
          child: IgnorePointer(
            ignoring: state.isDetailOpen, // hide while detail is open
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
                      duration: const Duration(milliseconds: 180),
                      transitionBuilder: (c, a) =>
                          FadeTransition(opacity: a, child: ScaleTransition(scale: a, child: c)),
                      child: Text(
                        current.name,
                        key: ValueKey(current.id),
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),

                    // Price (pink, updates with qty) + counter + compact add button
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          total.toStringAsFixed(2),
                          style: TextStyle(
                            color: pink,
                            fontWeight: FontWeight.w800,
                            fontSize: 18,
                          ),
                        ),
                        const SizedBox(width: 12),
                        _QtyStepper(
                          qty: _qty,
                          onDec: () => setState(() => _qty = (_qty > 1) ? _qty - 1 : 1),
                          onInc: () => setState(() => _qty = (_qty < 99) ? _qty + 1 : 99),
                        ),
                        const SizedBox(width: 10),
                        _AddIconButton(
                          onTap: () => _handleAddToCart(current, qty: _qty),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),

        // Nutrition panel on the RIGHT when detail is open
        Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: const EdgeInsets.only(right: 12.0),
            child: NutritionPanel(
              sweet: current,
              visible: state.isDetailOpen,
              onClose: () =>
                  ref.read(sweetsControllerProvider.notifier).closeDetail(),
            ),
          ),
        ),
      ],
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
            imageAsset: sweet.imageAsset,
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
    if (overlay == null) return;

    final start = _centerOfKey(_activeImageKey);
    final end = _centerOfKey(_cartBadgeKey);
    if (start == null || end == null) return;

    _flyEntry?.remove();

    final controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    final curve =
        CurvedAnimation(parent: controller, curve: Curves.easeInOutCubic);

    final tweenX = Tween<double>(begin: start.dx, end: end.dx);
    final tweenY = Tween<double>(begin: start.dy, end: end.dy - 8);
    final sizeTween = Tween<double>(begin: 48, end: 16);

    _flyEntry = OverlayEntry(builder: (ctx) {
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
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.black12,
                    ),
                    child: FittedBox(
                      fit: BoxFit.cover,
                      child: Image.asset(
                        sweet.imageAsset,
                        errorBuilder: (_, __, ___) =>
                            const Icon(Icons.circle, size: 12),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      );
    });

    overlay.insert(_flyEntry!);
    controller.addStatusListener((st) {
      if (st == AnimationStatus.completed || st == AnimationStatus.dismissed) {
        _flyEntry?.remove();
        _flyEntry = null;
        controller.dispose();
      }
    });
    controller.forward();
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

  const _QtyStepper({
    required this.qty,
    required this.onDec,
    required this.onInc,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.92),
          borderRadius: BorderRadius.circular(24),
          boxShadow: const [
            BoxShadow(color: Color(0x14000000), blurRadius: 14, offset: Offset(0, 8)),
          ],
          border: Border.all(color: const Color(0x10A0A0A0)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _step(icon: Icons.remove_rounded, onTap: onDec),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Text(
                qty.toString().padLeft(2, '0'),
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
              ),
            ),
            _step(icon: Icons.add_rounded, onTap: onInc),
          ],
        ),
      ),
    );
  }

  Widget _step({required IconData icon, required VoidCallback onTap}) {
    return InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Icon(icon, size: 22),
      ),
    );
  }
}

class _AddIconButton extends StatelessWidget {
  final VoidCallback onTap;
  const _AddIconButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: Colors.black87,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(color: Color(0x22000000), blurRadius: 14, offset: Offset(0, 8)),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: const SizedBox(
            width: 44,
            height: 44,
            child: Icon(Icons.shopping_bag_outlined, size: 22, color: Colors.white),
          ),
        ),
      ),
    );
  }
}
