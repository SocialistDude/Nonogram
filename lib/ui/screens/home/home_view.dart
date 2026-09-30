import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

import '../../app_theme.dart';
import '../../widgets/tangible_button.dart';
import '../game/game_view.dart';
import '../level_select/level_select_view.dart';
import '../../providers.dart';
import '../../../domain/user_progress.dart';  // UserProgress

class HomeView extends ConsumerStatefulWidget {
  const HomeView({super.key});

  @override
  ConsumerState<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends ConsumerState<HomeView> {
  @override
  void initState() {
    super.initState();
    // Ничего не делаем — HomeViewModel сам загружает прогресс в конструкторе.
  }

  Future<void> _openBank(BuildContext context) async {
    final levels = ref.read(levelRepositoryProvider);
    final raw = ref.read(homeViewModelProvider).progress?.currentLevel ?? 1;
    final startLevel = raw.clamp(1, levels.totalLevels);

    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => GameView(levelNumber: startLevel)),
    );

    // Вернулись — принудительно перечитываем прогресс.
    if (mounted) {
      ref.read(homeViewModelProvider.notifier).loadProgress();
    }
  }

  void _openBankSelect(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const LevelSelectView()),
    ).then((_) {
      if (mounted) {
        ref.read(homeViewModelProvider.notifier).loadProgress();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(homeViewModelProvider);
    final repo = ref.watch(progressRepositoryProvider);
    final levels = ref.watch(levelRepositoryProvider);

    // Прогресс мог быть испорчен (старый Hive, баг, ручная правка) —
    // страхуемся clamp'ом, даже если миграция уже отработала.
    final rawLevel = state.progress?.currentLevel ?? 1;
    final displayLevel = rawLevel.clamp(1, levels.totalLevels);

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Column(
            children: [
              // ─── Верхний ряд: индикатор уровня + иконки-тумблеры ───
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  if (state.progress != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(30),
                        border: Border.all(color: Colors.white24, width: 1),
                      ),
                      child: Text(
                        'LEVEL $displayLevel',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                          color: AppColors.headingDark,
                          letterSpacing: 0.8,
                        ),
                      ),
                    )
                  else
                    const SizedBox.shrink(),
                  Row(
                    children: [
                      _buildIconToggle(
                        icon: Icons.vibration,
                        active: repo.hapticsEnabled,
                        tooltip: 'Vibration',
                        onTap: () => repo.toggleHaptics(),
                      ),
                      const SizedBox(width: 8),
                      _buildIconToggle(
                        icon: Icons.auto_fix_high_rounded,
                        active: repo.autoCrossEnabled,
                        tooltip: 'Auto-cross',
                        onTap: () => repo.toggleAutoCross(),
                      ),
                    ],
                  ),
                ],
              ),

              // ─── Центр: место под цветную картинку последнего уровня ───
              Expanded(
                child: Center(
                  child: _buildCenterArtwork(state.progress),
                ),
              ),

              // ─── Play Bank ───
              _buildPlayRow(
                label: 'Play',
                onPlay: () => _openBank(context),
                onSelect: () => _openBankSelect(context),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────
  // Вспомогательные виджеты
  // ──────────────────────────────────────────────────────────────

  Widget _buildIconToggle({
    required IconData icon,
    required bool active,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: () {
          if (ref.read(progressRepositoryProvider).hapticsEnabled) {
            HapticFeedback.lightImpact();
          }
          onTap();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: active ? AppColors.accent : AppColors.surface,
            shape: BoxShape.circle,
            border: Border.all(
              color: active ? Colors.white : Colors.white24,
              width: 1.5,
            ),
          ),
          child: Icon(
            icon,
            size: 20,
            color: active ? Colors.black : AppColors.subtext,
          ),
        ),
      ),
    );
  }

  Widget _buildPlayRow({
    required String label,
    required VoidCallback onPlay,
    required VoidCallback onSelect,
    bool isSecondary = false,
  }) {
    return Row(
      children: [
        Expanded(
          child: TangibleButton(
            text: label,
            isSecondary: isSecondary,
            onPressed: onPlay,
          ),
        ),
        const SizedBox(width: 12),
        GestureDetector(
          onTap: () {
            if (ref.read(progressRepositoryProvider).hapticsEnabled) {
              HapticFeedback.lightImpact();
            }
            onSelect();
          },
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border, width: 1.5),
            ),
            child: const Icon(
              Icons.list_rounded,
              color: AppColors.headingDark,
              size: 24,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCenterArtwork(UserProgress? progress) {
    final completed = progress?.highestLevelCompleted ?? 0;
    if (completed == 0) {
      return Text(
        'COMPLETE A LEVEL\nTO SEE IT HERE',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w900,
          color: AppColors.subtext.withValues(alpha: 0.4),
          letterSpacing: 1.5,
          height: 1.6,
        ),
      );
    }

    final levels = ref.read(levelRepositoryProvider);
    if (completed < 1 || completed > levels.totalLevels) {
      // на всякий случай — если миграция ещё не отработала
      return const SizedBox.shrink();
    }

    final level = levels.getLevel(completed);

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 280, maxHeight: 280),
      child: AspectRatio(
        aspectRatio: level.width / level.height,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: AppColors.border, width: 1.5),
          ),
          child: CustomPaint(
            painter: _SolutionPainter(
              grid: level.solutionGrid,
              color: AppColors.accent,
              width: level.width,
              height: level.height,
            ),
          ),
        ),
      ),
    );
  }
}

class _SolutionPainter extends CustomPainter {
  _SolutionPainter({
    required this.grid,
    required this.color,
    required this.width,
    required this.height,
  });

  final List<List<bool>> grid;
  final Color color;
  final int width;
  final int height;

  @override
  void paint(Canvas canvas, Size canvasSize) {
    final cellW = canvasSize.width / width;
    final cellH = canvasSize.height / height;
    final paint = Paint()
      ..color = color
      ..isAntiAlias = false;

    for (int r = 0; r < height; r++) {
      for (int c = 0; c < width; c++) {
        if (grid[r][c]) {
          canvas.drawRect(
            Rect.fromLTWH(
              (c * cellW).roundToDouble(),
              (r * cellH).roundToDouble(),
              cellW.ceilToDouble(),
              cellH.ceilToDouble(),
            ),
            paint,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _SolutionPainter old) =>
      old.grid != grid ||
          old.color != color ||
          old.width != width ||
          old.height != height;
}
