import 'package:openrscp/openrscp.dart';

import 'energy_source.dart';

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

/// Loads chart data from the unit's database and keeps finished periods in memory, since the past
/// does not change. The current period is always fetched fresh.
class HistoryRepository {
  final EnergySource source;
  final _cache = <String, HistoryData>{};
  HistoryRepository(this.source);

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

  Future<HistoryData> load(HistoryRange r, DateTime anchor, {DateTime? now}) async {
    final (start, end) = bounds(r, anchor);
    final finished = !end.isAfter(now ?? DateTime.now());
    final key = '${r.name}-${start.toIso8601String()}';
    if (finished && _cache.containsKey(key)) return _cache[key]!;
    final data = r == HistoryRange.year ? await _year(start, end) : await _series(r, start, end);
    if (finished) _cache[key] = data;
    return data;
  }

  Future<HistoryData> _series(HistoryRange r, DateTime start, DateTime end) async {
    // Day in hours, week and month in days. Bucket times follow local calendar steps, so a day
    // with a clock change has 23 or 25 hours.
    final steps = <DateTime>[];
    for (
      var t = start;
      t.isBefore(end);
      t = r == HistoryRange.day ? t.add(const Duration(hours: 1)) : DateTime(t.year, t.month, t.day + 1)
    ) {
      steps.add(t);
    }
    final interval = r == HistoryRange.day ? const Duration(hours: 1) : const Duration(days: 1);
    final h = await source.history(start, interval, end.difference(start));
    final points = toPoints(h, steps);
    return HistoryData(range: r, start: start, end: end, points: points, sum: h.sum);
  }

  /// Months differ in length, so a year is twelve monthly sums.
  Future<HistoryData> _year(DateTime start, DateTime end) async {
    final points = <HistoryPoint>[];
    for (var m = 0; m < 12; m++) {
      final a = DateTime(start.year, start.month + m), b = DateTime(start.year, start.month + m + 1);
      final h = await source.history(a, b.difference(a), b.difference(a));
      points.add(HistoryPoint.fromSummary(a, h.sum));
    }
    double s(double Function(HistoryPoint) f) => points.fold(0, (a, p) => a + f(p));
    final solar = s((p) => p.solar),
        house = s((p) => p.house),
        purchase = s((p) => p.purchase),
        feedIn = s((p) => p.feedIn);
    final sum = DbSummary(
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
    return HistoryData(range: HistoryRange.year, start: start, end: end, points: points, sum: sum);
  }

  /// Turns raw buckets into Wh per bar. The unit's bucket values are either energy per interval
  /// or average power; the scale is taken from the sum container, which is always in Wh.
  static List<HistoryPoint> toPoints(DbHistory h, List<DateTime> steps) {
    final b = h.buckets.take(steps.length).toList();
    double total(double Function(DbBucket) f) => b.fold(0, (a, x) => a + f(x));
    double scale = 1;
    for (final (sumWh, raw) in [(h.sum.solarWh, total((x) => x.solar)), (h.sum.houseWh, total((x) => x.house))]) {
      if (sumWh > 0 && raw > 0) {
        scale = sumWh / raw;
        break;
      }
    }
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
