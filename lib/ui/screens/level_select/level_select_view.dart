import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app_theme.dart';
import '../../providers.dart';
import '../game/game_view.dart';
import '../../../domain/game_level.dart';
import '../../widgets/solution_painter.dart';

class LevelSelectView extends ConsumerWidget {
  const LevelSelectView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final homeState = ref.watch(homeViewModelProvider);
    final highestCompleted = homeState.progress?.highestLevelCompleted ?? 0;
    final repo = ref.watch(levelRepositoryProvider);

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'SELECT LEVEL',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w900,
            color: AppColors.headingDark,
            letterSpacing: 1.0,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.headingDark),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: GridView.builder(
          padding: const EdgeInsets.all(24),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 4,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            childAspectRatio: 1.0,
          ),
          itemCount: repo.totalLevels,
          itemBuilder: (context, index) {
            final levelNumber = index + 1;
            final isUnlocked = levelNumber <= highestCompleted + 1;
            final isCompleted = levelNumber <= highestCompleted;

            GameLevel? level;
            if (isCompleted && levelNumber <= repo.totalLevels) {
              level = repo.getLevel(levelNumber);
            }

            return GestureDetector(
              onTap: isUnlocked
                  ? () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => GameView(levelNumber: levelNumber),
                  ),
                );
                ref.read(homeViewModelProvider.notifier).loadProgress();
              }
                  : null,
              child: Container(
                decoration: BoxDecoration(
                  color: isCompleted
                      ? AppColors.surface
                      : (isUnlocked
                      ? AppColors.surface.withValues(alpha: 0.6)
                      : AppColors.surface.withValues(alpha: 0.3)),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isCompleted
                        ? AppColors.accent
                        : (isUnlocked ? AppColors.border : Colors.transparent),
                    width: isCompleted ? 2 : 1.5,
                  ),
                ),
                child: Stack(
                  children: [
                    // Превью решения
                    if (level != null)
                      Positioned.fill(
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: CustomPaint(
                            painter: SolutionPainter(
                              grid: level.solutionGrid,
                              color: AppColors.accent,
                              width: level.width,
                              height: level.height,
                            ),
                          ),
                        ),
                      ),

                    // Номер уровня в углу
                    Positioned(
                      top: 6,
                      left: 8,
                      child: Text(
                        '$levelNumber',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                          color: isUnlocked
                              ? AppColors.headingDark
                              : AppColors.subtext,
                        ),
                      ),
                    ),

                    // Замок для закрытых
                    if (!isUnlocked)
                      const Center(
                        child: Icon(
                          Icons.lock_rounded,
                          color: AppColors.subtext,
                          size: 20,
                        ),
                      ),

                    // Галочка для выполненных
                    if (isCompleted)
                      Positioned(
                        bottom: 6,
                        right: 6,
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: const BoxDecoration(
                            color: AppColors.accent,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.check_rounded,
                            size: 12,
                            color: Colors.black,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
