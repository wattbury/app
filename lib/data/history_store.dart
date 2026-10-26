// Files on native platforms; browser storage on the web, which has no file system.
export 'history_store_io.dart' if (dart.library.js_interop) 'history_store_web.dart';

/// Where [HistoryCache] keeps its month documents (JSON, keyed "2026-10").
abstract interface class HistoryStore {
  Future<String?> read(String month);
  Future<void> write(String month, String json);

  /// All stored months with their size in bytes.
  Future<Map<String, int>> list();
  Future<void> clear();
}
