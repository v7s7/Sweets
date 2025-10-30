// lib/core/branding/branding_repo.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'branding.dart';

class BrandingRepo {
  final FirebaseFirestore db;
  BrandingRepo(this.db);

  /// merchants/{m}/branches/{b}/config/branding
  DocumentReference<Map<String, dynamic>> _doc(String m, String b) {
    return db
        .collection('merchants').doc(m)
        .collection('branches').doc(b)
        .collection('config').doc('branding');
  }

  /// Live branding stream with safe fallbacks and deduping.
  Stream<Branding> watch(String m, String b) {
    final path = 'merchants/$m/branches/$b/config/branding';
    if (kDebugMode) debugPrint('BrandingRepo.watch -> $path');

    return _doc(m, b).snapshots().map((snap) {
      if (!snap.exists || snap.data() == null) {
        if (kDebugMode) debugPrint('Branding missing at $path -> using fallback');
        return const Branding(
          title: 'App',
          headerText: '',
          primaryHex: '#FFFFFF',
          secondaryHex: '#000000',
          logoUrl: null,
        );
      }
      final d = snap.data()!;
      return Branding(
        title: _str(d, 'title', 'App'),
        headerText: _str(d, 'headerText', ''),
        primaryHex: _str(d, 'primaryHex', '#FFFFFF'),
        secondaryHex: _str(d, 'secondaryHex', '#000000'),
        logoUrl: _strOrNull(d, 'logoUrl'),
      );
    }).distinct((a, b) => a == b);
  }

  /// Merge-save (only provided fields are updated).
  Future<void> save(String m, String b, Branding bnd) {
    return _doc(m, b).set({
      'title': bnd.title,
      'headerText': bnd.headerText,
      'primaryHex': bnd.primaryHex,
      'secondaryHex': bnd.secondaryHex,
      'logoUrl': bnd.logoUrl,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  // ----------------- helpers -----------------

  static String _str(Map<String, dynamic> m, String k, String fallback) {
    final s = (m[k] as String?)?.trim();
    return (s == null || s.isEmpty) ? fallback : s;
    }

  static String? _strOrNull(Map<String, dynamic> m, String k) {
    final s = (m[k] as String?)?.trim();
    return (s == null || s.isEmpty) ? null : s;
  }
}
