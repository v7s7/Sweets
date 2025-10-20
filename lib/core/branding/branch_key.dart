// lib/core/config/branch_key.dart (new file)
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' as rp;
import '../config/app_config.dart';

class BranchKey {
  final String m;
  final String b;
  const BranchKey(this.m, this.b);
}

final branchKeyProvider = rp.FutureProvider<BranchKey?>((ref) async {
  final cfg = ref.watch(appConfigProvider);
  if (cfg.merchantId != null && cfg.branchId != null) {
    return BranchKey(cfg.merchantId!, cfg.branchId!); // plain query case
  }
  if (cfg.slug != null && cfg.slug!.isNotEmpty) {
    final doc = await FirebaseFirestore.instance.doc('slugs/${cfg.slug}').get();
    if (doc.exists) {
      final data = doc.data()!;
      final m = data['merchantId']?.toString();
      final b = data['branchId']?.toString();
      if (m != null && b != null) return BranchKey(m, b);
    }
  }
  return null;
});
