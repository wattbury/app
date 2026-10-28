import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openrscp/openrscp.dart';
import 'package:wattbury/data/energy_source.dart';
import 'package:wattbury/data/history.dart';
import 'package:wattbury/data/history_cache.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wattbury/data/history_store_io.dart';
import 'package:wattbury/data/history_store_web.dart';

/// Demo unit that counts database requests.
class CountingSource extends DemoSource {
  int requests = 0;
  CountingSource(DateTime now) : super(clock: () => now);
  @override
  Future<DbHistory> history(DateTime start, Duration interval, Duration span) {
    requests++;
    return super.history(start, interval, span);
  }
}

void main() {
  final now = DateTime(2026, 10, 26, 12);
  late Directory dir;
  setUp(() async => dir = await Directory.systemTemp.createTemp('wattbury-cache'));
  tearDown(() => dir.delete(recursive: true));

  test('finished periods are fetched once and survive a restart', () async {
    final src = CountingSource(now);
    final repo = HistoryRepository(src, cache: HistoryCache(FileHistoryStore(dir)));
    final a = await repo.load(HistoryRange.day, DateTime(2026, 10, 20), now: now);
    await repo.load(HistoryRange.day, DateTime(2026, 10, 20), now: now);
    expect(src.requests, 1);
    await repo.load(HistoryRange.month, DateTime(2026, 9, 1), now: now);
    expect(src.requests, 2);
    // A week inside September comes from the cached month.
    final w = await repo.load(HistoryRange.week, DateTime(2026, 9, 9), now: now);
    expect(src.requests, 2);
    expect(w.points.length, 7);
    // New repository and cache object, same folder: nothing is fetched again.
    final src2 = CountingSource(now);
    final repo2 = HistoryRepository(src2, cache: HistoryCache(FileHistoryStore(dir)));
    final b = await repo2.load(HistoryRange.day, DateTime(2026, 10, 20), now: now);
    await repo2.load(HistoryRange.month, DateTime(2026, 9, 1), now: now);
    expect(src2.requests, 0);
    expect(b.sum.solarWh, closeTo(a.sum.solarWh, 6), reason: 'values are stored rounded to Wh');
  });

  test('the current period is always fetched fresh', () async {
    final src = CountingSource(now);
    final repo = HistoryRepository(src, cache: HistoryCache(FileHistoryStore(dir)));
    await repo.load(HistoryRange.day, now, now: now);
    await repo.load(HistoryRange.day, now, now: now);
    await repo.load(HistoryRange.month, now, now: now);
    await repo.load(HistoryRange.month, now, now: now);
    expect(src.requests, 4);
  });

  test('preload fills months and days; the year then needs one request for the current month', () async {
    final src = CountingSource(now);
    final repo = HistoryRepository(src, cache: HistoryCache(FileHistoryStore(dir)));
    final progress = <int>[];
    await repo.preload(
      months: 10,
      withHours: true,
      now: now,
      pause: Duration.zero,
      onProgress: (d, t) => progress.add(d),
    );
    // 10 months + all days of those months + 25 finished days of October.
    var days = 25;
    for (var d = DateTime(2025, 12); d.isBefore(DateTime(2026, 10)); d = DateTime(d.year, d.month, d.day + 1)) {
      days++;
    }
    expect(src.requests, 10 + days);
    expect(progress.last, 10 + days);
    final stats = await HistoryCache(FileHistoryStore(dir)).stats();
    expect(stats.months, 10);
    expect(stats.days, days);
    expect(stats.bytes, greaterThan(0));
    src.requests = 0;
    final y = await repo.load(HistoryRange.year, now, now: now);
    expect(y.points.length, 12);
    expect(src.requests, 1);
    // A second preload has nothing left to do.
    await repo.preload(months: 10, withHours: true, now: now, pause: Duration.zero);
    expect(src.requests, 1);
  });

  test('preload stops when cancelled', () async {
    final src = CountingSource(now);
    final repo = HistoryRepository(src, cache: HistoryCache(FileHistoryStore(dir)));
    await repo.preload(months: 6, now: now, pause: Duration.zero, cancelled: () => src.requests >= 2);
    expect(src.requests, 2);
  });

  test('browser storage keeps months per system', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final src = CountingSource(now);
    final repo = HistoryRepository(src, cache: HistoryCache(PrefsHistoryStore(prefs, 'history/a/')));
    await repo.load(HistoryRange.day, DateTime(2026, 10, 20), now: now);
    final other = PrefsHistoryStore(prefs, 'history/b/');
    await other.write('2026-01', '{}');
    final stats = await HistoryCache(PrefsHistoryStore(prefs, 'history/a/')).stats();
    expect(stats.days, 1);
    expect(stats.bytes, greaterThan(0));
    final src2 = CountingSource(now);
    await HistoryRepository(
      src2,
      cache: HistoryCache(PrefsHistoryStore(prefs, 'history/a/')),
    ).load(HistoryRange.day, DateTime(2026, 10, 20), now: now);
    expect(src2.requests, 0);
    await PrefsHistoryStore(prefs, 'history/a/').clear();
    expect(await PrefsHistoryStore(prefs, 'history/a/').list(), isEmpty);
    expect(await other.list(), {'2026-01': 2});
  });

  test('months from before the time fix are dropped', () async {
    final store = FileHistoryStore(dir);
    await store.write('2026-09', '{"v":1,"days":[["2026-09-01T00:00:00.000",1,2,3,4,5,6]],"hours":{}}');
    expect(await HistoryCache(store).days(DateTime(2026, 9)), isNull);
  });
}
