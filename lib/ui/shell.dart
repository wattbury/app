import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../data/app_settings.dart';
import '../data/credentials.dart';
import '../data/forecast.dart';
import '../data/history.dart';
import '../data/history_cache.dart';
import '../data/notification_service.dart';
import '../data/notifications.dart';
import '../data/live_controller.dart';
import '../theme/tokens.dart';
import 'flow/flow_page.dart';
import 'history/history_page.dart';
import 'monitor/monitor_page.dart';
import 'smart/smart_page.dart';
import 'settings/settings_page.dart';

/// App frame: header with title, connection state and refresh; fixed tab bar at the bottom.
class Shell extends StatefulWidget {
  final LiveController live;
  final AppSettings settings;
  final Credentials? credentials;
  final ForecastService? forecast;
  final HistoryCache? historyCache;
  final NotificationService? notifications;
  final VoidCallback onSignOut, onEditConnection;
  const Shell({
    super.key,
    required this.live,
    required this.settings,
    required this.credentials,
    this.forecast,
    this.historyCache,
    this.notifications,
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
  late HistoryRepository _history = HistoryRepository(widget.live.source, cache: widget.historyCache);

  StreamSubscription<Alert>? _alertSub;

  @override
  void initState() {
    super.initState();
    _alertSub = widget.notifications?.alerts.listen(_showAlert);
  }

  /// In-app banner for an alert; the system notification (if available) comes separately.
  void _showAlert(Alert a) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${a.title} · ${a.body}'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 6),
      ),
    );
  }

  @override
  void dispose() {
    _alertSub?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(Shell old) {
    super.didUpdateWidget(old);
    if (!identical(old.notifications, widget.notifications)) {
      _alertSub?.cancel();
      _alertSub = widget.notifications?.alerts.listen(_showAlert);
    }
    if (!identical(old.live.source, widget.live.source) || !identical(old.historyCache, widget.historyCache)) {
      _history = HistoryRepository(widget.live.source, cache: widget.historyCache);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.wb;
    return ListenableBuilder(
      listenable: Listenable.merge([widget.live, widget.settings, ?widget.forecast, ?widget.notifications]),
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
                    MonitorPage(live: widget.live, settings: widget.settings, forecast: widget.forecast?.forecast),
                    HistoryPage(
                      repo: _history,
                      settings: widget.settings,
                      online: widget.live.state == ConnState.online,
                    ),
                    // Animations run only while the tab is visible.
                    TickerMode(
                      enabled: _tab == 2,
                      child: FlowPage(live: widget.live, settings: widget.settings),
                    ),
                    SmartPage(source: widget.live.source, online: widget.live.state == ConnState.online),
                    SettingsPage(
                      live: widget.live,
                      settings: widget.settings,
                      credentials: widget.credentials,
                      forecast: widget.forecast,
                      history: _history,
                      notifications: widget.notifications,
                      onSignOut: widget.onSignOut,
                      onEditConnection: widget.onEditConnection,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        bottomNavigationBar: _blurred(
          Container(
            decoration: BoxDecoration(
              // Without blur (web) the bar is opaque, so content does not show through unblurred.
              color: kIsWeb ? c.card : c.card.withValues(alpha: .92),
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
    );
  }
}

/// Frosted bar on native platforms. In the browser the blur is redrawn on every scroll frame and
/// makes scrolling stutter, so the web gets a plain bar.
Widget _blurred(Widget child) => kIsWeb
    ? child
    : ClipRect(
        child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14), child: child),
      );

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
              // Shrinks instead of running into the neighbour on narrow screens or with larger text.
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  tab.label,
                  maxLines: 1,
                  softWrap: false,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    color: selected ? c.fg : c.muted,
                  ),
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
