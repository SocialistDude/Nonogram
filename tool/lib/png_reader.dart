import 'dart:io';
import 'package:image/image.dart' as img;
import 'clues.dart';
import 'level_data.dart';

const int _blackThreshold = 128;
const int _minSide = 3;
const int _maxSide = 32;

LevelData readLevelPng(File file) {
  final (width, height) = _parseDimensionsFromName(file.path);

  final decoded = img.decodeImage(file.readAsBytesSync());
  if (decoded == null) {
    throw StateError('Не удалось декодировать ${file.path}');
  }
  if (decoded.width < width || decoded.height < height) {
    throw StateError(
      'Картинка ${decoded.width}x${decoded.height} меньше сетки '
          '${width}x$height — невозможно нарезать',
    );
  }

  final cellW = decoded.width / width;
  final cellH = decoded.height / height;

  final grid = List.generate(
    height,
        (r) => List.generate(width, (c) {
      final px = ((c + 0.5) * cellW).floor().clamp(0, decoded.width - 1);
      final py = ((r + 0.5) * cellH).floor().clamp(0, decoded.height - 1);
      final pixel = decoded.getPixel(px, py);
      final lum = 0.299 * pixel.r + 0.587 * pixel.g + 0.114 * pixel.b;
      return lum < _blackThreshold;
    }),
  );

  return LevelData(
    width: width,
    height: height,
    solutionGrid: grid,
    rowClues: computeRowClues(grid, width, height),
    colClues: computeColClues(grid, width, height),
  );
}

(int, int) _parseDimensionsFromName(String path) {
  final name = path.split(Platform.pathSeparator).last;
  final match =
  RegExp(r'_(\d+)x(\d+)\.png$', caseSensitive: false).firstMatch(name);
  if (match == null) {
    throw ArgumentError(
      'Имя файла должно заканчиваться на _<W>x<H>.png\n'
          'Например: car_16x16.png, road_32x24.png\n'
          'Получено: "$name"',
    );
  }
  final w = int.parse(match.group(1)!);
  final h = int.parse(match.group(2)!);
  if (w < _minSide || w > _maxSide || h < _minSide || h > _maxSide) {
    throw ArgumentError(
      'Стороны сетки должны быть в диапазоне $_minSide..$_maxSide: "$name"',
    );
  }
  // Soft-warning, если хотя бы одна сторона не кратна 4.
  if (w % 4 != 0 || h % 4 != 0) {
    stderr.writeln(
      '   ⚠️  $name: стороны $w×$h не кратны 4 — '
          'разделители сетки в игре лягут неровно в последней группе',
    );
  }
  return (w, h);
}