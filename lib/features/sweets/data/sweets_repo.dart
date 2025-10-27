// lib/features/sweets/data/sweets_repo.dart (FIXED)
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/branding/branding_providers.dart'; // For IDs
import 'sweet.dart';

/// Live menu items for the effective merchant/branch
final sweetsStreamProvider = StreamProvider<List<Sweet>>((ref) {
  // IDs come from app.dart via the Notifier providers
  final m = ref.watch(merchantIdProvider);
  final b = ref.watch(branchIdProvider);

  debugPrint('🍬 SweetsRepo: Loading menu for m=$m b=$b');

  if (m.isEmpty || b.isEmpty) {
    debugPrint('⚠️ SweetsRepo: Empty IDs, returning empty stream');
    return const Stream<List<Sweet>>.empty();
  }

  final query = FirebaseFirestore.instance
      .collection('merchants').doc(m)
      .collection('branches').doc(b)
      .collection('menuItems')
      .where('isActive', isEqualTo: true)
      .orderBy('sort', descending: false);

  return query.snapshots().map((qs) {
    debugPrint('✅ SweetsRepo: Received ${qs.docs.length} items');

    return qs.docs.map((d) {
      final v = d.data();
      final imgUrl = (v['imageUrl'] ?? '').toString().trim();
      final imgAsset = (v['imageAsset'] ?? '').toString().trim();

      return Sweet(
        id: d.id,
        name: (v['name'] ?? d.id).toString(),
        imageAsset: imgAsset.isNotEmpty
            ? imgAsset
            : (imgUrl.isNotEmpty ? imgUrl : ''),
        imageUrl: imgUrl.isNotEmpty ? imgUrl : null,
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
