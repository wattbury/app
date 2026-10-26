import 'dart:convert';
import 'dart:io';

import 'history.dart';

/// Persistent store for finished history: past values never change, so fetching them again only
/// loads the unit (and the portal). One JSON file per month holds the daily values of the whole
/// month, once it is over, and the hourly values of each finished day that has been loaded.
class HistoryCache {
  /// Folder for the month files; null keeps everything in memory only (tests, unsupported platforms).
  final Directory? dir;
  final _months = <String, _MonthFile>{};

  HistoryCache(this.dir);

  static String _mkey(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}';
  static String _dkey(DateTime d) => '${_mkey(d)}-${d.day.toString().padLeft(2, '0')}';

  Future<_MonthFile> _month(DateTime d) async {
    final k = _mkey(d);
    final cached = _months[k];
    if (cached != null) return cached;
    var m = _MonthFile();
    final f = _file(k);
    if (f != null && await f.exists()) {
      try {
        m = _MonthFile.fromJson(jsonDecode(await f.readAsString()) as Map<String, dynamic>);
      } catch (_) {
        // A damaged file is dropped; the data is fetched again.
      }
    }
    return _months[k] = m;
  }

  File? _file(String monthKey) => dir == null ? null : File('${dir!.path}/$monthKey.json');

  Future<void> _save(DateTime d) async {
    final f = _file(_mkey(d));
    if (f == null) return;
    await f.parent.create(recursive: true);
    // Write to a temporary file first, so an interrupted write never leaves a broken month.
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(jsonEncode(_months[_mkey(d)]!.toJson()));
    await tmp.rename(f.path);
  }

  /// Daily values of a finished month, or null.
  Future<List<HistoryPoint>?> days(DateTime month) async => (await _month(month)).days;

  Future<void> putDays(DateTime month, List<HistoryPoint> points) async {
    (await _month(month)).days = points;
    await _save(month);
  }

  /// Hourly values of a finished day, or null.
  Future<List<HistoryPoint>?> hours(DateTime day) async => (await _month(day)).hours[_dkey(day)];

  Future<void> putHours(DateTime day, List<HistoryPoint> points) async {
    (await _month(day)).hours[_dkey(day)] = points;
    await _save(day);
  }

  /// What is stored: complete months, days with hourly values, size on disk.
  Future<({int months, int days, int bytes})> stats() async {
    final d = dir;
    if (d == null || !await d.exists()) {
      return (
        months: _months.values.where((m) => m.days != null).length,
        days: _months.values.fold(0, (a, m) => a + m.hours.length),
        bytes: 0,
      );
    }
    var months = 0, days = 0, bytes = 0;
    await for (final e in d.list()) {
      if (e is! File || !e.path.endsWith('.json')) continue;
      bytes += await e.length();
      final key = e.uri.pathSegments.last.replaceAll('.json', '');
      final parts = key.split('-');
      final m = await _month(DateTime(int.parse(parts[0]), int.parse(parts[1])));
      if (m.days != null) months++;
      days += m.hours.length;
    }
    return (months: months, days: days, bytes: bytes);
  }

  Future<void> clear() async {
    _months.clear();
    final d = dir;
    if (d != null && await d.exists()) await d.delete(recursive: true);
  }
}

class _MonthFile {
  List<HistoryPoint>? days;
  final Map<String, List<HistoryPoint>> hours;
  _MonthFile({this.days, Map<String, List<HistoryPoint>>? hours}) : hours = hours ?? {};

  static List<Object> _enc(List<HistoryPoint> ps) => [
    for (final p in ps)
      [
        p.start.toIso8601String(),
        p.solar.round(),
        p.purchase.round(),
        p.batteryOut.round(),
        p.house.round(),
        p.feedIn.round(),
        p.batteryIn.round(),
      ],
  ];

  static List<HistoryPoint> _dec(List<dynamic> l) => [
    for (final x in l)
      HistoryPoint(
        start: DateTime.parse(x[0] as String),
        solar: (x[1] as num).toDouble(),
        purchase: (x[2] as num).toDouble(),
        batteryOut: (x[3] as num).toDouble(),
        house: (x[4] as num).toDouble(),
        feedIn: (x[5] as num).toDouble(),
        batteryIn: (x[6] as num).toDouble(),
      ),
  ];

  Map<String, Object?> toJson() => {
    'v': 1,
    'days': days == null ? null : _enc(days!),
    'hours': {for (final e in hours.entries) e.key: _enc(e.value)},
  };

  static _MonthFile fromJson(Map<String, dynamic> j) => _MonthFile(
    days: j['days'] == null ? null : _dec(j['days'] as List),
    hours: {for (final e in (j['hours'] as Map<String, dynamic>).entries) e.key: _dec(e.value as List)},
  );
}
