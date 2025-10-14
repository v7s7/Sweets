import 'package:flutter_riverpod/flutter_riverpod.dart';

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

class SweetsController extends Notifier<SweetsState> {
  @override
  SweetsState build() => const SweetsState();

  void setIndex(int i) => state = state.copyWith(index: i);
  void openDetail()    => state = state.copyWith(isDetailOpen: true);
  void closeDetail()   => state = state.copyWith(isDetailOpen: false);
  void toggleDetail()  => state = state.copyWith(isDetailOpen: !state.isDetailOpen);
}

final sweetsControllerProvider =
    NotifierProvider<SweetsController, SweetsState>(SweetsController.new);
