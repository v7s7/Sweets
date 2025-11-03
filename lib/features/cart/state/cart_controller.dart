import 'dart:math' as math;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../sweets/data/sweet.dart';

/// Single cart line (immutable)
class CartLine {
  /// Stable unique id for this line (not tied to note/product).
  final String id;

  /// Product snapshot at time of add.
  final Sweet sweet;

  /// Quantity (1..999)
  final int qty;

  /// Optional per-line note. Empty/whitespace treated as null.
  final String? note;

  const CartLine({
    required this.id,
    required this.sweet,
    required this.qty,
    this.note,
  });

  double get lineTotal => sweet.price * qty;

  /// Normalized note used for equality/merging.
  String get noteNorm => (note ?? '').trim();

  /// For merge decisions: product + normalized note.
  String get compositeKey => '${sweet.id}::${noteNorm}';

  CartLine copyWith({
    String? id,
    Sweet? sweet,
    int? qty,
    String? note,
  }) {
    final norm = (note ?? this.note)?.trim();
    return CartLine(
      id: id ?? this.id,
      sweet: sweet ?? this.sweet,
      qty: qty ?? this.qty,
      note: (norm == null || norm.isEmpty) ? null : norm,
    );
  }
}

/// Cart state (immutable)
class CartState {
  /// Internal storage keyed by lineId (not composite).
  final Map<String, CartLine> linesById;

  const CartState(this.linesById);

  /// Back-compat: expose a read-only view of lines by id.
  Map<String, CartLine> get lines => Map.unmodifiable(linesById);

  /// Back-compat: original API exposed a `Map<String,int> items`.
  /// This returns an aggregated view of quantities keyed by sweetId.
  Map<String, int> get items {
    final agg = <String, int>{};
    for (final l in linesById.values) {
      agg[l.sweet.id] = (agg[l.sweet.id] ?? 0) + l.qty;
    }
    return Map.unmodifiable(agg);
  }

  /// Number of distinct lines
  int get lineCount => linesById.length;

  /// Sum of quantities
  int get totalCount => linesById.values.fold<int>(0, (sum, l) => sum + l.qty);

  /// Monetary subtotal
  double get subtotal =>
      linesById.values.fold<double>(0.0, (sum, l) => sum + l.lineTotal);

  /// Aggregated quantity for a given product id
  int qtyFor(String sweetId) =>
      linesById.values.where((l) => l.sweet.id == sweetId).fold(0, (s, l) => s + l.qty);

  /// Number of lines that carry notes
  int get notedLinesCount =>
      linesById.values.where((l) => l.noteNorm.isNotEmpty).length;

  bool get isEmpty => linesById.isEmpty;

  /// Stable ordered list (by product name, then note, then id)
  List<CartLine> get asList {
    final list = linesById.values.toList();
    list.sort((a, b) {
      final n = a.sweet.name.compareTo(b.sweet.name);
      if (n != 0) return n;
      final nn = a.noteNorm.compareTo(b.noteNorm);
      if (nn != 0) return nn;
      return a.id.compareTo(b.id);
    });
    return list;
  }

  /// Convert to order payload (one entry per **line**, preserves note)
  List<Map<String, dynamic>> toOrderItemsPayload() {
    return asList.map((l) {
      final m = <String, dynamic>{
        'id': l.sweet.id,
        'name': l.sweet.name,
        'price': double.parse(l.sweet.price.toStringAsFixed(3)),
        'qty': l.qty,
      };
      if (l.noteNorm.isNotEmpty) m['note'] = l.noteNorm;
      return m;
    }).toList();
  }
}

class CartController extends Notifier<CartState> {
  int _seq = math.Random().nextInt(1 << 20);

  @override
  CartState build() => const CartState(<String, CartLine>{});

  String _newId() {
    final t = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final s = (_seq++).toRadixString(36);
    return 'ln_${t}_$s';
  }

  String _compositeFor(Sweet sweet, String? note) {
    final n = (note ?? '').trim();
    return '${sweet.id}::${n}';
  }

  /// Find existing line by composite key (product+note).
  String? _findLineIdByComposite(String composite) {
    for (final entry in state.linesById.entries) {
      if (entry.value.compositeKey == composite) return entry.key;
    }
    return null;
  }

  /// Add quantity for a product. Lines are **separate** per distinct note.
  /// If a line with the **same** product+note exists, it merges quantities.
  void add(
    Sweet sweet, {
    int qty = 1,
    String? note,
  }) {
    if (qty <= 0) return;

    final composite = _compositeFor(sweet, note);
    final existingId = _findLineIdByComposite(composite);

    final next = Map<String, CartLine>.from(state.linesById);
    if (existingId == null) {
      final id = _newId();
      next[id] = CartLine(
        id: id,
        sweet: sweet,
        qty: qty.clamp(1, 999),
        note: (note ?? '').trim().isEmpty ? null : note!.trim(),
      );
    } else {
      final line = next[existingId]!;
      next[existingId] = line.copyWith(qty: (line.qty + qty).clamp(1, 999));
    }
    state = CartState(next);
  }

  /// Convenience alias to match older UI calls.
  void addWithNote(Sweet sweet, {int qty = 1, String? note}) =>
      add(sweet, qty: qty, note: note);

  /// Set exact quantity for a **line id**. Removes the line if qty <= 0.
  void setQtyLine(String lineId, int qty) {
    final next = Map<String, CartLine>.from(state.linesById);
    final existing = next[lineId];
    if (existing == null) return;

    final newQty = qty.clamp(0, 999);
    if (newQty <= 0) {
      next.remove(lineId);
    } else {
      next[lineId] = existing.copyWith(qty: newQty);
    }
    state = CartState(next);
  }

  /// Increment by step for a **line id**.
  void incrementLine(String lineId, {int step = 1}) {
    if (step <= 0) return;
    final next = Map<String, CartLine>.from(state.linesById);
    final existing = next[lineId];
    if (existing == null) return;
    next[lineId] = existing.copyWith(qty: (existing.qty + step).clamp(1, 999));
    state = CartState(next);
  }

  /// Decrement by step for a **line id**. Removes line if <=0.
  void decrementLine(String lineId, {int step = 1}) {
    if (step <= 0) return;
    final next = Map<String, CartLine>.from(state.linesById);
    final existing = next[lineId];
    if (existing == null) return;

    final after = existing.qty - step;
    if (after <= 0) {
      next.remove(lineId);
    } else {
      next[lineId] = existing.copyWith(qty: after);
    }
    state = CartState(next);
  }

  /// Remove a **line id** completely.
  void removeLine(String lineId) {
    final next = Map<String, CartLine>.from(state.linesById)..remove(lineId);
    state = CartState(next);
  }

  /// Clear all lines.
  void clear() => state = const CartState(<String, CartLine>{});

  /// Set/overwrite **note for a specific line**.
  /// If another line with the same product+newNote exists, we **merge**.
  void setNote(String lineId, String? note) {
    final next = Map<String, CartLine>.from(state.linesById);
    final existing = next[lineId];
    if (existing == null) return;

    final trimmed = (note ?? '').trim();
    final newComposite = _compositeFor(existing.sweet, trimmed);

    // Check if another line already has same composite → merge
    final otherId = _findLineIdByComposite(newComposite);

    if (otherId != null && otherId != lineId) {
      final other = next[otherId]!;
      next[otherId] =
          other.copyWith(qty: (other.qty + existing.qty).clamp(1, 999));
      next.remove(lineId);
    } else {
      next[lineId] =
          existing.copyWith(note: trimmed.isEmpty ? null : trimmed);
    }
    state = CartState(next);
  }

  /// Read a line by id (null if missing).
  CartLine? line(String lineId) => state.linesById[lineId];

  /// Back-compat helper (aggregate) – prefer line-specific methods in UI.
  void addLegacy(Sweet sweet, {int qty = 1}) => add(sweet, qty: qty);
}

final cartControllerProvider =
    NotifierProvider<CartController, CartState>(CartController.new);
