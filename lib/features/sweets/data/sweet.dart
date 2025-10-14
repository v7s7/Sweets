class Sweet {
  final String id;
  final String name;
  final String imageAsset; // e.g., assets/sweets/donut.png (transparent PNG)
  final int calories;      // kcal
  final double protein;    // g
  final double carbs;      // g
  final double fat;        // g
  final double price;      // currency-agnostic

  const Sweet({
    required this.id,
    required this.name,
    required this.imageAsset,
    required this.calories,
    required this.protein,
    required this.carbs,
    required this.fat,
    required this.price,
  });
}
