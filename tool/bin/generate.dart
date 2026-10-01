import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:nonogram_tools/manifest.dart';
import 'package:nonogram_tools/png_reader.dart';
import 'package:nonogram_tools/solver.dart';

const String _projectRoot = '..';
const String _levelsDir = '$_projectRoot/assets/levels';
const String _pendingDir = '$_projectRoot/assets/levels_pending';
const String _manifestPath = '$_levelsDir/manifest.json';
const String _outPath = '$_projectRoot/lib/domain/levels/builtin_levels.dart';

/// Куда PUT-им manifest.json. Без авторизации.
const String _remoteUrl =
    'https://socialist-dude.didns.ru/webdav/Public/Nonogram/manifest.json';

void main(List<String> args) async {
  if (args.contains('-h') || args.contains('--help')) {
    stdout.writeln(_help);
    return;
  }
  final skipUpload = args.contains('--no-upload');

  final levelsDir = Directory(_levelsDir);
  final pendingDir = Directory(_pendingDir);
  final manifestFile = File(_manifestPath);

  // ── 1. Манифест ────────────────────────────────────────────
  LevelManifest manifest = LevelManifest.load(manifestFile);

  if (manifest.entries.isEmpty && levelsDir.existsSync()) {
    final existing = levelsDir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.toLowerCase().endsWith('.png'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));

    if (existing.isNotEmpty) {
      stdout.writeln('📄 Манифест не найден — засеваю из $_levelsDir/:');
      for (final f in existing) {
        final name = f.uri.pathSegments.last;
        final lv = readLevelPng(f);
        manifest.entries.add(LevelEntry(
          file: name,
          width: lv.width,
          height: lv.height,
        ));
        stdout.writeln('   + $name (${lv.width}×${lv.height})');
      }
    }
  }

  // ── 2. Проверка целостности манифеста ──────────────────────
  for (final e in manifest.entries) {
    final f = File('$_levelsDir/${e.file}');
    if (!f.existsSync()) {
      stderr.writeln(
        '❌ Манифест ссылается на ${e.file}, но файла нет в $_levelsDir/.',
      );
      exit(2);
    }
  }

  // ── 3. Pending ─────────────────────────────────────────────
  final pending = pendingDir.existsSync()
      ? (pendingDir
      .listSync()
      .whereType<File>()
      .where((f) => f.path.toLowerCase().endsWith('.png'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path)))
      : <File>[];

  final accepted = <({File file, String name, int width, int height})>[];

  if (pending.isNotEmpty) {
    stdout.writeln('🔍 Проверяю ${pending.length} новых уровней...\n');
    final existingNames = manifest.entries.map((e) => e.file).toSet();

    for (final f in pending) {
      final name = f.uri.pathSegments.last;

      if (existingNames.contains(name)) {
        stderr.writeln('❌ $name уже есть в $_levelsDir/.');
        exit(1);
      }

      try {
        final lv = readLevelPng(f);
        final s = countSolutions(lv.width, lv.height, lv.rowClues, lv.colClues);

        switch (s) {
          case 1:
            stdout.writeln('  ✅ $name  ${lv.width}×${lv.height}');
            accepted.add((
            file: f,
            name: name,
            width: lv.width,
            height: lv.height,
            ));
            break;
          case 0:
            stderr.writeln('  ❌ $name — нет решения');
            exit(1);
          case 2:
            stderr.writeln('  ⚠️  $name — решений ≥ 2');
            exit(1);
          default:
            stderr.writeln('  ❓ $name — прервано (timeout)');
            exit(1);
        }
      } catch (e) {
        stderr.writeln('  ❌ $name — $e');
        exit(1);
      }
    }

    stdout.writeln('\n📦 Переношу в $_levelsDir/:');
    for (final a in accepted) {
      a.file.renameSync('$_levelsDir/${a.name}');
      manifest.entries.add(LevelEntry(
        file: a.name,
        width: a.width,
        height: a.height,
      ));
      stdout.writeln('   → ${a.name}');
    }

    manifest.save(manifestFile);
  } else {
    stdout.writeln('ℹ️  Новых уровней нет — обновляю код и JSON.');
  }

  // ── 4. Генерация builtin_levels.dart ───────────────────────
  _writeBuiltin(levelsDir, manifest, File(_outPath));
  stdout.writeln('📝 Код: $_outPath');

  // ── 5. Публикация манифеста в WebDAV ───────────────────────
  if (skipUpload) {
    stdout.writeln('⏭  --no-upload: пропускаю заливку.');
    return;
  }

  final ok = await _uploadManifest(levelsDir, manifest);
  if (ok) {
    stdout.writeln('☁️  Залито: $_remoteUrl');
    stdout.writeln('\n✅ Готово. Уровней: ${manifest.entries.length}.');
  } else {
    stderr.writeln('⚠️  Локальная генерация прошла, но заливка не удалась.');
    exit(3);
  }
}

// ────────────────────────────────────────────────────────────────
// WebDAV upload
// ────────────────────────────────────────────────────────────────

Future<bool> _uploadManifest(
    Directory levelsDir,
    LevelManifest manifest,
    ) async {
  final payload = <String, dynamic>{
    'schemaVersion': 1,
    'levels': <Map<String, dynamic>>[],
  };

  final list = payload['levels'] as List<Map<String, dynamic>>;

  for (final entry in manifest.entries) {
    final lv = readLevelPng(File('${levelsDir.path}/${entry.file}'));
    final id = entry.file.replaceAll(RegExp(r'\.png$'), '');
    list.add({
      'id': id,
      'width': lv.width,
      'height': lv.height,
      'grid': lv.solutionGrid
          .map((row) => row.map((b) => b ? '1' : '0').join())
          .toList(),
    });
  }

  final body = const JsonEncoder.withIndent('  ').convert(payload);

  try {
    final resp = await http
        .put(
      Uri.parse(_remoteUrl),
      headers: {'Content-Type': 'application/json; charset=utf-8'},
      body: utf8.encode(body),
    )
        .timeout(const Duration(seconds: 30));

    if (resp.statusCode >= 200 && resp.statusCode < 300) {
      return true;
    }
    stderr.writeln(
      '   HTTP ${resp.statusCode}: ${resp.body.isNotEmpty ? resp.body : "(пусто)"}',
    );
    return false;
  } catch (e) {
    stderr.writeln('   $e');
    return false;
  }
}

// ────────────────────────────────────────────────────────────────
// builtin_levels.dart
// ────────────────────────────────────────────────────────────────

void _writeBuiltin(
    Directory levelsDir,
    LevelManifest manifest,
    File outFile,
    ) {
  final buf = StringBuffer();
  buf.writeln('// GENERATED FILE — DO NOT EDIT MANUALLY.');
  buf.writeln('// Generated by: cd tool && dart run bin/generate.dart');
  buf.writeln('// Source: assets/levels/*.png (order in manifest.json)');
  buf.writeln();
  buf.writeln("import '../game_level.dart';");
  buf.writeln();
  buf.writeln('final List<GameLevel> builtinLevels = [');

  for (int i = 0; i < manifest.entries.length; i++) {
    final entry = manifest.entries[i];
    final lv = readLevelPng(File('${levelsDir.path}/${entry.file}'));
    buf.writeln('  _build(${i + 1}, ${lv.width}, ${lv.height}, [');
    for (final row in lv.solutionGrid) {
      buf.writeln("    '${row.map((b) => b ? '1' : '0').join()}',");
    }
    buf.writeln('  ]),');
  }

  buf.writeln('];');
  buf.writeln();
  buf.writeln('/// ID вшитых уровней. Используется, чтобы не скачивать их повторно.');
  buf.writeln('const List<String> builtinLevelIds = [');
  for (final entry in manifest.entries) {
    final id = entry.file.replaceAll(RegExp(r'\.png$'), '');
    buf.writeln("  '$id',");
  }

  buf.writeln('];');
  buf.writeln();
  buf.writeln(_helpers);

  outFile.parent.createSync(recursive: true);
  outFile.writeAsStringSync(buf.toString());
}

const String _help = '''
Usage: dart run bin/generate.dart [--no-upload]

Читает PNG из assets/levels_pending/, проверяет на единственное решение,
переносит в assets/levels/, перегенерирует builtin_levels.dart и
PUT-ит manifest.json на WebDAV.

Флаги:
  --no-upload   Только локальная генерация, без заливки на сервер.
  -h, --help    Эта справка.

Имена PNG: любые, но с суффиксом _<W>x<H>.png (например car_16x16.png).
''';

const String _helpers = r'''
GameLevel _build(int levelNumber, int width, int height, List<String> rows) {
  final grid = rows
      .map((r) => r.split('').map((c) => c == '1').toList(growable: false))
      .toList(growable: false);
  return GameLevel(
    levelNumber: levelNumber,
    width: width,
    height: height,
    solutionGrid: grid,
    rowClues: _rowClues(grid, width, height),
    colClues: _colClues(grid, width, height),
  );
}

List<List<int>> _rowClues(List<List<bool>> grid, int width, int height) {
  final out = <List<int>>[];
  for (int r = 0; r < height; r++) {
    final clue = <int>[];
    int count = 0;
    for (int c = 0; c < width; c++) {
      if (grid[r][c]) {
        count++;
      } else if (count > 0) {
        clue.add(count);
        count = 0;
      }
    }
    if (count > 0) clue.add(count);
    out.add(clue.isEmpty ? [0] : clue);
  }
  return out;
}

List<List<int>> _colClues(List<List<bool>> grid, int width, int height) {
  final out = <List<int>>[];
  for (int c = 0; c < width; c++) {
    final clue = <int>[];
    int count = 0;
    for (int r = 0; r < height; r++) {
      if (grid[r][c]) {
        count++;
      } else if (count > 0) {
        clue.add(count);
        count = 0;
      }
    }
    if (count > 0) clue.add(count);
    out.add(clue.isEmpty ? [0] : clue);
  }
  return out;
}
''';