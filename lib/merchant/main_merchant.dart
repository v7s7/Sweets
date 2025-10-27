// lib/merchant/main_merchant.dart (COMPLETE FIX)
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_plugins/url_strategy.dart';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_app_check/firebase_app_check.dart';

import '../firebase_options.dart';
import '../core/config/app_config.dart';
import '../core/config/slug_routing.dart';
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
  bool _idsApplied = false;

  @override
  void initState() {
    super.initState();
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _tryApplyIds();
    });
  }

  void _tryApplyIds() {
    final ids = ref.read(effectiveIdsProvider);
    
    if (ids != null && !_idsApplied) {
      print('🟢 Merchant App: Applying IDs m=${ids.merchantId} b=${ids.branchId}');
      
      ref.read(merchantIdProvider.notifier).setId(ids.merchantId);
      ref.read(branchIdProvider.notifier).setId(ids.branchId);
      
      setState(() {
        _idsApplied = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Listen for ID changes
    ref.listen<MerchantBranch?>(effectiveIdsProvider, (prev, next) {
      if (next != null && !_idsApplied) {
        _tryApplyIds();
      }
    });

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Sweets – Merchant Console',
      theme: ThemeData(colorSchemeSeed: Colors.pink, useMaterial3: true),
      initialRoute: '/',
      onGenerateRoute: (settings) {
        return MaterialPageRoute(
          builder: (_) => StreamBuilder<User?>(
            stream: FirebaseAuth.instance.authStateChanges(),
            builder: (context, snap) {
              final user = snap.data;
              if (user == null) return const LoginScreen();

              if (!_idsApplied) {
                final cfg = ref.watch(appConfigProvider);
                final hint = (cfg.merchantId != null && cfg.branchId != null)
                    ? 'Loading...'
                    : (cfg.slug != null
                        ? 'Resolving "${cfg.slug}"...'
                        : '⚠️ Open with:\n• /s/<slug>\n• ?m=<merchantId>&b=<branchId>');
                return _NeedIdsPage(hint: hint);
              }

              final m = ref.read(merchantIdProvider);
              final b = ref.read(branchIdProvider);
              
              return ProductsScreen(merchantId: m, branchId: b);
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
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 24),
              Text(hint, textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }
}