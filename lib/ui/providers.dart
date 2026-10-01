import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/progress_repository.dart';
import '../data/hive_service.dart';
import '../data/remote_levels_service.dart';
import '../domain/level_repository.dart';
import 'screens/game/game_view_model.dart';
import 'screens/home/home_view_model.dart';

const String kRemoteManifestUrl =
    'https://socialist-dude.didns.ru/webdav/Public/Nonogram/manifest.json';

final hiveServiceProvider = Provider<HiveService>((ref) {
  throw UnimplementedError('Must be overridden in main');
});

final progressRepositoryProvider =
ChangeNotifierProvider<ProgressRepository>((ref) {
  return ProgressRepository(hiveService: ref.watch(hiveServiceProvider));
});

final levelRepositoryProvider = Provider<LevelRepository>((ref) {
  return LevelRepository(hiveService: ref.watch(hiveServiceProvider));
});

final remoteLevelsServiceProvider = Provider<RemoteLevelsService>((ref) {
  return RemoteLevelsService(
    hiveService: ref.watch(hiveServiceProvider),
    manifestUrl: kRemoteManifestUrl,
  );
});

final homeViewModelProvider =
StateNotifierProvider<HomeViewModel, HomeViewModelState>((ref) {
  return HomeViewModel(progressRepository: ref.read(progressRepositoryProvider));
});

final gameViewModelProvider =
StateNotifierProvider.autoDispose<GameViewModel, GameViewModelState>((ref) {
  return GameViewModel(
    progressRepository: ref.read(progressRepositoryProvider),
    levelRepository: ref.read(levelRepositoryProvider),
  );
});