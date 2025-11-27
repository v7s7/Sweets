import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

import '../../core/config/app_config.dart';
import '../../core/services/email_service.dart';

class ReportsPage extends ConsumerStatefulWidget {
  const ReportsPage({super.key});

  @override
  ConsumerState<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends ConsumerState<ReportsPage> {
  final _emailController = TextEditingController();
  DateTimeRange? _selectedDateRange;
  bool _isGenerating = false;
  String? _errorMessage;
  String? _successMessage;

  // Quick range options
  final List<_QuickRange> _quickRanges = [
    _QuickRange(
      label: 'Today',
      start: DateTime.now(),
      end: DateTime.now(),
    ),
    _QuickRange(
      label: 'Yesterday',
      start: DateTime.now().subtract(const Duration(days: 1)),
      end: DateTime.now().subtract(const Duration(days: 1)),
    ),
    _QuickRange(
      label: 'Last 7 Days',
      start: DateTime.now().subtract(const Duration(days: 6)),
      end: DateTime.now(),
    ),
    _QuickRange(
      label: 'Last 30 Days',
      start: DateTime.now().subtract(const Duration(days: 29)),
      end: DateTime.now(),
    ),
  ];

  int _selectedQuickRange = 0;

  @override
  void initState() {
    super.initState();
    // Default to today
    _selectedDateRange = DateTimeRange(
      start: _quickRanges[0].start,
      end: _quickRanges[0].end,
    );
    // Load user email
    _loadUserEmail();
  }

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _loadUserEmail() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user?.email != null) {
      setState(() {
        _emailController.text = user!.email!;
      });
    } else {
      // Try to load from settings
      final merchantId = ref.read(merchantIdProvider);
      final branchId = ref.read(branchIdProvider);
      final settingsDoc = await FirebaseFirestore.instance
          .doc('merchants/$merchantId/branches/$branchId/config/settings')
          .get();
      final email = settingsDoc.data()?['emailNotifications']?['email'];
      if (email != null) {
        setState(() {
          _emailController.text = email;
        });
      }
    }
  }

  void _selectQuickRange(int index) {
    setState(() {
      _selectedQuickRange = index;
      _selectedDateRange = DateTimeRange(
        start: _quickRanges[index].start,
        end: _quickRanges[index].end,
      );
    });
  }

  Future<void> _selectCustomRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: _selectedDateRange,
    );

    if (picked != null) {
      setState(() {
        _selectedDateRange = picked;
        _selectedQuickRange = -1; // Custom range
      });
    }
  }

  Future<void> _generateReport() async {
    if (_selectedDateRange == null) {
      setState(() {
        _errorMessage = 'Please select a date range';
      });
      return;
    }

    if (_emailController.text.trim().isEmpty) {
      setState(() {
        _errorMessage = 'Please enter an email address';
      });
      return;
    }

    setState(() {
      _isGenerating = true;
      _errorMessage = null;
      _successMessage = null;
    });

    try {
      final merchantId = ref.read(merchantIdProvider);
      final branchId = ref.read(branchIdProvider);

      // Set time range to cover entire days
      final start = DateTime(
        _selectedDateRange!.start.year,
        _selectedDateRange!.start.month,
        _selectedDateRange!.start.day,
        0, 0, 0,
      );
      final end = DateTime(
        _selectedDateRange!.end.year,
        _selectedDateRange!.end.month,
        _selectedDateRange!.end.day,
        23, 59, 59, 999,
      );

      // Query orders in date range
      final ordersSnap = await FirebaseFirestore.instance
          .collection('merchants/$merchantId/branches/$branchId/orders')
          .where('createdAt', isGreaterThanOrEqualTo: start)
          .where('createdAt', isLessThanOrEqualTo: end)
          .get();

      // Calculate stats
      double totalRevenue = 0;
      int servedOrders = 0;
      int cancelledOrders = 0;
      final ordersByStatus = <String, int>{};
      final itemCounts = <String, _ItemStats>{};

      for (final doc in ordersSnap.docs) {
        final order = doc.data();
        final status = order['status'] as String? ?? 'unknown';

        ordersByStatus[status] = (ordersByStatus[status] ?? 0) + 1;

        if (status == 'served') {
          servedOrders++;
          totalRevenue += (order['subtotal'] as num?)?.toDouble() ?? 0.0;

          // Count items
          final items = order['items'] as List<dynamic>? ?? [];
          for (final item in items) {
            final name = item['name'] as String? ?? 'Unknown';
            final qty = (item['qty'] as num?)?.toInt() ?? 0;
            final price = (item['price'] as num?)?.toDouble() ?? 0.0;

            if (!itemCounts.containsKey(name)) {
              itemCounts[name] = _ItemStats(name: name);
            }
            itemCounts[name] = itemCounts[name]!.add(qty, price);
          }
        } else if (status == 'cancelled') {
          cancelledOrders++;
        }
      }

      // Get merchant name
      final brandingDoc = await FirebaseFirestore.instance
          .doc('merchants/$merchantId/branches/$branchId/config/branding')
          .get();
      final merchantName = brandingDoc.data()?['title'] as String? ?? 'Your Store';

      // Prepare data
      final dateRange = '${DateFormat('MM/dd/yyyy').format(start)} - ${DateFormat('MM/dd/yyyy').format(end)}';
      final topItems = itemCounts.values.toList()
        ..sort((a, b) => b.count.compareTo(a.count));
      final statusList = ordersByStatus.entries
          .map((e) => StatusCount(status: e.key, count: e.value))
          .toList();

      // Send email via Cloudflare Worker
      final result = await EmailService.sendReport(
        merchantName: merchantName,
        dateRange: dateRange,
        totalOrders: ordersSnap.docs.length,
        totalRevenue: totalRevenue,
        servedOrders: servedOrders,
        cancelledOrders: cancelledOrders,
        averageOrder: servedOrders > 0 ? totalRevenue / servedOrders : 0,
        topItems: topItems
            .map((item) => TopItem(
                  name: item.name,
                  count: item.count,
                  revenue: item.revenue,
                ))
            .toList(),
        ordersByStatus: statusList,
        toEmail: _emailController.text.trim(),
      );

      if (mounted) {
        if (result.success) {
          setState(() {
            _successMessage =
                'Report sent to ${_emailController.text.trim()}!\n${ordersSnap.docs.length} orders found.';
            _isGenerating = false;
          });

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(_successMessage!),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 4),
            ),
          );
        } else {
          setState(() {
            _errorMessage = 'Failed to send report: ${result.error}';
            _isGenerating = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to generate report: ${e.toString()}';
          _isGenerating = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dateFormat = DateFormat('MMM dd, yyyy');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sales Reports'),
        backgroundColor: theme.colorScheme.primaryContainer,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        Icon(
                          Icons.analytics_outlined,
                          size: 48,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Generate Sales Report',
                          style: theme.textTheme.headlineSmall,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Get detailed insights about your orders and revenue',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                // Quick range buttons
                Text(
                  'Select Period',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: List.generate(_quickRanges.length, (index) {
                    return ChoiceChip(
                      label: Text(_quickRanges[index].label),
                      selected: _selectedQuickRange == index,
                      onSelected: (_) => _selectQuickRange(index),
                    );
                  }),
                ),

                const SizedBox(height: 16),

                // Custom range button
                OutlinedButton.icon(
                  onPressed: _selectCustomRange,
                  icon: const Icon(Icons.calendar_month),
                  label: Text(
                    _selectedQuickRange == -1 && _selectedDateRange != null
                        ? 'Custom: ${dateFormat.format(_selectedDateRange!.start)} - ${dateFormat.format(_selectedDateRange!.end)}'
                        : 'Select Custom Range',
                  ),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.all(16),
                  ),
                ),

                const SizedBox(height: 24),

                // Selected date range display
                if (_selectedDateRange != null)
                  Card(
                    color: theme.colorScheme.primaryContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Icon(
                            Icons.date_range,
                            color: theme.colorScheme.onPrimaryContainer,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Selected Range',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onPrimaryContainer,
                                  ),
                                ),
                                Text(
                                  '${dateFormat.format(_selectedDateRange!.start)} - ${dateFormat.format(_selectedDateRange!.end)}',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    color: theme.colorScheme.onPrimaryContainer,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                const SizedBox(height: 24),

                // Email input
                Text(
                  'Email Address',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _emailController,
                  decoration: InputDecoration(
                    hintText: 'merchant@example.com',
                    prefixIcon: const Icon(Icons.email_outlined),
                    border: const OutlineInputBorder(),
                    helperText: 'Report will be sent to this email',
                  ),
                  keyboardType: TextInputType.emailAddress,
                ),

                const SizedBox(height: 24),

                // Error message
                if (_errorMessage != null)
                  Card(
                    color: theme.colorScheme.errorContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          Icon(
                            Icons.error_outline,
                            color: theme.colorScheme.onErrorContainer,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _errorMessage!,
                              style: TextStyle(
                                color: theme.colorScheme.onErrorContainer,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                // Success message
                if (_successMessage != null)
                  Card(
                    color: Colors.green.shade50,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.check_circle_outline,
                            color: Colors.green,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _successMessage!,
                              style: const TextStyle(color: Colors.green),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                const SizedBox(height: 16),

                // Generate button
                FilledButton.icon(
                  onPressed: _isGenerating ? null : _generateReport,
                  icon: _isGenerating
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.send),
                  label: Text(
                    _isGenerating ? 'Generating...' : 'Generate & Send Report',
                  ),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.all(16),
                  ),
                ),

                const SizedBox(height: 24),

                // Info card
                Card(
                  color: theme.colorScheme.surfaceContainerHighest,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.info_outline,
                              size: 20,
                              color: theme.colorScheme.primary,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Report Includes',
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _InfoItem(text: 'Total revenue and order count'),
                        _InfoItem(text: 'Average order value'),
                        _InfoItem(text: 'Orders breakdown by status'),
                        _InfoItem(text: 'Top selling items'),
                        _InfoItem(text: 'Cancelled orders analysis'),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ItemStats {
  final String name;
  final int count;
  final double revenue;

  _ItemStats({
    required this.name,
    this.count = 0,
    this.revenue = 0.0,
  });

  _ItemStats add(int qty, double price) {
    return _ItemStats(
      name: name,
      count: count + qty,
      revenue: revenue + (qty * price),
    );
  }
}

class _QuickRange {
  final String label;
  final DateTime start;
  final DateTime end;

  _QuickRange({
    required this.label,
    required this.start,
    required this.end,
  });
}

class _InfoItem extends StatelessWidget {
  final String text;

  const _InfoItem({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(
            Icons.check_circle,
            size: 16,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}
