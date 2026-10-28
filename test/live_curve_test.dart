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

/// Unit whose database reports 15-minute buckets as average W, as an S10E does: 1 kW in every
/// finished quarter hour, a momentary 11 kW in the one still running.
class RunningBucketSource extends DemoSource {
  final requests = <(DateTime, Duration)>[];

  @override
  Future<DbHistory> history(DateTime start, Duration interval, Duration span) async {
    requests.add((start, span));
    final finished = DateTime.now().difference(start).inMinutes ~/ 15;
    final buckets = [for (var i = 0; i < finished; i++) _b(1000), _b(11000)];
    final sumWh = buckets.fold<double>(0, (a, b) => a + b.solar) / 4;
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
  test('today\'s curve asks for the whole day and shows only finished quarter hours', () async {
    final now = DateTime.now();
    if (now.hour == 0 && now.minute < 20) return; // no finished quarter hour yet
    final src = RunningBucketSource();
    final live = LiveController(src);
    await live.start();
    expect(src.requests.single.$1, DateTime(now.year, now.month, now.day));
    expect(src.requests.single.$2.inHours, greaterThanOrEqualTo(23));
    // 1 kW for a quarter hour is 250 Wh; the running bucket's 11 kW is not part of the curve.
    expect(live.todayCurve, isNotEmpty);
    expect(live.todayCurve.map((p) => p.solar).toSet(), {250});
    expect(live.todayCurve.last.start.add(const Duration(minutes: 15)).isAfter(DateTime.now()), isFalse);
    live.dispose();
  });
}
