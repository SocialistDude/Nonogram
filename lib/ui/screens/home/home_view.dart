import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../app_theme.dart';
import '../../widgets/tangible_button.dart';
import '../../widgets/solution_painter.dart';
import '../game/game_view.dart';
import '../level_select/level_select_view.dart';
import '../../providers.dart';
import '../../../domain/user_progress.dart';

class HomeView extends ConsumerStatefulWidget {
  const HomeView({super.key});

  @override
  ConsumerState<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends ConsumerState<HomeView> {
  @override
  void initState() {
    super.initState();
  }

  Future<void> _openBank(BuildContext context) async {
    final levels = ref.read(levelRepositoryProvider);
    final raw = ref.read(homeViewModelProvider).progress?.currentLevel ?? 1;
    final startLevel = raw.clamp(1, levels.totalLevels);

    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => GameView(levelNumber: startLevel)),
    );

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

  Future<void> _showInfoDialog(BuildContext context) {
    final progress = ref.read(homeViewModelProvider).progress;
    return showDialog<void>(
      context: context,
      builder: (_) => _InfoDialog(progress: progress),
    );
  }

  Future<void> _confirmResetProgress(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
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
                'RESET PROGRESS?',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: AppColors.headingDark,
                  letterSpacing: 1.0,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Весь прогресс будет удалён: текущий уровень, лучшие '
                    'результаты и сохранённая партия. Настройки (вибрация, '
                    'автокресты) сохранятся.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  color: AppColors.subtext,
                ),
              ),
              const SizedBox(height: 24),
              TangibleButton(
                text: 'Reset',
                onPressed: () => Navigator.pop(dialogContext, true),
              ),
              const SizedBox(height: 10),
              TangibleButton(
                text: 'Cancel',
                isSecondary: true,
                onPressed: () => Navigator.pop(dialogContext, false),
              ),
            ],
          ),
        ),
      ),
    );

    if (confirmed != true) return;

    final repo = ref.read(progressRepositoryProvider);
    final haptics = repo.hapticsEnabled;
    final autoCross = repo.autoCrossEnabled;

    await repo.resetProgress();

    // resetProgress в репозитории обнуляет всё, включая настройки —
    // возвращаем их обратно.
    final restored = (await repo.getProgress()).copyWith(
      hapticsEnabled: haptics,
      autoCrossEnabled: autoCross,
    );
    await repo.saveProgress(restored);

    if (!mounted) return;
    ref.read(homeViewModelProvider.notifier).loadProgress();

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Прогресс сброшен'),
          duration: Duration(seconds: 2),
          backgroundColor: AppColors.surface,
        ),
      );
    }
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
                      const SizedBox(width: 8),
                      _buildPlainIconButton(
                        icon: Icons.info_outline_rounded,
                        tooltip: 'About',
                        onTap: () => _showInfoDialog(context),
                      ),
                      const SizedBox(width: 8),
                      _buildPlainIconButton(
                        icon: Icons.restart_alt_rounded,
                        tooltip: 'Reset progress',
                        onTap: () => _confirmResetProgress(context),
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

  Widget _buildPlainIconButton({
    required IconData icon,
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
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.surface,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white24, width: 1.5),
          ),
          child: Icon(icon, size: 20, color: AppColors.subtext),
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
      return Text('COMPLETE A LEVEL\nTO SEE IT HERE',
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
    if (completed > levels.totalLevels) return const SizedBox.shrink();

    // Какой уровень рисовать: последний пройденный, либо highest
    // для старых сохранений без этого поля.
    final targetNumber = (progress?.lastCompletedLevel ?? completed)
        .clamp(1, levels.totalLevels);
    final level = levels.getLevel(targetNumber);

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
            painter: SolutionPainter(
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

class _InfoDialog extends StatelessWidget {
  const _InfoDialog({required this.progress});

  final UserProgress? progress;

  static const String _githubOwner = 'https://github.com/SocialistDude/Nonogram';
  static const String _githubOriginal = 'https://github.com/sidhant947/Nonogram';

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 640),
        decoration: BoxDecoration(
          color: AppColors.bg,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppColors.border, width: 1.5),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 12, 0),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'ABOUT',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: AppColors.headingDark,
                        letterSpacing: 1.0,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded,
                        color: AppColors.subtext),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _sectionTitle('GAME'),
                    _paragraph(
                      'Nonogram (японский кроссворд) — логическая '
                          'головоломка. Числа у каждой строки и столбца '
                          'показывают длины блоков подряд идущих закрашенных '
                          'клеток в этой линии. Между блоками должна быть '
                          'минимум одна пустая клетка. Рисунок определяется '
                          'однозначно, если пазл составлен корректно.',
                    ),

                    const SizedBox(height: 20),
                    _sectionTitle('STATS'),
                    _kv('Уровней пройдено', '${progress?.highestLevelCompleted ?? 0}'),
                    _kv('Всего ходов', '${progress?.totalMoves ?? 0}'),

                    const SizedBox(height: 20),
                    _sectionTitle('CONTROLS'),
                    _bullet('Тап по клетке — переключить её состояние.'),
                    _bullet('Свайп — быстро закрасить линию. '
                        'Направление фиксируется по первому движению.'),
                    _bullet('Кнопка FILL / CROSS — выбрать режим рисования.'),
                    _bullet('Свайп по уже закрашенной клетке в том же '
                        'режиме — стирание.'),
                    _bullet('Два пальца — зум и перемещение поля.'),
                    _bullet('Undo — откатить последнее действие (до 50 шагов).'),
                    _bullet('Hint — режим подсказки: клетки ставятся в '
                        'правильное состояние по тапу.'),
                    _bullet('Vibration и Auto-cross — переключатели в '
                        'главном меню.'),

                    const SizedBox(height: 20),
                    _sectionTitle('LINK'),
                    _link(
                      context,
                      'Текущая версия: SocialistDude',
                      _githubOwner,
                    ),
                    const SizedBox(height: 4),
                    _link(
                      context,
                      'Оригинальная идея: sidhant947',
                      _githubOriginal,
                    ),

                    const SizedBox(height: 20),
                    _sectionTitle('CHANGES'),
                    _bullet('Убраны бесконечные процедурные уровни — '
                        'теперь фиксированный набор, нарисованный вручную.'),
                    _bullet('Добавлена поддержка прямоугольных сеток.'),
                    _bullet('Свайп-рисование по строкам и столбцам.'),
                    _bullet('Undo, автокресты, режим подсказки.'),
                    _bullet('Тёмная тема, шрифт Bebas Neue.'),
                    _bullet('Возможность подгрузки новых уровней '
                        'без обновления приложения.'),

                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w900,
          color: AppColors.subtext,
          letterSpacing: 1.5,
        ),
      ),
    );
  }

  Widget _paragraph(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 13,
        height: 1.5,
        color: AppColors.headingDark,
      ),
    );
  }

  Widget _bullet(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 6, right: 8),
            child: SizedBox(
              width: 4,
              height: 4,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: AppColors.subtext,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
          Expanded(child: _paragraph(text)),
        ],
      ),
    );
  }

  Widget _link(BuildContext context, String label, String url) {
    return GestureDetector(
      onTap: () async {
        final uri = Uri.parse(url);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      },
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 13,
          height: 1.5,
          color: Color(0xFF38BDF8),
          decoration: TextDecoration.underline,
          decorationColor: Color(0xFF38BDF8),
        ),
      ),
    );
  }

  Widget _kv(String key, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              key,
              style: const TextStyle(color: AppColors.subtext, fontSize: 13),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: AppColors.headingDark,
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
