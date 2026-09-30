import 'game_level.dart';
import 'levels/builtin_levels.dart';

class LevelRepository {
  LevelRepository({List<GameLevel>? levels})
      : _levels = levels ?? builtinLevels;

  final List<GameLevel> _levels;

  int get totalLevels => _levels.length;

  bool isLastLevel(int levelNumber) => levelNumber >= _levels.length;

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