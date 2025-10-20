// lib/app.dart — FINAL: switches to `home:` so UI updates when IDs apply
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart' show debugPrint;

import 'core/theme/app_theme.dart';
import 'core/branding/branding_providers.dart';
import 'core/branding/branding.dart';
import 'core/config/app_config.dart';
import 'core/config/slug_routing.dart';
import 'features/sweets/widgets/sweets_viewport.dart';

class SweetsApp extends ConsumerStatefulWidget {
  const SweetsApp({Key? key}) : super(key: key);
  @override
  ConsumerState<SweetsApp> createState() => _SweetsAppState();
}

class _SweetsAppState extends ConsumerState<SweetsApp> {
  String? _m;
  String? _b;

  // Manual subscription so we can listen from initState (Riverpod v3 rule)
  ProviderSubscription<AsyncValue<({String merchantId, String branchId})?>>? _slugSub;

  void _applyIdsAfterFrame(String m, String b) {
    if (_m == m && _b == b) return; // already applied
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(merchantIdProvider.notifier).setId(m);
      ref.read(branchIdProvider.notifier).setId(b);
      if (mounted) {
        setState(() {
          _m = m;
          _b = b;
        });
      }
      debugPrint('Applied IDs => m=$m b=$b');
    });
  }

  @override
  void initState() {
    super.initState();

    final cfg = ref.read(appConfigProvider);
    debugPrint('AppConfig => $cfg');

    // 1) Apply explicit IDs if provided (?m=&b=)
    if (cfg.merchantId != null && cfg.branchId != null) {
      _applyIdsAfterFrame(cfg.merchantId!, cfg.branchId!);
    }

    // 2) Otherwise resolve /slugs/<slug>
    _slugSub = ref.listenManual(
      slugLookupProvider,
      (prev, next) {
        next.when(
          data: (mb) {
            if (mb != null) {
              _applyIdsAfterFrame(mb.merchantId, mb.branchId);
            } else {
              final s = cfg.slug ?? '';
              debugPrint('Slug "$s" not found or invalid.');
              if (mounted && _m == null && _b == null) setState(() {});
            }
          },
          loading: () {},
          error: (e, st) {
            debugPrint('Slug lookup error: $e');
            if (mounted) setState(() {});
          },
        );
      },
    );

    // Kick the FutureProvider right away
    ref.read(slugLookupProvider);
  }

  @override
  void dispose() {
    _slugSub?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeDataProvider);
    final branding = ref.watch(brandingProvider).maybeWhen(
      data: (b) => b,
      orElse: () => const Branding(
        title: 'App',
        headerText: '',
        primaryHex: '#E91E63',
        secondaryHex: '#FFB300',
      ),
    );

    return MaterialApp(
      title: branding.title,
      debugShowCheckedModeBanner: false,
      theme: theme,

      // Force Flutter to start at "/" even if URL is /s/<slug>
      // Using `home:` ensures rebuild when _m/_b change.
      initialRoute: '/',

      home: (_m == null || _b == null)
          ? _WaitingOrError()
          : Scaffold(
              backgroundColor: const Color(0xFFF9EFF3),
              appBar: AppBar(
                elevation: 0,
                scrolledUnderElevation: 0,
                backgroundColor: Colors.transparent,
                centerTitle: true,
                title: Text(branding.title, style: AppTheme.scriptTitle),
              ),
              body: const _GradientShell(child: SweetsViewport()),
            ),
    );
  }
}

class _WaitingOrError extends ConsumerWidget {
  const _WaitingOrError({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cfg = ref.watch(appConfigProvider);
    final slug = cfg.slug;
    final async = ref.watch(slugLookupProvider);

    String baseHint;
    if (cfg.merchantId != null && cfg.branchId != null) {
      baseHint = 'Applying IDs…';
    } else if (slug != null && slug.isNotEmpty) {
      baseHint = 'Resolving slug "$slug"…';
    } else {
      baseHint = 'Open with ?m=<merchantId>&b=<branchId> or /s/<slug>';
    }

    final text = async.when(
      data: (mb) => (mb == null && (slug ?? '').isNotEmpty)
          ? 'Unknown or unregistered slug "$slug".'
          : baseHint,
      loading: () => baseHint,
      error: (e, st) => 'Slug lookup failed: $e',
    );

    return Scaffold(body: Center(child: Text(text)));
  }
}

class _GradientShell extends StatelessWidget {
  final Widget child;
  const _GradientShell({required this.child, Key? key}) : super(key: key);
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFF9EFF3), Color(0xFFFFF5F8)],
        ),
      ),
      child: SafeArea(top: false, child: child),
    );
  }
}
