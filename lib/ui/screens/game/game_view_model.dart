import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/progress_repository.dart';
import '../../../domain/game_level.dart';
import '../../../domain/level_repository.dart';
import '../../../domain/nonogram_rules.dart';

enum CellState {
  empty,
  filled,
  cross,
}

@immutable
class _Snapshot {
  const _Snapshot(this.board, this.moveCount);
  final List<List<CellState>> board;
  final int moveCount;
}

@immutable
class GameViewModelState {
  const GameViewModelState({
    this.level,
    this.board = const [],
    this.conflicts = const [],
    this.isLoading = false,
    this.isComplete = false,
    this.moveCount = 0,
    this.elapsedSeconds = 0,
    this.canUndo = false,
    this.hintMode = false,
    this.error,
  });

  final GameLevel? level;
  final List<List<CellState>> board;
  final List<List<bool>> conflicts;
  final bool isLoading;
  final bool isComplete;
  final int moveCount;
  final int elapsedSeconds;
  final bool canUndo;
  final bool hintMode;
  final String? error;

  GameViewModelState copyWith({
    GameLevel? level,
    List<List<CellState>>? board,
    List<List<bool>>? conflicts,
    bool? isLoading,
    bool? isComplete,
    int? moveCount,
    int? elapsedSeconds,
    bool? canUndo,
    bool? hintMode,
    String? error,
  }) {
    return GameViewModelState(
      level: level ?? this.level,
      board: board ?? this.board,
      conflicts: conflicts ?? this.conflicts,
      isLoading: isLoading ?? this.isLoading,
      isComplete: isComplete ?? this.isComplete,
      moveCount: moveCount ?? this.moveCount,
      elapsedSeconds: elapsedSeconds ?? this.elapsedSeconds,
      canUndo: canUndo ?? this.canUndo,
      hintMode: hintMode ?? this.hintMode,
      error: error,
    );
  }

  int get filledCount {
    int n = 0;
    for (final row in board) {
      for (final cell in row) {
        if (cell == CellState.filled) n++;
      }
    }
    return n;
  }
}

class GameViewModel extends StateNotifier<GameViewModelState> {
  GameViewModel({
    required this.progressRepository,
    required this.levelRepository,
  }) : super(const GameViewModelState());

  final ProgressRepository progressRepository;
  final LevelRepository levelRepository;

  static const int _maxUndo = 50;
  final List<_Snapshot> _undoStack = [];
  bool _strokeUndoPushed = false;
  Timer? _timer;
  Timer? _hintTimer;

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (state.isComplete) {
        _timer?.cancel();
        return;
      }
      state = state.copyWith(elapsedSeconds: state.elapsedSeconds + 1);
    });
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  void _triggerHaptic(Future<void> Function() hapticAction) {
    if (progressRepository.hapticsEnabled) {
      hapticAction();
    }
  }

  List<List<CellState>> _emptyBoard(int width, int height) =>
      List.generate(height, (_) => List<CellState>.filled(width, CellState.empty));

  Future<void> loadLevel(int levelNumber) async {
    _undoStack.clear();
    state = const GameViewModelState(isLoading: true);

    try {
      final level = levelRepository.getLevel(levelNumber);
      final progress = await progressRepository.getProgress();
      List<List<CellState>> board;
      int moveCount = 0;
      int elapsed = 0;

      if (progress.savedLevelNumber == levelNumber &&
          progress.savedBoard != null &&
          progress.savedBoard!.length == level.height &&
          (progress.savedBoard!.isEmpty ||
              progress.savedBoard![0].length == level.width)) {
        board = progress.savedBoard!
            .map((row) =>
                row.map((i) => CellState.values[i]).toList(growable: false))
            .toList();
        moveCount = progress.savedMoveCount;
        elapsed = progress.savedElapsedSeconds;
      } else {
        board = _emptyBoard(level.width, level.height);
      }

      final conflicts = NonogramRules.computeConflicts(board, level);
      final isComplete = NonogramRules.isComplete(board, level);

      state = GameViewModelState(
        level: level,
        board: board,
        conflicts: conflicts,
        moveCount: moveCount,
        elapsedSeconds: elapsed,
        isComplete: isComplete,
      );
      if (!isComplete) _startTimer();
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Failed to load level: $e',
      );
    }
  }

  void toggleCell(int r, int c) {
    if (state.hintMode) {
      _applyHintAt(r, c);
      return;
    }
    final level = state.level;
    if (state.isComplete || level == null) return;

    _pushUndo();

    final newBoard = List.generate(
      level.height,
          (r) => List<CellState>.from(state.board[r]),
    );

    final current = newBoard[r][c];
    CellState next;
    int movesDelta = 0;

    if (current == CellState.empty) {
      next = CellState.filled;
      movesDelta = 1;
      _triggerHaptic(HapticFeedback.mediumImpact);
    } else if (current == CellState.filled) {
      next = CellState.cross;
      _triggerHaptic(HapticFeedback.lightImpact);
    } else {
      next = CellState.empty;
      _triggerHaptic(HapticFeedback.lightImpact);
    }

    newBoard[r][c] = next;

    final newConflicts = NonogramRules.computeConflicts(newBoard, level);
    final isComplete = NonogramRules.isComplete(newBoard, level);

    if (isComplete) {
      _triggerHaptic(HapticFeedback.heavyImpact);
      _stopTimer();
    }

    state = state.copyWith(
      board: newBoard,
      conflicts: newConflicts,
      moveCount: state.moveCount + movesDelta,
      isComplete: isComplete,
      canUndo: _undoStack.isNotEmpty,
    );

    _persistInProgress();
  }

  void setCellState(int r, int c, CellState next) {
    if (state.hintMode) {
      _applyHintAt(r, c);
      return;
    }
    final level = state.level;
    if (state.isComplete || level == null) return;

    final current = state.board[r][c];
    if (current == next) return;

    _pushUndo();

    final newBoard = List.generate(
      level.height,
      (row) => List<CellState>.from(state.board[row]),
    );

    newBoard[r][c] = next;

    if (next == CellState.filled) {
      _applyAutoCrosses(newBoard, level);
    }

    final newConflicts = NonogramRules.computeConflicts(newBoard, level);
    final isComplete = NonogramRules.isComplete(newBoard, level);

    if (isComplete) {
      _triggerHaptic(HapticFeedback.heavyImpact);
      _stopTimer();
    } else {
      _triggerHaptic(HapticFeedback.selectionClick);
    }

    state = state.copyWith(
      board: newBoard,
      conflicts: newConflicts,
      moveCount: state.moveCount + (next == CellState.filled ? 1 : 0),
      isComplete: isComplete,
      canUndo: _undoStack.isNotEmpty,
    );

    _persistInProgress();
  }

  // ─── Stroke (свайп) ─────────────────────────────────────────────

  /// Вызывается в начале свайпа. Реальный undo-push произойдёт
  /// лениво при первой же реальной правке.
  void beginStroke() {
    _strokeUndoPushed = false;
  }

  /// Красит одну клетку в рамках свайпа.
  /// [mode] — текущий режим (fill или cross).
  /// [erase] = true  → стирает клетки, стоящие в [mode] (переводит в empty).
  /// [erase] = false → ставит [mode] на пустые клетки; чужие (противоположные) не трогает.
  void paintCell(int r, int c, CellState mode, {required bool erase}) {
    if (state.hintMode) {
      _applyHintAt(r, c);
      return;
    }
    final level = state.level;
    if (state.isComplete || level == null) return;
    if (mode == CellState.empty) return;

    final current = state.board[r][c];

    CellState target;
    if (erase) {
      // Стираем только те клетки, которые уже в текущем режиме
      if (current != mode) return;
      target = CellState.empty;
    } else {
      // Рисуем только на пустых; filled↔cross не меняем
      if (current != CellState.empty) return;
      target = mode;
    }

    if (!_strokeUndoPushed) {
      _pushUndo();
      _strokeUndoPushed = true;
    }

    final newBoard = List.generate(
      level.height,
          (row) => List<CellState>.from(state.board[row]),
    );
    newBoard[r][c] = target;

    // Автокресты запускаем только при добавлении заливки:
    // добавление — единственное действие, которое может завершить линию.
    if (target == CellState.filled) {
      _applyAutoCrosses(newBoard, level);
    }

    final newConflicts = NonogramRules.computeConflicts(newBoard, level);
    final isComplete = NonogramRules.isComplete(newBoard, level);

    if (isComplete) {
      _triggerHaptic(HapticFeedback.heavyImpact);
      _stopTimer();
    }

    state = state.copyWith(
      board: newBoard,
      conflicts: newConflicts,
      moveCount: state.moveCount + (target == CellState.filled ? 1 : 0),
      isComplete: isComplete,
      canUndo: _undoStack.isNotEmpty,
    );
  }

  /// Вызывается в конце свайпа — сохраняет прогресс одним махом.
  void endStroke() {
    if (_strokeUndoPushed) {
      _persistInProgress();
    }
    _strokeUndoPushed = false;
  }

// ─── Автокресты ────────────────────────────────────────────────

  /// Проставляет крестики в линиях, где группы filled-клеток уже
  /// полностью совпали с подсказкой. Работает итеративно: автокрест
  /// в строке может помочь завершить столбец, и наоборот.
  void _applyAutoCrosses(List<List<CellState>> board, GameLevel level) {
    if (!progressRepository.autoCrossEnabled) return;
    bool changed = true;
    int safety = 0;

    while (changed && safety++ < 20) {
      changed = false;

      // Строки
      for (int r = 0; r < level.height; r++) {
        if (_lineMatchesClue(board[r], level.rowClues[r])) {
          for (int c = 0; c < level.width; c++) {
            if (board[r][c] == CellState.empty) {
              board[r][c] = CellState.cross;
              changed = true;
            }
          }
        }
      }

      // Столбцы
      for (int c = 0; c < level.width; c++) {
        final col = List<CellState>.generate(level.width, (r) => board[r][c]);
        if (_lineMatchesClue(col, level.colClues[c])) {
          for (int r = 0; r < level.height; r++) {
            if (board[r][c] == CellState.empty) {
              board[r][c] = CellState.cross;
              changed = true;
            }
          }
        }
      }
    }
  }

  void _applyHintAt(int r, int c) {
    final level = state.level;
    if (level == null || state.isComplete) return;

    final isFilled = level.solutionGrid[r][c];
    final target = isFilled ? CellState.filled : CellState.cross;
    if (state.board[r][c] == target) return;

    if (!_strokeUndoPushed) {
      _pushUndo();
      _strokeUndoPushed = true;
    }

    final newBoard = List.generate(
      level.height,
          (row) => List<CellState>.from(state.board[row]),
    );
    newBoard[r][c] = target;

    final newConflicts = NonogramRules.computeConflicts(newBoard, level);
    final isComplete = NonogramRules.isComplete(newBoard, level);

    if (isComplete) {
      _triggerHaptic(HapticFeedback.heavyImpact);
      _stopTimer();
    }

    state = state.copyWith(
      board: newBoard,
      conflicts: newConflicts,
      isComplete: isComplete,
      canUndo: _undoStack.isNotEmpty,
      hintMode: isComplete ? false : state.hintMode,
    );

    _persistInProgress();
  }

  /// true, если группы подряд идущих filled-клеток в линии
  /// ровно совпадают с подсказкой. Пустые клетки считаются
  /// разделителями — значит, если структура совпала, всё остальное
  /// в линии можно смело превращать в крестики.
  bool _lineMatchesClue(List<CellState> line, List<int> clues) {
    final groups = <int>[];
    int count = 0;
    for (final cell in line) {
      if (cell == CellState.filled) {
        count++;
      } else {
        if (count > 0) groups.add(count);
        count = 0;
      }
    }
    if (count > 0) groups.add(count);

    if (groups.length != clues.length) return false;
    for (int i = 0; i < groups.length; i++) {
      if (groups[i] != clues[i]) return false;
    }
    return true;
  }

  void _pushUndo() {
    final snapshotBoard = state.board
        .map((row) => List<CellState>.from(row))
        .toList(growable: false);
    _undoStack.add(_Snapshot(snapshotBoard, state.moveCount));
    if (_undoStack.length > _maxUndo) {
      _undoStack.removeAt(0);
    }
  }

  void undo() {
    if (_undoStack.isEmpty || state.level == null || state.isComplete) return;
    final snapshot = _undoStack.removeLast();
    final conflicts = NonogramRules.computeConflicts(snapshot.board, state.level!);
    _triggerHaptic(HapticFeedback.lightImpact);
    state = state.copyWith(
      board: snapshot.board,
      conflicts: conflicts,
      moveCount: snapshot.moveCount,
      canUndo: _undoStack.isNotEmpty,
    );
    _persistInProgress();
  }

  void toggleHintMode() {
    if (state.isComplete) return;
    _triggerHaptic(HapticFeedback.selectionClick);
    state = state.copyWith(hintMode: !state.hintMode);
  }

  void _persistInProgress() {
    final level = state.level;
    if (level == null || state.isComplete) return;
    final boardIndices = state.board
        .map((row) => row.map((cell) => cell.index).toList())
        .toList();
    progressRepository.saveInProgress(
      level.levelNumber,
      boardIndices,
      state.moveCount,
      state.elapsedSeconds,
    );
  }

  Future<void> completeLevel() async {
    final level = state.level;
    if (level == null || !state.isComplete) return;
    await progressRepository.completeLevel(level.levelNumber, state.moveCount);
    await progressRepository.recordLevelResult(
      level.levelNumber,
      state.moveCount,
      state.elapsedSeconds,
    );
    await progressRepository.clearInProgress();
  }

  Future<void> resetLevel() async {
    final level = state.level;
    if (level == null) return;
    await progressRepository.clearInProgress();
    await loadLevel(level.levelNumber);
  }

  @override
  void dispose() {
    _stopTimer();
    super.dispose();
  }
}
