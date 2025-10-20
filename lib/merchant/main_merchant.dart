import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_plugins/url_strategy.dart';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_app_check/firebase_app_check.dart';

import '../firebase_options.dart';
import '../core/config/app_config.dart';
import '../core/config/slug_routing.dart'; // slugLookupProvider/effectiveIds
import '../core/branding/branding_providers.dart';
import 'screens/login_screen.dart';
import 'screens/products_screen.dart';

const bool kUseAppCheck =
    bool.fromEnvironment('USE_APP_CHECK', defaultValue: false);
const String _appCheckProvider =
    String.fromEnvironment('APP_CHECK_PROVIDER', defaultValue: 'v3');
const String _siteKey =
    String.fromEnvironment('RECAPTCHA_SITE_KEY', defaultValue: '');

bool _appCheckActivated = false;
Future<void> _activateAppCheck() async {
  if (_appCheckActivated || !kUseAppCheck) return;
  _appCheckActivated = true;
  try {
    if (_appCheckProvider.toLowerCase() == 'enterprise') {
      await FirebaseAppCheck.instance.activate(
        webProvider: ReCaptchaEnterpriseProvider(_siteKey),
      );
    } else {
      await FirebaseAppCheck.instance.activate(
        webProvider: ReCaptchaV3Provider(_siteKey),
      );
    }
    await FirebaseAppCheck.instance.setTokenAutoRefreshEnabled(true);
  } catch (e) {
    final msg = e.toString();
    if (!msg.contains('app-check/already-initialized')) rethrow;
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  setUrlStrategy(PathUrlStrategy());
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await _activateAppCheck();
  runApp(const ProviderScope(child: MerchantApp()));
}

class MerchantApp extends ConsumerStatefulWidget {
  const MerchantApp({super.key});
  @override
  ConsumerState<MerchantApp> createState() => _MerchantAppState();
}

class _MerchantAppState extends ConsumerState<MerchantApp> {
  String? _m;
  String? _b;

  void _applyIdsAfterFrame(String m, String b) {
    if (_m == m && _b == b) return; // already applied
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(merchantIdProvider.notifier).setId(m);
      ref.read(branchIdProvider.notifier).setId(b);
      if (mounted) setState(() {
        _m = m;
        _b = b;
      });
    });
  }

  @override
  void initState() {
    super.initState();

    // 1) Try explicit IDs from URL (?m=&b=)
    final cfg = ref.read(appConfigProvider);
    if (cfg.merchantId != null && cfg.branchId != null) {
      _applyIdsAfterFrame(cfg.merchantId!, cfg.branchId!);
    }

    // ❌ Do NOT call ref.listen here (Riverpod v3 forbids it in initState)
  }

  @override
  Widget build(BuildContext context) {
    // ✅ Allowed in Riverpod v3: listen during build
    ref.listen<AsyncValue<({String merchantId, String branchId})?>>(
      slugLookupProvider,
      (prev, next) {
        next.whenData((mb) {
          if (mb != null) _applyIdsAfterFrame(mb.merchantId, mb.branchId);
        });
      },
    );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Sweets – Merchant Console',
      theme: ThemeData(colorSchemeSeed: Colors.pink, useMaterial3: true),

      // Force start at "/" even if URL is /s/<slug>; we still parse slug via AppConfig.
      initialRoute: '/',

      onGenerateRoute: (settings) {
        return MaterialPageRoute(
          builder: (_) => StreamBuilder<User?>(
            stream: FirebaseAuth.instance.authStateChanges(),
            builder: (context, snap) {
              final user = snap.data;
              if (user == null) return const LoginScreen();

              if (_m == null || _b == null) {
                // Waiting for ?m=&b= or slug resolution
                final cfg = ref.watch(appConfigProvider);
                final hint = (cfg.merchantId != null && cfg.branchId != null)
                    ? 'Applying IDs…'
                    : (cfg.slug != null
                        ? 'Resolving slug "${cfg.slug}"…'
                        : 'Open with ?m=<merchantId>&b=<branchId> or /s/<slug>');
                return _NeedIdsPage(hint: hint);
              }

              return ProductsScreen(merchantId: _m!, branchId: _b!);
            },
          ),
          settings: settings,
        );
      },
    );
  }
}

class _NeedIdsPage extends StatelessWidget {
  final String hint;
  const _NeedIdsPage({required this.hint});
  @override
  Widget build(BuildContext context) {
    return Scaffold(body: Center(child: Text(hint)));
  }
}
