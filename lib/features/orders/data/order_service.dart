import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Use a prefix to avoid the name clash with Firestore's internal `Order` type.
import 'order_models.dart' as om;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../../../core/config/app_config.dart';

typedef Json = Map<String, dynamic>;

/// Read Functions region from a build-time define. Defaults to me-central2.
/// Pass like: --dart-define FUNCTIONS_REGION=me-central2
const String _kFunctionsRegion =
    String.fromEnvironment('FUNCTIONS_REGION', defaultValue: 'me-central2');

const String _kCreateOrderFn = 'createOrder';

/// OrderService:
/// - createOrder(): calls Cloud Function (server-authoritative).
/// - watchOrder(): live stream of the order doc in Firestore.
class OrderService {
  OrderService(this._config)
      : _functions = FirebaseFunctions.instanceFor(region: _kFunctionsRegion);

  final AppConfig _config;
  final FirebaseFirestore _fs = FirebaseFirestore.instance;
  final FirebaseFunctions _functions;

  /// Creates an order via Cloud Function (no client-side fallback).
  ///
  /// Server is authoritative over:
  /// - Pricing (reads from menuItems)
  /// - Subtotal (rounded to 3dp)
  /// - Order number (sequential via counters doc)
  /// - createdAt (serverTimestamp)
  Future<om.Order> createOrder({
    required List<om.OrderItem> items,
    String? table,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      throw StateError('Not signed in; anonymous auth must be initialized.');
    }

    try {
      if (kDebugMode) {
        debugPrint(
          '[OrderService] Calling $_kCreateOrderFn in region=$_kFunctionsRegion '
          'm=${_config.merchantId} b=${_config.branchId} items=${items.length}',
        );
      }

      final callable = _functions.httpsCallable(_kCreateOrderFn);
      final res = await callable.call(<String, dynamic>{
        'merchantId': _config.merchantId,
        'branchId': _config.branchId,
        'items': items
            .map((e) => <String, dynamic>{
                  'productId': e.productId,
                  'qty': e.qty,
                })
            .toList(),
        'table': table,
      });

      // Defensive parsing (Functions can serialize numbers as int or double)
      final Json data = _safeJson(res.data);

      final String orderId = _asString(data['orderId']);
      final String orderNo = _asString(data['orderNo'], fallback: '—');
      final om.OrderStatus status =
          _statusFromString(_asString(data['status'], fallback: 'pending'));
      final double subtotal =
          _asNum(data['subtotal']).toDouble(); // already 3dp from server

      return om.Order(
        orderId: orderId,
        orderNo: orderNo,
        status: status,
        createdAt: DateTime.now(), // replaced by stream below
        items: items, // UI will rehydrate from Firestore stream anyway
        subtotal: subtotal,
        table: table,
      );
    } on FirebaseFunctionsException catch (e, st) {
      if (kDebugMode) {
        debugPrint(
            'createOrder(): FirebaseFunctionsException code=${e.code} message=${e.message}\n$st');
      }
      rethrow;
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('createOrder(): Unexpected error: $e\n$st');
      }
      rethrow;
    }
  }

  /// Live stream of the order doc in Firestore.
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
          .whereType<Map>() // tighter than Object
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

  DocumentReference<Json> _orderDoc(String orderId) {
    return _fs
        .collection('merchants')
        .doc(_config.merchantId)
        .collection('branches')
        .doc(_config.branchId)
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
    );
  }

  // --------------------------- helpers: parsing ---------------------------

  static Json _safeJson(Object? o) {
    if (o is Map<String, dynamic>) {
      return o;
    }
    if (o is Map) {
      // No cast needed; we're already inside the `o is Map` branch.
      return Map<String, dynamic>.from(o);
    }
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

/// Riverpod provider wiring AppConfig into OrderService.
final orderServiceProvider = Provider<OrderService>((ref) {
  final cfg = ref.watch(appConfigProvider);
  return OrderService(cfg);
});
