import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../sweets/data/sweets_repo.dart';
import '../../sweets/data/sweet.dart';
import '../state/cart_controller.dart';

import '../../orders/data/order_models.dart';
import '../../orders/data/order_service.dart';
import '../../orders/screens/order_status_page.dart';

import '../../../core/config/app_config.dart';

class CartSheet extends ConsumerWidget {
  final VoidCallback? onConfirm;

  const CartSheet({super.key, this.onConfirm});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cart = ref.watch(cartControllerProvider);
    final sweets = ref.watch(sweetsRepoProvider);

    // Resolve items (skip IDs that no longer exist in repo)
    final lines = <_CartLine>[];
    double subtotal = 0.0;

    cart.items.forEach((id, qty) {
      final Sweet s = sweets.firstWhere(
        (e) => e.id == id,
        orElse: () => const Sweet(
          id: '__missing__',
          name: 'Item removed',
          imageAsset: '',
          calories: 0,
          protein: 0.0,
          carbs: 0.0,
          fat: 0.0,
          price: 0.0,
        ),
      );
      if (s.id != '__missing__') {
        lines.add(_CartLine(sweet: s, qty: qty));
        subtotal += s.price * qty;
      }
    });

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.black12,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Text(
                  'Your Order',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
                const Spacer(),
                Text(
                  '${cart.totalCount} item${cart.totalCount == 1 ? '' : 's'}',
                  style: const TextStyle(color: Colors.black54),
                ),
              ],
            ),
            const SizedBox(height: 12),

            if (lines.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
                    Icon(Icons.shopping_bag_outlined,
                        size: 24, color: Colors.black38),
                    SizedBox(width: 8),
                    Text('Cart is empty',
                        style: TextStyle(color: Colors.black54)),
                  ],
                ),
              )
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: lines.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, i) => _CartRow(line: lines[i]),
                ),
              ),

            const SizedBox(height: 16),
            Row(
              children: [
                const Text(
                  'Subtotal',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                ),
                const Spacer(),
                Text(
                  subtotal.toStringAsFixed(3), // BHD: 3 decimals
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 18),
                ),
              ],
            ),
            const SizedBox(height: 12),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: lines.isEmpty
                    ? null
                    : () async {
                        final items = lines
                            .map((l) => OrderItem(
                                  productId: l.sweet.id,
                                  name: l.sweet.name,
                                  price: l.sweet.price,
                                  qty: l.qty,
                                ))
                            .toList();

                        final cfg = ref.read(appConfigProvider);
                        final table = cfg.qr.table;

                        final service = ref.read(orderServiceProvider);
                        final order = await service.createOrder(
                          items: items,
                          table: table,
                        );

                        // ignore: use_build_context_synchronously
                        Navigator.of(context).maybePop();
                        // ignore: use_build_context_synchronously
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) =>
                                OrderStatusPage(orderId: order.orderId),
                          ),
                        );

                        onConfirm?.call();
                      },
                icon: const Icon(Icons.check_circle_outline),
                label: const Text('Confirm Order'),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _CartLine {
  final Sweet sweet;
  final int qty;
  _CartLine({required this.sweet, required this.qty});
}

class _CartRow extends ConsumerWidget {
  final _CartLine line;
  const _CartRow({required this.line});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cart = ref.watch(cartControllerProvider);
    final qty = cart.qtyFor(line.sweet.id);

    // Image path/URL (null-safe + decode any % encodings)
    final img = _cleanSrc(line.sweet.imageAsset);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Container(
            color: const Color(0xFFF3F3F3),
            width: 56,
            height: 56,
            child: _thumb(img),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                line.sweet.name,
                style:
                    const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
              ),
              const SizedBox(height: 2),
              Text(
                line.sweet.price.toStringAsFixed(3),
                style: const TextStyle(color: Colors.black54),
              ),
            ],
          ),
        ),
        _QtyChip(
          qty: qty,
          onDec: () => ref
              .read(cartControllerProvider.notifier)
              .decrement(line.sweet.id),
          onInc: () =>
              ref.read(cartControllerProvider.notifier).add(line.sweet),
          onRemove: () =>
              ref.read(cartControllerProvider.notifier).remove(line.sweet.id),
        ),
      ],
    );
  }

  static String _cleanSrc(String? src) {
    var s = (src ?? '').trim();
    for (var i = 0; i < 3; i++) {
      final before = s;
      try {
        s = Uri.decodeFull(s);
      } catch (_) {
        try {
          s = Uri.decodeComponent(s);
        } catch (_) {
          // stop if decoding fails
        }
      }
      if (s == before) break;
    }
    return s;
  }

  bool _looksLikeNetwork(String s) {
    final lower = s.toLowerCase();
    return lower.startsWith('http://') ||
        lower.startsWith('https://') ||
        lower.startsWith('//') ||
        lower.startsWith('data:');
  }

  /// Small 56x56 thumbnail that supports either assets or full URLs.
  Widget _thumb(String src) {
    if (src.isEmpty) {
      return const Icon(Icons.image_not_supported_outlined, color: Colors.black26);
    }

    if (_looksLikeNetwork(src)) {
      return Image.network(
        src,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.medium,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) =>
            const Icon(Icons.broken_image_outlined, color: Colors.black26),
        loadingBuilder: (c, child, progress) =>
            progress == null ? child : const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    return Image.asset(
      src,
      fit: BoxFit.cover,
      filterQuality: FilterQuality.medium,
      gaplessPlayback: true,
      errorBuilder: (_, __, ___) =>
          const Icon(Icons.broken_image_outlined, color: Colors.black26),
    );
  }
}

class _QtyChip extends StatelessWidget {
  final int qty;
  final VoidCallback onDec;
  final VoidCallback onInc;
  final VoidCallback onRemove;

  const _QtyChip({
    required this.qty,
    required this.onDec,
    required this.onInc,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 8,
            offset: Offset(0, 4),
          )
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _iconBtn(Icons.remove_rounded, onDec),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Text(
              qty.toString().padLeft(2, '0'),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          _iconBtn(Icons.add_rounded, onInc),
          const SizedBox(width: 6),
          _iconBtn(Icons.delete_outline, onRemove),
        ],
      ),
    );
  }

  Widget _iconBtn(IconData icon, VoidCallback onTap) {
    return InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Icon(icon, size: 20),
      ),
    );
  }
}
