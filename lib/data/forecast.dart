import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'plant.dart';

/// Expected average PV power in one 15-minute slot, in W, before any learned correction.
class ForecastSlot {
  final DateTime start;
  final double watts;
  const ForecastSlot(this.start, this.watts);

  /// Energy of the slot in Wh.
  double get wh => watts / 4;
}

class Forecast {
  final List<ForecastSlot> slots;

  /// WMO weather code per day (local date at midnight), from the provider if it has one.
  final Map<DateTime, int> weatherCodes;
  final DateTime fetchedAt;
  const Forecast({required this.slots, required this.weatherCodes, required this.fetchedAt});

  /// Energy in Wh between [from] and [to].
  double wh(DateTime from, DateTime to) =>
      slots.where((s) => !s.start.isBefore(from) && s.start.isBefore(to)).fold(0, (a, s) => a + s.wh);

  double dayWh(DateTime day) {
    final d = DateTime(day.year, day.month, day.day);
    return wh(d, DateTime(d.year, d.month, d.day + 1));
  }
}

/// Short German weather text for a WMO weather code.
String weatherText(int code) => switch (code) {
  0 => 'sonnig',
  1 || 2 => 'heiter',
  3 => 'bewölkt',
  45 || 48 => 'Nebel',
  >= 51 && <= 57 => 'Niesel',
  >= 61 && <= 67 => 'Regen',
  >= 71 && <= 77 => 'Schnee',
  >= 80 && <= 82 => 'Schauer',
  85 || 86 => 'Schneeschauer',
  >= 95 => 'Gewitter',
  _ => '',
};

/// Small JSON GET without extra packages; works on iOS, Android and desktop.
Future<Object?> getJson(Uri url, {Map<String, String> headers = const {}}) async {
  final http = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  try {
    final req = await http.getUrl(url);
    headers.forEach(req.headers.set);
    final res = await req.close().timeout(const Duration(seconds: 20));
    final body = await res.transform(utf8.decoder).join();
    if (res.statusCode != 200) throw HttpException('HTTP ${res.statusCode}: $body', uri: url);
    return jsonDecode(body);
  } finally {
    http.close(force: true);
  }
}

/// Open-Meteo: free, no account. Asks per tracker for the irradiance on the tilted plane and the
/// air temperature, then turns that into power itself. Only location, azimuth and tilt are sent.
class OpenMeteo {
  final Future<Object?> Function(Uri) _get;
  OpenMeteo({Future<Object?> Function(Uri)? get}) : _get = get ?? getJson;

  /// Losses for inverter, wiring, soiling and mismatch; the learned factor refines this.
  static const performanceRatio = 0.86;

  /// Power change of crystalline modules per kelvin above 25 °C cell temperature.
  static const tempCoefficient = -0.0037;

  /// Average PV power in W for [kwp] at irradiance [gti] (W/m²) and air temperature [airC].
  static double power(double kwp, double gti, double airC) {
    if (gti <= 0) return 0;
    // Cell temperature from the NOCT model (45 °C at 800 W/m², 20 °C air).
    final cell = airC + gti / 800 * 25;
    final temp = 1 + tempCoefficient * (cell - 25);
    return kwp * 1000 * gti / 1000 * performanceRatio * temp;
  }

  Future<Forecast> fetch(PlantConfig plant, {int days = 3}) async {
    final sum = <DateTime, double>{};
    Map<DateTime, int> codes = const {};
    for (final t in plant.trackers.where((t) => t.kwp > 0)) {
      final url = Uri.https('api.open-meteo.com', '/v1/forecast', {
        'latitude': plant.latitude!.toStringAsFixed(4),
        'longitude': plant.longitude!.toStringAsFixed(4),
        'minutely_15': 'global_tilted_irradiance,temperature_2m',
        'tilt': '${t.tilt}',
        'azimuth': '${t.azimuthSouth}',
        'forecast_days': '$days',
        'timezone': 'auto',
        if (codes.isEmpty) 'daily': 'weather_code',
      });
      final j = await _get(url) as Map<String, dynamic>;
      final m = j['minutely_15'] as Map<String, dynamic>;
      final times = (m['time'] as List).cast<String>();
      final gti = m['global_tilted_irradiance'] as List, temp = m['temperature_2m'] as List;
      for (var i = 0; i < times.length; i++) {
        // Radiation values are the mean of the preceding 15 minutes; the slot starts 15 minutes earlier.
        final start = DateTime.parse(times[i]).subtract(const Duration(minutes: 15));
        final w = power(t.kwp, (gti[i] as num?)?.toDouble() ?? 0, (temp[i] as num?)?.toDouble() ?? 15);
        sum[start] = (sum[start] ?? 0) + w;
      }
      final daily = j['daily'] as Map<String, dynamic>?;
      if (daily != null) {
        final dt = (daily['time'] as List).cast<String>(), wc = daily['weather_code'] as List;
        codes = {for (var i = 0; i < dt.length; i++) DateTime.parse(dt[i]): (wc[i] as num?)?.toInt() ?? -1};
      }
    }
    final slots = [for (final e in sum.entries) ForecastSlot(e.key, e.value)]
      ..sort((a, b) => a.start.compareTo(b.start));
    return Forecast(slots: slots, weatherCodes: codes, fetchedAt: DateTime.now());
  }

  /// Coordinates for a postcode and city via Open-Meteo's geocoding (GeoNames). Searches by city
  /// and prefers the result that lists the postcode.
  Future<({double lat, double lon, String label})?> locate(
    String postcode,
    String city, {
    String country = 'DE',
  }) async {
    final q = city.isNotEmpty ? city : postcode;
    if (q.isEmpty) return null;
    final j = await _get(
      Uri.https('geocoding-api.open-meteo.com', '/v1/search', {
        'name': q,
        'count': '20',
        'language': 'de',
        if (country.length == 2) 'countryCode': country.toUpperCase(),
      }),
    ) as Map<String, dynamic>;
    final results = (j['results'] as List? ?? const []).cast<Map<String, dynamic>>();
    if (results.isEmpty) return null;
    final match = results.firstWhere(
      (r) => ((r['postcodes'] as List?) ?? const []).contains(postcode),
      orElse: () => results.first,
    );
    return (
      lat: (match['latitude'] as num).toDouble(),
      lon: (match['longitude'] as num).toDouble(),
      label: [postcode, city].where((s) => s.isNotEmpty).join(' '),
    );
  }
}

/// Keeps the forecast fresh (hourly) for the configured plant.
class ForecastService extends ChangeNotifier {
  final OpenMeteo provider;
  PlantConfig _plant;
  Forecast? forecast;
  String? error;
  Timer? _timer;
  bool _loading = false;

  ForecastService(this._plant, {OpenMeteo? provider}) : provider = provider ?? OpenMeteo() {
    refresh();
    _timer = Timer.periodic(const Duration(hours: 1), (_) => refresh());
  }

  PlantConfig get plant => _plant;
  set plant(PlantConfig p) {
    _plant = p;
    forecast = null;
    refresh();
  }

  Future<void> refresh() async {
    if (_loading || !_plant.complete) {
      if (!_plant.complete) {
        forecast = null;
        notifyListeners();
      }
      return;
    }
    _loading = true;
    try {
      forecast = await provider.fetch(_plant);
      error = null;
    } catch (e) {
      error = '$e';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
