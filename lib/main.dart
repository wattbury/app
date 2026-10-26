import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'data/app_settings.dart';
import 'data/credentials.dart';
import 'data/energy_source.dart';
import 'data/live_controller.dart';
import 'theme/tokens.dart';
import 'ui/setup/setup_page.dart';
import 'ui/shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('de_DE');
  final settings = await AppSettings.load();
  final store = CredentialStore();
  PortalCredentials? creds;
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
  final PortalCredentials? initial;
  final String? storeError;
  const WattburyApp({super.key, required this.settings, required this.store, this.initial, this.storeError});

  @override
  State<WattburyApp> createState() => _WattburyAppState();
}

class _WattburyAppState extends State<WattburyApp> {
  PortalCredentials? _creds;
  LiveController? _live;

  @override
  void initState() {
    super.initState();
    _creds = widget.initial;
    if (_creds != null) {
      _start(PortalSource(_creds!));
    } else if (widget.settings.demo) {
      _start(DemoSource());
    }
  }

  void _start(EnergySource source) {
    _live?.dispose();
    _live = LiveController(source)..start();
  }

  Future<void> _connected(PortalCredentials c) async {
    await widget.store.save(c);
    widget.settings.demo = false;
    setState(() {
      _creds = c;
      _start(PortalSource(c));
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
        home: _live == null
            ? SetupPage(onConnected: _connected, onDemo: _demo, notice: widget.storeError)
            : Shell(
                live: _live!,
                settings: widget.settings,
                account: _creds == null ? null : '${_creds!.username} · ${_creds!.serial}',
                onSignOut: _signOut,
              ),
      ),
    );
  }
}
