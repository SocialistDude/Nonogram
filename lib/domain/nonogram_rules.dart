import 'game_level.dart';
import '../ui/screens/game/game_view_model.dart';

class NonogramRules {
  NonogramRules._();

  /// Check if the player's current board matches the solution requirements
  static bool isComplete(List<List<CellState>> board, GameLevel level) {
    for (int r = 0; r < level.height; r++) {
      for (int c = 0; c < level.width; c++) {
        if (level.solutionGrid[r][c] != (board[r][c] == CellState.filled)) {
          return false;
        }
      }
    }
    return true;
  }

  /// Compute conflicts matrix (cells incorrectly filled where solution expects empty)
  static List<List<bool>> computeConflicts(
      List<List<CellState>> board,
      GameLevel level,
      ) {
    return List.generate(
      level.height,
          (r) => List.generate(
        level.width,
            (c) => board[r][c] == CellState.filled && !level.solutionGrid[r][c],
      ),
    );
  }

  /// Suggest a hint: returns [row, col] of an unrevealed or incorrect cell
  static List<int>? suggestHint(
      List<List<CellState>> board,
      GameLevel level,
      ) {
    for (int r = 0; r < level.height; r++) {
      for (int c = 0; c < level.width; c++) {
        if (board[r][c] == CellState.filled && !level.solutionGrid[r][c]) {
          return [r, c];
        }
      }
    }
    for (int r = 0; r < level.height; r++) {
      for (int c = 0; c < level.width; c++) {
        if (level.solutionGrid[r][c] && board[r][c] != CellState.filled) {
          return [r, c];
        }
      }
    }
    return null;
  }
}
