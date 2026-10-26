import 'package:flutter_test/flutter_test.dart';
import 'package:wattbury/data/correction.dart';

DayRecord day(int d, {double morning = 1, double rest = 1, bool curtailNoon = false, String? excluded}) {
  final f = List<double>.filled(24, 0), a = List<double>.filled(24, 0), v = List<bool>.filled(24, true);
  for (var h = 8; h < 18; h++) {
    f[h] = 1000;
    a[h] = 1000 * (h < 11 ? morning : rest);
  }
  if (curtailNoon) {
    a[12] = 400;
    v[12] = false;
  }
  return DayRecord(day: DateTime(2026, 10, d), actualWh: a, forecastWh: f, valid: v, excluded: excluded);
}

void main() {
  final today = DateTime(2026, 10, 26);

  test('needs seven days before it applies', () {
    final c = Correction.compute([for (var d = 20; d < 26; d++) day(d, morning: .8)], today: today);
    expect(c.days, 6);
    expect(c.ready, isFalse);
    expect(c.factorAt(DateTime(2026, 10, 26, 9)), 1);
  });

  test('learns a lower factor for shaded morning hours', () {
    final c = Correction.compute([for (var d = 10; d < 26; d++) day(d, morning: .8)], today: today);
    expect(c.ready, isTrue);
    expect(c.hourly[9], closeTo(.8, 1e-9));
    expect(c.hourly[14], closeTo(1, 1e-9));
    expect(c.overall, closeTo((3 * .8 + 7) / 10, 1e-9));
    expect(c.rawError, greaterThan(c.correctedError!));
  });

  test('curtailed hours and excluded days do not count', () {
    final c = Correction.compute([
      for (var d = 10; d < 26; d++) day(d, curtailNoon: true),
      day(9, rest: .05, excluded: 'Schnee oder Ausfall'),
      day(8, rest: .05, excluded: 'Schnee oder Ausfall'),
    ], today: DateTime(2026, 10, 26));
    expect(c.hourly[12], 1, reason: 'curtailed hour skipped, so no data and the factor stays 1');
    expect(c.curtailedDays, 16);
    expect(c.excludedDays, 2);
  });

  test('fromSlots: hour sums, curtailment and snow', () {
    final starts = [for (var q = 0; q < 96; q++) DateTime(2026, 10, 20).add(Duration(minutes: 15 * q))];
    final actual = [for (var q = 0; q < 96; q++) q >= 40 && q < 56 ? 1000.0 : 0.0];
    final forecast = [for (var q = 0; q < 96; q++) q >= 40 && q < 56 ? 1100.0 : 0.0];
    final feed = [for (var q = 0; q < 96; q++) q == 48 ? 1800.0 : 0.0]; // 7.2 kW in the 12:00 slot
    final r = DayRecord.fromSlots(
      day: DateTime(2026, 10, 20),
      actualWh: actual,
      forecastWh: forecast,
      feedInWh: feed,
      slotStarts: starts,
      kwp: 10.74,
      feedLimitW: 7400,
    );
    expect(r.actualWh[10], 4000);
    expect(r.forecastWh[10], 4400);
    expect(r.valid[12], isFalse);
    expect(r.valid[11], isTrue);
    expect(r.excluded, isNull);
    final snow = DayRecord.fromSlots(
      day: DateTime(2026, 10, 20),
      actualWh: List.filled(96, 10),
      forecastWh: forecast,
      feedInWh: List.filled(96, 0),
      slotStarts: starts,
      kwp: 10.74,
    );
    expect(snow.excluded, isNotNull);
  });
}
