import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';

import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_app_check/firebase_app_check.dart';

import 'firebase_options.dart';

/// Cloud Functions region (must match your deployed region)
const String kFunctionsRegion =
    String.fromEnvironment('FUNCTIONS_REGION', defaultValue: 'me-central2');

/// Toggle Firebase emulators (debug builds only)
const bool kUseEmulators =
    bool.fromEnvironment('USE_EMULATORS', defaultValue: false);

const String _emuHost = '127.0.0.1';

/// Toggle Firebase App Check (off by default)
const bool kUseAppCheck =
    bool.fromEnvironment('USE_APP_CHECK', defaultValue: false);

/// If you enable App Check on the web, choose one provider and set its site key.
const String _appCheckProvider =
    String.fromEnvironment('APP_CHECK_PROVIDER', defaultValue: 'v3'); // 'v3' | 'enterprise'
const String _siteKey =
    String.fromEnvironment('RECAPTCHA_SITE_KEY', defaultValue: '');

bool _appCheckActivated = false;

Future<void> _configureEmulatorsIfNeeded() async {
  // Only wire emulators when explicitly enabled in debug builds
  if (!kDebugMode || !kUseEmulators) return;

  try {
    // Auth emulator
    await FirebaseAuth.instance.useAuthEmulator(_emuHost, 9099);
  } catch (_) {
    // already set
  }

  try {
    // Firestore emulator
    FirebaseFirestore.instance.useFirestoreEmulator(_emuHost, 8081);
    FirebaseFirestore.instance.settings = const Settings(
      sslEnabled: false, // required for web + emulator
      persistenceEnabled: false,
    );
  } catch (_) {}

  try {
    // Functions emulator (default + explicit region handle)
    FirebaseFunctions.instance.useFunctionsEmulator(_emuHost, 5001);
    FirebaseFunctions.instanceFor(region: kFunctionsRegion)
        .useFunctionsEmulator(_emuHost, 5001);
  } catch (_) {}
}

Future<void> _activateAppCheck() async {
  if (!kUseAppCheck || _appCheckActivated) return;
  _appCheckActivated = true;

  if (kIsWeb) {
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
    } catch (e) {
      final msg = e.toString();
      if (!msg.contains('app-check/already-initialized')) rethrow;
    }
  } else {
    await FirebaseAppCheck.instance.activate(
      androidProvider: AndroidProvider.playIntegrity,
      appleProvider: AppleProvider.deviceCheck,
    );
  }

  await FirebaseAppCheck.instance.setTokenAutoRefreshEnabled(true);
}

Future<void> _ensureSignedIn() async {
  // Anonymous auth is enough for guests placing orders.
  try {
    if (FirebaseAuth.instance.currentUser == null) {
      await FirebaseAuth.instance.signInAnonymously();
    }
  } catch (_) {
    // swallow – UI can still render and retry later
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Pretty paths (no hash) so /s/<slug> stays in the address bar.
  setUrlStrategy(PathUrlStrategy());

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // App Check (no-op unless enabled via env flags + keys).
  await _activateAppCheck();

  // Point SDKs to local emulators when enabled (before any network calls).
  await _configureEmulatorsIfNeeded();

  // Ensure we have a user for security rules that require auth.
  await _ensureSignedIn();

  runApp(const ProviderScope(child: SweetsApp()));
}
