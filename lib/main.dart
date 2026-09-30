import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/hive_service.dart';
import 'ui/app_theme.dart';
import 'ui/providers.dart';
import 'ui/screens/home/home_view.dart';
import 'data/progress_repository.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final hiveService = HiveService();
  await hiveService.init();

  final progressRepository = ProgressRepository(hiveService: hiveService);

  // ─── Миграция схемы ───────────────────────────────────────────
  if (hiveService.schemaVersion < HiveService.currentSchemaVersion) {
    debugPrint(
      '⚙️ Миграция схемы: ${hiveService.schemaVersion} → '
          '${HiveService.currentSchemaVersion}. Сбрасываю прогресс уровней.',
    );
    await progressRepository.resetLevelsKeepSettings();
    await hiveService.setSchemaVersion(HiveService.currentSchemaVersion);
  }
  // ──────────────────────────────────────────────────────────────

  await progressRepository.getProgress(); // прогрев кеша

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
  ));

  runApp(
    ProviderScope(
      overrides: [
        hiveServiceProvider.overrideWithValue(hiveService),
        progressRepositoryProvider.overrideWith((ref) => progressRepository),
      ],
      child: const NonogramApp(),
    ),
  );
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
