// lib/merchant/screens/orders_admin_page.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/branding/branding_providers.dart';
import '../../features/orders/data/order_models.dart' as om;

/// ===== Filters =====
enum OrdersFilter { all, pending, preparing, ready, served, cancelled }

extension OrdersFilterX on OrdersFilter {
  String? get statusString {
    switch (this) {
      case OrdersFilter.all:
        return null; // "All" excludes cancelled below
      case OrdersFilter.pending:
        return 'pending';
      case OrdersFilter.preparing:
        return 'preparing';
      case OrdersFilter.ready:
        return 'ready';
      case OrdersFilter.served:
        return 'served';
      case OrdersFilter.cancelled:
        return 'cancelled';
    }
  }

  String get label {
    switch (this) {
      case OrdersFilter.all:
        return 'All';
      case OrdersFilter.pending:
        return 'Pending';
      case OrdersFilter.preparing:
        return 'Preparing';
      case OrdersFilter.ready:
        return 'Ready';
      case OrdersFilter.served:
        return 'Served';
      case OrdersFilter.cancelled:
        return 'Cancelled';
    }
  }
}

final ordersFilterProvider =
    StateProvider<OrdersFilter>((_) => OrdersFilter.all);

/// ===== Lightweight admin models =====
class _AdminOrder {
  final String id;
  final String orderNo;
  final om.OrderStatus status;
  final DateTime createdAt;
  final List<_AdminItem> items;
  final double subtotal;
  final String? table;

  _AdminOrder({
    required this.id,
    required this.orderNo,
    required this.status,
    required this.createdAt,
    required this.items,
    required this.subtotal,
    this.table,
  });
}

class _AdminItem {
  final String name;
  final double price;
  final int qty;
  final String? note;

  _AdminItem({
    required this.name,
    required this.price,
    required this.qty,
    this.note,
  });
}

/// ===== Orders stream (recent first) =====
final ordersStreamProvider =
    StreamProvider.autoDispose<List<_AdminOrder>>((ref) {
  final m = ref.watch(merchantIdProvider);
  final b = ref.watch(branchIdProvider);

  final col = FirebaseFirestore.instance
      .collection('merchants')
      .doc(m)
      .collection('branches')
      .doc(b)
      .collection('orders')
      .orderBy('createdAt', descending: true)
      .limit(200);

  return col.snapshots().map((qs) {
    return qs.docs.map((d) {
      final data = d.data();
      final ts = data['createdAt'];
      final dt = ts is Timestamp ? ts.toDate() : DateTime.now();

      final rawItems = (data['items'] as List?) ?? const [];
      final items = rawItems.whereType<Map>().map((m) {
        final price = (m['price'] is num)
            ? (m['price'] as num).toDouble()
            : double.tryParse('${m['price']}') ?? 0.0;
        final qty = (m['qty'] is num)
            ? (m['qty'] as num).toInt()
            : int.tryParse('${m['qty']}') ?? 0;
        return _AdminItem(
          name: (m['name'] ?? '').toString(),
          price: price,
          qty: qty,
          note: (m['note'] as String?)?.trim(),
        );
      }).toList();

      final subtotal = (data['subtotal'] is num)
          ? (data['subtotal'] as num).toDouble()
          : double.tryParse('${data['subtotal']}') ?? 0.0;

      return _AdminOrder(
        id: d.id,
        orderNo: (data['orderNo'] ?? '—').toString(),
        status: _statusFromString((data['status'] ?? 'pending').toString()),
        createdAt: dt,
        items: items,
        subtotal: double.parse(subtotal.toStringAsFixed(3)),
        table: (data['table'] as String?)?.trim(),
      );
    }).toList();
  });
});

/// ===== Status helpers =====
om.OrderStatus _statusFromString(String s) {
  switch (s) {
    case 'pending':
      return om.OrderStatus.pending;
    case 'accepted':
      return om.OrderStatus.accepted;
    case 'preparing':
      return om.OrderStatus.preparing;
    case 'ready':
      return om.OrderStatus.ready;
    case 'served':
      return om.OrderStatus.served;
    case 'cancelled':
      return om.OrderStatus.cancelled;
    default:
      return om.OrderStatus.pending;
  }
}

String _toFirestore(om.OrderStatus s) {
  switch (s) {
    case om.OrderStatus.pending:
      return 'pending';
    case om.OrderStatus.accepted:
      return 'accepted';
    case om.OrderStatus.preparing:
      return 'preparing';
    case om.OrderStatus.ready:
      return 'ready';
    case om.OrderStatus.served:
      return 'served';
    case om.OrderStatus.cancelled:
      return 'cancelled';
  }
}

String _label(om.OrderStatus s) {
  switch (s) {
    case om.OrderStatus.pending:
      return 'Pending';
    case om.OrderStatus.accepted:
      return 'Accepted';
    case om.OrderStatus.preparing:
      return 'Preparing';
    case om.OrderStatus.ready:
      return 'Ready';
    case om.OrderStatus.served:
      return 'Served';
    case om.OrderStatus.cancelled:
      return 'Cancelled';
  }
}

/// ===== Page =====
class OrdersAdminPage extends ConsumerWidget {
  const OrdersAdminPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(ordersStreamProvider);
    final selected = ref.watch(ordersFilterProvider);
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Orders'),
        centerTitle: true,
      ),
      body: Column(
        children: [
          _FiltersRow(selected: selected),
          const Divider(height: 1),
          Expanded(
            child: async.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text('Failed to load orders\n$e',
                      textAlign: TextAlign.center),
                ),
              ),
              data: (all) {
                // “All” excludes cancelled
                final f = selected.statusString;
                final list = (f == null)
                    ? all
                        .where((o) => o.status != om.OrderStatus.cancelled)
                        .toList()
                    : all.where((o) => _toFirestore(o.status) == f).toList();

                if (list.isEmpty) {
                  return Center(
                    child: Text('No orders',
                        style: TextStyle(color: onSurface.withOpacity(0.7))),
                  );
                }
                return ListView.separated(
                  itemCount: list.length,
                  separatorBuilder: (_, __) =>
                      Divider(height: 1, color: onSurface.withOpacity(0.08)),
                  itemBuilder: (_, i) => _OrderTile(order: list[i]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// ===== Filters row =====
class _FiltersRow extends ConsumerWidget {
  final OrdersFilter selected;
  const _FiltersRow({required this.selected});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Widget chip(OrdersFilter f) {
      final isSel = selected == f;
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: FilterChip(
          label: Text(f.label),
          selected: isSel,
          onSelected: (_) => ref.read(ordersFilterProvider.notifier).state = f,
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Row(
        children: [
          chip(OrdersFilter.all),
          chip(OrdersFilter.pending),
          chip(OrdersFilter.preparing),
          chip(OrdersFilter.ready),
          chip(OrdersFilter.served),
          chip(OrdersFilter.cancelled),
        ],
      ),
    );
  }
}

/// ===== Order tile =====
class _OrderTile extends ConsumerWidget {
  final _AdminOrder order;
  const _OrderTile({required this.order});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final notesCount =
        order.items.where((it) => (it.note ?? '').trim().isNotEmpty).length;

    return ListTile(
      dense: false,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      title: Row(
        children: [
          Text(
            order.orderNo.isNotEmpty ? '#${order.orderNo}' : '#${order.id}',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(width: 8),
          if (order.table != null && order.table!.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: onSurface.withOpacity(0.06),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                'Table ${order.table}',
                style: TextStyle(
                  fontSize: 12,
                  color: onSurface.withOpacity(0.85),
                ),
              ),
            ),
          const Spacer(),
          Text(
            order.subtotal.toStringAsFixed(3), // BHD 3dp
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ],
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Wrap(
          spacing: 8,
          runSpacing: -6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _StatusPill(status: order.status),
            Text(
              _fmtTime(order.createdAt),
              style: TextStyle(color: onSurface.withOpacity(0.7), fontSize: 12),
            ),
            Text('•', style: TextStyle(color: onSurface.withOpacity(0.5))),
            Text(
              '${order.items.length} items',
              style: TextStyle(color: onSurface.withOpacity(0.7), fontSize: 12),
            ),
            if (notesCount > 0) ...[
              Text('•', style: TextStyle(color: onSurface.withOpacity(0.5))),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: onSurface.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.note_alt_outlined,
                        size: 14, color: onSurface.withOpacity(0.85)),
                    const SizedBox(width: 4),
                    Text(
                      '$notesCount note${notesCount == 1 ? '' : 's'}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: onSurface.withOpacity(0.85),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      trailing: _StatusChanger(order: order),
      onTap: () => _showItems(context, order),
    );
  }

  String _fmtTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} • $h:$m';
  }

  void _showItems(BuildContext context, _AdminOrder o) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (_) {
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          itemCount: o.items.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (_, i) {
            final it = o.items[i];
            final note = (it.note ?? '').trim();
            final hasNote = note.isNotEmpty;

            return ListTile(
              dense: true,
              title: Text(it.name,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(it.price.toStringAsFixed(3)),
                  if (hasNote) ...[
                    const SizedBox(height: 6),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.note_alt_outlined,
                            size: 16, color: onSurface.withOpacity(0.8)),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            note,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
              trailing: Text('x${it.qty}'),
            );
          },
        );
      },
    );
  }
}

/// ===== Status pill (with translucent “shadow” tints) =====
class _StatusPill extends StatelessWidget {
  final om.OrderStatus status;
  const _StatusPill({required this.status});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final onSurface = scheme.onSurface;

    // Base neutral
    Color bg = onSurface.withOpacity(0.06);
    Color border = Colors.transparent;
    Color fg = onSurface;
    List<BoxShadow> shadow = const [];

    if (status == om.OrderStatus.served || status == om.OrderStatus.cancelled) {
      final bool served = status == om.OrderStatus.served;
      final Color tint = served
          ? const Color(0xFF22C55E) // green-500
          : const Color(0xFFEF4444);  // red-500

      bg = tint.withOpacity(served ? 0.16 : 0.12);
      border = tint.withOpacity(served ? 0.28 : 0.22);
      fg = onSurface.withOpacity(0.95);
      shadow = [
        BoxShadow(
          color: tint.withOpacity(0.16),
          blurRadius: 12,
          spreadRadius: 0,
          offset: const Offset(0, 2),
        ),
      ];
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border),
        boxShadow: shadow,
      ),
      child: Text(
        _label(status),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: fg,
        ),
      ),
    );
  }
}

/// ===== Status changer (rules + “advance” button) =====
class _StatusChanger extends ConsumerStatefulWidget {
  final _AdminOrder order;
  const _StatusChanger({required this.order});

  @override
  ConsumerState<_StatusChanger> createState() => _StatusChangerState();
}

class _StatusChangerState extends ConsumerState<_StatusChanger> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final cur = widget.order.status;
    final nextOptions = _nextOptionsFor(cur); // forward step + cancel

    // Dropdown shows CURRENT status; menu lists current + forward options.
    final items = <om.OrderStatus>[cur, ...nextOptions];

    final disabled =
        cur == om.OrderStatus.served || cur == om.OrderStatus.cancelled;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        DropdownButton<om.OrderStatus>(
          value: cur,
          isDense: true,
          onChanged: _busy || disabled
              ? null
              : (s) async {
                  if (s == null || s == cur) {
                    _hint(context);
                    return;
                  }
                  // never go back to pending
                  if (s == om.OrderStatus.pending) {
                    _hint(context);
                    return;
                  }
                  if (s == om.OrderStatus.accepted) {
                    await _acceptAndStartPreparing();
                  } else {
                    await _setStatus(s);
                  }
                },
          items: items
              .map((s) => DropdownMenuItem(
                    value: s,
                    child: Text(
                      s == cur ? '${_label(s)} (current)' : _label(s),
                    ),
                  ))
              .toList(),
        ),
        const SizedBox(width: 6),
        IconButton(
          tooltip: 'Cancel order',
          icon: const Icon(Icons.cancel_outlined),
          onPressed: _busy || disabled
              ? null
              : () => _setStatus(om.OrderStatus.cancelled),
        ),
        const SizedBox(width: 2),
        // ✓ = advance to next step (pending→accepted→preparing, preparing→ready, ready→served)
        IconButton(
          tooltip: 'Advance to next step',
          icon: const Icon(Icons.check_circle_outline),
          onPressed: _busy || disabled ? null : _advance,
        ),
      ],
    );
  }

  void _hint(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Choose a next step from the menu or click the ✓ button.'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  om.OrderStatus? _nextOf(om.OrderStatus s) {
    switch (s) {
      case om.OrderStatus.pending:
        return om.OrderStatus.preparing; // via accept→preparing
      case om.OrderStatus.accepted:
        return om.OrderStatus.preparing;
      case om.OrderStatus.preparing:
        return om.OrderStatus.ready;
      case om.OrderStatus.ready:
        return om.OrderStatus.served;
      case om.OrderStatus.served:
      case om.OrderStatus.cancelled:
        return null;
    }
  }

  List<om.OrderStatus> _nextOptionsFor(om.OrderStatus cur) {
    switch (cur) {
      case om.OrderStatus.pending:
        return const [om.OrderStatus.preparing, om.OrderStatus.cancelled];
      case om.OrderStatus.accepted:
        return const [om.OrderStatus.preparing, om.OrderStatus.cancelled];
      case om.OrderStatus.preparing:
        return const [om.OrderStatus.ready, om.OrderStatus.cancelled];
      case om.OrderStatus.ready:
        return const [om.OrderStatus.served, om.OrderStatus.cancelled];
      case om.OrderStatus.served:
      case om.OrderStatus.cancelled:
        return const <om.OrderStatus>[];
    }
  }

  Future<void> _advance() async {
    final cur = widget.order.status;
    if (cur == om.OrderStatus.pending) {
      await _acceptAndStartPreparing();
      return;
    }
    final next = _nextOf(cur);
    if (next == null) return;
    await _setStatus(next);
  }

  Future<void> _acceptAndStartPreparing() async {
    setState(() => _busy = true);
    final m = ref.read(merchantIdProvider);
    final b = ref.read(branchIdProvider);
    final doc = FirebaseFirestore.instance
        .collection('merchants')
        .doc(m)
        .collection('branches')
        .doc(b)
        .collection('orders')
        .doc(widget.order.id);

    try {
      await doc.update({
        'status': _toFirestore(om.OrderStatus.accepted),
        'acceptedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      await doc.update({
        'status': _toFirestore(om.OrderStatus.preparing),
        'preparingAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setStatus(om.OrderStatus newStatus) async {
    final cur = widget.order.status;
    if (newStatus == om.OrderStatus.pending && cur != om.OrderStatus.pending) {
      return;
    }

    setState(() => _busy = true);
    final m = ref.read(merchantIdProvider);
    final b = ref.read(branchIdProvider);
    final doc = FirebaseFirestore.instance
        .collection('merchants')
        .doc(m)
        .collection('branches')
        .doc(b)
        .collection('orders')
        .doc(widget.order.id);

    try {
      final payload = <String, dynamic>{
        'status': _toFirestore(newStatus),
        'updatedAt': FieldValue.serverTimestamp(),
      };

      switch (newStatus) {
        case om.OrderStatus.preparing:
          payload['preparingAt'] = FieldValue.serverTimestamp();
          break;
        case om.OrderStatus.ready:
          payload['readyAt'] = FieldValue.serverTimestamp();
          break;
        case om.OrderStatus.served:
          payload['servedAt'] = FieldValue.serverTimestamp();
          break;
        case om.OrderStatus.cancelled:
          payload['cancelledAt'] = FieldValue.serverTimestamp();
          break;
        case om.OrderStatus.pending:
        case om.OrderStatus.accepted:
          break;
      }

      await doc.update(payload);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
