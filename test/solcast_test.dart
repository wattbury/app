import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wattbury/data/app_settings.dart';
import 'package:wattbury/data/forecast.dart';
import 'package:wattbury/data/plant.dart';
import 'package:wattbury/data/solcast.dart';

const plant = PlantConfig(
  latitude: 52.5,
  longitude: 13.4,
  trackers: [
    TrackerConfig(pvi: 0, index: 0, name: 'T1', azimuth: 135, tilt: 35, strings: [PvString(modules: 20, wp: 355)]),
    TrackerConfig(pvi: 0, index: 1, name: 'T2', azimuth: 315, tilt: 35, strings: [PvString(modules: 8, wp: 455)]),
  ],
);

Map<String, dynamic> openMeteo(Uri u) => {
  if (u.queryParameters.containsKey('minutely_15'))
    'minutely_15': {
      'time': ['2026-10-20T12:15'],
      'global_tilted_irradiance': [400],
      'temperature_2m': [10],
    },
  'daily': {
    'time': ['2026-10-21'],
    'weather_code': [0],
  },
};

void main() {
  test('30-minute UTC periods become two local 15-minute slots; other trackers use Open-Meteo', () async {
    final calls = <Uri>[];
    final om = OpenMeteo(get: (u) async => openMeteo(u));
    final sc = Solcast(
      fallback: om,
      get: (u, {headers = const {}}) async {
        calls.add(u);
        expect(headers['Authorization'], 'Bearer KEY');
        return {
          'forecasts': [
            {'pv_estimate': 2.0, 'period_end': DateTime.utc(2026, 10, 20, 11).toIso8601String(), 'period': 'PT30M'},
          ],
        };
      },
    );
    final f = await sc.fetch(plant, 'KEY', {'0-0': 'site-a'});
    expect(calls.single.path, '/rooftop_sites/site-a/forecasts');
    final end = DateTime.utc(2026, 10, 20, 11).toLocal();
    final s1 = f.slots.firstWhere((s) => s.start == end.subtract(const Duration(minutes: 30)));
    final s2 = f.slots.firstWhere((s) => s.start == end.subtract(const Duration(minutes: 15)));
    expect(s1.watts, 2000);
    expect(s2.watts, 2000);
    expect(f.slots.any((s) => s.start == DateTime(2026, 10, 20, 12)), isTrue, reason: 'T2 from Open-Meteo');
    expect(f.weatherCodes[DateTime(2026, 10, 21)], 0);
  });

  test('the service spends Solcast requests only every three hours', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = await AppSettings.load();
    settings.plant = plant;
    settings.forecastProvider = 'sc';
    settings.solcastSites = {'0-0': 'a', '0-1': 'b'};
    var requests = 0;
    final sc = Solcast(
      fallback: OpenMeteo(get: (u) async => openMeteo(u)),
      get: (u, {headers = const {}}) async {
        requests++;
        return {'forecasts': <Object>[]};
      },
    );
    final svc = ForecastService(
      settings,
      solcast: sc,
      provider: OpenMeteo(get: (u) async => openMeteo(u)),
      solcastKey: () async => 'KEY',
    );
    await Future<void>.delayed(Duration.zero);
    await svc.refresh();
    final afterFirst = requests;
    await svc.refresh();
    await svc.refresh();
    final hour = DateTime.now().hour;
    if (hour >= 5 && hour < 21) expect(afterFirst, 2, reason: 'one request per site');
    expect(requests, afterFirst, reason: 'later refreshes use the cached forecast');
    await svc.refresh(force: true);
    expect(requests, afterFirst + 2);
    svc.dispose();
  });
}
