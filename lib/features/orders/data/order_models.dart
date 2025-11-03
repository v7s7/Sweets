import 'package:flutter/foundation.dart';

enum OrderStatus { pending, accepted, preparing, ready, served, cancelled }

extension OrderStatusX on OrderStatus {
  String get label => describeEnum(this).toUpperCase();
}

class OrderItem {
  final String productId;
  final String name;
  final double price; // unit price
  final int qty;
  final String? note; // NEW: per-item note

  const OrderItem({
    required this.productId,
    required this.name,
    required this.price,
    required this.qty,
    this.note,
  });

  double get lineTotal => price * qty;
}

class Order {
  final String orderId;   // e.g., local_1700000000000
  final String orderNo;   // human readable, e.g., "A-001" (stubbed)
  final OrderStatus status;
  final DateTime createdAt;
  final List<OrderItem> items;
  final double subtotal;
  final String? table; // from QR later

  const Order({
    required this.orderId,
    required this.orderNo,
    required this.status,
    required this.createdAt,
    required this.items,
    required this.subtotal,
    this.table,
  });

  Order copyWith({OrderStatus? status}) {
    return Order(
      orderId: orderId,
      orderNo: orderNo,
      status: status ?? this.status,
      createdAt: createdAt,
      items: items,
      subtotal: subtotal,
      table: table,
    );
  }
}
  