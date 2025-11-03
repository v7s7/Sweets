import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../sweets/data/sweets_repo.dart'; // sweetsStreamProvider
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
    final sweetsAsync = ref.watch(sweetsStreamProvider);

    return sweetsAsync.when(
      loading: () => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: const [
              SizedBox(height: 12),
              Center(child: CircularProgressIndicator()),
              SizedBox(height: 12),
            ],
          ),
        ),
      ),
      error: (e, _) => SafeArea(
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
              const Row(
                children: [
                  Text(
                    'Your Order',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Text(
                'Error loading products.\nPlease try again.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
      data: (sweets) {
        // Build view lines from cart state, refreshing Sweet from repo if present
        final List<CartLine> lines = [];
        for (final l in cart.asList) {
          Sweet? updated;
          for (final s in sweets) {
            if (s.id == l.sweet.id) {
              updated = s;
              break;
            }
          }
          if (updated != null) {
            lines.add(l.copyWith(sweet: updated));
          }
          // If product missing from repo, skip the line silently
        }

        final subtotal = lines.fold<double>(0.0, (sum, l) => sum + l.lineTotal);
        final onSurface = Theme.of(context).colorScheme.onSurface;

        // Keep the "always disabled" visual style
        final Color _fgDisabled = onSurface.withOpacity(0.38);
        final Color _bgDisabled = onSurface.withOpacity(0.12);
        final ButtonStyle _confirmStyle = ButtonStyle(
          foregroundColor: MaterialStatePropertyAll(_fgDisabled),
          backgroundColor: MaterialStatePropertyAll(_bgDisabled),
          overlayColor: const MaterialStatePropertyAll(Colors.transparent),
          shadowColor: const MaterialStatePropertyAll(Colors.transparent),
          elevation: const MaterialStatePropertyAll(0),
          minimumSize: const MaterialStatePropertyAll(Size.fromHeight(48)),
          shape: MaterialStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );

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
                      style: TextStyle(color: onSurface.withOpacity(0.6)),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                if (lines.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.shopping_bag_outlined,
                            size: 24, color: onSurface.withOpacity(0.5)),
                        const SizedBox(width: 8),
                        Text('Cart is empty',
                            style: TextStyle(color: onSurface.withOpacity(0.6))),
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
                      subtotal.toStringAsFixed(3), // BHD 3dp
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                        color: onSurface,
                      ),
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
                            // One OrderItem per line, preserve note
                            final items = lines
                                .map((l) => OrderItem(
                                      productId: l.sweet.id,
                                      name: l.sweet.name,
                                      price: l.sweet.price,
                                      qty: l.qty,
                                      note: l.note, // keep per-line note
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
                    style: _confirmStyle,
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _CartRow extends ConsumerWidget {
  final CartLine line;
  const _CartRow({required this.line});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cartCtl = ref.read(cartControllerProvider.notifier);
    final onSurface = Theme.of(context).colorScheme.onSurface;

    final img = _cleanSrc(line.sweet.imageAsset);
    final note = line.note;
    final qty = line.qty;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 56,
          height: 56,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: _thumb(img),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Name
              Text(
                line.sweet.name,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
              ),
              const SizedBox(height: 2),
              // Price
              Text(
                line.sweet.price.toStringAsFixed(3),
                style: TextStyle(color: onSurface),
              ),
              const SizedBox(height: 6),
              // Note chip (per-line)
              _NoteChip(
                hasNote: (note ?? '').trim().isNotEmpty,
                preview: _preview(note),
                onSurface: onSurface,
                onTap: () => _openNoteEditor(context, cartCtl, line.id, note),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        _QtyChip(
          qty: qty,
          onDec: () => cartCtl.decrementLine(line.id),
          onInc: () => cartCtl.incrementLine(line.id),
          onRemove: () => cartCtl.removeLine(line.id),
        ),
      ],
    );
  }

  static String _preview(String? note) {
    final n = (note ?? '').trim();
    if (n.isEmpty) return 'Add note';
    return n.length <= 24 ? n : '${n.substring(0, 24)}…';
  }

  Future<void> _openNoteEditor(
    BuildContext context,
    CartController cartCtl,
    String lineId,
    String? current,
  ) async {
    final ctrl = TextEditingController(text: current ?? '');
    final res = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) {
        final onSurface = Theme.of(ctx).colorScheme.onSurface;
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
            top: 8,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Item note', style: Theme.of(ctx).textTheme.titleMedium),
              const SizedBox(height: 8),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: onSurface.withOpacity(0.04),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: onSurface.withOpacity(0.12)),
                ),
                child: TextField(
                  controller: ctrl,
                  autofocus: true,
                  maxLines: 5,
                  minLines: 3,
                  maxLength: 200,
                  decoration: const InputDecoration(
                    hintText:
                        'Write special instructions (e.g., less sugar, extra sauce)…',
                    border: InputBorder.none,
                    counterText: '',
                    contentPadding: EdgeInsets.all(12),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: () => Navigator.pop(ctx, ''), // clear
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: const Text('Clear'),
                  ),
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
                    icon: const Icon(Icons.check, size: 18),
                    label: const Text('Save'),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );

    if (res == null) return;
    cartCtl.setNote(lineId, res);
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
        } catch (_) {}
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

  Widget _thumb(String src) {
    if (src.isEmpty) return const SizedBox.shrink();
    if (_looksLikeNetwork(src)) {
      return Image.network(
        src,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
        loadingBuilder: (c, child, progress) =>
            progress == null ? child : const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    return Image.asset(
      src,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      gaplessPlayback: true,
      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
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
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.10),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _iconBtn(Icons.remove_rounded, onDec, onSurface),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Text(
              qty.toString().padLeft(2, '0'),
              style: TextStyle(fontWeight: FontWeight.w700, color: onSurface),
            ),
          ),
          _iconBtn(Icons.add_rounded, onInc, onSurface),
          const SizedBox(width: 6),
          _iconBtn(Icons.delete_outline, onRemove, onSurface),
        ],
      ),
    );
  }

  Widget _iconBtn(IconData icon, VoidCallback onTap, Color onSurface) {
    return InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Icon(icon, size: 20, color: onSurface),
      ),
    );
  }
}

class _NoteChip extends StatelessWidget {
  final bool hasNote;
  final String preview;
  final Color onSurface;
  final VoidCallback onTap;
  const _NoteChip({
    required this.hasNote,
    required this.preview,
    required this.onSurface,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(40, 34),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        visualDensity: const VisualDensity(horizontal: -2, vertical: -2),
        side: BorderSide(color: onSurface.withOpacity(0.18)),
        shape: const StadiumBorder(),
        foregroundColor: onSurface.withOpacity(0.95),
        backgroundColor:
            hasNote ? onSurface.withOpacity(0.08) : Colors.transparent,
      ),
      icon: Icon(hasNote ? Icons.sticky_note_2 : Icons.note_add_outlined, size: 18),
      label: Text(hasNote ? preview : 'Add note'),
    );
  }
}
