import '../data/hive_service.dart';
import 'game_level.dart';
import 'levels/builtin_levels.dart';

class LevelRepository {
  LevelRepository({required HiveService hiveService})
      : _hiveService = hiveService {
    _reload();
  }

  final HiveService _hiveService;
  late List<GameLevel> _levels;

  void _reload() {
    final builtin = builtinLevels;
    final remote = _hiveService.loadRemoteLevels();
    _levels = [
      ...builtin,
      for (int i = 0; i < remote.length; i++)
        remote[i].toGameLevel(builtin.length + i + 1),
    ];
  }

  /// Вызывать после успешной синхронизации с сервером.
  void refresh() => _reload();

  int get totalLevels => _levels.length;

  bool isLastLevel(int n) => n >= _levels.length;

  GameLevel getLevel(int levelNumber) {
    if (levelNumber < 1 || levelNumber > _levels.length) {
      throw RangeError.range(
        levelNumber, 1, _levels.length, 'levelNumber',
        'Уровень $levelNumber не существует (доступно 1..${_levels.length})',
      );
    }
    return _levels[levelNumber - 1];
  }
}