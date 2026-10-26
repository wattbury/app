import 'package:flutter_test/flutter_test.dart';
import 'package:openrscp/openrscp.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wattbury/data/app_settings.dart';
import 'package:wattbury/data/energy_source.dart';
import 'package:wattbury/data/live_controller.dart';
import 'package:wattbury/data/notification_service.dart';
import 'package:wattbury/data/notifications.dart';

/// Demo unit with an almost empty battery.
class LowBattery extends DemoSource {
  @override
  Future<LiveSnapshot> live() async {
    final s = await super.live();
    return LiveSnapshot(
      solarW: s.solarW,
      batteryW: s.batteryW,
      houseW: s.houseW,
      gridW: s.gridW,
      additionalW: 0,
      wallboxW: 0,
      wallboxSolarW: 0,
      soc: 7,
      autarkyPct: 0,
      selfConsumptionPct: 0,
      receivedAt: s.receivedAt,
    );
  }
}

void main() {
  test('an alert reaches the stream, the system channel and the recent list once', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = await AppSettings.load();
    settings.rules = const [NotificationRule(id: 'low', kind: RuleKind.socBelow, threshold: 10)];
    final delivered = <Alert>[];
    final svc = NotificationService(settings, deliver: (id, a) async => delivered.add(a))..systemAvailable = true;
    final live = LiveController(LowBattery());
    await live.start();
    final streamed = <Alert>[];
    final sub = svc.alerts.listen(streamed.add);
    await svc.check(live, DateTime(2026, 10, 26, 20));
    await svc.check(live, DateTime(2026, 10, 26, 20, 1));
    await Future<void>.delayed(Duration.zero);
    expect(delivered.single.title, 'Batterie unter 10 %');
    expect(streamed, hasLength(1));
    expect(svc.recent.single.body, 'Ladestand 7 %.');
    await sub.cancel();
    live.dispose();
    svc.dispose();
  });

  test('without system notifications the banner stream still gets the alert', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = await AppSettings.load();
    settings.rules = const [NotificationRule(id: 'low', kind: RuleKind.socBelow, threshold: 10)];
    var delivered = 0;
    final svc = NotificationService(settings, deliver: (id, a) async => delivered++);
    final live = LiveController(LowBattery());
    await live.start();
    final first = svc.alerts.first;
    await svc.check(live, DateTime(2026, 10, 26, 20));
    expect((await first).ruleId, 'low');
    expect(delivered, 0);
    live.dispose();
    svc.dispose();
  });
}
