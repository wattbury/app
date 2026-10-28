import 'package:flutter_test/flutter_test.dart';
import 'package:openrscp/openrscp.dart';
import 'package:wattbury/data/energy_source.dart';
import 'package:wattbury/data/live_controller.dart';

DbBucket _b(double solar) => DbBucket(
  index: 0,
  solar: solar,
  house: 0,
  gridPurchase: 0,
  gridFeedIn: 0,
  batteryIn: 0,
  batteryOut: 0,
  autarkyPct: 0,
  consumedProductionPct: 0,
  socPct: 0,
);

/// Unit whose database reports 15-minute buckets as average W, 1 kW all day. Today's sum runs
/// ahead of the buckets (the running quarter hour is counted, but not yet a bucket).
class LaggingSource extends DemoSource {
  final requests = <(DateTime, Duration)>[];

  @override
  Future<DbHistory> history(DateTime start, Duration interval, Duration span) async {
    requests.add((start, span));
    final n = (span.inSeconds / interval.inSeconds).round();
    final now = DateTime.now();
    final today = start.day == now.day;
    // Today only the finished quarter hours have values.
    final filled = today ? now.difference(start).inMinutes ~/ 15 : n;
    final buckets = [for (var i = 0; i < n; i++) _b(i < filled ? 1000 : 0)];
    final sumWh = filled * 250.0 + (today ? 900 : 0);
    return DbHistory(
      start: start,
      interval: interval,
      span: span,
      sum: DbSummary(
        start: start,
        span: span,
        solarWh: sumWh,
        houseWh: 0,
        gridPurchaseWh: 0,
        gridFeedInWh: 0,
        batteryInWh: 0,
        batteryOutWh: 0,
        autarkyPct: 0,
        consumedProductionPct: 0,
        socPct: 0,
      ),
      buckets: buckets,
    );
  }
}

void main() {
  test('today\'s curve uses the scale of yesterday and asks for whole days', () async {
    final now = DateTime.now();
    if (now.hour == 0 && now.minute < 20) return; // no finished quarter hour yet
    final src = LaggingSource();
    final live = LiveController(src);
    await live.start();
    final midnight = DateTime(now.year, now.month, now.day);
    // Yesterday for the scale, then today, both as whole days.
    expect(src.requests.map((r) => r.$1), [DateTime(now.year, now.month, now.day - 1), midnight]);
    expect(src.requests.every((r) => r.$2.inHours >= 23), isTrue);
    // 1 kW for a quarter hour is 250 Wh, not inflated by the sum running ahead.
    expect(live.todayCurve, isNotEmpty);
    expect(live.todayCurve.map((p) => p.solar).toSet(), {250});
    // Only finished quarter hours.
    expect(live.todayCurve.last.start.add(const Duration(minutes: 15)).isAfter(DateTime.now()), isFalse);
    live.dispose();
  });
}
