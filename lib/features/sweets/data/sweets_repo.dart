import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/config/slug_routing.dart'; // <- provides effectiveIdsProvider
import 'sweet.dart';

/// Live menu items for the effective merchant/branch (IDs or slug).
final _sweetsStreamProvider = StreamProvider<List<Sweet>>((ref) {
  final ids = ref.watch(effectiveIdsProvider);
  if (ids == null) {
    // No merchant/branch yet → empty stream so UI stays calm.
    return const Stream<List<Sweet>>.empty();
  }

  final m = ids.merchantId;
  final b = ids.branchId;

  final qs = FirebaseFirestore.instance
      .collection('merchants/$m/branches/$b/menuItems')
      .where('isActive', isEqualTo: true)
      .orderBy('sort', descending: false)
      .snapshots();

  return qs.map((snap) => snap.docs.map((d) {
        final v = d.data();
        return Sweet(
          id: d.id,
          name: (v['name'] ?? d.id).toString(),
          // Pass network URL through imageAsset so existing SweetImage can render it.
          imageAsset: (v['imageUrl'] ?? '').toString(),
          // If you later use Sweet.imageUrl in widgets, it's fine to also set:
          // imageUrl: (v['imageUrl'] ?? '').toString(),
          calories: _asInt(v['calories']),
          protein: _asDoubleOrNull(v['protein']),
          carbs: _asDoubleOrNull(v['carbs']),
          fat: _asDoubleOrNull(v['fat']),
          sugar: _asDoubleOrNull(v['sugar']),
          price: _asDouble(v['price']),
        );
      }).toList());
});

/// Keep your current call sites unchanged: they read a plain `List<Sweet>`.
final sweetsRepoProvider = Provider<List<Sweet>>((ref) {
  final async = ref.watch(_sweetsStreamProvider);
  return async.value ?? const <Sweet>[];
});

// ---- helpers ----
int _asInt(Object? v) => v is int ? v : int.tryParse(v?.toString() ?? '') ?? 0;

double _asDouble(Object? v) =>
    v is num ? v.toDouble() : double.tryParse(v?.toString() ?? '') ?? 0.0;

double? _asDoubleOrNull(Object? v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString());
}
