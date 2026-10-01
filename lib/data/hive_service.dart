import 'dart:convert';
import 'package:hive_flutter/hive_flutter.dart';
import '../domain/user_progress.dart';
import '../domain/remote_level.dart';
import 'user_progress_adapter.dart';

class HiveService {
  static const String _progressBoxName = 'nonogram_user_progress';
  static const String _metaBoxName = 'nonogram_meta';
  static const String _progressKey = 'progress';
  static const String _versionKey = 'schema_version';
  static const String _remoteLevelsKey = 'remote_levels_json';

  static const int currentSchemaVersion = 2;

  late Box<UserProgress> _progressBox;
  late Box _metaBox;

  Future<void> init() async {
    await Hive.initFlutter();
    Hive.registerAdapter(UserProgressAdapter());
    _progressBox = await Hive.openBox<UserProgress>(_progressBoxName);
    _metaBox = await Hive.openBox(_metaBoxName);
  }

  // ─── schema version ───────────────────────────────────────
  int get schemaVersion =>
      _metaBox.get(_versionKey, defaultValue: 1) as int;

  Future<void> setSchemaVersion(int v) => _metaBox.put(_versionKey, v);

  // ─── прогресс ─────────────────────────────────────────────
  Future<UserProgress> getProgress() async =>
      _progressBox.get(_progressKey) ?? const UserProgress();

  Future<void> saveProgress(UserProgress p) =>
      _progressBox.put(_progressKey, p);

  Future<void> clearProgress() => _progressBox.delete(_progressKey);

  // ─── скачанные уровни ─────────────────────────────────────
  List<RemoteLevel> loadRemoteLevels() {
    final raw = _metaBox.get(_remoteLevelsKey) as String?;
    if (raw == null || raw.isEmpty) return const [];
    try {
      final parsed = (jsonDecode(raw) as List)
          .cast<Map<String, dynamic>>()
          .map(RemoteLevel.fromJson)
          .toList();

      // Дедупликация по id — на случай, если в старых сборках
      // случайно сохранились повторные записи.
      final seen = <String>{};
      final unique = <RemoteLevel>[];
      for (final l in parsed) {
        if (seen.add(l.id)) unique.add(l);
      }
      return unique;
    } catch (_) {
      return const [];
    }
  }

  Future<void> saveRemoteLevels(List<RemoteLevel> levels) {
    final json = jsonEncode(levels.map((l) => l.toJson()).toList());
    return _metaBox.put(_remoteLevelsKey, json);
  }
}