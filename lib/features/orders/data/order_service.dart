import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Avoid name clash with Firestore's internal Order types.
import 'order_models.dart' as om;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../../core/config/slug_routing.dart';

typedef Json = Map<String, dynamic>;

/// OrderService (FREE plan):
/// - createOrder(): writes directly to Firestore (no Cloud Functions).
/// - watchOrder(): streams the order doc from Firestore.
class OrderService {
  OrderService({required this.merchantId, required this.branchId});

  final String merchantId;
  final String branchId;
  final FirebaseFirestore _fs = FirebaseFirestore.instance;

  // Shorthands
  String get _m => merchantId;
  String get _b => branchId;

  /// Creates an order by writing to Firestore (server-authoritative rules).
  ///
  /// Firestore Rules will validate:
  /// - userId matches current uid
  /// - status == "pending"
  /// - merchantId / branchId match path
  /// - items is a non-empty list (bounded)
  /// - Only staff can later update `status`
  Future<om.Order> createOrder({
    required List<om.OrderItem> items,
    String? table,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      throw StateError('Not signed in; initialize anonymous auth first.');
    }
    if (items.isEmpty) {
      throw StateError('Cart is empty.');
    }

    // Subtotal rounded to 3 decimals (BHD)
    final subtotal = double.parse(
      items
          .fold<num>(0, (s, it) => s + (it.price * it.qty))
          .toStringAsFixed(3),
    );

    try {
      if (kDebugMode) {
        debugPrint(
          '[OrderService] Creating order m=$_m b=$_b items=${items.length}',
        );
      }

      final doc = _fs
          .collection('merchants')
          .doc(_m)
          .collection('branches')
          .doc(_b)
          .collection('orders')
          .doc();

  await doc.set({
      'merchantId': _m,
      'branchId': _b,
      'userId': uid,
      'status': 'pending',
      'items': items.map((e) => {
            'productId': e.productId,
            'name': e.name,
            'price': e.price,
            'qty': e.qty,
            if ((e.note ?? '').trim().isNotEmpty) 'note': e.note!.trim(), // NEW
          }).toList(),
      'subtotal': subtotal,
      'currency': 'BHD',
      'table': table,
      'createdAt': FieldValue.serverTimestamp(),
      // 'orderNo' optional
    });

    return om.Order(
      orderId: doc.id,
      orderNo: '—',
      status: om.OrderStatus.pending,
      createdAt: DateTime.now(),
      items: items,
      subtotal: subtotal,
      table: table,
    );
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('createOrder(): Unexpected error: $e\n$st');
      }
      rethrow;
    }
  }

  /// Live stream of the order document.
  Stream<om.Order> watchOrder(String orderId) {
    final docRef = _orderDoc(orderId);
    return docRef.snapshots().where((s) => s.exists).map((snap) {
      final data = snap.data()!;
      final String statusStr = _asString(data['status'], fallback: 'pending');

      final dynamic ts = data['createdAt'];
      final DateTime createdAt =
          ts is Timestamp ? ts.toDate() : DateTime.now();

      final List<dynamic> rawItems = (data['items'] as List?) ?? const [];
      final List<om.OrderItem> itemsList = rawItems
          .whereType<Map>() // ensures map elements only
          .map((m) => _itemFromMap(_safeJson(m)))
          .toList();

      final double subtotalNum = (data['subtotal'] is num)
          ? (data['subtotal'] as num).toDouble()
          : itemsList.fold<double>(
              0.0, (s, it) => s + (it.price * it.qty.toDouble()));

      return om.Order(
        orderId: snap.id,
        orderNo: _asString(data['orderNo'], fallback: '—'),
        status: _statusFromString(statusStr),
        createdAt: createdAt,
        items: itemsList,
        subtotal: double.parse(subtotalNum.toStringAsFixed(3)),
        table: _asNullableString(data['table']),
      );
    });
  }

  DocumentReference<Map<String, dynamic>> _orderDoc(String orderId) {
    return _fs
        .collection('merchants')
        .doc(_m)
        .collection('branches')
        .doc(_b)
        .collection('orders')
        .doc(orderId);
  }

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

  om.OrderItem _itemFromMap(Json m) {
    return om.OrderItem(
      productId: _asString(m['productId']),
      name: _asString(m['name']),
      price: _asNum(m['price']).toDouble(),
      qty: _asNum(m['qty']).toInt(),
      note: _asNullableString(m['note']), // NEW
    );
  }

  // --------------------------- helpers: parsing ---------------------------

  static Json _safeJson(Object? o) {
    if (o is Map<String, dynamic>) return o;
    if (o is Map) return Map<String, dynamic>.from(o);
    throw StateError('Expected Map, got $o');
  }

  static String _asString(Object? v, {String fallback = ''}) {
    if (v == null) return fallback;
    if (v is String) return v;
    return v.toString();
  }

  static String? _asNullableString(Object? v) {
    if (v == null) return null;
    if (v is String) return v;
    return v.toString();
  }

  static num _asNum(Object? v, {num fallback = 0}) {
    if (v == null) return fallback;
    if (v is num) return v;
    if (v is String) {
      final parsed = num.tryParse(v);
      return parsed ?? fallback;
    }
    return fallback;
  }
}

/// Riverpod provider resolving pretty links (slug) or explicit IDs.
final orderServiceProvider = Provider<OrderService>((ref) {
  final ids = ref.watch(effectiveIdsProvider);
  if (ids == null) {
    throw StateError('Missing merchant/branch (provide ?m=&b= or a valid slug).');
  }
  return OrderService(merchantId: ids.merchantId, branchId: ids.branchId);
});
