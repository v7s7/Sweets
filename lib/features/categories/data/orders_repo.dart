import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/branding/branding_providers.dart'; // merchantIdProvider, branchIdProvider
import '../../orders/data/order_models.dart' as om;

enum OrdersFilter { all, pending, accepted, preparing, ready, served, cancelled }

final ordersFilterProvider = StateProvider<OrdersFilter>((_) => OrdersFilter.all);

final ordersStreamProvider = StreamProvider<List<om.Order>>((ref) {
  final m = ref.watch(merchantIdProvider);
  final b = ref.watch(branchIdProvider);
  final filter = ref.watch(ordersFilterProvider);

  Query<Map<String, dynamic>> q = FirebaseFirestore.instance
      .collection('merchants').doc(m)
      .collection('branches').doc(b)
      .collection('orders');

  if (filter != OrdersFilter.all) {
    q = q.where('status', isEqualTo: _statusString(filter));
  }

  // Most recent first; cap to a reasonable number
  q = q.orderBy('createdAt', descending: true).limit(100);

  return q.snapshots().map((snap) {
    return snap.docs.map((d) => _fromDoc(d)).toList();
  });
});

String _statusString(OrdersFilter f) {
  switch (f) {
    case OrdersFilter.pending:   return 'pending';
    case OrdersFilter.accepted:  return 'accepted';
    case OrdersFilter.preparing: return 'preparing';
    case OrdersFilter.ready:     return 'ready';
    case OrdersFilter.served:    return 'served';
    case OrdersFilter.cancelled: return 'cancelled';
    case OrdersFilter.all:       return '';
  }
}

om.Order _fromDoc(DocumentSnapshot<Map<String, dynamic>> snap) {
  final d = snap.data() ?? const <String, dynamic>{};
  final rawItems = (d['items'] as List?) ?? const [];
  final items = rawItems.whereType<Map>().map((m) {
    final price = _asNum(m['price']).toDouble();
    final qty   = _asNum(m['qty']).toInt();
    return om.OrderItem(
      productId: (m['productId'] ?? '').toString(),
      name: (m['name'] ?? '').toString(),
      price: price,
      qty: qty,
    );
  }).toList();

  final subtotal = (d['subtotal'] is num)
      ? (d['subtotal'] as num).toDouble()
      : items.fold<double>(0, (s, it) => s + it.price * it.qty);

  final ts = d['createdAt'];
  final createdAt = ts is Timestamp ? ts.toDate() : DateTime.now();

  return om.Order(
    orderId: snap.id,
    orderNo: (d['orderNo'] ?? '—').toString(),
    status: _statusFromString((d['status'] ?? 'pending').toString()),
    createdAt: createdAt,
    items: items,
    subtotal: double.parse(subtotal.toStringAsFixed(3)),
    table: (d['table'] as String?)?.trim(),
  );
}

om.OrderStatus _statusFromString(String s) {
  switch (s) {
    case 'pending':   return om.OrderStatus.pending;
    case 'accepted':  return om.OrderStatus.accepted;
    case 'preparing': return om.OrderStatus.preparing;
    case 'ready':     return om.OrderStatus.ready;
    case 'served':    return om.OrderStatus.served;
    case 'cancelled': return om.OrderStatus.cancelled;
    default:          return om.OrderStatus.pending;
  }
}

num _asNum(Object? v, {num fallback = 0}) {
  if (v == null) return fallback;
  if (v is num) return v;
  if (v is String) return num.tryParse(v) ?? fallback;
  return fallback;
}
