// lib/core/config/slug_routing.dart (COMPLETE FIX)
import 'package:flutter_riverpod/flutter_riverpod.dart' as rp;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'app_config.dart';

typedef MerchantBranch = ({String merchantId, String branchId});

/// Resolves slug → IDs or returns explicit IDs from URL
final slugLookupProvider = rp.FutureProvider<MerchantBranch?>((ref) async {
  final cfg = ref.watch(appConfigProvider);

  // Priority 1: Explicit IDs from URL
  if (cfg.merchantId != null && cfg.branchId != null) {
    return (merchantId: cfg.merchantId!, branchId: cfg.branchId!);
  }

  // Priority 2: Resolve slug
  final slug = cfg.slug?.trim();
  if (slug == null || slug.isEmpty) return null;

  try {
    final snap = await FirebaseFirestore.instance
        .doc('slugs/$slug')
        .get();
    
    if (!snap.exists) {
      print('❌ Slug "$slug" not found in Firestore');
      return null;
    }

    final data = snap.data()!;
    final m = (data['merchantId'] ?? '').toString().trim();
    final b = (data['branchId'] ?? '').toString().trim();
    
    if (m.isEmpty || b.isEmpty) {
      print('❌ Slug "$slug" has invalid data: $data');
      return null;
    }

    print('✅ Slug "$slug" resolved to m=$m b=$b');
    return (merchantId: m, branchId: b);
  } catch (e) {
    print('❌ Slug lookup error: $e');
    return null;
  }
});

/// Sync provider that returns IDs immediately if available
final effectiveIdsProvider = rp.Provider<MerchantBranch?>((ref) {
  final cfg = ref.watch(appConfigProvider);
  
  // Explicit IDs always win
  if (cfg.merchantId != null && cfg.branchId != null) {
    return (merchantId: cfg.merchantId!, branchId: cfg.branchId!);
  }
  
  // Otherwise wait for slug resolution
  final async = ref.watch(slugLookupProvider);
  return async.maybeWhen(
    data: (mb) => mb,
    orElse: () => null,
  );
});