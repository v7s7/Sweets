// lib/core/branding/branding.dart
import 'dart:ui' as ui; // use ui.Color directly

class Branding {
  final String title;
  final String headerText;
  final String primaryHex;
  final String secondaryHex;
  final String? logoUrl;

  const Branding({
    required this.title,
    required this.headerText,
    required this.primaryHex,
    required this.secondaryHex,
    this.logoUrl,
  });

  factory Branding.fromMap(Map<String, dynamic> m) {
    String? _s(Object? v) {
      final s = (v as String?)?.trim();
      return (s == null || s.isEmpty) ? null : s;
    }

    return Branding(
      title: (m['title'] ?? 'App').toString(),
      headerText: (m['headerText'] ?? '').toString(),
      primaryHex: (m['primaryHex'] ?? '#FFFFFF').toString(),
      secondaryHex: (m['secondaryHex'] ?? '#000000').toString(),
      logoUrl: _s(m['logoUrl']),
    );
  }

  Map<String, dynamic> toMap() => {
        'title': title,
        'headerText': headerText,
        'primaryHex': primaryHex,
        'secondaryHex': secondaryHex,
        'logoUrl': logoUrl,
      };

  Branding copyWith({
    String? title,
    String? headerText,
    String? primaryHex,
    String? secondaryHex,
    String? logoUrl,
  }) {
    return Branding(
      title: title ?? this.title,
      headerText: headerText ?? this.headerText,
      primaryHex: primaryHex ?? this.primaryHex,
      secondaryHex: secondaryHex ?? this.secondaryHex,
      logoUrl: logoUrl ?? this.logoUrl,
    );
  }

  @override
  String toString() =>
      'Branding(title: $title, headerText: $headerText, primaryHex: $primaryHex, secondaryHex: $secondaryHex, logoUrl: $logoUrl)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Branding &&
          runtimeType == other.runtimeType &&
          title == other.title &&
          headerText == other.headerText &&
          primaryHex == other.primaryHex &&
          secondaryHex == other.secondaryHex &&
          logoUrl == other.logoUrl;

  @override
  int get hashCode =>
      Object.hash(title, headerText, primaryHex, secondaryHex, logoUrl);
}

extension HexColor on String {
  /// Parses "#RRGGBB" or "RRGGBB" (adds FF alpha). Returns black on failure.
  ui.Color toColor() {
    var c = replaceAll('#', '').trim();
    if (c.length == 6) c = 'FF$c'; // add full opacity
    final value = int.tryParse(c, radix: 16) ?? 0xFF000000;
    return ui.Color(value);
  }
}
