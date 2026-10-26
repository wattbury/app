import 'dart:ui';

import 'package:flutter/material.dart';

import '../data/app_settings.dart';
import '../data/credentials.dart';
import '../data/live_controller.dart';
import '../theme/tokens.dart';
import 'flow/flow_page.dart';
import 'monitor/monitor_page.dart';
import 'settings/settings_page.dart';

/// App frame: header with title, connection state and refresh; fixed tab bar at the bottom.
class Shell extends StatefulWidget {
  final LiveController live;
  final AppSettings settings;
  final Credentials? credentials;
  final VoidCallback onSignOut, onEditConnection;
  const Shell({
    super.key,
    required this.live,
    required this.settings,
    required this.credentials,
    required this.onSignOut,
    required this.onEditConnection,
  });

  @override
  State<Shell> createState() => _ShellState();
}

class _Tab {
  final String label, title;
  final IconData icon;
  const _Tab(this.label, this.title, this.icon);
}

const _tabs = [
  _Tab('Monitor', 'Wattbury', Icons.dashboard_outlined),
  _Tab('Diagramme', 'Diagramme', Icons.bar_chart),
  _Tab('Fluss', 'Energiefluss', Icons.hub_outlined),
  _Tab('Smart', 'Smart-Funktionen', Icons.auto_awesome_outlined),
  _Tab('Einstellungen', 'Einstellungen', Icons.settings_outlined),
];

class _ShellState extends State<Shell> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final c = context.wb;
    return ListenableBuilder(
      listenable: Listenable.merge([widget.live, widget.settings]),
      builder: (context, _) => Scaffold(
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              _Header(title: _tabs[_tab].title, live: widget.live),
              Expanded(
                child: IndexedStack(
                  index: _tab,
                  children: [
                    MonitorPage(live: widget.live, settings: widget.settings),
                    const _Later(
                      icon: Icons.bar_chart,
                      text: 'Diagramme aus der Datenbank des S10 kommen mit Ausbaustufe 4.',
                    ),
                    // Animations run only while the tab is visible.
                    TickerMode(
                      enabled: _tab == 2,
                      child: FlowPage(live: widget.live, settings: widget.settings),
                    ),
                    const _Later(
                      icon: Icons.auto_awesome_outlined,
                      text: 'Sperrzeiten, Lade-/Entladeleistung und Notstrom kommen mit Ausbaustufe 4.',
                    ),
                    SettingsPage(
                      live: widget.live,
                      settings: widget.settings,
                      credentials: widget.credentials,
                      onSignOut: widget.onSignOut,
                      onEditConnection: widget.onEditConnection,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        bottomNavigationBar: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
            child: Container(
              decoration: BoxDecoration(
                color: c.card.withValues(alpha: .92),
                border: Border(top: BorderSide(color: c.sep)),
              ),
              child: SafeArea(
                top: false,
                minimum: const EdgeInsets.only(bottom: 8),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
                  child: Row(
                    children: [
                      for (var i = 0; i < _tabs.length; i++)
                        Expanded(
                          child: _TabButton(tab: _tabs[i], selected: i == _tab, onTap: () => setState(() => _tab = i)),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  final _Tab tab;
  final bool selected;
  final VoidCallback onTap;
  const _TabButton({required this.tab, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.wb;
    return Semantics(
      selected: selected,
      button: true,
      label: tab.label,
      child: InkResponse(
        onTap: onTap,
        radius: 32,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(tab.icon, size: 24, color: selected ? c.solar : c.muted),
              const SizedBox(height: 3),
              Text(
                tab.label,
                maxLines: 1,
                overflow: TextOverflow.visible,
                softWrap: false,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  color: selected ? c.fg : c.muted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final String title;
  final LiveController live;
  const _Header({required this.title, required this.live});

  @override
  Widget build(BuildContext context) {
    final c = context.wb;
    final (dot, text) = switch (live.state) {
      ConnState.online => (c.good, '${live.source.label} · ${_seconds(live.source.liveInterval)}'),
      ConnState.connecting => (c.warn, 'Verbinde …'),
      ConnState.offline => (c.crit, 'Keine Verbindung'),
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
      child: Row(
        children: [
          const SizedBox(width: 40),
          Expanded(
            child: Column(
              children: [
                Text(title, style: sora(17, color: c.fg)),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 5),
                    Text(text, style: TextStyle(fontSize: 11, color: c.muted)),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: live.refresh,
            icon: Icon(Icons.refresh, color: c.fg),
            tooltip: 'Aktualisieren',
          ),
        ],
      ),
    );
  }

  static String _seconds(Duration d) => '${d.inSeconds} Sek.';
}

class _Later extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Later({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final c = context.wb;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: c.muted),
            const SizedBox(height: 12),
            Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: c.muted),
            ),
          ],
        ),
      ),
    );
  }
}
