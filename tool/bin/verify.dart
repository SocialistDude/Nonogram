import 'dart:io';
import 'package:nonogram_tools/clues.dart'; // ← на самом деле не нужен, но оставим для переиспользования
import 'package:nonogram_tools/png_reader.dart';
import 'package:nonogram_tools/solver.dart';

void main(List<String> args) {
  final dirPath = args.isNotEmpty ? args[0] : '../assets/levels_pending';
  final dir = Directory(dirPath);
  if (!dir.existsSync()) {
    stderr.writeln('Папка не найдена: $dirPath');
    exit(2);
  }

  final files = dir
      .listSync()
      .whereType<File>()
      .where((f) => f.path.toLowerCase().endsWith('.png'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  if (files.isEmpty) {
    stderr.writeln('В $dirPath нет PNG-файлов.');
    exit(2);
  }

  print('Проверяю ${files.length} уровней из $dirPath\n');

  int failed = 0;
  for (int i = 0; i < files.length; i++) {
    final f = files[i];
    final name = f.uri.pathSegments.last;
    try {
      final lv = readLevelPng(f);
      final solutions = countSolutions(lv.width, lv.height, lv.rowClues, lv.colClues);

      final String status;
      switch (solutions) {
        case 0:
          status = '❌ нет решения';
          failed++;
          break;
        case 1:
          status = '✅ OK';
          break;
        case 2:
          status = '⚠️  решений ≥ 2 (неоднозначный)';
          failed++;
          break;
        default:
          status = '❓ прервано (maxStates) — упростите пазл';
          failed++;
      }

      final emptyRows =
          lv.rowClues.where((c) => c.length == 1 && c[0] == 0).length;
      final emptyCols =
          lv.colClues.where((c) => c.length == 1 && c[0] == 0).length;

      print('${name.padRight(24)} '
          '${lv.width}x${lv.height}  '
          'emptyRows=$emptyRows emptyCols=$emptyCols  $status');
    } catch (e) {
      failed++;
      print('${name.padRight(24)} ❌ ошибка чтения: $e');
    }
  }

  print('\nПровалено: $failed из ${files.length}');
  exit(failed == 0 ? 0 : 1);
}