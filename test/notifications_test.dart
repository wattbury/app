import 'package:flutter_test/flutter_test.dart';
import 'package:openrscp/openrscp.dart';
import 'package:wattbury/data/notifications.dart';

LiveSnapshot snap({int soc = 50, int grid = 0}) => LiveSnapshot(
  solarW: 0,
  batteryW: 0,
  houseW: 500,
  gridW: grid,
  additionalW: 0,
  wallboxW: 0,
  wallboxSolarW: 0,
  soc: soc,
  autarkyPct: 0,
  selfConsumptionPct: 0,
  receivedAt: DateTime(2026),
);

void main() {
  final t0 = DateTime(2026, 10, 26, 19);

  test('fires once, re-arms only past the margin', () {
    final e = RuleEngine();
    const r = [NotificationRule(id: 'soc', kind: RuleKind.socBelow, threshold: 10)];
    expect(e.evaluate(r, live: snap(soc: 9), online: true, now: t0).single.body, 'Ladestand 9 %.');
    expect(e.evaluate(r, live: snap(soc: 8), online: true, now: t0), isEmpty);
    // 10 % is no longer "below", but within the margin: still quiet afterwards.
    expect(e.evaluate(r, live: snap(soc: 10), online: true, now: t0), isEmpty);
    expect(e.evaluate(r, live: snap(soc: 9), online: true, now: t0), isEmpty);
    // 12 % clears it; dropping again fires again.
    expect(e.evaluate(r, live: snap(soc: 12), online: true, now: t0), isEmpty);
    expect(e.evaluate(r, live: snap(soc: 9), online: true, now: t0), hasLength(1));
  });

  test('duration: the condition must hold without a gap', () {
    final e = RuleEngine();
    const r = [
      NotificationRule(id: 'grid', kind: RuleKind.purchaseAbove, threshold: 2, holdFor: Duration(minutes: 10)),
    ];
    expect(e.evaluate(r, live: snap(grid: 2500), online: true, now: t0), isEmpty);
    expect(e.evaluate(r, live: snap(grid: 2500), online: true, now: t0.add(const Duration(minutes: 9))), isEmpty);
    // A dip below the threshold restarts the clock.
    expect(
      e.evaluate(r, live: snap(grid: 1900), online: true, now: t0.add(const Duration(minutes: 9, seconds: 30))),
      isEmpty,
    );
    expect(e.evaluate(r, live: snap(grid: 2500), online: true, now: t0.add(const Duration(minutes: 10))), isEmpty);
    final a = e.evaluate(r, live: snap(grid: 2500), online: true, now: t0.add(const Duration(minutes: 20)));
    expect(a.single.title, 'Netzbezug über 2,0 kW');
  });

  test('time window, also across midnight', () {
    const evening = NotificationRule(id: 'a', kind: RuleKind.socBelow, fromMinute: 18 * 60, toMinute: 23 * 60);
    expect(evening.inWindow(DateTime(2026, 1, 1, 18)), isTrue);
    expect(evening.inWindow(DateTime(2026, 1, 1, 23)), isFalse);
    const night = NotificationRule(id: 'b', kind: RuleKind.socBelow, fromMinute: 22 * 60, toMinute: 6 * 60);
    expect(night.inWindow(DateTime(2026, 1, 1, 23, 30)), isTrue);
    expect(night.inWindow(DateTime(2026, 1, 1, 5, 59)), isTrue);
    expect(night.inWindow(DateTime(2026, 1, 1, 12)), isFalse);
    // Outside the window the rule waits and fires when the window opens.
    final e = RuleEngine();
    const r = [
      NotificationRule(id: 's', kind: RuleKind.socBelow, threshold: 10, fromMinute: 18 * 60, toMinute: 23 * 60),
    ];
    expect(e.evaluate(r, live: snap(soc: 5), online: true, now: DateTime(2026, 1, 1, 17)), isEmpty);
    expect(e.evaluate(r, live: snap(soc: 5), online: true, now: DateTime(2026, 1, 1, 18)), hasLength(1));
  });

  test('offline fires after its duration and re-arms when online again', () {
    final e = RuleEngine();
    const r = [NotificationRule(id: 'off', kind: RuleKind.offline, holdFor: Duration(minutes: 5))];
    expect(e.evaluate(r, live: null, online: false, now: t0), isEmpty);
    expect(e.evaluate(r, live: null, online: false, now: t0.add(const Duration(minutes: 5))), hasLength(1));
    expect(e.evaluate(r, live: null, online: false, now: t0.add(const Duration(minutes: 6))), isEmpty);
    expect(e.evaluate(r, live: snap(), online: true, now: t0.add(const Duration(minutes: 7))), isEmpty);
    expect(e.evaluate(r, live: null, online: false, now: t0.add(const Duration(minutes: 8))), isEmpty);
    expect(e.evaluate(r, live: null, online: false, now: t0.add(const Duration(minutes: 13))), hasLength(1));
  });

  test('rules survive JSON and power rules ignore stale values while offline', () {
    for (final r in NotificationRule.defaults()) {
      final back = NotificationRule.fromJson(r.toJson());
      expect(back.title, r.title);
      expect(back.detail, r.detail);
    }
    final e = RuleEngine();
    const r = [NotificationRule(id: 'f', kind: RuleKind.feedInAbove, threshold: 5)];
    expect(e.evaluate(r, live: snap(grid: -6000), online: false, now: t0), isEmpty);
    expect(e.evaluate(r, live: snap(grid: -6000), online: true, now: t0).single.body, 'Einspeisung 6,00 kW.');
  });
}
