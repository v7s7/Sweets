// lib/core/branding/branding_providers.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' as rp; // v3 bindings
import 'package:cloud_firestore/cloud_firestore.dart';

import 'branding.dart';
import 'branding_repo.dart';

/// ---------------- Merchant/Branch IDs (Riverpod v3 Notifier) ----------------

class MerchantIdNotifier extends rp.Notifier<String> {
  @override
  String build() => 'demo_merchant';
  void setId(String id) => state = id;          // <— add this
}

final merchantIdProvider =
    rp.NotifierProvider<MerchantIdNotifier, String>(MerchantIdNotifier.new);

class BranchIdNotifier extends rp.Notifier<String> {
  @override
  String build() => 'dev_branch';
  void setId(String id) => state = id;          // <— add this
}

final branchIdProvider =
    rp.NotifierProvider<BranchIdNotifier, String>(BranchIdNotifier.new);

/// --------------------------- Repo + Streams ---------------------------------

final brandingRepoProvider =
    rp.Provider<BrandingRepo>((ref) => BrandingRepo(FirebaseFirestore.instance));

final brandingProvider = rp.StreamProvider<Branding>((ref) {
  final m = ref.watch(merchantIdProvider);
  final b = ref.watch(branchIdProvider);
  return ref.watch(brandingRepoProvider).watch(m, b);
});

/// ---------------------------- Theme from Branding ---------------------------

final themeDataProvider = rp.Provider<ThemeData>((ref) {
  final branding = ref.watch(brandingProvider).maybeWhen(
        data: (b) => b,
        orElse: () => const Branding(
          title: 'App',
          headerText: '',
          primaryHex: '#E91E63',
          secondaryHex: '#FFB300',
        ),
      );

  final primary = branding.primaryHex.toColor();
  final secondary = branding.secondaryHex.toColor();

  final scheme = ColorScheme.fromSeed(seedColor: primary);
  return ThemeData(
    colorScheme: scheme.copyWith(secondary: secondary),
    useMaterial3: true,
    appBarTheme: AppBarTheme(
      backgroundColor: primary,
      foregroundColor: Colors.white,
      centerTitle: true,
      elevation: 0,
    ),
  );
});
