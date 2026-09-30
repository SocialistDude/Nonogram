import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/progress_repository.dart';
import '../data/hive_service.dart';
import '../domain/level_repository.dart';
import '../ui/screens/game/game_view_model.dart';
import '../ui/screens/home/home_view_model.dart';

final hiveServiceProvider = Provider<HiveService>((ref) {
  throw UnimplementedError('Must be overridden in main');
});

final progressRepositoryProvider =
ChangeNotifierProvider<ProgressRepository>((ref) {
  final hiveService = ref.watch(hiveServiceProvider);
  return ProgressRepository(hiveService: hiveService);
});

final levelRepositoryProvider = Provider<LevelRepository>((ref) {
  return LevelRepository();
});

final homeViewModelProvider =
StateNotifierProvider<HomeViewModel, HomeViewModelState>((ref) {
  final repo = ref.read(progressRepositoryProvider);
  return HomeViewModel(progressRepository: repo);
});

final gameViewModelProvider =
StateNotifierProvider.autoDispose<GameViewModel, GameViewModelState>((ref) {
  final progressRepo = ref.read(progressRepositoryProvider);
  final levelRepo = ref.read(levelRepositoryProvider);
  return GameViewModel(
    progressRepository: progressRepo,
    levelRepository: levelRepo,
  );
});