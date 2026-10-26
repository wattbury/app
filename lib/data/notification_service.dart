import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'app_settings.dart';
import 'live_controller.dart';
import 'notifications.dart';

/// Watches the live values while the app runs, evaluates the rules and delivers alerts as system
/// notifications and as an in-app stream. Background delivery needs the bridge (later).
class NotificationService extends ChangeNotifier {
  final AppSettings settings;
  final RuleEngine engine = RuleEngine();

  /// Shows a system notification; replaceable in tests.
  final Future<void> Function(int id, Alert alert) deliver;

  final _alerts = StreamController<Alert>.broadcast();
  final List<Alert> recent = [];
  LiveController? _live;
  bool systemAvailable = false;

  NotificationService(this.settings, {Future<void> Function(int, Alert)? deliver}) : deliver = deliver ?? _showSystem;

  /// In-app stream, e.g. for a banner.
  Stream<Alert> get alerts => _alerts.stream;

  static final _plugin = FlutterLocalNotificationsPlugin();

  /// Sets up system notifications; on iOS this asks for permission. Failure (e.g. no notification
  /// service on a Linux desktop) leaves the in-app banner as the only channel.
  Future<void> init() async {
    try {
      final ok = await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: DarwinInitializationSettings(),
          macOS: DarwinInitializationSettings(),
          linux: LinuxInitializationSettings(defaultActionName: 'Öffnen'),
        ),
      );
      systemAvailable = ok ?? false;
    } catch (_) {
      systemAvailable = false;
    }
    notifyListeners();
  }

  static Future<void> _showSystem(int id, Alert a) => _plugin.show(
    id: id,
    title: a.title,
    body: a.body,
    notificationDetails: const NotificationDetails(
      android: AndroidNotificationDetails('rules', 'Regeln', importance: Importance.high),
      iOS: DarwinNotificationDetails(),
      macOS: DarwinNotificationDetails(),
      linux: LinuxNotificationDetails(),
    ),
  );

  void attach(LiveController live) {
    _live?.removeListener(_onLive);
    _live = live..addListener(_onLive);
  }

  void _onLive() {
    final l = _live;
    if (l == null) return;
    check(l, DateTime.now());
  }

  /// Evaluates the rules once; public for tests.
  Future<void> check(LiveController l, DateTime now) async {
    final found = engine.evaluate(settings.rules, live: l.live, online: l.state == ConnState.online, now: now);
    for (final a in found) {
      recent.insert(0, a);
      if (recent.length > 20) recent.removeLast();
      _alerts.add(a);
      if (systemAvailable) {
        try {
          await deliver(a.ruleId.hashCode & 0x7fffffff, a);
        } catch (_) {
          // The in-app banner still shows it.
        }
      }
    }
    if (found.isNotEmpty) notifyListeners();
  }

  @override
  void dispose() {
    _live?.removeListener(_onLive);
    _alerts.close();
    super.dispose();
  }
}
