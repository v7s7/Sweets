import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';

import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'firebase_options.dart';

// Match your Cloud Functions region
const String kFunctionsRegion =
    String.fromEnvironment('FUNCTIONS_REGION', defaultValue: 'me-central2');

// Toggle emulators with: --dart-define=USE_EMULATORS=true
const bool kUseEmulators =
    bool.fromEnvironment('USE_EMULATORS', defaultValue: false);

const String _emuHost = '127.0.0.1';

// App Check reCAPTCHA v3 site key (from Firebase Console → App Check → your Web app)
const String _webRecaptchaV3SiteKey = '6LcuU-wrAAAAADummtUty7ZsCjvC_WHR9FxG_1YU';

Future<void> _configureEmulatorsIfNeeded() async {
  if (!kDebugMode || !kUseEmulators) return;

  // ----- Auth emulator -----
  try {
    await FirebaseAuth.instance.useAuthEmulator(_emuHost, 9099);
  } catch (_) {}

  // ----- Firestore emulator (8081) -----
  try {
    FirebaseFirestore.instance.useFirestoreEmulator(_emuHost, 8081);
    FirebaseFirestore.instance.settings = const Settings(
      sslEnabled: false, // required for Flutter web with emulator
      persistenceEnabled: false,
    );
  } catch (_) {}

  // ----- Functions emulator (5001) -----
  try {
    FirebaseFunctions.instance.useFunctionsEmulator(_emuHost, 5001);
    FirebaseFunctions.instanceFor(region: kFunctionsRegion)
        .useFunctionsEmulator(_emuHost, 5001);
  } catch (_) {}
}

Future<void> _activateAppCheck() async {
  // Activate App Check for web (and mobile if you add those flavors later)
  if (kIsWeb) {
    await FirebaseAppCheck.instance.activate(
      webProvider: ReCaptchaV3Provider(_webRecaptchaV3SiteKey),
    );
  } else {
    await FirebaseAppCheck.instance.activate(
      androidProvider: AndroidProvider.playIntegrity,
      appleProvider: AppleProvider.deviceCheck,
    );
  }
  // Enable automatic refresh (newer API)
  await FirebaseAppCheck.instance.setTokenAutoRefreshEnabled(true);
}

Future<void> _ensureSignedIn() async {
  try {
    if (FirebaseAuth.instance.currentUser == null) {
      await FirebaseAuth.instance.signInAnonymously();
    }
  } catch (_) {}
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // App Check must be activated before calling protected resources.
  await _activateAppCheck();

  // Optional: use local emulators when toggled
  await _configureEmulatorsIfNeeded();

  // Your flow expects an anonymous user
  await _ensureSignedIn();

  runApp(const ProviderScope(child: SweetsApp()));
}
