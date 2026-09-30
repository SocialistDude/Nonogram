import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/progress_repository.dart';
import '../../../domain/user_progress.dart';

class HomeViewModelState {
  const HomeViewModelState({
    this.progress,
    this.isLoading = false,
  });

  final UserProgress? progress;
  final bool isLoading;

  HomeViewModelState copyWith({
    UserProgress? progress,
    bool? isLoading,
  }) {
    return HomeViewModelState(
      progress: progress ?? this.progress,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

class HomeViewModel extends StateNotifier<HomeViewModelState> {
  HomeViewModel({required this.progressRepository})
      : super(const HomeViewModelState()) {
    progressRepository.addListener(_onRepoChanged);
    loadProgress();
  }

  final ProgressRepository progressRepository;

  void _onRepoChanged() {
    // Репозиторий что-то сохранил — перечитываем прогресс.
    // getProgress() вернёт кеш моментально, без обращения к Hive.
    loadProgress();
  }

  Future<void> loadProgress() async {
    state = state.copyWith(isLoading: true);
    final progress = await progressRepository.getProgress();
    if (!mounted) return;
    state = HomeViewModelState(progress: progress, isLoading: false);
  }

  @override
  void dispose() {
    progressRepository.removeListener(_onRepoChanged);
    super.dispose();
  }
}
