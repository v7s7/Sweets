/// Domain model for a menu item (“Sweet”).
/// Works with both static demo data (asset images) and live merchant data
/// (network image URLs from Firestore / external hosts).
class Sweet {
  final String id;
  final String name;

  /// Prefer `imageUrl` when present (merchant-provided network image).
  final String? imageUrl;

  /// Optional local fallback used by the demo (e.g. assets/sweets/donut.png).
  final String? imageAsset;

  /// Nutrition (all optional so the UI can render even if merchant omits some).
  final int? calories;      // kcal
  final double? protein;    // g
  final double? carbs;      // g
  final double? fat;        // g
  final double? sugar;      // g

  /// Price in the merchant’s currency. Format to 3dp in the UI.
  final double price;

  const Sweet({
    required this.id,
    required this.name,
    required this.price,
    this.imageUrl,
    this.imageAsset,
    this.calories,
    this.protein,
    this.carbs,
    this.fat,
    this.sugar,
  });

  /// Build from a Firestore/JSON map (defensive with number parsing).
  factory Sweet.fromMap(Map<String, dynamic> m, {required String id}) {
    double _toDouble(dynamic v) {
      if (v == null) return 0.0;
      if (v is num) return v.toDouble();
      final p = double.tryParse(v.toString());
      return p ?? 0.0;
    }

    int? _toIntNullable(dynamic v) {
      if (v == null) return null;
      if (v is num) return v.toInt();
      return int.tryParse(v.toString());
    }

    double? _toDoubleNullable(dynamic v) {
      if (v == null) return null;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString());
    }

    return Sweet(
      id: id,
      name: (m['name'] ?? '').toString(),
      price: _toDouble(m['price']),
      imageUrl: (m['imageUrl'] as String?)?.trim().isEmpty == true
          ? null
          : m['imageUrl'] as String?,
      imageAsset: m['imageAsset'] as String?,
      calories: _toIntNullable(m['calories']),
      protein: _toDoubleNullable(m['protein']),
      carbs: _toDoubleNullable(m['carbs']),
      fat: _toDoubleNullable(m['fat']),
      sugar: _toDoubleNullable(m['sugar']),
    );
  }

  Map<String, dynamic> toMap() => {
        'name': name,
        'price': price,
        'imageUrl': imageUrl,
        'imageAsset': imageAsset,
        'calories': calories,
        'protein': protein,
        'carbs': carbs,
        'fat': fat,
        'sugar': sugar,
      };

  Sweet copyWith({
    String? id,
    String? name,
    String? imageUrl,
    String? imageAsset,
    int? calories,
    double? protein,
    double? carbs,
    double? fat,
    double? sugar,
    double? price,
  }) {
    return Sweet(
      id: id ?? this.id,
      name: name ?? this.name,
      imageUrl: imageUrl ?? this.imageUrl,
      imageAsset: imageAsset ?? this.imageAsset,
      calories: calories ?? this.calories,
      protein: protein ?? this.protein,
      carbs: carbs ?? this.carbs,
      fat: fat ?? this.fat,
      sugar: sugar ?? this.sugar,
      price: price ?? this.price,
    );
  }
}
