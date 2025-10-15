import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'order_models.dart';

/// In-memory stub used until we wire Cloud Functions in Step 7.
/// createOrder() returns an Order and starts a timed stream of status updates.
/// watchOrder() lets the UI observe those updates.
class OrderService {
  final Map<String, StreamController<Order>> _controllers = {};
  final Map<String, Order> _orders = {};

  Future<Order> createOrder({
    required List<OrderItem> items,
    String? table,
  }) async {
    final subtotal = items.fold<double>(0, (a, it) => a + it.lineTotal);
    final id = 'local_${DateTime.now().millisecondsSinceEpoch}';
    final order = Order(
      orderId: id,
      orderNo: '#LOCAL',
      status: OrderStatus.pending,
      createdAt: DateTime.now(),
      items: items,
      subtotal: subtotal,
      table: table,
    );
    _orders[id] = order;

    // Create a stream and emit status progression
    final ctrl = StreamController<Order>.broadcast();
    _controllers[id] = ctrl;
    ctrl.add(order);

    // Fake timeline: PENDING -> ACCEPTED -> PREPARING -> READY -> (leave READY)
    Future<void>.delayed(const Duration(seconds: 1), () {
      _emit(id, OrderStatus.accepted);
    });
    Future<void>.delayed(const Duration(seconds: 3), () {
      _emit(id, OrderStatus.preparing);
    });
    Future<void>.delayed(const Duration(seconds: 6), () {
      _emit(id, OrderStatus.ready);
    });

    return order;
  }

  Stream<Order> watchOrder(String orderId) {
    final ctrl = _controllers[orderId];
    if (ctrl != null) return ctrl.stream;
    // If not found (e.g., app restarted), return a completed stream.
    final o = _orders[orderId];
    if (o != null) {
      final sc = StreamController<Order>();
      sc.add(o);
      sc.close();
      return sc.stream;
    }
    // Empty stream
    return const Stream.empty();
  }

  void _emit(String id, OrderStatus status) {
    final current = _orders[id];
    final ctrl = _controllers[id];
    if (current == null || ctrl == null || ctrl.isClosed) return;
    final next = current.copyWith(status: status);
    _orders[id] = next;
    ctrl.add(next);
  }

  void dispose() {
    for (final c in _controllers.values) {
      c.close();
    }
    _controllers.clear();
  }
}

final orderServiceProvider = Provider<OrderService>((ref) {
  final svc = OrderService();
  ref.onDispose(svc.dispose);
  return svc;
});
