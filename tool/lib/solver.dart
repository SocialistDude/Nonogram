/// Возвращает: 0 — нет решений, 1 — единственное, 2 — ≥2, -1 — таймаут.
int countSolutions(
    int width,
    int height,
    List<List<int>> rowClues,   // length = height
    List<List<int>> colClues,   // length = width
    {
      int maxSolutions = 2,
      Duration timeout = const Duration(minutes: 5),
    }) {
  final deadline = DateTime.now().add(timeout);
  int solutionsFound = 0;
  bool timedOut = false;

  // Пропагация: удаляет варианты, о которых точно известно, что они не подходят.
  // Возвращает null при противоречии.
  // Изменяет rowPoss и colPoss на месте.
  bool propagate(
      List<List<List<bool>>> rowPoss,
      List<List<List<bool>>> colPoss,
      ) {
    bool changed = true;
    while (changed) {
      changed = false;

      for (int r = 0; r < height; r++) {
        if (rowPoss[r].isEmpty) return false;
        for (int c = 0; c < width; c++) {
          bool allTrue = true, allFalse = true;
          for (final rp in rowPoss[r]) {
            if (rp[c]) {
              allFalse = false;
            } else {
              allTrue = false;
            }
            if (!allTrue && !allFalse) break;
          }
          if (allTrue || allFalse) {
            final target = allTrue;
            final prev = colPoss[c].length;
            colPoss[c].removeWhere((cp) => cp[r] != target);
            if (colPoss[c].length < prev) {
              changed = true;
              if (colPoss[c].isEmpty) return false;
            }
          }
        }
      }

      for (int c = 0; c < width; c++) {
        if (colPoss[c].isEmpty) return false;
        for (int r = 0; r < height; r++) {
          bool allTrue = true, allFalse = true;
          for (final cp in colPoss[c]) {
            if (cp[r]) {
              allFalse = false;
            } else {
              allTrue = false;
            }
            if (!allTrue && !allFalse) break;
          }
          if (allTrue || allFalse) {
            final target = allTrue;
            final prev = rowPoss[r].length;
            rowPoss[r].removeWhere((rp) => rp[c] != target);
            if (rowPoss[r].length < prev) {
              changed = true;
              if (rowPoss[r].isEmpty) return false;
            }
          }
        }
      }
    }
    return true;
  }

  void search(
      List<List<List<bool>>> rowPoss,
      List<List<List<bool>>> colPoss,
      ) {
    if (solutionsFound >= maxSolutions || timedOut) return;
    if (DateTime.now().isAfter(deadline)) {
      timedOut = true;
      return;
    }

    if (!propagate(rowPoss, colPoss)) return;

    // Все строки и столбцы имеют ровно один вариант — решение найдено.
    bool solved = true;
    for (int r = 0; r < height && solved; r++) {
      if (rowPoss[r].length != 1) solved = false;
    }
    for (int c = 0; c < width && solved; c++) {
      if (colPoss[c].length != 1) solved = false;
    }
    if (solved) {
      solutionsFound++;
      return;
    }

    // Выбираем строку с наименьшим числом вариантов > 1 (MRV-эвристика).
    int bestRow = -1;
    int bestCount = 1 << 30;
    for (int r = 0; r < height; r++) {
      final n = rowPoss[r].length;
      if (n > 1 && n < bestCount) {
        bestCount = n;
        bestRow = r;
      }
    }
    if (bestRow == -1) {
      // Все строки однозначны, но столбцы ещё нет — редкий случай,
      // считаем как решение (пропагация гарантирует корректность).
      solutionsFound++;
      return;
    }

    for (final candidate in rowPoss[bestRow]) {
      if (solutionsFound >= maxSolutions || timedOut) return;

      // Глубокая копия для ветвления.
      final newRow = List.generate(
        height,
            (i) => rowPoss[i].map((l) => List<bool>.from(l)).toList(),
      );
      final newCol = List.generate(
        width,
            (i) => colPoss[i].map((l) => List<bool>.from(l)).toList(),
      );

      // Фиксируем выбранную строку.
      newRow[bestRow] = [List<bool>.from(candidate)];

      search(newRow, newCol);
    }
  }

  final rowPoss = List.generate(
    height,
        (r) => _linePossibilities(height, rowClues[r]),
  );
  final colPoss = List.generate(
    width,
        (c) => _linePossibilities(width, colClues[c]),
  );

  search(rowPoss, colPoss);

  if (timedOut) return -1;
  return solutionsFound;
}

// _linePossibilities оставляем без изменений.

List<List<bool>> _linePossibilities(int size, List<int> clues) {
  final results = <List<bool>>[];
  if (clues.isEmpty || (clues.length == 1 && clues[0] == 0)) {
    results.add(List<bool>.filled(size, false));
    return results;
  }

  void build(int idx, int pos, List<bool> line) {
    if (idx == clues.length) {
      results.add(List<bool>.from(line));
      return;
    }
    final len = clues[idx];
    final remainingSum =
    clues.sublist(idx + 1).fold<int>(0, (a, b) => a + b);
    final remainingGaps = clues.length - 1 - idx;
    final maxStart = size - (remainingSum + remainingGaps) - len;

    for (int start = pos; start <= maxStart; start++) {
      for (int i = start; i < start + len; i++) {
        line[i] = true;
      }
      build(idx + 1, start + len + 1, line);
      for (int i = start; i < start + len; i++) {
        line[i] = false;
      }
    }
  }

  build(0, 0, List<bool>.filled(size, false));
  return results;
}