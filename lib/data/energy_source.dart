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

  /// Housekeeping between polls, e.g. switching back to a faster connection.
  Future<void> maintain();
}

/// RSCP over any [RscpTransport]; the transport decides whether it goes local or through the portal.
class RscpSource implements EnergySource {
  final RscpTransport Function() _create;
  @override
  final String label;
  @override
  final Duration liveInterval;
  RscpTransport? _t;
  E3dcClient? _c;

  RscpSource(this._create, {required this.label, required this.liveInterval});

  /// Direct connection in the home network; fast enough for one-second updates.
  factory RscpSource.local(Credentials c) => RscpSource(
    () => LocalTransport(
      host: c.local!.host,
      port: c.local!.port,
      username: c.username,
      password: c.password!,
      rscpPassword: c.local!.rscpPassword,
      timeout: const Duration(seconds: 4),
    ),
    label: 'RSCP lokal',
    liveInterval: const Duration(seconds: 1),
  );

  /// Through the E3/DC portal relay. The relay is shared infrastructure; poll it more gently.
  factory RscpSource.portal(Credentials c) => RscpSource(
    () => PortalTransport(username: c.username, password: c.passwordMd5, passwordIsMd5: true, serial: c.serial!),
    label: 'RSCP Portal',
    liveInterval: const Duration(seconds: 2),
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

  AutoSource(Credentials c)
    : local = c.hasLocal ? RscpSource.local(c) : null,
      portal = c.hasPortal ? RscpSource.portal(c) : null;

  RscpSource get _src => _active ?? (throw RscpTransportException('not connected'));

  @override
  String get label => _active?.label ?? (local != null ? 'RSCP lokal' : 'RSCP Portal');

  @override
  Duration get liveInterval => _active?.liveInterval ?? const Duration(seconds: 2);

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
