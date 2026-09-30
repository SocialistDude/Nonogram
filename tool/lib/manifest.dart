import 'dart:convert';
import 'dart:io';

class LevelEntry {
  LevelEntry({
    required this.file,
    required this.width,
    required this.height,
  });

  final String file;
  final int width;
  final int height;

  Map<String, dynamic> toJson() =>
      {'file': file, 'width': width, 'height': height};

  factory LevelEntry.fromJson(Map<String, dynamic> j) => LevelEntry(
    file: j['file'] as String,
    width: j['width'] as int,
    height: j['height'] as int,
  );
}

class LevelManifest {
  LevelManifest(this.entries);

  final List<LevelEntry> entries;

  static LevelManifest load(File file) {
    if (!file.existsSync()) return LevelManifest([]);
    final raw = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    final list = (raw['levels'] as List).cast<Map<String, dynamic>>();
    return LevelManifest(list.map(LevelEntry.fromJson).toList());
  }

  void save(File file) {
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert({
        'levels': entries.map((e) => e.toJson()).toList(),
      }),
    );
  }
}