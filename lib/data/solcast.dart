import 'forecast.dart';
import 'plant.dart';

/// Solcast with the user's own API key. The user creates the rooftop sites (azimuth, tilt, kWp)
/// on solcast.com and enters one resource id per tracker; trackers without an id are computed
/// with Open-Meteo. The free hobbyist plan allows two sites and a few requests a day.
class Solcast {
  final Future<Object?> Function(Uri, {Map<String, String> headers}) _get;
  final OpenMeteo fallback;
  Solcast({Future<Object?> Function(Uri, {Map<String, String> headers})? get, OpenMeteo? fallback})
    : _get = get ?? getJson,
      fallback = fallback ?? OpenMeteo();

  /// Key of a tracker in the site map.
  static String trackerKey(TrackerConfig t) => '${t.pvi}-${t.index}';

  Future<Forecast> fetch(PlantConfig plant, String apiKey, Map<String, String> sites) async {
    final sum = <DateTime, double>{};
    final rest = <TrackerConfig>[];
    for (final t in plant.trackers) {
      final id = sites[trackerKey(t)]?.trim() ?? '';
      if (id.isEmpty) {
        rest.add(t);
        continue;
      }
      final j = await _get(
        Uri.https('api.solcast.com.au', '/rooftop_sites/$id/forecasts', {'format': 'json', 'hours': '72'}),
        headers: {'Authorization': 'Bearer $apiKey'},
      ) as Map<String, dynamic>;
      for (final f in (j['forecasts'] as List).cast<Map<String, dynamic>>()) {
        // 30-minute periods in UTC, stamped at their end; split into two local 15-minute slots.
        final end = DateTime.parse(f['period_end'] as String).toLocal();
        final w = ((f['pv_estimate'] as num?)?.toDouble() ?? 0) * 1000;
        for (final back in const [30, 15]) {
          final start = end.subtract(Duration(minutes: back));
          sum[start] = (sum[start] ?? 0) + w;
        }
      }
    }
    var codes = const <DateTime, int>{};
    if (rest.isNotEmpty) {
      final om = await fallback.fetch(plant.copyWith(trackers: rest));
      for (final s in om.slots) {
        sum[s.start] = (sum[s.start] ?? 0) + s.watts;
      }
      codes = om.weatherCodes;
    } else {
      codes = await fallback.weather(plant.latitude!, plant.longitude!);
    }
    final slots = [for (final e in sum.entries) ForecastSlot(e.key, e.value)]
      ..sort((a, b) => a.start.compareTo(b.start));
    return Forecast(slots: slots, weatherCodes: codes, fetchedAt: DateTime.now());
  }
}
