import 'package:flutter_test/flutter_test.dart';
import 'package:openrscp/openrscp.dart';
import 'package:wattbury/data/energy_source.dart';
import 'package:wattbury/data/history.dart';

DbSummary _sum(double solar, double house) => DbSummary(
  start: DateTime(2026),
  span: const Duration(days: 1),
  solarWh: solar,
  houseWh: house,
  gridPurchaseWh: 0,
  gridFeedInWh: 0,
  batteryInWh: 0,
  batteryOutWh: 0,
  autarkyPct: 0,
  consumedProductionPct: 0,
  socPct: 0,
);

DbBucket _b(double solar, double house) => DbBucket(
  index: 0,
  solar: solar,
  house: house,
  gridPurchase: 0,
  gridFeedIn: 0,
  batteryIn: 0,
  batteryOut: 0,
  autarkyPct: 0,
  consumedProductionPct: 0,
  socPct: 0,
);

void main() {
  test('weeks start on Monday', () {
    final (s, e) = HistoryRepository.bounds(HistoryRange.week, DateTime(2026, 10, 25)); // Sunday
    expect(s, DateTime(2026, 10, 19));
    expect(e, DateTime(2026, 10, 26));
  });

  test('buckets in Wh stay as they are', () {
    final h = DbHistory(
      start: DateTime(2026),
      interval: const Duration(hours: 1),
      span: const Duration(hours: 2),
      sum: _sum(300, 100),
      buckets: [_b(100, 50), _b(200, 50)],
    );
    final p = HistoryRepository.toPoints(h, [DateTime(2026), DateTime(2026, 1, 1, 1)]);
    expect(p.map((x) => x.solar), [100, 200]);
  });

  test('buckets in average W are scaled to Wh by the sum container', () {
    // 15-minute buckets of 400 W and 800 W are 100 Wh and 200 Wh.
    final h = DbHistory(
      start: DateTime(2026),
      interval: const Duration(minutes: 15),
      span: const Duration(minutes: 30),
      sum: _sum(300, 0),
      buckets: [_b(400, 0), _b(800, 0)],
    );
    final p = HistoryRepository.toPoints(h, [DateTime(2026), DateTime(2026, 1, 1, 0, 15)]);
    expect(p.map((x) => x.solar), [100, 200]);
  });

  test('a bucket still being written does not skew the scale', () {
    // Morning, 15-minute buckets in average W: 1 kW, 2 kW, then the running quarter hour is not in
    // the database yet, while the sum already counts 0.5 kWh of it.
    final steps = [for (var i = 0; i < 3; i++) DateTime(2026, 10, 27, 9).add(Duration(minutes: 15 * i))];
    final h = DbHistory(
      start: steps.first,
      interval: const Duration(minutes: 15),
      span: const Duration(minutes: 45),
      sum: _sum(250 + 500 + 500, 0),
      buckets: [_b(1000, 0), _b(2000, 0), _b(0, 0)],
    );
    final p = HistoryRepository.toPoints(h, steps);
    // Ratio 1250 / 3000 = 0.42 would make the 2 kW quarter 833 Wh (a 3.3 kW peak); snapped to 0.25 it stays 500 Wh.
    expect(p.map((x) => x.solar), [250, 500, 0]);
  });

  test('scale snaps to Wh or average W, other formats keep the ratio', () {
    expect(HistoryRepository.snapScale(0.42, 0.25), 0.25);
    expect(HistoryRepository.snapScale(1.6, 0.25), 1);
    expect(HistoryRepository.snapScale(30, 24), 24);
    expect(HistoryRepository.snapScale(5, 0.25), 5);
  });

  // In Germany 25 bars; the test also holds on machines running in UTC.
  test('a day with a clock change gets one bar per real hour', () async {
    final repo = HistoryRepository(DemoSource(clock: () => DateTime(2026, 11, 1)));
    final d = await repo.load(HistoryRange.day, DateTime(2026, 10, 25), now: DateTime(2026, 11, 1));
    expect(d.points.length, d.end.difference(d.start).inHours);
    expect(d.sum.solarWh, greaterThan(0));
  });

  test('a year has twelve monthly bars', () async {
    final repo = HistoryRepository(DemoSource(clock: () => DateTime(2027, 1, 2)));
    final d = await repo.load(HistoryRange.year, DateTime(2026, 6), now: DateTime(2027, 1, 2));
    expect(d.points.length, 12);
    expect(d.points.first.start, DateTime(2026));
  });
}
