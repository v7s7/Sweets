import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'email_service.dart';

/// Service to listen for new orders and send email notifications
class OrderNotificationService {
  StreamSubscription<QuerySnapshot>? _subscription;
  final Set<String> _processedOrders = {};

  /// Start listening for new orders
  void startListening({
    required String merchantId,
    required String branchId,
    required String merchantEmail,
    required String merchantName,
    required bool enabled,
  }) {
    if (!enabled) {
      stopListening();
      return;
    }

    // Cancel existing subscription
    stopListening();

    // Listen to orders created in the last 5 minutes (to catch any we missed)
    final fiveMinutesAgo = DateTime.now().subtract(const Duration(minutes: 5));

    _subscription = FirebaseFirestore.instance
        .collection('merchants/$merchantId/branches/$branchId/orders')
        .where('status', isEqualTo: 'pending')
        .where('createdAt', isGreaterThan: fiveMinutesAgo)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .listen((snapshot) {
      for (final change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.added) {
          final orderId = change.doc.id;

          // Skip if already processed
          if (_processedOrders.contains(orderId)) {
            continue;
          }

          _processedOrders.add(orderId);

          // Send notification
          _sendOrderNotification(
            orderId: orderId,
            orderData: change.doc.data()!,
            merchantEmail: merchantEmail,
            merchantName: merchantName,
          );
        }
      }
    });
  }

  /// Stop listening for new orders
  void stopListening() {
    _subscription?.cancel();
    _subscription = null;
  }

  /// Send email notification for a new order
  Future<void> _sendOrderNotification({
    required String orderId,
    required Map<String, dynamic> orderData,
    required String merchantEmail,
    required String merchantName,
  }) async {
    try {
      final orderNo = orderData['orderNo'] as String? ?? orderId;
      final table = orderData['table'] as String?;
      final subtotal = (orderData['subtotal'] as num?)?.toDouble() ?? 0.0;

      final items = (orderData['items'] as List<dynamic>?)
              ?.map((item) => OrderItem(
                    name: item['name'] as String? ?? 'Unknown',
                    qty: (item['qty'] as num?)?.toInt() ?? 1,
                    price: (item['price'] as num?)?.toDouble() ?? 0.0,
                    note: item['note'] as String?,
                  ))
              .toList() ??
          [];

      final createdAt = orderData['createdAt'] as Timestamp?;
      final timestamp = createdAt != null
          ? DateFormat('MM/dd/yyyy hh:mm a').format(createdAt.toDate())
          : DateFormat('MM/dd/yyyy hh:mm a').format(DateTime.now());

      final result = await EmailService.sendOrderNotification(
        orderNo: orderNo,
        table: table,
        items: items,
        subtotal: subtotal,
        timestamp: timestamp,
        merchantName: merchantName,
        dashboardUrl: 'https://sweetweb.web.app/merchant',
        toEmail: merchantEmail,
      );

      if (result.success) {
        print('[OrderNotificationService] Email sent for order $orderNo: ${result.messageId}');
      } else {
        print('[OrderNotificationService] Failed to send email for order $orderNo: ${result.error}');
      }
    } catch (e) {
      print('[OrderNotificationService] Exception sending notification: $e');
    }
  }

  /// Clean up processed orders list (keep only last 100)
  void cleanupProcessedOrders() {
    if (_processedOrders.length > 100) {
      final toRemove = _processedOrders.length - 100;
      final iterator = _processedOrders.iterator;
      for (var i = 0; i < toRemove && iterator.moveNext(); i++) {
        _processedOrders.remove(iterator.current);
      }
    }
  }
}
