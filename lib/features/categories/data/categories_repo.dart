import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/branding/branding_providers.dart';
import 'category.dart';

final categoriesStreamProvider = StreamProvider<List<Category>>((ref) {
  final m = ref.watch(merchantIdProvider);
  final b = ref.watch(branchIdProvider);
  final col = FirebaseFirestore.instance
      .collection('merchants').doc(m)
      .collection('branches').doc(b)
      .collection('categories')
      .where('isActive', isEqualTo: true)
      .orderBy('parentId')
      .orderBy('sort');

  return col.snapshots().map((qs) =>
      qs.docs.map((d) => Category.fromDoc(d.id, d.data())).toList());
});
