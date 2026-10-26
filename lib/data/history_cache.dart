import 'dart:convert';

import 'history.dart';
import 'history_store.dart';

/// Persistent store for finished history: past values never change, so fetching them again only
/// loads the unit (and the portal). One JSON document per month holds the daily values of the whole
/// month, once it is over, and the hourly values of each finished day that has been loaded.
class HistoryCache {
  /// Where the months are kept; null keeps everything in memory only (tests, unsupported platforms).
  final HistoryStore? store;
  final _months = <String, _MonthFile>{};

  HistoryCache(this.store);

  static String _mkey(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}';
  static String _dkey(DateTime d) => '${_mkey(d)}-${d.day.toString().padLeft(2, '0')}';

  Future<_MonthFile> _month(DateTime d) async {
    final k = _mkey(d);
    final cached = _months[k];
    if (cached != null) return cached;
    var m = _MonthFile();
    final raw = await store?.read(k);
    if (raw != null) {
      try {
        m = _MonthFile.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      } catch (_) {
        // A damaged file is dropped; the data is fetched again.
      }
    }
    return _months[k] = m;
  }

  Future<void> _save(DateTime d) async => await store?.write(_mkey(d), jsonEncode(_months[_mkey(d)]!.toJson()));

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
    final stored = await store?.list() ?? const {};
    if (stored.isEmpty) {
      return (
        months: _months.values.where((m) => m.days != null).length,
        days: _months.values.fold(0, (a, m) => a + m.hours.length),
        bytes: 0,
      );
    }
    var months = 0, days = 0, bytes = 0;
    for (final MapEntry(:key, :value) in stored.entries) {
      bytes += value;
      final parts = key.split('-');
      final m = await _month(DateTime(int.parse(parts[0]), int.parse(parts[1])));
      if (m.days != null) months++;
      days += m.hours.length;
    }
    return (months: months, days: days, bytes: bytes);
  }

  Future<void> clear() async {
    _months.clear();
    await store?.clear();
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
