import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Feature flags you can toggle via --dart-define (all optional).
class FeatureFlags {
  final bool healthyMode;
  final bool requireGeofence;

  const FeatureFlags({
    this.healthyMode = false,
    this.requireGeofence = false,
  });

  static bool _toBool(String s) =>
      s.toLowerCase() == 'true' || s == '1' || s.toLowerCase() == 'yes';

  factory FeatureFlags.fromEnv() {
    const ffHealthy = String.fromEnvironment('FF_HEALTHY', defaultValue: 'false');
    const ffGeofence = String.fromEnvironment('FF_GEOFENCE', defaultValue: 'false');
    return FeatureFlags(
      healthyMode: _toBool(ffHealthy),
      requireGeofence: _toBool(ffGeofence),
    );
  }

  @override
  String toString() =>
      'FeatureFlags(healthyMode=$healthyMode, requireGeofence=$requireGeofence)';
}

/// Parsed QR/table context. These will be verified server-side later.
class QrContext {
  final String? table; // e.g. A12
  final int? exp;      // epoch seconds
  final String? sig;   // HMAC signature

  const QrContext({this.table, this.exp, this.sig});

  factory QrContext.fromUri(Uri uri) {
    final qp = uri.queryParameters;
    int? _toInt(String? s) => s == null ? null : int.tryParse(s);
    // Only use query params now; (m,b) also arrive here for convenience.
    return QrContext(
      table: qp['t'],
      exp: _toInt(qp['exp']),
      sig: qp['sig'],
    );
  }

  @override
  String toString() => 'QrContext(table=$table, exp=$exp, sig=${sig != null ? "<redacted>" : null})';
}

/// Global app config: merchant/branch identifiers, API base, flags, and QR context.
/// This only *parses* config; no network calls and no behavior change yet.
class AppConfig {
  final String merchantId;
  final String branchId;
  final String apiBase;
  final FeatureFlags flags;
  final QrContext qr;

  const AppConfig({
    required this.merchantId,
    required this.branchId,
    required this.apiBase,
    required this.flags,
    required this.qr,
  });

  /// Load config by combining:
  /// - --dart-define MERCHANT_ID / BRANCH_ID / API_BASE (preferred)
  /// - Web query params ?m=&b=&t=&exp=&sig= (useful during dev)
  factory AppConfig.load() {
    const envM = String.fromEnvironment('MERCHANT_ID', defaultValue: '');
    const envB = String.fromEnvironment('BRANCH_ID', defaultValue: '');
    const envApi = String.fromEnvironment('API_BASE', defaultValue: '');

    // Defaults keep the app running without server wiring.
    String m = envM.isEmpty ? 'demo_merchant' : envM;
    String b = envB.isEmpty ? 'demo_branch' : envB;
    String api = envApi.isEmpty ? '/api' : envApi;

    var qr = const QrContext();

    if (kIsWeb) {
      final uri = Uri.base;
      final qp = uri.queryParameters;
      // Allow overriding via URL for quick testing: ?m=<id>&b=<id>
      m = qp['m'] ?? m;
      b = qp['b'] ?? b;
      qr = QrContext.fromUri(uri);
    }

    return AppConfig(
      merchantId: m,
      branchId: b,
      apiBase: api,
      flags: FeatureFlags.fromEnv(),
      qr: qr,
    );
  }

  @override
  String toString() =>
      'AppConfig(merchantId=$merchantId, branchId=$branchId, apiBase=$apiBase, flags=$flags, qr=$qr)';
}

/// Riverpod providers you can read anywhere.
final appConfigProvider = Provider<AppConfig>((ref) => AppConfig.load());
final qrContextProvider = Provider<QrContext>((ref) => ref.watch(appConfigProvider).qr);
