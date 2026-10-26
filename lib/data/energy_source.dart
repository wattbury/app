import 'dart:math' as math;

import 'package:openrscp/openrscp.dart';

import 'credentials.dart';

/// Where the app gets its data from: local RSCP or the portal tunnel, picked by [AutoSource].
/// Cloud API and bridge may follow as further implementations (docs/02-architektur.md).
abstract class EnergySource {
  /// Short label for the header, e.g. "RSCP Portal".
  String get label;

  /// Suggested polling interval for live values.
  Duration get liveInterval;

  Future<void> connect();
  Future<void> close();
  Future<LiveSnapshot> live();
  Future<SystemInfo> systemInfo();

  /// Energy totals since local midnight.
  Future<DbSummary> today();
  Future<List<PvTracker>> trackers();
  Future<List<WallboxInfo>> wallboxes();

  /// Database time series from [start] over [span] in buckets of [interval].
  Future<DbHistory> history(DateTime start, Duration interval, Duration span);

  /// Housekeeping between polls, e.g. switching back to a faster connection.
  Future<void> maintain();
}

/// RSCP over any [RscpTransport]; the transport decides whether it goes local or through the portal.
class RscpSource implements EnergySource {
  final RscpTransport Function() _create;
  @override
  final String label;

  /// Read on every poll, so a changed setting applies without reconnecting.
  final Duration Function() interval;
  RscpTransport? _t;
  E3dcClient? _c;

  RscpSource(this._create, {required this.label, required this.interval});

  @override
  Duration get liveInterval => interval();

  /// Direct connection in the home network; fast enough for one-second updates.
  factory RscpSource.local(Credentials c, {Duration Function()? interval}) => RscpSource(
    () => LocalTransport(
      host: c.local!.host,
      port: c.local!.port,
      username: c.username,
      password: c.password!,
      rscpPassword: c.local!.rscpPassword,
      timeout: const Duration(seconds: 4),
    ),
    label: 'RSCP lokal',
    interval: interval ?? () => const Duration(seconds: 1),
  );

  /// Through the E3/DC portal relay. The relay is shared infrastructure; poll it more gently.
  factory RscpSource.portal(Credentials c, {Duration Function()? interval}) => RscpSource(
    () => PortalTransport(username: c.username, password: c.passwordMd5, passwordIsMd5: true, serial: c.serial!),
    label: 'RSCP Portal',
    interval: interval ?? () => const Duration(seconds: 5),
  );

  E3dcClient get _client => _c ?? (throw RscpTransportException('not connected'));

  @override
  Future<void> connect() async {
    await _t?.close();
    final t = _create();
    try {
      await t.connect();
    } catch (_) {
      await t.close();
      rethrow;
    }
    _t = t;
    _c = E3dcClient(t);
  }

  @override
  Future<void> close() async {
    await _t?.close();
    _t = null;
    _c = null;
  }

  @override
  Future<void> maintain() async {}

  @override
  Future<LiveSnapshot> live() => _client.live();

  @override
  Future<SystemInfo> systemInfo() => _client.systemInfo();

  @override
  Future<DbSummary> today() {
    final now = DateTime.now();
    return _client.dbSummary(DateTime(now.year, now.month, now.day), const Duration(days: 1));
  }

  @override
  Future<DbHistory> history(DateTime start, Duration interval, Duration span) =>
      _client.dbHistory(start, interval, span);

  @override
  Future<List<PvTracker>> trackers() async => (await _client.pvTrackers()).where((t) => t.active).toList();

  @override
  Future<List<WallboxInfo>> wallboxes() => _client.detectWallboxes();
}

/// Picks the best way like my4E: local first when configured, the portal otherwise. While on the
/// portal it tries the local connection again every minute, so coming home switches back by itself.
class AutoSource implements EnergySource {
  final RscpSource? local, portal;
  RscpSource? _active;
  DateTime _lastLocalTry = DateTime(0);
  static const _retryLocal = Duration(minutes: 1);

  AutoSource(Credentials c, {Duration Function()? localInterval, Duration Function()? portalInterval})
    : local = c.hasLocal ? RscpSource.local(c, interval: localInterval) : null,
      portal = c.hasPortal ? RscpSource.portal(c, interval: portalInterval) : null;

  RscpSource get _src => _active ?? (throw RscpTransportException('not connected'));

  @override
  String get label => _active?.label ?? (local != null ? 'RSCP lokal' : 'RSCP Portal');

  @override
  Duration get liveInterval => (_active ?? local ?? portal)!.liveInterval;

  @override
  Future<void> connect() async {
    await _active?.close();
    _active = null;
    Object? localError;
    if (local != null) {
      _lastLocalTry = DateTime.now();
      try {
        await local!.connect();
        _active = local;
        return;
      } catch (e) {
        localError = e;
      }
    }
    if (portal == null) throw localError ?? RscpTransportException('no connection configured');
    await portal!.connect();
    _active = portal;
  }

  @override
  Future<void> maintain() async {
    if (local == null || identical(_active, local)) return;
    if (DateTime.now().difference(_lastLocalTry) < _retryLocal) return;
    _lastLocalTry = DateTime.now();
    try {
      await local!.connect();
    } catch (_) {
      return;
    }
    final old = _active;
    _active = local;
    await old?.close();
  }

  @override
  Future<void> close() async {
    await local?.close();
    await portal?.close();
    _active = null;
  }

  @override
  Future<LiveSnapshot> live() => _src.live();
  @override
  Future<SystemInfo> systemInfo() => _src.systemInfo();
  @override
  Future<DbSummary> today() => _src.today();
  @override
  Future<DbHistory> history(DateTime start, Duration interval, Duration span) => _src.history(start, interval, span);
  @override
  Future<List<PvTracker>> trackers() => _src.trackers();
  @override
  Future<List<WallboxInfo>> wallboxes() => _src.wallboxes();
}

/// Sample values for trying the app without an E3/DC login, and for tests and screenshots.
/// Shaped like the test system: two trackers, no wallbox.
class DemoSource implements EnergySource {
  final DateTime Function() clock;
  DemoSource({DateTime Function()? clock}) : clock = clock ?? DateTime.now;

  @override
  String get label => 'Demo';

  @override
  Duration get liveInterval => const Duration(seconds: 1);

  @override
  Future<void> connect() async {}

  @override
  Future<void> close() async {}

  @override
  Future<void> maintain() async {}

  /// Clear-sky bell between 07:50 and 18:20 with a little jitter, 7.4 kW peak.
  double _solarW(DateTime t) {
    final h = t.hour + t.minute / 60 + t.second / 3600;
    const rise = 7 + 50 / 60, set = 18 + 20 / 60;
    if (h <= rise || h >= set) return 0;
    final s = math.pow(math.sin(math.pi * (h - rise) / (set - rise)), 1.4).toDouble();
    return 7400 * s * (0.94 + 0.06 * math.sin(t.second / 3));
  }

  @override
  Future<LiveSnapshot> live() async {
    final now = clock();
    final solar = _solarW(now).round();
    const house = 612;
    final surplus = solar - house;
    final battery = surplus > 0 ? math.min(surplus, 4500) : -math.min(-surplus, 1500);
    final grid = -(surplus - battery);
    return LiveSnapshot(
      solarW: solar,
      batteryW: battery,
      houseW: house,
      gridW: grid,
      additionalW: 0,
      wallboxW: 0,
      wallboxSolarW: 0,
      soc: 68,
      autarkyPct: 96.6,
      selfConsumptionPct: 70.4,
      receivedAt: now,
    );
  }

  @override
  Future<SystemInfo> systemInfo() async => const SystemInfo(
    serial: 'S10-000000000000',
    swRelease: 'S10_2026_027',
    productionDate: '',
    macAddress: '',
    installedPeakPowerW: 10740,
    derateAtPercent: 70,
    derateAtPowerW: 7518,
  );

  @override
  Future<DbSummary> today() async {
    final now = clock();
    return DbSummary(
      start: DateTime(now.year, now.month, now.day),
      span: const Duration(days: 1),
      solarWh: 14200,
      houseWh: 8700,
      gridPurchaseWh: 310,
      gridFeedInWh: 4220,
      batteryInWh: 4800,
      batteryOutWh: 3200,
      autarkyPct: 96.6,
      consumedProductionPct: 70.4,
      socPct: 68,
    );
  }

  /// Deterministic sample series: hourly or daily energy with a seasonal and a per-day weather factor.
  @override
  Future<DbHistory> history(DateTime start, Duration interval, Duration span) async {
    final n = (span.inSeconds / interval.inSeconds).round();
    final now = clock();
    final buckets = <DbBucket>[];
    for (var i = 0; i < n; i++) {
      final t = start.add(interval * i);
      if (t.isAfter(now)) break;
      final season = 0.35 + 0.65 * math.pow(math.sin(math.pi * (t.month - 0.5) / 12), 2);
      final weather = 0.35 + 0.65 * ((math.sin(t.year * 13.0 + t.month * 7.0 + t.day * 3.1) + 1) / 2);
      double solar, house;
      if (interval <= const Duration(hours: 1)) {
        final h = t.hour + t.minute / 60 + interval.inMinutes / 120;
        final sun = h > 6 && h < 20 ? math.pow(math.sin(math.pi * (h - 6) / 14), 1.5).toDouble() : 0.0;
        solar = 7400 * season * weather * sun * interval.inMinutes / 60;
        house = (300 + (h >= 7 && h < 9 ? 500 : 0) + (h >= 18 && h < 22 ? 900 : 0)) * interval.inMinutes / 60;
      } else {
        final days = interval.inHours / 24;
        solar = 42000 * season * weather * days;
        house = (11000 - 3000 * season) * days;
      }
      final direct = math.min(solar, house * 0.55);
      // At most one full battery (13 kWh, used 9 kWh a day) per day of the interval.
      final batteryIn = math.min(solar - direct, interval.inHours >= 24 ? 9000.0 * interval.inDays : 1500.0);
      final feedIn = solar - direct - batteryIn;
      // Within an hour the battery either charges or discharges; over days it does both.
      final batteryOut = interval <= const Duration(hours: 1)
          ? (solar >= house ? 0.0 : (house - direct) * 0.8)
          : math.min(batteryIn * 0.9, (house - direct) * 0.8);
      final purchase = math.max(0.0, house - direct - batteryOut);
      buckets.add(
        DbBucket(
          index: i.toDouble(),
          solar: solar,
          house: house,
          gridPurchase: purchase,
          gridFeedIn: feedIn,
          batteryIn: batteryIn,
          batteryOut: batteryOut,
          autarkyPct: house == 0 ? 0 : (1 - purchase / house) * 100,
          consumedProductionPct: solar == 0 ? 0 : (1 - feedIn / solar) * 100,
          socPct: 60,
        ),
      );
    }
    double s(double Function(DbBucket) f) => buckets.fold(0, (a, b) => a + f(b));
    final solar = s((b) => b.solar), house = s((b) => b.house);
    final purchase = s((b) => b.gridPurchase), feedIn = s((b) => b.gridFeedIn);
    return DbHistory(
      start: start,
      interval: interval,
      span: span,
      buckets: buckets,
      sum: DbSummary(
        start: start,
        span: span,
        solarWh: solar,
        houseWh: house,
        gridPurchaseWh: purchase,
        gridFeedInWh: feedIn,
        batteryInWh: s((b) => b.batteryIn),
        batteryOutWh: s((b) => b.batteryOut),
        autarkyPct: house == 0 ? 0 : (1 - purchase / house) * 100,
        consumedProductionPct: solar == 0 ? 0 : (1 - feedIn / solar) * 100,
        socPct: 60,
      ),
    );
  }

  @override
  Future<List<PvTracker>> trackers() async {
    final solar = _solarW(clock());
    return [
      PvTracker(pviIndex: 0, index: 0, active: true, powerW: solar * 0.53, voltageV: 412),
      PvTracker(pviIndex: 0, index: 1, active: true, powerW: solar * 0.47, voltageV: 398),
    ];
  }

  @override
  Future<List<WallboxInfo>> wallboxes() async => const [];
}
