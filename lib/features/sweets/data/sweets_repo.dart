// lib/features/sweets/data/sweets_repo.dart (FINAL)
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/branding/branding_providers.dart'; // merchantIdProvider / branchIdProvider
import 'sweet.dart';

/// Live menu items for the effective merchant/branch
final sweetsStreamProvider = StreamProvider<List<Sweet>>((ref) {
  // IDs are set by app.dart via the Notifier providers
  final m = ref.watch(merchantIdProvider);
  final b = ref.watch(branchIdProvider);

  // Basic guard
  if (m.isEmpty || b.isEmpty) {
    return const Stream<List<Sweet>>.empty();
  }

  final col = FirebaseFirestore.instance
      .collection('merchants').doc(m)
      .collection('branches').doc(b)
      .collection('menuItems')
      .where('isActive', isEqualTo: true)
      .orderBy('sort', descending: false);

  return col.snapshots().map((qs) {
    return qs.docs.map((d) {
      final v = d.data();

      final imgUrl = (v['imageUrl'] ?? '').toString().trim();
      final imgAsset = (v['imageAsset'] ?? '').toString().trim();
      final categoryId = (v['categoryId'] ?? '').toString().trim();
      final subcategoryId = (v['subcategoryId'] ?? '').toString().trim();

      return Sweet(
        id: d.id,
        name: (v['name'] ?? d.id).toString(),
        // Keep imageAsset non-null for existing widgets that expect it
        imageAsset: imgAsset.isNotEmpty
            ? imgAsset
            : (imgUrl.isNotEmpty ? imgUrl : ''),
        imageUrl: imgUrl.isNotEmpty ? imgUrl : null,
        categoryId: categoryId.isEmpty ? null : categoryId,
        subcategoryId: subcategoryId.isEmpty ? null : subcategoryId,
        calories: _asInt(v['calories']),
        protein: _asDoubleOrNull(v['protein']),
        carbs: _asDoubleOrNull(v['carbs']),
        fat: _asDoubleOrNull(v['fat']),
        sugar: _asDoubleOrNull(v['sugar']),
        price: _asDouble(v['price']),
      );
    }).toList();
  });
});

int _asInt(Object? v) => v is int ? v : int.tryParse(v?.toString() ?? '') ?? 0;

double _asDouble(Object? v) =>
    v is num ? v.toDouble() : double.tryParse(v?.toString() ?? '') ?? 0.0;

double? _asDoubleOrNull(Object? v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString());
}
