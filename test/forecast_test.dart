import 'package:flutter_test/flutter_test.dart';
import 'package:wattbury/data/forecast.dart';
import 'package:wattbury/data/plant.dart';

void main() {
  const plant = PlantConfig(
    latitude: 52.52,
    longitude: 13.40,
    place: 'Beispiel',
    trackers: [
      TrackerConfig(pvi: 0, index: 0, name: 'T1', azimuth: 135, tilt: 35, strings: [PvString(modules: 20, wp: 355)]),
      TrackerConfig(pvi: 0, index: 1, name: 'T2', azimuth: 315, tilt: 35, strings: [PvString(modules: 8, wp: 455)]),
    ],
  );

  test('azimuth is converted to the south-based convention', () {
    expect(plant.trackers[0].azimuthSouth, -45);
    expect(plant.trackers[1].azimuthSouth, 135);
    expect(const TrackerConfig(pvi: 0, index: 0, name: '', azimuth: 0, tilt: 0, strings: []).azimuthSouth, 180);
    expect(plant.trackers[0].direction, 'SO');
  });

  test('power: STC-like irradiance gives kWp times losses, heat lowers it', () {
    expect(OpenMeteo.power(10, 0, 20), 0);
    final mild = OpenMeteo.power(10, 1000, 0), hot = OpenMeteo.power(10, 1000, 30);
    expect(mild, closeTo(10000 * 0.86 * (1 - 0.0037 * (31.25 - 25)), 1));
    expect(hot, lessThan(mild));
  });

  test('trackers are summed per slot and slots start 15 minutes before the stamp', () async {
    final urls = <Uri>[];
    final om = OpenMeteo(
      get: (u) async {
        urls.add(u);
        return {
          'minutely_15': {
            'time': ['2026-10-26T12:00', '2026-10-26T12:15'],
            'global_tilted_irradiance': [500, 0],
            'temperature_2m': [10, 10],
          },
          if (u.queryParameters.containsKey('daily'))
            'daily': {
              'time': ['2026-10-26'],
              'weather_code': [3],
            },
        };
      },
    );
    final f = await om.fetch(plant);
    expect(urls.length, 2);
    expect(urls.first.queryParameters['azimuth'], '-45');
    expect(urls.last.queryParameters.containsKey('daily'), isFalse);
    expect(f.slots.first.start, DateTime(2026, 10, 26, 11, 45));
    expect(f.slots.first.watts, closeTo(OpenMeteo.power(plant.kwp, 500, 10), 1));
    expect(weatherText(f.weatherCodes[DateTime(2026, 10, 26)]!), 'bewölkt');
  });
}
