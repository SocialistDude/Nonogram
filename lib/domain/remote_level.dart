import 'package:flutter/foundation.dart';
import 'game_level.dart';

@immutable
class RemoteLevel {
  const RemoteLevel({
    required this.id,
    required this.width,
    required this.height,
    required this.gridRows,
  });

  final String id;
  final int width;
  final int height;
  final List<String> gridRows;

  GameLevel toGameLevel(int levelNumber) {
    final grid = gridRows
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

  Map<String, dynamic> toJson() => {
    'id': id,
    'width': width,
    'height': height,
    'grid': gridRows,
  };

  factory RemoteLevel.fromJson(Map<String, dynamic> j) => RemoteLevel(
    id: j['id'] as String,
    width: j['width'] as int,
    height: j['height'] as int,
    gridRows: (j['grid'] as List).cast<String>(),
  );

  static List<List<int>> _rowClues(List<List<bool>> g, int w, int h) {
    final out = <List<int>>[];
    for (int r = 0; r < h; r++) {
      final clue = <int>[];
      int count = 0;
      for (int c = 0; c < w; c++) {
        if (g[r][c]) {
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

  static List<List<int>> _colClues(List<List<bool>> g, int w, int h) {
    final out = <List<int>>[];
    for (int c = 0; c < w; c++) {
      final clue = <int>[];
      int count = 0;
      for (int r = 0; r < h; r++) {
        if (g[r][c]) {
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
}