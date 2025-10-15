import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../sweets/data/sweet.dart';

class CartState {
  final Map<String, int> items; // sweetId -> qty
  const CartState(this.items);

  int get totalCount => items.values.fold(0, (a, b) => a + b);

  int qtyFor(String id) => items[id] ?? 0;

  bool get isEmpty => items.isEmpty;
}

class CartController extends Notifier<CartState> {
  @override
  CartState build() => const CartState({});

  void add(Sweet sweet, {int qty = 1}) {
    final map = Map<String, int>.from(state.items);
    map[sweet.id] = (map[sweet.id] ?? 0) + qty;
    state = CartState(map);
  }

  void decrement(String sweetId, {int step = 1}) {
    final map = Map<String, int>.from(state.items);
    final current = map[sweetId] ?? 0;
    final next = current - step;
    if (next <= 0) {
      map.remove(sweetId);
    } else {
      map[sweetId] = next;
    }
    state = CartState(map);
  }

  void remove(String sweetId) {
    final map = Map<String, int>.from(state.items);
    map.remove(sweetId);
    state = CartState(map);
  }

  void clear() => state = const CartState({});
}

final cartControllerProvider =
    NotifierProvider<CartController, CartState>(CartController.new);
