import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../cart/state/cart_controller.dart';

class CartBadge extends ConsumerWidget {
  final GlobalKey? hostKey; // allow parent to measure for fly-to-cart
  const CartBadge({super.key, this.hostKey});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final total = ref.watch(cartControllerProvider.select((s) => s.totalCount));

    final badge = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black87,
        borderRadius: BorderRadius.circular(20),
      ),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 180),
        transitionBuilder: (child, anim) => ScaleTransition(scale: anim, child: child),
        child: Row(
          key: ValueKey(total),
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.shopping_bag_outlined, size: 18, color: Colors.white),
            const SizedBox(width: 6),
            Text('$total', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );

    return KeyedSubtree(key: hostKey, child: badge);
  }
}
