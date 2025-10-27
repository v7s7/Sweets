// lib/app.dart - CUSTOMER APP (URL PRESERVED)
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart' show debugPrint;

import 'core/theme/app_theme.dart';
import 'core/branding/branding_providers.dart';
import 'core/branding/branding.dart';
import 'core/config/app_config.dart';
import 'core/config/slug_routing.dart';
import 'features/sweets/widgets/sweets_viewport.dart';
import 'features/cart/widgets/cart_sheet.dart';

class SweetsApp extends ConsumerStatefulWidget {
  const SweetsApp({Key? key}) : super(key: key);
  @override
  ConsumerState<SweetsApp> createState() => _SweetsAppState();
}

class _SweetsAppState extends ConsumerState<SweetsApp> {
  bool _idsApplied = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _tryApplyIds());
  }

  void _tryApplyIds() {
    final ids = ref.read(effectiveIdsProvider);
    if (ids != null && !_idsApplied) {
      debugPrint('🔵 Customer App: Applying IDs m=${ids.merchantId} b=${ids.branchId}');
      ref.read(merchantIdProvider.notifier).setId(ids.merchantId);
      ref.read(branchIdProvider.notifier).setId(ids.branchId);
      setState(() => _idsApplied = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    // react to ID changes
    ref.listen<MerchantBranch?>(effectiveIdsProvider, (prev, next) {
      if (next != null && !_idsApplied) _tryApplyIds();
    });

    final baseTheme = ref.watch(themeDataProvider);

    // branding (for title + colors)
    final branding = ref.watch(brandingProvider).maybeWhen(
      data: (b) => b,
      orElse: () => const Branding(
        title: 'App',
        headerText: '',
        primaryHex: '#FFFFFF',
        secondaryHex: '#000000',
      ),
    );
    final primary = _hexToColor(branding.primaryHex);     // BG color ONLY
    final secondary = _hexToColor(branding.secondaryHex); // TEXT color ONLY

    // status/nav icon color based on BG luminance
    final overlay = (primary.computeLuminance() > 0.5)
        ? SystemUiOverlayStyle.dark
        : SystemUiOverlayStyle.light;
    SystemChrome.setSystemUIOverlayStyle(overlay.copyWith(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
    ));

    // global theme: solid background = primary, fonts = secondary, bar = transparent
    final theme = baseTheme.copyWith(
      scaffoldBackgroundColor: primary,
      // Global font + text color
      textTheme: baseTheme.textTheme.apply(
        fontFamily: 'YourFont', // ensure added in pubspec
        bodyColor: secondary,
        displayColor: secondary,
        decorationColor: secondary,
      ),
      primaryTextTheme: baseTheme.primaryTextTheme.apply(
        fontFamily: 'YourFont',
        bodyColor: secondary,
        displayColor: secondary,
        decorationColor: secondary,
      ),
      appBarTheme: baseTheme.appBarTheme.copyWith(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        foregroundColor: secondary,        // AppBar text/icons use secondary
        systemOverlayStyle: overlay,
      ),
    );

    return MaterialApp(
      title: branding.title,
      debugShowCheckedModeBanner: false,
      theme: theme,
      onGenerateRoute: (settings) => MaterialPageRoute(
        settings: settings,
        builder: (_) => _idsApplied ? const _CustomerScaffold() : const _WaitingOrError(),
      ),
    );
  }
}

// Stateful so we can hold a GlobalKey for the AppBar cart button
class _CustomerScaffold extends ConsumerStatefulWidget {
  const _CustomerScaffold({Key? key}) : super(key: key);
  @override
  ConsumerState<_CustomerScaffold> createState() => _CustomerScaffoldState();
}

class _CustomerScaffoldState extends ConsumerState<_CustomerScaffold> {
  // Shared with SweetsViewport for fly-to-cart target
  final GlobalKey _cartActionKey = GlobalKey();

  void _openCartSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const CartSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final b = ref.watch(brandingProvider).maybeWhen(
      data: (x) => x,
      orElse: () => const Branding(
        title: 'App',
        headerText: '',
        primaryHex: '#FFFFFF',
        secondaryHex: '#000000',
      ),
    );

    final onSurface = Theme.of(context).colorScheme.onSurface;

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface, // ensure primaryHex fills background
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text(
          b.title,
          style: AppTheme.scriptTitle.copyWith(color: onSurface),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: OutlinedButton(
              key: _cartActionKey, // key shared with SweetsViewport
              style: OutlinedButton.styleFrom(
                shape: const CircleBorder(),
                side: BorderSide(color: onSurface),
                minimumSize: const Size(40, 40),
                padding: EdgeInsets.zero,
                foregroundColor: onSurface, // icon color
              ),
              onPressed: _openCartSheet,
              child: const Icon(Icons.shopping_bag_outlined, size: 18),
            ),
          ),
        ],
      ),
      body: SweetsViewport(cartBadgeKey: _cartActionKey),
    );
  }
}

class _WaitingOrError extends ConsumerWidget {
  const _WaitingOrError({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cfg = ref.watch(appConfigProvider);
    final async = ref.watch(slugLookupProvider);

    String message;
    if (cfg.merchantId != null && cfg.branchId != null) {
      message = 'Loading menu...';
    } else if (cfg.slug != null && cfg.slug!.isNotEmpty) {
      message = async.when(
        data: (mb) => mb == null
            ? '❌ Slug "${cfg.slug}" not found.\n\nAsk the merchant for the correct link.'
            : 'Loading menu...',
        loading: () => 'Resolving link...',
        error: (e, _) => '❌ Error: $e',
      );
    } else {
      message = '⚠️ No merchant specified.\n\nOpen with:\n'
          '• /s/<slug>\n'
          '• ?m=<merchantId>&b=<branchId>';
    }

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface, // ensure primaryHex fills background
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (async.isLoading)
                const CircularProgressIndicator()
              else
                const Icon(Icons.store_outlined, size: 64, color: Colors.black26),
              const SizedBox(height: 24),
              Text(message, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16)),
            ],
          ),
        ),
      ),
    );
  }
}

Color _hexToColor(String hex) {
  final s = hex.replaceAll('#', '').trim();
  final v = int.parse(s.length == 6 ? 'FF$s' : s, radix: 16);
  return Color(v);
}
