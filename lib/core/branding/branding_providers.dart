// lib/core/branding/branding_providers.dart
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart' as rp; // v3 bindings
import 'package:cloud_firestore/cloud_firestore.dart';

import 'branding.dart';
import 'branding_repo.dart';

/// ---------------- Merchant/Branch IDs (Riverpod v3 Notifier) ----------------
class MerchantIdNotifier extends rp.Notifier<String> {
@override
String build() => 'demo_merchant';
void setId(String id) => state = id;
}
final merchantIdProvider =
rp.NotifierProvider<MerchantIdNotifier, String>(MerchantIdNotifier.new);

class BranchIdNotifier extends rp.Notifier<String> {
@override
String build() => 'dev_branch';
void setId(String id) => state = id;
}
final branchIdProvider =
rp.NotifierProvider<BranchIdNotifier, String>(BranchIdNotifier.new);

/// --------------------------- Repo + Streams ---------------------------------
final brandingRepoProvider =
rp.Provider<BrandingRepo>((ref) => BrandingRepo(FirebaseFirestore.instance));

final brandingProvider = rp.StreamProvider<Branding>((ref) {
final m = ref.watch(merchantIdProvider);
final b = ref.watch(branchIdProvider);
debugPrint('brandingProvider: m=$m b=$b');
return ref.watch(brandingRepoProvider).watch(m, b);
});

/// ---------------------------- Theme from Branding ---------------------------
/// Global rules:
/// - Background/surfaces = primaryHex (solid)
/// - All text/icons = secondaryHex
/// - AppBar transparent
/// - Global font = 'YourFont'
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

final primary = branding.primaryHex.toColor(); // BG color
final secondary = branding.secondaryHex.toColor(); // Text/Icon color
final isLightBg = primary.computeLuminance() > 0.5;

// Start from a seeded scheme to populate all tokens, then force them.
final seeded = ColorScheme.fromSeed(
seedColor: primary,
brightness: isLightBg ? Brightness.light : Brightness.dark,
);

final scheme = seeded.copyWith(
// Core roles
primary: primary,
onPrimary: secondary,
secondary: primary,
onSecondary: secondary,
tertiary: primary,
onTertiary: secondary,
background: primary,
onBackground: secondary,
surface: primary,
onSurface: secondary,
// M3 surface families (many widgets use these, not just surface)
surfaceDim: primary,
surfaceBright: primary,
surfaceContainerLowest: primary,
surfaceContainerLow: primary,
surfaceContainer: primary,
surfaceContainerHigh: primary,
surfaceContainerHighest: primary,
);

// Base theme with global font + scheme
final base = ThemeData(
useMaterial3: true,
fontFamily: 'YourFont', // ensure declared in pubspec.yaml
colorScheme: scheme,
scaffoldBackgroundColor: primary,
);

return base.copyWith(
// Ensure widgets that ignore ColorScheme still match
canvasColor: primary,
cardColor: primary,
dialogBackgroundColor: primary,
dividerColor: secondary.withOpacity(0.12),
iconTheme: IconThemeData(color: secondary),

// Text defaults to secondary
textTheme: base.textTheme.apply(
  bodyColor: secondary,
  displayColor: secondary,
  decorationColor: secondary,
),
primaryTextTheme: base.primaryTextTheme.apply(
  bodyColor: secondary,
  displayColor: secondary,
  decorationColor: secondary,
),

// Transparent AppBar; secondary for foreground (title/icons)
appBarTheme: const AppBarTheme(
  backgroundColor: Colors.transparent,
  surfaceTintColor: Colors.transparent,
  elevation: 0,
  scrolledUnderElevation: 0,
  centerTitle: true,
).copyWith(foregroundColor: secondary),

// Inputs/buttons adopt secondary for text/icons
inputDecorationTheme: InputDecorationTheme(
  hintStyle: TextStyle(color: secondary.withOpacity(0.6)),
  labelStyle: TextStyle(color: secondary),
  iconColor: secondary,
),
elevatedButtonTheme: ElevatedButtonThemeData(
  style: ButtonStyle(foregroundColor: MaterialStatePropertyAll(secondary)),
),
textButtonTheme: TextButtonThemeData(
  style: ButtonStyle(foregroundColor: MaterialStatePropertyAll(secondary)),
),
outlinedButtonTheme: OutlinedButtonThemeData(
  style: ButtonStyle(
    foregroundColor: MaterialStatePropertyAll(secondary),
    side: MaterialStatePropertyAll(BorderSide(color: secondary)),
  ),
),

// Harden common backgrounds to the primary surface
bottomSheetTheme: BottomSheetThemeData(
  backgroundColor: primary,
  surfaceTintColor: Colors.transparent,
  modalBackgroundColor: primary,
),
// NOTE: Avoid version-specific type mismatch (DialogTheme vs DialogThemeData).
// dialog background is covered by `dialogBackgroundColor` above.

// Likewise, `cardColor` above handles cards across SDK versions.
drawerTheme: DrawerThemeData(
  backgroundColor: primary,
  surfaceTintColor: Colors.transparent,
),
popupMenuTheme: PopupMenuThemeData(
  color: primary,
  surfaceTintColor: Colors.transparent,
),


);
});