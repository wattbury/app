import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'app_settings.dart';
import 'correction.dart';
import 'energy_source.dart';
import 'history.dart';
import 'live_controller.dart';
import 'plant.dart';
import 'solcast.dart';

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

  Map<String, Object> toJson() => {
    'at': fetchedAt.toIso8601String(),
    's': [
      for (final x in slots) [x.start.toIso8601String(), x.watts.round()],
    ],
    'w': {for (final e in weatherCodes.entries) e.key.toIso8601String(): e.value},
  };

  static Forecast fromJson(Map<String, dynamic> j) => Forecast(
    fetchedAt: DateTime.parse(j['at'] as String),
    slots: [for (final x in j['s'] as List) ForecastSlot(DateTime.parse(x[0] as String), (x[1] as num).toDouble())],
    weatherCodes: {
      for (final e in (j['w'] as Map<String, dynamic>).entries) DateTime.parse(e.key): (e.value as num).toInt(),
    },
  );
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

/// Small JSON GET; package:http uses dart:io natively and fetch in the browser.
Future<Object?> getJson(Uri url, {Map<String, String> headers = const {}}) async {
  final res = await http.get(url, headers: headers).timeout(const Duration(seconds: 30));
  final body = utf8.decode(res.bodyBytes);
  if (res.statusCode != 200) throw http.ClientException('HTTP ${res.statusCode}: $body', url);
  return jsonDecode(body);
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

  /// Daily weather codes only, for providers that deliver power but no weather.
  Future<Map<DateTime, int>> weather(double lat, double lon, {int days = 3}) async {
    final j = await _get(
      Uri.https('api.open-meteo.com', '/v1/forecast', {
        'latitude': lat.toStringAsFixed(4),
        'longitude': lon.toStringAsFixed(4),
        'daily': 'weather_code',
        'forecast_days': '$days',
        'timezone': 'auto',
      }),
    ) as Map<String, dynamic>;
    final d = j['daily'] as Map<String, dynamic>;
    final dt = (d['time'] as List).cast<String>(), wc = d['weather_code'] as List;
    return {for (var i = 0; i < dt.length; i++) DateTime.parse(dt[i]): (wc[i] as num?)?.toInt() ?? -1};
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

/// Keeps the forecast fresh (hourly) for the configured plant, archives what it promised for each
/// day, learns a correction from the unit's measurements once a day and applies it.
class ForecastService extends ChangeNotifier {
  final AppSettings settings;
  final OpenMeteo provider;
  final Solcast solcast;

  /// Reads and stores the Solcast API key in the keychain.
  final Future<String?> Function() solcastKey;
  final Future<void> Function(String?) saveSolcastKey;
  Forecast? _raw;
  String? error;
  Correction correction = Correction.none;
  DateTime? learnedAt;
  Timer? _timer;
  bool _loading = false, _learning = false;
  LiveController? _live;

  /// Provider id used in storage keys, so a change of provider starts learning afresh.
  String get _id => settings.forecastProvider;
  static const _keepDays = 40;

  /// Solcast's free plan allows few requests a day: fetch at most every 3 hours, only in daylight,
  /// and keep the last result across restarts.
  static const _solcastEvery = Duration(hours: 3);
  String get _cacheKey => 'fcCache.$_id';
  String get _archiveKey => 'fcArchive.$_id';
  String get _recordsKey => 'fcRecords.$_id';

  ForecastService(
    this.settings, {
    OpenMeteo? provider,
    Solcast? solcast,
    Future<String?> Function()? solcastKey,
    Future<void> Function(String?)? saveSolcastKey,
  }) : provider = provider ?? OpenMeteo(),
       solcast = solcast ?? Solcast(fallback: provider),
       solcastKey = solcastKey ?? (() async => null),
       saveSolcastKey = saveSolcastKey ?? ((_) async {}) {
    correction = Correction.compute(_records());
    refresh();
    _timer = Timer.periodic(const Duration(hours: 1), (_) => refresh());
  }

  PlantConfig get plant => settings.plant;
  set plant(PlantConfig p) {
    _raw = null;
    refresh();
  }

  /// Forecast as shown: corrected when learning is on and has enough days.
  Forecast? get forecast {
    final r = _raw;
    if (r == null || !settings.correctionEnabled || !correction.ready) return r;
    return Forecast(
      slots: [for (final s in r.slots) ForecastSlot(s.start, s.watts * correction.factorAt(s.start))],
      weatherCodes: r.weatherCodes,
      fetchedAt: r.fetchedAt,
    );
  }

  Forecast? get rawForecast => _raw;

  /// Call after switching the provider: shows that provider's forecast and learning.
  void providerChanged() {
    _raw = null;
    correction = Correction.compute(_records());
    learnedAt = null;
    refresh(force: true);
  }

  /// [force] ignores Solcast's request budget, e.g. for "Zugang prüfen".
  Future<void> refresh({bool force = false}) async {
    final p = settings.plant;
    if (!p.complete) {
      _raw = null;
      notifyListeners();
      return;
    }
    if (_loading) return;
    _loading = true;
    try {
      if (_id == 'sc') {
        final cached = _readCache();
        final now = DateTime.now();
        final daylight = now.hour >= 5 && now.hour < 21;
        if (!force && cached != null && (now.difference(cached.fetchedAt) < _solcastEvery || !daylight)) {
          _raw = cached;
        } else {
          final key = await solcastKey();
          if (key == null || key.isEmpty) throw StateError('Solcast: API-Key fehlt');
          _raw = await solcast.fetch(p, key, settings.solcastSites);
          await settings.writeRaw(_cacheKey, jsonEncode(_raw!.toJson()));
        }
      } else {
        _raw = await provider.fetch(p);
      }
      error = null;
      await _archive(_raw!);
    } catch (e) {
      error = '$e';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Forecast? _readCache() {
    final raw = settings.readRaw(_cacheKey);
    if (raw == null) return null;
    try {
      return Forecast.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  // ---------- archive of what was forecast, per day and slot ----------

  Map<String, dynamic> _readArchive() {
    final raw = settings.readRaw(_archiveKey);
    if (raw == null) return {};
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }

  static String _date(DateTime d) => d.toIso8601String().substring(0, 10);
  static String _hm(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  /// Keeps the latest forecast for each day; the most recent one before a slot is the fairest
  /// comparison for that slot.
  Future<void> _archive(Forecast f) async {
    final a = _readArchive();
    final today = DateTime.now();
    for (final s in f.slots) {
      final day = DateTime(s.start.year, s.start.month, s.start.day);
      if (day.isBefore(DateTime(today.year, today.month, today.day))) continue;
      final m = (a[_date(day)] as Map<String, dynamic>?) ?? <String, dynamic>{};
      m[_hm(s.start)] = s.watts.round();
      a[_date(day)] = m;
    }
    final cutoff = _date(DateTime(today.year, today.month, today.day - _keepDays));
    a.removeWhere((k, _) => k.compareTo(cutoff) < 0);
    await settings.writeRaw(_archiveKey, jsonEncode(a));
  }

  List<DayRecord> _records() {
    final raw = settings.readRaw(_recordsKey);
    if (raw == null) return [];
    try {
      return [for (final j in jsonDecode(raw) as List) DayRecord.fromJson(j as Map<String, dynamic>)];
    } catch (_) {
      return [];
    }
  }

  List<DayRecord> get records => _records();

  // ---------- learning ----------

  /// Learns from [live]'s source whenever it is online and has not learned today.
  void attach(LiveController live) {
    _live?.removeListener(_onLive);
    _live = live..addListener(_onLive);
    _onLive();
  }

  void _onLive() {
    final l = _live;
    if (l == null || l.state != ConnState.online || _learning) return;
    final now = DateTime.now();
    if (learnedAt != null && learnedAt!.day == now.day && learnedAt!.month == now.month) return;
    learn(l.source, feedLimitW: l.system?.derateAtPowerW);
  }

  /// Compares archived forecasts of past days with the 15-minute values from the unit's database.
  Future<void> learn(EnergySource source, {int? feedLimitW, DateTime? now}) async {
    if (_learning) return;
    _learning = true;
    try {
      final t = now ?? DateTime.now();
      final today = DateTime(t.year, t.month, t.day);
      final archive = _readArchive();
      final records = _records();
      final known = {for (final r in records) _date(r.day)};
      final kwp = settings.plant.kwp;
      for (final key in archive.keys.toList()..sort()) {
        final day = DateTime.parse(key);
        if (!day.isBefore(today) || known.contains(key)) continue;
        final next = DateTime(day.year, day.month, day.day + 1);
        const step = Duration(minutes: 15);
        final starts = [for (var s = day; s.isBefore(next); s = s.add(step)) s];
        final h = await source.history(day, step, next.difference(day));
        final pts = HistoryRepository.toPoints(h, starts);
        final fc = archive[key] as Map<String, dynamic>;
        records.add(
          DayRecord.fromSlots(
            day: day,
            actualWh: [for (final p in pts) p.solar],
            forecastWh: [for (final s in starts) ((fc[_hm(s)] as num?)?.toDouble() ?? 0) / 4],
            feedInWh: [for (final p in pts) p.feedIn],
            slotStarts: starts,
            kwp: kwp,
            feedLimitW: feedLimitW,
          ),
        );
      }
      final cutoff = DateTime(today.year, today.month, today.day - _keepDays);
      records.removeWhere((r) => r.day.isBefore(cutoff));
      records.sort((a, b) => a.day.compareTo(b.day));
      await settings.writeRaw(_recordsKey, jsonEncode([for (final r in records) r.toJson()]));
      correction = Correction.compute(records, today: today);
      learnedAt = t;
      error = null;
    } catch (e) {
      error = 'Lernen fehlgeschlagen: $e';
    } finally {
      _learning = false;
      notifyListeners();
    }
  }

  /// Forgets what was learned; the archive of forecasts stays, so learning restarts from tomorrow.
  Future<void> resetLearning() async {
    await settings.removeRaw(_recordsKey);
    correction = Correction.none;
    learnedAt = DateTime.now();
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _live?.removeListener(_onLive);
    super.dispose();
  }
}
