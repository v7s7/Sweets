// lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';

import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter_web_plugins/url_strategy.dart';

// Firebase
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_options.dart';

/// Enable Firebase emulators with: --dart-define=USE_EMULATORS=true
const bool kUseEmulators =
    bool.fromEnvironment('USE_EMULATORS', defaultValue: false);

const String _emuHost = '127.0.0.1';

Future<void> _configureEmulatorsIfNeeded() async {
  if (!kDebugMode || !kUseEmulators) return;

  // Auth emulator
  try {
    await FirebaseAuth.instance.useAuthEmulator(_emuHost, 9099);
  } catch (_) {}

  // Firestore emulator
  try {
    FirebaseFirestore.instance.useFirestoreEmulator(_emuHost, 8081);
    FirebaseFirestore.instance.settings = const Settings(
      sslEnabled: false, // required for web + emulator
      persistenceEnabled: false,
    );
  } catch (_) {}
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

  if (kIsWeb) {
    setUrlStrategy(PathUrlStrategy());
  }

  // Initialize Firebase on all platforms with generated options.
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  await _configureEmulatorsIfNeeded();
  await _ensureSignedIn();

  runApp(const ProviderScope(child: SweetsApp()));
}
