import 'package:flutter_riverpod/flutter_riverpod.dart' as rp;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'app_config.dart';

typedef MerchantBranch = ({String merchantId, String branchId});

final slugLookupProvider = rp.FutureProvider<MerchantBranch?>((ref) async {
  final cfg = ref.watch(appConfigProvider);

  if (cfg.merchantId != null && cfg.branchId != null) {
    return (merchantId: cfg.merchantId!, branchId: cfg.branchId!);
  }

  final slug = cfg.slug?.trim();
  if (slug == null || slug.isEmpty) return null;

  final snap = await FirebaseFirestore.instance.doc('slugs/$slug').get();
  if (!snap.exists) return null;

  final data = snap.data()!;
  final m = (data['merchantId'] ?? '').toString().trim();
  final b = (data['branchId'] ?? '').toString().trim();
  if (m.isEmpty || b.isEmpty) return null;

  return (merchantId: m, branchId: b);
});

final effectiveIdsProvider = rp.Provider<MerchantBranch?>((ref) {
  final cfg = ref.watch(appConfigProvider);
  if (cfg.merchantId != null && cfg.branchId != null) {
    return (merchantId: cfg.merchantId!, branchId: cfg.branchId!);
  }
  final async = ref.watch(slugLookupProvider);
  return async.maybeWhen(data: (mb) => mb, orElse: () => null);
});
