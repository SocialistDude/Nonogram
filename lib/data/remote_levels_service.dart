import 'dart:convert';
import 'package:http/http.dart' as http;
import '../domain/remote_level.dart';
import '../domain/levels/builtin_levels.dart';
import 'hive_service.dart';

class RemoteLevelsService {
  RemoteLevelsService({
    required this.hiveService,
    required this.manifestUrl,
  });

  final HiveService hiveService;
  final String manifestUrl;

  static const Duration _timeout = Duration(seconds: 10);

  /// Возвращает true, если появились новые уровни и кеш надо обновить.
  Future<bool> sync() async {
    try {
      final resp = await http.get(Uri.parse(manifestUrl)).timeout(_timeout);
      if (resp.statusCode != 200) return false;

      final body = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
      final remoteLevels = (body['levels'] as List)
          .cast<Map<String, dynamic>>()
          .map(RemoteLevel.fromJson)
          .toList();

      final existing = hiveService.loadRemoteLevels();
      final existingIds = existing.map((l) => l.id).toSet();
      final builtinIds = builtinLevelIds.toSet();

      // Новые = есть на сервере, но нет ни в Hive, ни среди вшитых.
      final fresh = remoteLevels
          .where((l) => !existingIds.contains(l.id))
          .where((l) => !builtinIds.contains(l.id))
          .toList();

      if (fresh.isEmpty) return false;

      await hiveService.saveRemoteLevels([...existing, ...fresh]);
      return true;
    } catch (_) {
      return false;
    }
  }
}