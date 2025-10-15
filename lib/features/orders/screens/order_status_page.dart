import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../orders/data/order_models.dart';
import '../../orders/data/order_service.dart';

class OrderStatusPage extends ConsumerWidget {
  final String orderId;
  const OrderStatusPage({super.key, required this.orderId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stream = ref.watch(orderServiceProvider).watchOrder(orderId);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Order Status'),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.transparent,
        scrolledUnderElevation: 0,
      ),
      body: StreamBuilder<Order>(
        stream: stream,
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final order = snap.data!;
          return Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                _StatusPills(status: order.status),
                const SizedBox(height: 16),
                Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: const BorderSide(color: Color(0x11000000)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      children: [
                        Text('Order ',
                            style: Theme.of(context).textTheme.titleMedium),
                        Text(order.orderNo,
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w800)),
                        const Spacer(),
                        Text(order.subtotal.toStringAsFixed(3),
                            style: const TextStyle(
                                fontWeight: FontWeight.w800, fontSize: 16)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: ListView.separated(
                    itemCount: order.items.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final it = order.items[i];
                      return ListTile(
                        title: Text(it.name,
                            style:
                                const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle:
                            Text(it.price.toStringAsFixed(3)),
                        trailing: Text('x${it.qty}'),
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _StatusPills extends StatelessWidget {
  final OrderStatus status;
  const _StatusPills({required this.status});

  @override
  Widget build(BuildContext context) {
    final steps = const [
      OrderStatus.pending,
      OrderStatus.accepted,
      OrderStatus.preparing,
      OrderStatus.ready,
    ];
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: steps.map((s) {
        final active = _indexOf(status) >= _indexOf(s);
        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: active ? Colors.black : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0x22000000)),
            boxShadow: const [
              BoxShadow(color: Color(0x12000000), blurRadius: 8, offset: Offset(0,4))
            ],
          ),
          child: Text(
            s.label,
            style: TextStyle(
              color: active ? Colors.white : Colors.black87,
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
          ),
        );
      }).toList(),
    );
  }

  int _indexOf(OrderStatus s) {
    switch (s) {
      case OrderStatus.pending: return 0;
      case OrderStatus.accepted: return 1;
      case OrderStatus.preparing: return 2;
      case OrderStatus.ready: return 3;
      case OrderStatus.served: return 4;
      case OrderStatus.cancelled: return 5;
    }
  }
}
