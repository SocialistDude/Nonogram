import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

import '../../app_theme.dart';
import '../../widgets/tangible_button.dart';
import '../../providers.dart';
import 'game_view_model.dart';

class GameView extends ConsumerStatefulWidget {
  const GameView({
    super.key,
    required this.levelNumber,
  });

  final int levelNumber;

  @override
  ConsumerState<GameView> createState() => _GameViewState();
}

class _GameViewState extends ConsumerState<GameView> {
  CellState _currentDrawMode = CellState.filled;

  // --- свайп-рисование ---
  Offset? _panStartPos;
  int? _strokeStartR;
  int? _strokeStartC;
  int? _lastR;
  int? _lastC;
  int _strokeAxis = 0;
  bool _strokeActive = false;
  bool _strokeErase = false;
  bool _strokeSkipped = false;
  static const double _directionThreshold = 8.0;

  // --- мультитач навигация ---
  late final TransformationController _transformationController;
  final Map<int, Offset> _activePointers = {};
  Offset? _lastMid;
  double? _lastDist;

  @override
  void initState() {
    super.initState();
    _transformationController = TransformationController();
    Future.microtask(() {
      ref.read(gameViewModelProvider.notifier).loadLevel(widget.levelNumber);
    });
  }

  @override
  void deactivate() {
    try {
      ref.read(gameViewModelProvider.notifier).flushPersist();
    } catch (_) {}
    super.deactivate();
  }

  @override
  void dispose() {
    _transformationController.dispose();
    super.dispose();
  }

  String _formatTime(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  void _applyTwoFingerTransform() {
    final points = _activePointers.values.toList();
    if (points.length < 2) return;

    final p1 = points[0];
    final p2 = points[1];
    final mid = (p1 + p2) / 2;
    final dist = (p1 - p2).distance;

    if (_lastMid != null && _lastDist != null && _lastDist! > 0) {
      final delta = mid - _lastMid!;
      final scaleFactor = dist / _lastDist!;

      final currentScale = _transformationController.value.getMaxScaleOnAxis();
      final targetScale = (currentScale * scaleFactor).clamp(0.5, 12.0);
      final actualScale = currentScale == 0 ? 1.0 : targetScale / currentScale;

      final panMatrix = Matrix4.translationValues(delta.dx, delta.dy, 0);
      final scaleMatrix = Matrix4.identity()
        ..translate(mid.dx, mid.dy)
        ..scale(actualScale)
        ..translate(-mid.dx, -mid.dy);

      _transformationController.value =
          panMatrix * scaleMatrix * _transformationController.value;
    }

    _lastMid = mid;
    _lastDist = dist;
  }

  void _handleTapUp(
      TapUpDetails d,
      double cellSize,
      int width,
      int height,
      GameViewModelState state,
      GameViewModel vm,
      ) {
    if (_activePointers.length > 1) return;
    final r = (d.localPosition.dy / cellSize).floor().clamp(0, height - 1);
    final c = (d.localPosition.dx / cellSize).floor().clamp(0, width - 1);
    if (state.hintMode) {
      vm.setCellState(r, c, CellState.empty);
    } else if (state.board[r][c] == _currentDrawMode) {
      vm.setCellState(r, c, CellState.empty);
    } else {
      vm.setCellState(r, c, _currentDrawMode);
    }
  }

  void _handlePanDown(DragDownDetails d, double cellSize, int width, int height) {
    if (_activePointers.length > 1) {
      _resetStroke();
      return;
    }
    _panStartPos = d.localPosition;
    _strokeStartR = (d.localPosition.dy / cellSize).floor().clamp(0, height - 1);
    _strokeStartC = (d.localPosition.dx / cellSize).floor().clamp(0, width - 1);
    _lastR = _strokeStartR;
    _lastC = _strokeStartC;
    _strokeAxis = 0;
    _strokeActive = false;
    _strokeErase = false;
    _strokeSkipped = false;
  }

  void _handlePanUpdate(
      DragUpdateDetails d,
      double cellSize,
      int width,
      int height,
      GameViewModel vm,
      ) {
    if (_activePointers.length > 1) return;
    if (_panStartPos == null || _strokeStartR == null || _strokeStartC == null) {
      return;
    }
    if (_strokeSkipped) return;

    final hintMode = ref.read(gameViewModelProvider).hintMode;

    if (!_strokeActive) {
      final delta = d.localPosition - _panStartPos!;
      if (delta.distance < _directionThreshold) return;

      if (!hintMode) {
        final board = ref.read(gameViewModelProvider).board;
        final firstCell = board[_strokeStartR!][_strokeStartC!];

        if (firstCell == CellState.empty) {
          _strokeErase = false;
        } else if (firstCell == _currentDrawMode) {
          _strokeErase = true;
        } else {
          _strokeSkipped = true;
          return;
        }
      }

      _strokeAxis = delta.dx.abs() > delta.dy.abs() ? 1 : 2;
      _strokeActive = true;
      vm.beginStroke();

      vm.paintCell(_lastR!, _lastC!, _currentDrawMode, erase: _strokeErase);
      if (ref.read(progressRepositoryProvider).hapticsEnabled) {
        HapticFeedback.selectionClick();
      }
    }

    int r, c;
    if (_strokeAxis == 1) {
      r = _strokeStartR!;
      c = (d.localPosition.dx / cellSize).floor().clamp(0, width - 1);
    } else {
      c = _strokeStartC!;
      r = (d.localPosition.dy / cellSize).floor().clamp(0, height - 1);
    }

    if (r != _lastR || c != _lastC) {
      _paintPath(_lastR!, _lastC!, r, c, vm);
      _lastR = r;
      _lastC = c;
    }
  }

  void _handlePanEnd(GameViewModel vm) {
    if (_strokeActive) {
      vm.endStroke();
    }
    _resetStroke();
  }

  void _resetStroke() {
    _strokeActive = false;
    _panStartPos = null;
    _strokeStartR = null;
    _strokeStartC = null;
    _lastR = null;
    _lastC = null;
    _strokeAxis = 0;
    _strokeErase = false;
    _strokeSkipped = false;
  }

  void _paintPath(int r0, int c0, int r1, int c1, GameViewModel vm) {
    if (r0 == r1) {
      final step = c1 >= c0 ? 1 : -1;
      for (int c = c0 + step;; c += step) {
        vm.paintCell(r0, c, _currentDrawMode, erase: _strokeErase);
        if (c == c1) break;
      }
    } else if (c0 == c1) {
      final step = r1 >= r0 ? 1 : -1;
      for (int r = r0 + step;; r += step) {
        vm.paintCell(r, c0, _currentDrawMode, erase: _strokeErase);
        if (r == r1) break;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(gameViewModelProvider);
    final vm = ref.read(gameViewModelProvider.notifier);

    ref.listen<GameViewModelState>(gameViewModelProvider, (previous, next) {
      if ((previous == null || !previous.isComplete) && next.isComplete) {
        _showCompletionDialog(context, next, vm);
      }
    });

    final level = state.level;
    final totalFilled = level == null
        ? 0
        : level.solutionGrid.expand((r) => r).where((b) => b).length;

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: AppColors.headingDark),
            onPressed: vm.resetLevel,
            tooltip: 'Restart',
          ),
        ],
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: AppColors.headingDark,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'LEVEL ${widget.levelNumber}',
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w900,
            color: AppColors.headingDark,
            letterSpacing: 1.0,
          ),
        ),
      ),
      body: SafeArea(
        child: state.isLoading || state.level == null
            ? const Center(
          child: CircularProgressIndicator(color: AppColors.accent),
        )
            : Stack(
          children: [
            Column(
              children: [
                Expanded(
                  child: Listener(
                      behavior: HitTestBehavior.opaque,
                      onPointerDown: (event) {
                        _activePointers[event.pointer] =
                            event.localPosition;
                        if (_activePointers.length >= 2) {
                          if (_strokeActive) {
                            ref
                                .read(gameViewModelProvider.notifier)
                                .endStroke();
                          }
                          _resetStroke();
                          _lastMid = null;
                          _lastDist = null;
                        }
                      },
                      onPointerMove: (event) {
                        if (_activePointers.containsKey(event.pointer)) {
                          _activePointers[event.pointer] =
                              event.localPosition;
                        }
                        if (_activePointers.length >= 2) {
                          _applyTwoFingerTransform();
                        }
                      },
                      onPointerUp: (event) {
                        _activePointers.remove(event.pointer);
                        if (_activePointers.length < 2) {
                          _lastMid = null;
                          _lastDist = null;
                        }
                      },
                      onPointerCancel: (event) {
                        _activePointers.remove(event.pointer);
                        if (_activePointers.length < 2) {
                          _lastMid = null;
                          _lastDist = null;
                        }
                      },
                      child: InteractiveViewer(
                        transformationController: _transformationController,
                        panEnabled: false,
                        scaleEnabled: false,
                        minScale: 0.5,
                        maxScale: 12.0,
                        boundaryMargin: const EdgeInsets.all(80.0),
                        clipBehavior: Clip.none,
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16.0,
                              vertical: 8.0,
                            ),
                            child: _buildNonogramGrid(context, state, vm),
                          ),
                        ),
                      ),
                    ),
                ),
              ],
            ),

            // ─── Верхняя панель: таймер + filled ───
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Padding(
                padding: const EdgeInsets.only(
                  bottom: 24,
                  left: 24,
                  right: 24,
                  top: 8,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.timer_outlined,
                          color: AppColors.subtext,
                          size: 18,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _formatTime(state.elapsedSeconds),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: AppColors.subtext,
                          ),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        const Icon(
                          Icons.grid_on_rounded,
                          color: AppColors.subtext,
                          size: 18,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'filled ${state.filledCount}/$totalFilled',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: AppColors.subtext,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            // ─── Нижняя панель: undo / mode / hint ───
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Padding(
                padding: const EdgeInsets.only(top: 24, bottom: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildCircleActionButton(
                      icon: Icons.undo_rounded,
                      onPressed:
                      state.canUndo && !state.isComplete ? vm.undo : null,
                    ),
                    const SizedBox(width: 20),
                    _buildModeToggle(state.hintMode, vm),
                    const SizedBox(width: 20),
                    _buildHintButton(state.hintMode, vm),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showCompletionDialog(
      BuildContext context,
      GameViewModelState state,
      GameViewModel vm,
      ) {
    final level = state.level!;
    final isLast = ref.read(levelRepositoryProvider).isLastLevel(widget.levelNumber);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.bg,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: AppColors.border, width: 1.5),
          ),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'LEVEL COMPLETED!',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  color: AppColors.headingDark,
                  letterSpacing: 1.0,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Time: ${_formatTime(state.elapsedSeconds)}',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: AppColors.subtext,
                ),
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border, width: 1.0),
                ),
                child: SizedBox(
                  width: 120 * (level.width / level.height).clamp(0.5, 2.0),
                  height: 120,
                  child: GridView.builder(
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: level.width,
                      crossAxisSpacing: 2.0,
                      mainAxisSpacing: 2.0,
                    ),
                    itemCount: level.width * level.height,
                    itemBuilder: (context, index) {
                      final r = index ~/ level.width;
                      final c = index % level.width;
                      final isFilled = level.solutionGrid[r][c];
                      return Container(
                        decoration: BoxDecoration(
                          color: isFilled ? AppColors.accent : Colors.transparent,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 20),
              TangibleButton(
                text: isLast ? 'Finish' : 'Next Level',
                onPressed: () async {
                  await vm.completeLevel();
                  if (!dialogContext.mounted) return;
                  Navigator.pop(dialogContext);
                  if (isLast) {
                    Navigator.pop(context);
                  } else {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            GameView(levelNumber: widget.levelNumber + 1),
                      ),
                    );
                  }
                },
              ),
              const SizedBox(height: 12),
              TangibleButton(
                text: 'Home',
                isSecondary: true,
                icon: Icons.home_rounded,
                onPressed: () async {
                  await vm.completeLevel();
                  if (!dialogContext.mounted) return;
                  Navigator.pop(dialogContext);
                  Navigator.pop(context);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCircleActionButton({
    required IconData icon,
    required VoidCallback? onPressed,
    Color? iconColor,
  }) {
    final isDisabled = onPressed == null;
    return GestureDetector(
      onTap: onPressed,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: AppColors.surface,
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.border, width: 2),
        ),
        child: Icon(
          icon,
          size: 24,
          color: isDisabled
              ? AppColors.subtext.withValues(alpha: 0.4)
              : (iconColor ?? AppColors.headingDark),
        ),
      ),
    );
  }

  Widget _buildModeToggle(bool hintMode, GameViewModel vm) {
    final isFill = _currentDrawMode == CellState.filled;
    final Color color = isFill ? AppColors.accent : AppColors.cellCross;
    final IconData icon = isFill ? Icons.square : Icons.close_rounded;
    final String label = isFill ? 'FILL' : 'CROSS';
    final Color fgColor = isFill ? Colors.black : Colors.white;

    return GestureDetector(
      onTap: () {
        if (ref.read(progressRepositoryProvider).hapticsEnabled) {
          HapticFeedback.selectionClick();
        }
        if (hintMode) {
          vm.toggleHintMode(); // выход из hint-режима
        }
        setState(() {
          _currentDrawMode = isFill ? CellState.cross : CellState.filled;
        });
      },
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 180),
        opacity: hintMode ? 0.35 : 1.0,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.4),
                blurRadius: 10,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: fgColor, size: 24),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                  letterSpacing: 0.8,
                  color: fgColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHintButton(bool hintMode, GameViewModel vm) {
    final isDisabled = ref.read(gameViewModelProvider).isComplete;
    return GestureDetector(
      onTap: isDisabled
          ? null
          : () {
        if (ref.read(progressRepositoryProvider).hapticsEnabled) {
          HapticFeedback.selectionClick();
        }
        vm.toggleHintMode();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: hintMode ? AppColors.gold : AppColors.surface,
          shape: BoxShape.circle,
          border: Border.all(
            color: hintMode ? AppColors.gold : AppColors.border,
            width: 2,
          ),
          boxShadow: hintMode
              ? [
            BoxShadow(
              color: AppColors.gold.withValues(alpha: 0.5),
              blurRadius: 16,
              spreadRadius: 3,
            ),
          ]
              : null,
        ),
        child: Icon(
          Icons.lightbulb_rounded,
          size: 24,
          color: hintMode
              ? Colors.black
              : (isDisabled
              ? AppColors.subtext.withValues(alpha: 0.4)
              : AppColors.gold),
        ),
      ),
    );
  }

  Widget _buildNonogramGrid(
      BuildContext context,
      GameViewModelState state,
      GameViewModel vm,
      ) {
    final level = state.level!;
    final w = level.width;
    final h = level.height;

    final maxColClueLen =
    level.colClues.map((c) => c.length).fold(1, (a, b) => a > b ? a : b);
    final maxRowClueLen =
    level.rowClues.map((r) => r.length).fold(1, (a, b) => a > b ? a : b);

    return LayoutBuilder(
      builder: (context, constraints) {
        final availWidth = constraints.maxWidth;
        final availHeight = constraints.maxHeight;

        const double maxClueWidthRatio = 0.28;
        const double maxClueHeightRatio = 0.25;

        final cellByWidth =
            (availWidth * (1.0 - maxClueWidthRatio)) / w;
        final cellByHeight =
            (availHeight * (1.0 - maxClueHeightRatio)) / (h + 1);

        double cellSize =
        (cellByWidth < cellByHeight ? cellByWidth : cellByHeight)
            .floorToDouble();
        cellSize = cellSize.clamp(6.0, 68.0);

        final fontSize = (cellSize * 0.42).clamp(9.0, 18.0);
        final rowClueWidth = (maxRowClueLen * (fontSize * 0.9))
            .clamp(cellSize * 1.2, availWidth * maxClueWidthRatio);
        final clueHeight = (maxColClueLen * (fontSize * 1.15))
            .clamp(cellSize * 1.2, availHeight * maxClueHeightRatio);

        final boardWidth = cellSize * w;
        final boardHeight = cellSize * h;
        final totalWidth = rowClueWidth + boardWidth;
        final totalHeight = clueHeight + boardHeight;

        return Center(
          child: SizedBox(
            width: totalWidth,
            height: totalHeight,
            child: Stack(
              children: [
                Table(
                  columnWidths: {
                    0: FixedColumnWidth(rowClueWidth),
                    for (int c = 0; c < w; c++)
                      c + 1: FixedColumnWidth(cellSize),
                  },
                  children: [
                    TableRow(
                      children: [
                        const SizedBox.shrink(),
                        for (int c = 0; c < w; c++)
                          SizedBox(
                            height: clueHeight,
                            child: Container(
                              alignment: Alignment.bottomCenter,
                              padding: const EdgeInsets.only(bottom: 4),
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.bottomCenter,
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: level.colClues[c]
                                      .map((val) => Text(
                                    '$val',
                                    style: TextStyle(
                                      fontSize: fontSize,
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.subtext,
                                    ),
                                  ))
                                      .toList(),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    for (int r = 0; r < h; r++)
                      TableRow(
                        children: [
                          SizedBox(
                            height: cellSize,
                            child: Container(
                              alignment: Alignment.centerRight,
                              padding: const EdgeInsets.only(right: 8),
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerRight,
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: level.rowClues[r]
                                      .map((val) => Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 2.0,
                                    ),
                                    child: Text(
                                      '$val',
                                      style: TextStyle(
                                        fontSize: fontSize,
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.headingDark,
                                      ),
                                    ),
                                  ))
                                      .toList(),
                                ),
                              ),
                            ),
                          ),
                          for (int c = 0; c < w; c++)
                            SizedBox(
                              width: cellSize,
                              height: cellSize,
                              child: Center(
                                child: Container(
                                  width: cellSize - 2,
                                  height: cellSize - 2,
                                  decoration: BoxDecoration(
                                    color: _getCellColor(r, c, state),
                                    borderRadius: BorderRadius.circular(
                                      (w > 12 || h > 12) ? 3 : 6,
                                    ),
                                    border: Border.all(
                                      color: AppColors.border,
                                      width: 1,
                                    ),
                                  ),
                                  child: _buildCellContent(
                                    state.board[r][c],
                                    cellSize,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                  ],
                ),

                // Разделительные линии каждые 4 клетки
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: _GridSeparatorsPainter(
                        rowClueWidth: rowClueWidth,
                        clueHeight: clueHeight,
                        cellSize: cellSize,
                        width: w,
                        height: h,
                        color: Colors.white24,
                        every: 4,
                      ),
                    ),
                  ),
                ),

                // Обработчик жестов только над полем
                Positioned(
                  left: rowClueWidth,
                  top: clueHeight,
                  width: boardWidth,
                  height: boardHeight,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapUp: (d) =>
                        _handleTapUp(d, cellSize, w, h, state, vm),
                    onPanDown: (d) => _handlePanDown(d, cellSize, w, h),
                    onPanUpdate: (d) =>
                        _handlePanUpdate(d, cellSize, w, h, vm),
                    onPanEnd: (_) => _handlePanEnd(vm),
                    onPanCancel: () => _handlePanEnd(vm),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Color _getCellColor(int r, int c, GameViewModelState state) {
    final cellState = state.board[r][c];
    if (cellState == CellState.filled) {
      return AppColors.accent;
    }
    return AppColors.surface;
  }

  Widget? _buildCellContent(CellState cellState, double cellSize) {
    if (cellState == CellState.cross) {
      return Icon(
        Icons.close_rounded,
        size: (cellSize * 0.65).clamp(8.0, 36.0),
        color: AppColors.cellCross,
      );
    }
    return null;
  }
}

class _GridSeparatorsPainter extends CustomPainter {
  _GridSeparatorsPainter({
    required this.rowClueWidth,
    required this.clueHeight,
    required this.cellSize,
    required this.width,
    required this.height,
    required this.color,
    this.every = 4,
  });

  final double rowClueWidth;
  final double clueHeight;
  final double cellSize;
  final int width;
  final int height;
  final Color color;
  final int every;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.0;

    for (int c = every; c < width; c += every) {
      final x = rowClueWidth + c * cellSize;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (int r = every; r < height; r += every) {
      final y = clueHeight + r * cellSize;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _GridSeparatorsPainter old) =>
      old.cellSize != cellSize ||
          old.width != width ||
          old.height != height ||
          old.rowClueWidth != rowClueWidth ||
          old.clueHeight != clueHeight ||
          old.color != color ||
          old.every != every;
}