import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:openrscp/openrscp.dart';

import 'energy_source.dart';

enum ConnState { connecting, online, offline }

/// Keeps one [EnergySource] connected and polls it: live values at the source's interval,
/// PV trackers every few seconds, today's totals once a minute (with [EnergySource.maintain], which
/// may switch from the portal back to the local connection). Reconnects with backoff.
class LiveController extends ChangeNotifier {
  final EnergySource source;
  LiveController(this.source);

  static const _trackerEvery = Duration(seconds: 5);
  static const _todayEvery = Duration(minutes: 1);

  ConnState state = ConnState.connecting;
  String? error;
  LiveSnapshot? live;
  DbSummary? today;
  SystemInfo? system;
  List<PvTracker> trackers = const [];
  List<WallboxInfo> wallboxes = const [];

  Timer? _timer;
  bool _busy = false, _disposed = false;
  DateTime _trackersAt = DateTime(0), _todayAt = DateTime(0);
  int _failures = 0;

  Future<void> start() => _connect();

  Future<void> _connect() async {
    _timer?.cancel();
    _set(() {
      state = ConnState.connecting;
      error = null;
    });
    try {
      await source.connect();
      system = await source.systemInfo();
      wallboxes = await source.wallboxes();
      _failures = 0;
      _trackersAt = _todayAt = DateTime(0);
      _set(() => state = ConnState.online);
      await _poll();
    } catch (e) {
      _fail(e);
    }
  }

  /// Fetches everything now, also today's totals; for the refresh button.
  Future<void> refresh() async {
    if (state != ConnState.online) return _connect();
    _trackersAt = _todayAt = DateTime(0);
    await _poll();
  }

  Future<void> _poll() async {
    if (_busy || _disposed) return;
    _busy = true;
    _timer?.cancel();
    try {
      live = await source.live();
      final now = DateTime.now();
      if (now.difference(_trackersAt) >= _trackerEvery) {
        trackers = await source.trackers();
        _trackersAt = now;
      }
      if (now.difference(_todayAt) >= _todayEvery) {
        await source.maintain();
        today = await source.today();
        _todayAt = now;
      }
      _set(() {
        state = ConnState.online;
        error = null;
      });
      _schedule(source.liveInterval, _poll);
    } catch (e) {
      _fail(e);
    } finally {
      _busy = false;
    }
  }

  void _fail(Object e) {
    _failures++;
    _set(() {
      state = ConnState.offline;
      error = e is RscpAuthException ? 'Anmeldung abgelehnt. Bitte Zugangsdaten prüfen.' : e.toString();
    });
    if (e is RscpAuthException) return;
    final wait = Duration(seconds: [2, 5, 10, 30][(_failures - 1).clamp(0, 3)]);
    _schedule(wait, _connect);
  }

  void _schedule(Duration d, Future<void> Function() f) {
    if (_disposed) return;
    _timer?.cancel();
    _timer = Timer(d, f);
  }

  void _set(VoidCallback f) {
    if (_disposed) return;
    f();
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    source.close();
    super.dispose();
  }
}
