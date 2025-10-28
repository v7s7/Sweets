// lib/merchant/main_merchant.dart — FIXED: Unified Firebase init (web + mobile)
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_web_plugins/url_strategy.dart';

// Firebase
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../firebase_options.dart';

import '../core/config/app_config.dart';
import '../core/config/slug_routing.dart';
import '../core/branding/branding_providers.dart';
import 'screens/login_screen.dart';
import 'screens/products_screen.dart';

Future<void> main() async {
WidgetsFlutterBinding.ensureInitialized();

// Clean URLs on the web (no '#')
if (kIsWeb) {
setUrlStrategy(PathUrlStrategy());
}

// Initialize Firebase on all platforms with generated options.
await Firebase.initializeApp(
options: DefaultFirebaseOptions.currentPlatform,
);

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
WidgetsBinding.instance.addPostFrameCallback((_) => _tryApplyIds());
}

void _tryApplyIds() {
final ids = ref.read(effectiveIdsProvider);
if (ids != null && !_idsApplied) {
// Apply merchant/branch to global providers once
// (URL: ?m=<merchantId>&b=<branchId> or /s/<slug>)
ref.read(merchantIdProvider.notifier).setId(ids.merchantId);
ref.read(branchIdProvider.notifier).setId(ids.branchId);
setState(() => _idsApplied = true);
}
}

@override
Widget build(BuildContext context) {
// Re-apply when URL-derived IDs resolve
ref.listen<MerchantBranch?>(effectiveIdsProvider, (prev, next) {
if (next != null && !_idsApplied) _tryApplyIds();
});

return MaterialApp(
  debugShowCheckedModeBanner: false,
  title: 'Sweets – Merchant Console',
  theme: ThemeData(colorSchemeSeed: Colors.pink, useMaterial3: true),
  initialRoute: '/',
  onGenerateRoute: (settings) {
    return MaterialPageRoute(
      settings: settings,
      builder: (_) {
        return StreamBuilder<User?>(
          stream: FirebaseAuth.instance.authStateChanges(),
          builder: (context, snap) {
            final user = snap.data;

            // Require real sign-in for admin (don’t auto anon-sign-in here)
            if (user == null) return const LoginScreen();

            // Wait until merchant/branch IDs are known
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
        );
      },
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