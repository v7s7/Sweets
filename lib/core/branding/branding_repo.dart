// lib/core/branding/branding_repo.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'branding.dart';

class BrandingRepo {
  final FirebaseFirestore _db;
  BrandingRepo(this._db);

  Stream<Branding> watch(String merchantId, String branchId) {
    final ref = _db
        .collection('merchants').doc(merchantId)
        .collection('branches').doc(branchId)
        .collection('config').doc('branding');

    return ref.snapshots().map((s) => s.exists
        ? Branding.fromMap(s.data()!)
        : const Branding(
            title: 'App',
            headerText: '',
            primaryHex: '#E91E63',
            secondaryHex: '#FFB300',
          ));
  }

  Future<void> save(String merchantId, String branchId, Branding b) async {
    final ref = _db
        .collection('merchants').doc(merchantId)
        .collection('branches').doc(branchId)
        .collection('config').doc('branding');
    await ref.set(b.toMap(), SetOptions(merge: true));
  }
}
