// lib/core/config/app_config.dart
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart' as rp;

/// Simple feature flags you can toggle via URL, e.g. ?hm=1&geo=0
class FeatureFlags {
  final bool healthyMode;
  final bool requireGeofence;
  const FeatureFlags({
    this.healthyMode = false,
    this.requireGeofence = false,
  });

  @override
  String toString() =>
      'FeatureFlags(healthyMode=$healthyMode, requireGeofence=$requireGeofence)';
}

/// Optional QR context carried in the URL (not required for now).
class QrContext {
  final String? table;
  final int? exp;
  final String? sig;
  const QrContext({this.table, this.exp, this.sig});

  @override
  String toString() => 'QrContext(table=$table, exp=$exp, sig=$sig)';
}

/// App-wide config parsed from the URL (on web) or defaults (elsewhere).
///
/// Supports either:
///   • Query IDs:           ?m=<merchantId>&b=<branchId>
///   • Pretty slug routes:  /s/<slug>   or   #/s/<slug>
///   • Slug query alias:    ?s=<slug>   or   ?slug=<slug>
///
/// How to use a slug:
///   1) Put a human-friendly slug in the URL (e.g. https://your.app/#/s/donuts-budaiya)
///   2) Store a mapping doc in Firestore: /slugs/{slug} => { merchantId, branchId }
///   3) Resolve that doc at startup and wire the IDs into your providers.
class AppConfig {
  /// Explicit IDs from URL (highest priority if present)
  final String? merchantId; // ?m= | ?merchant | ?merchantId
  final String? branchId;   // ?b= | ?branch  | ?branchId

  /// Human-friendly slug (e.g. "my-cafe"); resolve to IDs via Firestore /slugs/{slug}
  final String? slug;       // /s/<slug> | ?s= | ?slug=

  /// Optional API base path
  final String apiBase;     // ?api= (optional; default /api)

  /// Feature flags & QR context
  final FeatureFlags flags;
  final QrContext qr;

  const AppConfig({
    required this.merchantId,
    required this.branchId,
    this.slug,
    this.apiBase = '/api',
    this.flags = const FeatureFlags(),
    this.qr = const QrContext(),
  });

  /// Convenience: true if both IDs are present.
  bool get hasIds => merchantId != null && branchId != null;

  /// Build from the current URL. Accepted aliases:
  /// m|merchant|merchantId, b|branch|branchId, t|table, s|slug
  ///
  /// Also parses the hash part on web (e.g. `#/s/<slug>?hm=1`)
  /// so you can share links like `https://your.app/#/s/donuts-budaiya`.
  factory AppConfig.fromUrl(Uri uri) {
    // Real query (location.search)
    final qp = uri.queryParameters;

    // Hash-based router support on web: parse the fragment as a mini-URI
    final fragUri = _parseFragmentAsUri(uri.fragment);
    final fqp = fragUri?.queryParameters ?? const <String, String>{};

    String? pick(List<String> keys) {
      for (final k in keys) {
        final v = qp[k] ?? fqp[k];
        if (v != null && v.isNotEmpty) return v;
      }
      return null;
    }

    bool asBool(String? v) {
      if (v == null) return false;
      final s = v.toLowerCase();
      return s == '1' || s == 'true' || s == 'yes' || s == 'y';
    }

    // Explicit IDs
    final m = pick(['m', 'merchant', 'merchantId']);
    final b = pick(['b', 'branch', 'branchId']);

    // API base
    final api = pick(['api']) ?? '/api';

    // QR context
    final table = pick(['t', 'table']);
    final exp = int.tryParse(pick(['exp']) ?? '');
    final sig = pick(['sig']);

    // Flags
    final hm = asBool(pick(['hm', 'healthy']));
    final geo = asBool(pick(['geo', 'requireGeofence']));

    // Slug from query OR from path(/fragment) /s/<slug>
    final slugFromQuery = pick(['s', 'slug']);
    final slugFromFragPath =
        _extractSlugFromPath(fragUri?.pathSegments ?? const []);
    final slugFromMainPath = _extractSlugFromPath(uri.pathSegments);
    final slug = _firstNonEmpty([slugFromQuery, slugFromFragPath, slugFromMainPath]);

    return AppConfig(
      merchantId: m?.trim(),
      branchId: b?.trim(),
      slug: slug?.trim(),
      apiBase: api,
      flags: FeatureFlags(healthyMode: hm, requireGeofence: geo),
      qr: QrContext(table: table, exp: exp, sig: sig),
    );
  }

  @override
  String toString() =>
      'AppConfig(merchantId=$merchantId, branchId=$branchId, slug=$slug, '
      'apiBase=$apiBase, flags=$flags, qr=$qr)';

  /* ------------------------------- helpers -------------------------------- */

  static Uri? _parseFragmentAsUri(String fragment) {
    if (!kIsWeb) return null;
    if (fragment.isEmpty) return null;
    // Normalize: '#/s/x?y=1' -> '/s/x?y=1'
    final text = fragment.startsWith('/') ? fragment : '/$fragment';
    try {
      return Uri.parse(text);
    } catch (_) {
      return null;
    }
  }

  /// Accepts paths like:
  ///   /s/<slug>
  ///   /app/s/<slug>
  ///   /<slug>           (fallback: single segment)
  static String? _extractSlugFromPath(List<String> segs) {
    if (segs.isEmpty) return null;
    // Prefer '/s/<slug>' shape anywhere in the path
    final i = segs.indexOf('s');
    if (i >= 0 && i + 1 < segs.length) {
      final candidate = segs[i + 1].trim();
      return candidate.isEmpty ? null : candidate;
    }
    // Fallback: single-segment path -> treat as slug
    if (segs.length == 1) {
      final solo = segs.first.trim();
      if (solo.isNotEmpty) return solo;
    }
    return null;
  }

  static String? _firstNonEmpty(List<String?> vals) {
    for (final v in vals) {
      if (v != null && v.trim().isNotEmpty) return v.trim();
    }
    return null;
  }
}

/// Riverpod provider exposed app-wide.
/// On web, reads from the current URL (?m=&b=&... or #/s/<slug>); elsewhere returns defaults.
final appConfigProvider = rp.Provider<AppConfig>((ref) {
  final uri = kIsWeb ? Uri.base : Uri();
  return AppConfig.fromUrl(uri);
});
