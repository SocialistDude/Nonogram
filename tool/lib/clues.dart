List<List<int>> computeRowClues(List<List<bool>> grid, int width, int height) {
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

List<List<int>> computeColClues(List<List<bool>> grid, int width, int height) {
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