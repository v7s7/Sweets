import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'sweet.dart';

/// All prices are in Bahraini Dinar (BD), using 3 decimal places.
final sweetsRepoProvider = Provider<List<Sweet>>((ref) {
  // Replace imageAsset names with your actual PNGs under assets/sweets/
  return const [
    Sweet(
      id: 'donut',
      name: 'Glazed Donut',
      imageAsset: 'assets/sweets/donut.png',
      calories: 260,
      protein: 4,
      carbs: 31,
      fat: 13,
      price: 0.600, // BD
    ),
    Sweet(
      id: 'cookie',
      name: 'Chocolate Cookie',
      imageAsset: 'assets/sweets/cookie.png',
      calories: 210,
      protein: 3.5,
      carbs: 28,
      fat: 9,
      price: 0.500, // BD
    ),
    Sweet(
      id: 'cinnabon',
      name: 'Cinnabon Roll',
      imageAsset: 'assets/sweets/cinnabon.png',
      calories: 420,
      protein: 6,
      carbs: 62,
      fat: 16,
      price: 1.200, // BD
    ),
  ];
});
