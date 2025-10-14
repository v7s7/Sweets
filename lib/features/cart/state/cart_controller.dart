import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../sweets/data/sweet.dart';

class CartState {
  final Map<String, int> items; // sweetId -> qty
  const CartState(this.items);

  int get totalCount => items.values.fold(0, (a, b) => a + b);
}

class CartController extends Notifier<CartState> {
  @override
  CartState build() => const CartState({});

  void add(Sweet sweet, {int qty = 1}) {
    final map = Map<String, int>.from(state.items);
    map[sweet.id] = (map[sweet.id] ?? 0) + qty;
    state = CartState(map);
  }
}

final cartControllerProvider =
    NotifierProvider<CartController, CartState>(CartController.new);
