import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:openrscp/openrscp.dart';

import 'energy_source.dart';
import 'history_cache.dart';

enum HistoryRange { day, week, month, year }

/// Energy in one bar of a chart, all in Wh. Sources (solar, grid purchase, battery discharge) and
/// sinks (house, feed-in, battery charge) of the same period.
class HistoryPoint {
  final DateTime start;
  final double solar, purchase, batteryOut, house, feedIn, batteryIn;
  const HistoryPoint({
    required this.start,
    required this.solar,
    required this.purchase,
    required this.batteryOut,
    required this.house,
    required this.feedIn,
    required this.batteryIn,
  });

  static HistoryPoint fromSummary(DateTime start, DbSummary s) => HistoryPoint(
    start: start,
    solar: s.solarWh,
    purchase: s.gridPurchaseWh,
    batteryOut: s.batteryOutWh,
    house: s.houseWh,
    feedIn: s.gridFeedInWh,
    batteryIn: s.batteryInWh,
  );
}

class HistoryData {
  final HistoryRange range;
  final DateTime start, end;
  final List<HistoryPoint> points;
  final DbSummary sum;
  const HistoryData({
    required this.range,
    required this.start,
    required this.end,
    required this.points,
    required this.sum,
  });
}

/// Loads chart data from the unit's database. Finished periods go into a persistent
/// [HistoryCache] and are never fetched again; weeks and years are assembled from cached months.
class HistoryRepository {
  final EnergySource source;
  final HistoryCache cache;
  HistoryRepository(this.source, {HistoryCache? cache}) : cache = cache ?? HistoryCache(null);

  /// First and last moment of the period that contains [anchor]. Weeks start on Monday.
  static (DateTime, DateTime) bounds(HistoryRange r, DateTime anchor) {
    final d = DateTime(anchor.year, anchor.month, anchor.day);
    return switch (r) {
      HistoryRange.day => (d, DateTime(d.year, d.month, d.day + 1)),
      HistoryRange.week => (
        DateTime(d.year, d.month, d.day - (d.weekday - 1)),
        DateTime(d.year, d.month, d.day - (d.weekday - 1) + 7),
      ),
      HistoryRange.month => (DateTime(d.year, d.month), DateTime(d.year, d.month + 1)),
      HistoryRange.year => (DateTime(d.year), DateTime(d.year + 1)),
    };
  }

  /// Anchor of the neighbouring period, [step] = −1 for back, +1 for forward.
  static DateTime shift(HistoryRange r, DateTime anchor, int step) => switch (r) {
    HistoryRange.day => DateTime(anchor.year, anchor.month, anchor.day + step),
    HistoryRange.week => DateTime(anchor.year, anchor.month, anchor.day + 7 * step),
    HistoryRange.month => DateTime(anchor.year, anchor.month + step),
    HistoryRange.year => DateTime(anchor.year + step),
  };

  /// Totals of a period computed from its bars, for views assembled from the cache.
  static DbSummary sumOf(DateTime start, DateTime end, List<HistoryPoint> points) {
    double s(double Function(HistoryPoint) f) => points.fold(0, (a, p) => a + f(p));
    final solar = s((p) => p.solar),
        house = s((p) => p.house),
        purchase = s((p) => p.purchase),
        feedIn = s((p) => p.feedIn);
    return DbSummary(
      start: start,
      span: end.difference(start),
      solarWh: solar,
      houseWh: house,
      gridPurchaseWh: purchase,
      gridFeedInWh: feedIn,
      batteryInWh: s((p) => p.batteryIn),
      batteryOutWh: s((p) => p.batteryOut),
      autarkyPct: house == 0 ? 0 : (1 - purchase / house).clamp(0, 1) * 100,
      consumedProductionPct: solar == 0 ? 0 : (1 - feedIn / solar).clamp(0, 1) * 100,
      socPct: 0,
    );
  }

  static List<DateTime> _steps(DateTime start, DateTime end, {required bool hourly}) => [
    for (
      var t = start;
      t.isBefore(end);
      t = hourly ? t.add(const Duration(hours: 1)) : DateTime(t.year, t.month, t.day + 1)
    )
      t,
  ];

  Future<HistoryData> load(HistoryRange r, DateTime anchor, {DateTime? now}) async {
    final n = now ?? DateTime.now();
    final (start, end) = bounds(r, anchor);
    final finished = !end.isAfter(n);
    switch (r) {
      case HistoryRange.day:
        final points = finished ? await _dayHours(start) : await _fetch(start, end, hourly: true);
        return HistoryData(range: r, start: start, end: end, points: points, sum: sumOf(start, end, points));
      case HistoryRange.month:
        final points = finished ? await _monthDays(start) : await _fetch(start, end, hourly: false);
        return HistoryData(range: r, start: start, end: end, points: points, sum: sumOf(start, end, points));
      case HistoryRange.week:
        // A finished week whose months are both over comes from the cached months.
        final lastDay = end.subtract(const Duration(days: 1));
        final monthsOver = !DateTime(lastDay.year, lastDay.month + 1).isAfter(n);
        List<HistoryPoint> points;
        if (finished && monthsOver) {
          final all = [...await _monthDays(DateTime(start.year, start.month))];
          if (lastDay.month != start.month) all.addAll(await _monthDays(DateTime(lastDay.year, lastDay.month)));
          points = all.where((p) => !p.start.isBefore(start) && p.start.isBefore(end)).toList();
        } else {
          points = await _fetch(start, end, hourly: false);
        }
        return HistoryData(range: r, start: start, end: end, points: points, sum: sumOf(start, end, points));
      case HistoryRange.year:
        final points = <HistoryPoint>[];
        for (var m = 0; m < 12; m++) {
          final a = DateTime(start.year, start.month + m), b = DateTime(start.year, start.month + m + 1);
          if (!b.isAfter(n)) {
            points.add(_total(a, await _monthDays(a)));
          } else if (a.isBefore(n)) {
            final h = await source.history(a, b.difference(a), b.difference(a));
            points.add(HistoryPoint.fromSummary(a, h.sum));
          } else {
            points.add(HistoryPoint.fromSummary(a, sumOf(a, b, const [])));
          }
        }
        return HistoryData(range: r, start: start, end: end, points: points, sum: sumOf(start, end, points));
    }
  }

  static HistoryPoint _total(DateTime start, List<HistoryPoint> ps) {
    double s(double Function(HistoryPoint) f) => ps.fold(0, (a, p) => a + f(p));
    return HistoryPoint(
      start: start,
      solar: s((p) => p.solar),
      purchase: s((p) => p.purchase),
      batteryOut: s((p) => p.batteryOut),
      house: s((p) => p.house),
      feedIn: s((p) => p.feedIn),
      batteryIn: s((p) => p.batteryIn),
    );
  }

  Future<List<HistoryPoint>> _fetch(DateTime start, DateTime end, {required bool hourly}) async {
    final h = await source.history(
      start,
      hourly ? const Duration(hours: 1) : const Duration(days: 1),
      end.difference(start),
    );
    return toPoints(h, _steps(start, end, hourly: hourly));
  }

  /// Daily values of a finished month, from the cache or fetched once and stored.
  Future<List<HistoryPoint>> _monthDays(DateTime month) async {
    final cached = await cache.days(month);
    if (cached != null) return cached;
    final points = await _fetch(month, DateTime(month.year, month.month + 1), hourly: false);
    await cache.putDays(month, points);
    return points;
  }

  /// Hourly values of a finished day, from the cache or fetched once and stored.
  Future<List<HistoryPoint>> _dayHours(DateTime day) async {
    final cached = await cache.hours(day);
    if (cached != null) return cached;
    final points = await _fetch(day, DateTime(day.year, day.month, day.day + 1), hourly: true);
    await cache.putHours(day, points);
    return points;
  }

  /// Fills the cache for the last [months] finished months: daily values (one request per month)
  /// and, with [withHours], hourly values (one request per day). Reports progress as done/total and
  /// stops when [cancelled] returns true. Pauses briefly between requests to spare the unit.
  Future<void> preload({
    required int months,
    bool withHours = false,
    DateTime? now,
    void Function(int done, int total)? onProgress,
    bool Function()? cancelled,
    Duration pause = const Duration(milliseconds: 150),
  }) async {
    final n = now ?? DateTime.now();
    final today = DateTime(n.year, n.month, n.day);
    final list = [for (var m = 1; m <= months; m++) DateTime(n.year, n.month - m)];
    // Finished days of the current month count for hourly values too.
    final days = <DateTime>[
      if (withHours) ...[
        for (final m in list)
          for (var d = m; d.isBefore(DateTime(m.year, m.month + 1)); d = DateTime(d.year, d.month, d.day + 1)) d,
        for (var d = DateTime(n.year, n.month); d.isBefore(today); d = DateTime(d.year, d.month, d.day + 1)) d,
      ],
    ];
    final total = list.length + days.length;
    var done = 0;
    onProgress?.call(done, total);
    for (final m in list) {
      if (cancelled?.call() ?? false) return;
      if (await cache.days(m) == null) {
        await _monthDays(m);
        await Future<void>.delayed(pause);
      }
      onProgress?.call(++done, total);
    }
    for (final d in days) {
      if (cancelled?.call() ?? false) return;
      if (await cache.hours(d) == null) {
        await _dayHours(d);
        await Future<void>.delayed(pause);
      }
      onProgress?.call(++done, total);
    }
  }

  /// Turns raw buckets into Wh per bar. The unit's bucket values are either energy per interval
  /// or average power; the sum container, which is always in Wh, tells which.
  static List<HistoryPoint> toPoints(DbHistory h, List<DateTime> steps, {double? scale}) {
    final b = h.buckets.take(steps.length).toList();
    final hours = steps.length >= 2 ? steps[1].difference(steps[0]).inSeconds / 3600 : 1.0;
    return _scaled(b, steps, scale ?? measuredScale(h, b, hours));
  }

  /// Scale from bucket values to Wh: the sum container (always Wh) over the buckets' total, snapped
  /// to a possible format. Reliable only when both cover the same, finished period.
  static double measuredScale(DbHistory h, List<DbBucket> buckets, double bucketHours) {
    double total(double Function(DbBucket) f) => buckets.fold(0, (a, x) => a + f(x));
    double ratio = 1;
    for (final (sumWh, raw) in [(h.sum.solarWh, total((x) => x.solar)), (h.sum.houseWh, total((x) => x.house))]) {
      if (sumWh > 0 && raw > 0) {
        ratio = sumWh / raw;
        break;
      }
    }
    return snapScale(ratio, bucketHours);
  }

  /// Only two scales are physically possible, 1 (Wh per bucket) and the bucket length in hours
  /// (average W; an S10E reports this), so a measured ratio only picks between them and small
  /// deviations (a bucket still being written) do not leak into every value. Far from both
  /// (unknown format), the ratio is used unchanged.
  @visibleForTesting
  static double snapScale(double ratio, double bucketHours) {
    double off(double c) => (math.log(ratio / c)).abs();
    final best = off(1) <= off(bucketHours) ? 1.0 : bucketHours;
    return off(best) <= math.ln2 ? best : ratio;
  }

  static List<HistoryPoint> _scaled(List<DbBucket> b, List<DateTime> steps, double scale) {
    return [
      for (var i = 0; i < steps.length; i++)
        i < b.length
            ? HistoryPoint(
                start: steps[i],
                solar: b[i].solar * scale,
                purchase: b[i].gridPurchase * scale,
                batteryOut: b[i].batteryOut * scale,
                house: b[i].house * scale,
                feedIn: b[i].gridFeedIn * scale,
                batteryIn: b[i].batteryIn * scale,
              )
            : HistoryPoint(start: steps[i], solar: 0, purchase: 0, batteryOut: 0, house: 0, feedIn: 0, batteryIn: 0),
    ];
  }
}
