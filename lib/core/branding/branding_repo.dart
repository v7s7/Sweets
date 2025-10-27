import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'branding.dart';

class BrandingRepo {
  final FirebaseFirestore db;
  BrandingRepo(this.db);

  DocumentReference<Map<String, dynamic>> _doc(String m, String b) {
    // ✅ Match your Firestore structure
    return db
        .collection('merchants').doc(m)
        .collection('branches').doc(b)
        .collection('config').doc('branding');
  }

  Stream<Branding> watch(String m, String b) {
    final path = 'merchants/$m/branches/$b/config/branding';
    debugPrint('BrandingRepo.watch -> $path'); // sanity log
    return _doc(m, b).snapshots().map((snap) {
      if (!snap.exists) {
        debugPrint('Branding doc missing at $path -> using fallback');
        return const Branding(
          title: 'App',
          headerText: '',
          primaryHex: '#FFFFFF',
          secondaryHex: '#000000',
        );
      }
      final d = snap.data()!;
      return Branding(
        title: (d['title'] as String?)?.trim().isNotEmpty == true ? d['title'] as String : 'App',
        headerText: (d['headerText'] as String?) ?? '',
        primaryHex: (d['primaryHex'] as String?) ?? '#FFFFFF',
        secondaryHex: (d['secondaryHex'] as String?) ?? '#000000',
        logoUrl: d['logoUrl'] as String?,
      );
    });
  }

  Future<void> save(String m, String b, Branding bnd) {
    return _doc(m, b).set({
      'title': bnd.title,
      'headerText': bnd.headerText,
      'primaryHex': bnd.primaryHex,
      'secondaryHex': bnd.secondaryHex,
      'logoUrl': bnd.logoUrl,
    }, SetOptions(merge: true));
  }
}
