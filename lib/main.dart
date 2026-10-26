import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'data/app_settings.dart';
import 'data/credentials.dart';
import 'data/energy_source.dart';
import 'data/forecast.dart';
import 'data/live_controller.dart';
import 'theme/tokens.dart';
import 'ui/setup/setup_page.dart';
import 'ui/shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('de_DE');
  final settings = await AppSettings.load();
  final store = CredentialStore();
  Credentials? creds;
  String? storeError;
  try {
    creds = await store.load();
  } catch (e) {
    // On Linux this fails when no secret service (gnome-keyring) is running.
    storeError = 'Schlüsselbund nicht erreichbar: $e';
  }
  runApp(WattburyApp(settings: settings, store: store, initial: creds, storeError: storeError));
}

class WattburyApp extends StatefulWidget {
  final AppSettings settings;
  final CredentialStore store;
  final Credentials? initial;
  final String? storeError;
  const WattburyApp({super.key, required this.settings, required this.store, this.initial, this.storeError});

  @override
  State<WattburyApp> createState() => _WattburyAppState();
}

class _WattburyAppState extends State<WattburyApp> {
  Credentials? _creds;
  LiveController? _live;
  bool _editing = false;
  late final ForecastService _forecast = ForecastService(
    widget.settings,
    solcastKey: widget.store.solcastKey,
    saveSolcastKey: widget.store.setSolcastKey,
  );

  @override
  void initState() {
    super.initState();
    _creds = widget.initial;
    if (_creds != null) {
      _start(_auto(_creds!));
    } else if (widget.settings.demo) {
      _start(DemoSource());
    }
  }

  AutoSource _auto(Credentials c) => AutoSource(
    c,
    localInterval: () => Duration(seconds: widget.settings.localIntervalS),
    portalInterval: () => Duration(seconds: widget.settings.portalIntervalS),
  );

  void _start(EnergySource source) {
    _live?.dispose();
    _live = LiveController(source)..start();
    _forecast.attach(_live!);
  }

  Future<void> _connected(Credentials c) async {
    await widget.store.save(c);
    widget.settings.demo = false;
    setState(() {
      _creds = c;
      _editing = false;
      _start(_auto(c));
    });
  }

  void _demo() {
    widget.settings.demo = true;
    setState(() => _start(DemoSource()));
  }

  Future<void> _signOut() async {
    if (_creds != null) await widget.store.clear();
    widget.settings.demo = false;
    setState(() {
      _creds = null;
      _live?.dispose();
      _live = null;
    });
  }

  @override
  void dispose() {
    _forecast.dispose();
    _live?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.settings,
      builder: (context, _) => MaterialApp(
        title: 'Wattbury',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        themeMode: widget.settings.themeMode,
        home: _live == null || _editing
            ? SetupPage(
                onConnected: _connected,
                onDemo: _demo,
                notice: widget.storeError,
                initial: _creds,
                onCancel: _editing ? () => setState(() => _editing = false) : null,
              )
            : Shell(
                live: _live!,
                settings: widget.settings,
                credentials: _creds,
                forecast: _forecast,
                onSignOut: _signOut,
                onEditConnection: () => setState(() => _editing = true),
              ),
      ),
    );
  }
}
