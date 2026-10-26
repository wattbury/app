import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wattbury/data/app_settings.dart';
import 'package:wattbury/data/energy_source.dart';
import 'package:wattbury/data/forecast.dart';
import 'package:wattbury/data/history.dart';
import 'package:wattbury/data/plant.dart';

void main() {
  test('learns about 0.8 when the forecast was 25 % too high', () async {
    final now = DateTime(2026, 10, 20, 8);
    final demo = DemoSource(clock: () => now);
    // Archive: what the demo unit produced on each of the last 8 days, times 1.25, as W per slot.
    final archive = <String, dynamic>{};
    for (var d = 1; d <= 8; d++) {
      final day = DateTime(2026, 10, 20 - d), next = DateTime(2026, 10, 21 - d);
      final starts = [for (var s = day; s.isBefore(next); s = s.add(const Duration(minutes: 15))) s];
      final h = await demo.history(day, const Duration(minutes: 15), next.difference(day));
      final pts = HistoryRepository.toPoints(h, starts);
      archive[day.toIso8601String().substring(0, 10)] = {
        for (final p in pts)
          '${p.start.hour.toString().padLeft(2, '0')}:${p.start.minute.toString().padLeft(2, '0')}':
              (p.solar * 4 * 1.25).round(),
      };
    }
    SharedPreferences.setMockInitialValues({'fcArchive.om': jsonEncode(archive)});
    final settings = await AppSettings.load();
    settings.plant = const PlantConfig(
      latitude: 52.5,
      longitude: 13.4,
      trackers: [
        TrackerConfig(pvi: 0, index: 0, name: 'T1', azimuth: 180, tilt: 30, strings: [PvString(modules: 20, wp: 400)]),
      ],
    );
    final svc = ForecastService(
      settings,
      provider: OpenMeteo(get: (_) async => throw StateError('no network in tests')),
    );
    await svc.learn(demo, now: now);
    expect(svc.correction.days, 8);
    expect(svc.correction.ready, isTrue);
    expect(svc.correction.overall, closeTo(0.8, 0.02));
    expect(svc.correction.hourly[12], closeTo(0.8, 0.02));
    expect(svc.correction.correctedError!, lessThan(svc.correction.rawError!));
    // Learning again the same day adds nothing new.
    await svc.learn(demo, now: now);
    expect(svc.records.length, 8);
    await svc.resetLearning();
    expect(svc.correction.ready, isFalse);
    svc.dispose();
  });
}
