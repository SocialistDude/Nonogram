class LevelData {
  const LevelData({
    required this.width,
    required this.height,
    required this.solutionGrid,
    required this.rowClues,
    required this.colClues,
  });

  final int width;
  final int height;
  final List<List<bool>> solutionGrid;  // [height][width]
  final List<List<int>> rowClues;       // length = height
  final List<List<int>> colClues;       // length = width
}