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

  factory Branding.fromMap(Map<String, dynamic> m) => Branding(
        title: m['title'] ?? 'App',
        headerText: m['headerText'] ?? '',
        primaryHex: m['primaryHex'] ?? '#FFFFFF',
        secondaryHex: m['secondaryHex'] ?? '#000000',
        logoUrl: (m['logoUrl'] as String?)?.trim(),
      );

  Map<String, dynamic> toMap() => {
        'title': title,
        'headerText': headerText,
        'primaryHex': primaryHex,
        'secondaryHex': secondaryHex,
        'logoUrl': logoUrl,
      };
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
