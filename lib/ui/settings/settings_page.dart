import 'package:flutter/material.dart';

import '../../data/app_settings.dart';
import '../../data/credentials.dart';
import '../../data/live_controller.dart';
import '../../format.dart';
import '../../theme/tokens.dart';

class SettingsPage extends StatelessWidget {
  final LiveController live;
  final AppSettings settings;
  final Credentials? credentials;
  final VoidCallback onSignOut, onEditConnection;
  const SettingsPage({
    super.key,
    required this.live,
    required this.settings,
    required this.credentials,
    required this.onSignOut,
    required this.onEditConnection,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.wb;
    final sys = live.system;
    final online = live.state == ConnState.online;
    return ListView(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 16),
      children: [
        _Section(
          title: 'Verbindung',
          children: [
            _Row(
              label: online ? 'Verbunden über ${live.source.label}' : 'Nicht verbunden',
              sub: credentials == null ? 'Beispieldaten, keine echte Anlage' : credentials!.username,
              trailing: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: online ? c.good : c.crit, shape: BoxShape.circle),
              ),
            ),
            if (credentials != null) ...[
              _Row(
                label: 'Zu Hause im WLAN',
                sub: credentials!.hasLocal ? 'Wird bevorzugt, wenn erreichbar' : null,
                value: credentials!.hasLocal
                    ? '${credentials!.local!.host}:${credentials!.local!.port}'
                    : 'nicht eingerichtet',
              ),
              _Row(
                label: 'Unterwegs über das Portal',
                value: credentials!.hasPortal ? credentials!.serial! : 'nicht eingerichtet',
              ),
              _Row(
                label: 'Verbindung ändern',
                trailing: TextButton(onPressed: onEditConnection, child: const Text('Bearbeiten')),
              ),
            ],
            _Row(
              label: credentials == null ? 'Echte Anlage verbinden' : 'Abmelden',
              sub: credentials == null ? null : 'Löscht die Zugangsdaten von diesem Gerät',
              trailing: TextButton(onPressed: onSignOut, child: Text(credentials == null ? 'Einrichten' : 'Abmelden')),
            ),
          ],
        ),
        _Section(
          title: 'Geräte am Hauskraftwerk',
          children: [
            _Row(
              label: 'Wallbox',
              sub: switch (settings.wallboxMode) {
                WallboxMode.auto =>
                  live.wallboxes.isEmpty
                      ? 'Automatisch: keine Wallbox gemeldet'
                      : 'Automatisch: ${live.wallboxes.length} gemeldet',
                WallboxMode.show => 'Immer anzeigen',
                WallboxMode.hide => 'Immer ausblenden',
              },
            ),
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 8),
              child: SegmentedButton<WallboxMode>(
                segments: const [
                  ButtonSegment(value: WallboxMode.auto, label: Text('Automatisch')),
                  ButtonSegment(value: WallboxMode.show, label: Text('Anzeigen')),
                  ButtonSegment(value: WallboxMode.hide, label: Text('Ausblenden')),
                ],
                selected: {settings.wallboxMode},
                showSelectedIcon: false,
                onSelectionChanged: (s) => settings.wallboxMode = s.first,
              ),
            ),
          ],
        ),
        _Section(
          title: 'Darstellung',
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: SegmentedButton<ThemeMode>(
                segments: const [
                  ButtonSegment(value: ThemeMode.system, label: Text('System')),
                  ButtonSegment(value: ThemeMode.light, label: Text('Hell')),
                  ButtonSegment(value: ThemeMode.dark, label: Text('Dunkel')),
                ],
                selected: {settings.themeMode},
                showSelectedIcon: false,
                onSelectionChanged: (s) => settings.themeMode = s.first,
              ),
            ),
          ],
        ),
        if (sys != null)
          _Section(
            title: 'Anlage',
            children: [
              _Row(label: 'PV-Leistung', sub: 'aus dem S10', value: '${fmt(sys.installedPeakPowerW / 1000, 2)} kWp'),
              _Row(label: 'Firmware', value: sys.swRelease),
              _Row(label: 'Tracker', sub: 'mit Messwerten', value: '${live.trackers.length}'),
            ],
          ),
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Text(
            'Wattbury 0.1 · Open Source · Zugangsdaten nur im Schlüsselbund',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: c.muted),
          ),
        ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _Section({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    final c = context.wb;
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0 && children[i] is _Row && children[i - 1] is _Row) rows.add(Divider(height: 1, color: c.sep));
      rows.add(children[i]);
    }
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
      decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: c.fg),
          ),
          ...rows,
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final String label;
  final String? sub, value;
  final Widget? trailing;
  const _Row({required this.label, this.sub, this.value, this.trailing});

  @override
  Widget build(BuildContext context) {
    final c = context.wb;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(fontSize: 15, color: c.fg)),
                if (sub != null) Text(sub!, style: TextStyle(fontSize: 12, color: c.muted)),
              ],
            ),
          ),
          if (value != null)
            Text(
              value!,
              style: TextStyle(fontSize: 14, color: c.muted, fontFeatures: const [FontFeature.tabularFigures()]),
            ),
          ?trailing,
        ],
      ),
    );
  }
}
