import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:openrscp/openrscp.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wattbury/data/app_settings.dart';
import 'package:wattbury/data/credentials.dart';
import 'package:wattbury/data/energy_source.dart';
import 'package:wattbury/data/forecast.dart';
import 'package:wattbury/data/live_controller.dart';
import 'package:wattbury/theme/tokens.dart';
import 'package:wattbury/ui/shell.dart';

/// Like RscpSource before the connection is up: every call throws "not connected" synchronously.
class NotConnected extends DemoSource {
  Never _no() => throw RscpTransportException('not connected');
  @override
  String get label => 'RSCP lokal';
  @override
  Future<void> connect() async => throw RscpTransportException('connection refused');
  @override
  Future<LiveSnapshot> live() => _no();
  @override
  Future<SystemInfo> systemInfo() => _no();
  @override
  Future<DbSummary> today() => _no();
  @override
  Future<DbHistory> history(DateTime start, Duration interval, Duration span) => _no();
  @override
  Future<PowerSettings> powerSettings() => _no();
  @override
  Future<Map<String, int>> sysSpecs() => _no();
  @override
  Future<List<IdlePeriod>> idlePeriods() => _no();
  @override
  Future<({String postcode, String city, String country})> facilityLocation() => _no();
}

void main() {
  setUpAll(() => initializeDateFormatting('de_DE'));

  testWidgets('starting without a connection raises no unhandled errors', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final settings = await AppSettings.load();
    final live = LiveController(NotConnected());
    final forecast = ForecastService(settings, provider: OpenMeteo(get: (_) async => throw StateError('offline')));
    forecast.attach(live);
    await tester.runAsync(live.start);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.light),
        home: Shell(
          live: live,
          settings: settings,
          credentials: const Credentials(username: 'u', passwordMd5: 'x', serial: 'S10-1'),
          forecast: forecast,
          onSignOut: () {},
          onEditConnection: () {},
        ),
      ),
    );
    for (final tab in ['Diagramme', 'Fluss', 'Smart', 'Einstellungen', 'Monitor']) {
      await tester.tap(find.text(tab).last);
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }
    expect(tester.takeException(), isNull);
    live.dispose();
    forecast.dispose();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('pages wait for the connection and load once it is up', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final settings = await AppSettings.load();
    final gate = Completer<void>();
    final src = GatedDemo(gate.future);
    final live = LiveController(src);
    unawaited(live.start());
    await tester.pumpWidget(
      ListenableBuilder(
        listenable: live,
        builder: (context, _) => MaterialApp(
          theme: buildTheme(Brightness.light),
          home: Shell(
            live: live,
            settings: settings,
            credentials: const Credentials(username: 'u', passwordMd5: 'x', serial: 'S10-1'),
            onSignOut: () {},
            onEditConnection: () {},
          ),
        ),
      ),
    );
    await tester.pump();
    expect(src.historyCalls, 0, reason: 'nothing asked before the connection is up');
    expect(src.smartCalls, 0);
    gate.complete();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
    expect(src.historyCalls, greaterThan(0));
    expect(src.smartCalls, greaterThan(0));
    live.dispose();
    await tester.pumpWidget(const SizedBox());
  });
}

/// Demo source whose connect() waits for [gate] and which counts history and smart reads.
class GatedDemo extends DemoSource {
  final Future<void> gate;
  int historyCalls = 0, smartCalls = 0;
  GatedDemo(this.gate);
  @override
  Future<void> connect() => gate;
  @override
  Future<DbHistory> history(DateTime start, Duration interval, Duration span) {
    historyCalls++;
    return super.history(start, interval, span);
  }

  @override
  Future<PowerSettings> powerSettings() {
    smartCalls++;
    return super.powerSettings();
  }
}
