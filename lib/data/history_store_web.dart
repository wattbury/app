import 'package:shared_preferences/shared_preferences.dart';

import 'history_store.dart';

/// In the browser the months go to local storage, one entry per month, prefixed per system.
Future<HistoryStore Function(String id)?> openHistoryStorage() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    return (id) => PrefsHistoryStore(prefs, 'history/$id/');
  } catch (_) {
    return null;
  }
}

class PrefsHistoryStore implements HistoryStore {
  final SharedPreferences prefs;
  final String prefix;
  PrefsHistoryStore(this.prefs, this.prefix);

  Iterable<String> get _keys => prefs.getKeys().where((k) => k.startsWith(prefix));

  @override
  Future<String?> read(String month) async => prefs.getString('$prefix$month');

  @override
  Future<void> write(String month, String json) => prefs.setString('$prefix$month', json);

  @override
  Future<Map<String, int>> list() async => {
    for (final k in _keys) k.substring(prefix.length): prefs.getString(k)?.length ?? 0,
  };

  @override
  Future<void> clear() async {
    for (final k in _keys.toList()) {
      await prefs.remove(k);
    }
  }
}
