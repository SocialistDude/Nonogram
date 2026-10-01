import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/progress_repository.dart';
import 'data/hive_service.dart';
import 'ui/app_theme.dart';
import 'ui/providers.dart';
import 'ui/screens/home/home_view.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final hiveService = HiveService();
  await hiveService.init();

  final progressRepository = ProgressRepository(hiveService: hiveService);

  // Миграция схемы
  if (hiveService.schemaVersion < HiveService.currentSchemaVersion) {
    debugPrint(
      '⚙️ Миграция: ${hiveService.schemaVersion} → '
          '${HiveService.currentSchemaVersion}',
    );
    await progressRepository.resetLevelsKeepSettings();
    await hiveService.setSchemaVersion(HiveService.currentSchemaVersion);
  }

  await progressRepository.getProgress();

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
  ));

  final container = ProviderContainer(
    overrides: [
      hiveServiceProvider.overrideWithValue(hiveService),
      progressRepositoryProvider.overrideWith((ref) => progressRepository),
    ],
  );

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const NonogramApp(),
    ),
  );

  final observer = _SyncLifecycleObserver(container);
  WidgetsBinding.instance.addObserver(observer);

  // Фоновая синхронизация. Не блокирует запуск.
  unawaited(
    container.read(remoteLevelsServiceProvider).sync().then((updated) {
      if (updated) {
        debugPrint('🔄 Есть новые уровни — пересоздаю LevelRepository');
        // Пересоздать провайдер → все виджеты, которые его watch,
        // получат новый инстанс и перерисуются.
        container.invalidate(levelRepositoryProvider);
        // Обновить прогресс, если он зависит от количества уровней
        container.read(homeViewModelProvider.notifier).loadProgress();
      }
    }),
  );
}

class _SyncLifecycleObserver extends WidgetsBindingObserver {
  _SyncLifecycleObserver(this.container);
  final ProviderContainer container;
  DateTime _lastSync = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    // Не чаще раза в 5 минут
    final now = DateTime.now();
    if (now.difference(_lastSync).inMinutes < 5) return;
    _lastSync = now;

    unawaited(
      container.read(remoteLevelsServiceProvider).sync().then((updated) {
        if (updated) {
          container.invalidate(levelRepositoryProvider);
        }
      }),
    );
  }
}

class NonogramApp extends StatelessWidget {
  const NonogramApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Nonogram',
      theme: AppTheme.darkTheme,
      home: const HomeView(),
      debugShowCheckedModeBanner: false,
    );
  }
}