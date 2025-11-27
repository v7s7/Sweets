import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/email_config.dart';

/// Email service for sending notifications and reports via Cloudflare Worker
class EmailService {
  /// Send order notification email
  static Future<EmailResult> sendOrderNotification({
    required String orderNo,
    String? table,
    required List<OrderItem> items,
    required double subtotal,
    required String timestamp,
    required String merchantName,
    required String dashboardUrl,
    required String toEmail,
  }) async {
    if (!EmailConfig.isConfigured) {
      return EmailResult.error(
          'Email service not configured. Please set the Cloudflare Worker URL in email_config.dart');
    }

    try {
      final response = await http.post(
        Uri.parse(EmailConfig.orderNotificationEndpoint),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'action': 'order-notification',
          'data': {
            'orderNo': orderNo,
            'table': table,
            'items': items.map((item) => item.toJson()).toList(),
            'subtotal': subtotal,
            'timestamp': timestamp,
            'merchantName': merchantName,
            'dashboardUrl': dashboardUrl,
            'toEmail': toEmail,
          },
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          return EmailResult.success(data['messageId']);
        } else {
          return EmailResult.error(data['error'] ?? 'Unknown error');
        }
      } else {
        return EmailResult.error(
            'HTTP ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      return EmailResult.error('Network error: $e');
    }
  }

  /// Send customer order confirmation email
  static Future<EmailResult> sendCustomerConfirmation({
    required String orderNo,
    String? table,
    required List<OrderItem> items,
    required double subtotal,
    required String timestamp,
    required String merchantName,
    String? estimatedTime,
    required String toEmail,
  }) async {
    if (!EmailConfig.isConfigured) {
      return EmailResult.error(
          'Email service not configured. Please set the Cloudflare Worker URL in email_config.dart');
    }

    try {
      final response = await http.post(
        Uri.parse(EmailConfig.orderNotificationEndpoint),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'action': 'customer-confirmation',
          'data': {
            'orderNo': orderNo,
            'table': table,
            'items': items.map((item) => item.toJson()).toList(),
            'subtotal': subtotal,
            'timestamp': timestamp,
            'merchantName': merchantName,
            'estimatedTime': estimatedTime,
            'toEmail': toEmail,
          },
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          return EmailResult.success(data['messageId']);
        } else {
          return EmailResult.error(data['error'] ?? 'Unknown error');
        }
      } else {
        return EmailResult.error(
            'HTTP ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      return EmailResult.error('Network error: $e');
    }
  }

  /// Send sales report email
  static Future<EmailResult> sendReport({
    required String merchantName,
    required String dateRange,
    required int totalOrders,
    required double totalRevenue,
    required int servedOrders,
    required int cancelledOrders,
    required double averageOrder,
    required List<TopItem> topItems,
    required List<StatusCount> ordersByStatus,
    required String toEmail,
  }) async {
    if (!EmailConfig.isConfigured) {
      return EmailResult.error(
          'Email service not configured. Please set the Cloudflare Worker URL in email_config.dart');
    }

    try {
      final response = await http.post(
        Uri.parse(EmailConfig.reportEndpoint),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'action': 'report',
          'data': {
            'merchantName': merchantName,
            'dateRange': dateRange,
            'totalOrders': totalOrders,
            'totalRevenue': totalRevenue,
            'servedOrders': servedOrders,
            'cancelledOrders': cancelledOrders,
            'averageOrder': averageOrder,
            'topItems': topItems.map((item) => item.toJson()).toList(),
            'ordersByStatus':
                ordersByStatus.map((status) => status.toJson()).toList(),
            'toEmail': toEmail,
          },
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          return EmailResult.success(data['messageId']);
        } else {
          return EmailResult.error(data['error'] ?? 'Unknown error');
        }
      } else {
        return EmailResult.error(
            'HTTP ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      return EmailResult.error('Network error: $e');
    }
  }
}

/// Order item for email
class OrderItem {
  final String name;
  final int qty;
  final double price;
  final String? note;

  OrderItem({
    required this.name,
    required this.qty,
    required this.price,
    this.note,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'qty': qty,
        'price': price,
        if (note != null) 'note': note,
      };
}

/// Top selling item for reports
class TopItem {
  final String name;
  final int count;
  final double revenue;

  TopItem({
    required this.name,
    required this.count,
    required this.revenue,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'count': count,
        'revenue': revenue,
      };
}

/// Status count for reports
class StatusCount {
  final String status;
  final int count;

  StatusCount({
    required this.status,
    required this.count,
  });

  Map<String, dynamic> toJson() => {
        'status': status,
        'count': count,
      };
}

/// Email operation result
class EmailResult {
  final bool success;
  final String? messageId;
  final String? error;

  EmailResult._({
    required this.success,
    this.messageId,
    this.error,
  });

  factory EmailResult.success(String messageId) => EmailResult._(
        success: true,
        messageId: messageId,
      );

  factory EmailResult.error(String error) => EmailResult._(
        success: false,
        error: error,
      );
}
