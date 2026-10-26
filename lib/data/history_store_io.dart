import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'history_store.dart';

/// One store per system below the app support folder; null when there is none (history then stays in memory).
Future<HistoryStore Function(String id)?> openHistoryStorage() async {
  try {
    final base = await getApplicationSupportDirectory();
    return (id) => FileHistoryStore(Directory('${base.path}/history/$id'));
  } catch (_) {
    return null;
  }
}

/// One JSON file per month in [dir].
class FileHistoryStore implements HistoryStore {
  final Directory dir;
  FileHistoryStore(this.dir);

  File _file(String month) => File('${dir.path}/$month.json');

  @override
  Future<String?> read(String month) async {
    final f = _file(month);
    return await f.exists() ? f.readAsString() : null;
  }

  @override
  Future<void> write(String month, String json) async {
    final f = _file(month);
    await f.parent.create(recursive: true);
    // Write to a temporary file first, so an interrupted write never leaves a broken month.
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(json);
    await tmp.rename(f.path);
  }

  @override
  Future<Map<String, int>> list() async {
    if (!await dir.exists()) return {};
    return {
      await for (final e in dir.list())
        if (e is File && e.path.endsWith('.json')) e.uri.pathSegments.last.replaceAll('.json', ''): await e.length(),
    };
  }

  @override
  Future<void> clear() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  }
}
