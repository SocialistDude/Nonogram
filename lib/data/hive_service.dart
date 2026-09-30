import 'package:hive_flutter/hive_flutter.dart';
import '../domain/user_progress.dart';
import 'user_progress_adapter.dart';

class HiveService {
  static const String _progressBoxName = 'nonogram_user_progress';
  static const String _metaBoxName = 'nonogram_meta';
  static const String _progressKey = 'progress';
  static const String _versionKey = 'schema_version';

  /// 1 — старые версии с бесконечным генератором (1..∞)
  /// 2 — фиксированный список PNG-уровней
  static const int currentSchemaVersion = 2;

  late Box<UserProgress> _progressBox;
  late Box _metaBox;

  Future<void> init() async {
    await Hive.initFlutter();
    Hive.registerAdapter(UserProgressAdapter());
    _progressBox = await Hive.openBox<UserProgress>(_progressBoxName);
    _metaBox = await Hive.openBox(_metaBoxName);
  }

  int get schemaVersion =>
      _metaBox.get(_versionKey, defaultValue: 1) as int;

  Future<void> setSchemaVersion(int value) =>
      _metaBox.put(_versionKey, value);

  Future<UserProgress> getProgress() async {
    return _progressBox.get(_progressKey) ?? const UserProgress();
  }

  Future<void> saveProgress(UserProgress progress) async {
    await _progressBox.put(_progressKey, progress);
  }

  Future<void> clearProgress() async {
    await _progressBox.delete(_progressKey);
  }
}