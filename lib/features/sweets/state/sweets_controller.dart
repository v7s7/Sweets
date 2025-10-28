import 'package:flutter_riverpod/flutter_riverpod.dart' as rp;

/// UI state for the sweets carousel + detail panel.
class SweetsState {
  final int index;
  final bool isDetailOpen;

  const SweetsState({this.index = 0, this.isDetailOpen = false});

  SweetsState copyWith({int? index, bool? isDetailOpen}) {
    return SweetsState(
      index: index ?? this.index,
      isDetailOpen: isDetailOpen ?? this.isDetailOpen,
    );
  }
}

class SweetsController extends rp.Notifier<SweetsState> {
  @override
  SweetsState build() => const SweetsState();

  void setIndex(int i) => state = state.copyWith(index: i);
  void openDetail() => state = state.copyWith(isDetailOpen: true);
  void closeDetail() => state = state.copyWith(isDetailOpen: false);
  void toggleDetail() => state = state.copyWith(isDetailOpen: !state.isDetailOpen);
}

/// Category filter state (null = All)
final selectedCategoryIdProvider =
    rp.StateProvider<String?>((ref) => null);

/// Subcategory filter state (null = no sub-filter)
final selectedSubcategoryIdProvider =
    rp.StateProvider<String?>((ref) => null);

/// Expose controller
final sweetsControllerProvider =
    rp.NotifierProvider<SweetsController, SweetsState>(SweetsController.new);
