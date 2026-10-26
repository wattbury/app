import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../data/app_settings.dart';
import '../../data/credentials.dart';
import '../../data/forecast.dart';
import '../../data/history.dart';
import '../../data/notification_service.dart';
import '../../data/live_controller.dart';
import '../../format.dart';
import '../../theme/tokens.dart';
import '../forecast/forecast_page.dart';
import '../plant/plant_page.dart';
import 'rules_section.dart';

class SettingsPage extends StatelessWidget {
  final LiveController live;
  final AppSettings settings;
  final Credentials? credentials;
  final ForecastService? forecast;
  final HistoryRepository? history;
  final NotificationService? notifications;
  final VoidCallback onSignOut, onEditConnection;
  const SettingsPage({
    super.key,
    required this.live,
    required this.settings,
    required this.credentials,
    this.forecast,
    this.history,
    this.notifications,
    required this.onSignOut,
    required this.onEditConnection,
  });

  /// Asks for a price in ct/kWh; an empty field removes it.
  Future<void> _editCt(BuildContext context, String title, double? current, ValueChanged<double?> set) async {
    final v = await showDialog<String>(
      context: context,
      builder: (context) => _CtDialog(title: title, initial: current == null ? '' : fmt(current, 2)),
    );
    if (v == null) return;
    // Comma or point as decimal separator ("31,2" and "31.2").
    final n = double.tryParse(v.trim().replaceAll(',', '.'));
    if (v.trim().isEmpty) {
      set(null);
    } else if (n != null && n >= 0 && n < 200) {
      set(n);
    }
  }

  void _openPlant(BuildContext context) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => PlantPage(
        initial: settings.plant,
        trackers: live.trackers,
        system: live.system,
        source: live.source,
        onSave: (p) {
          settings.plant = p;
          forecast?.plant = p;
        },
      ),
    ),
  );

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
              if (!kIsWeb)
                _Row(
                  label: 'Zu Hause im WLAN',
                  sub: credentials!.hasLocal ? 'Wird bevorzugt, wenn erreichbar' : null,
                  value: credentials!.hasLocal ? credentials!.local!.host : 'nicht eingerichtet',
                ),
              if (credentials!.hasLocal)
                _IntervalSlider(
                  choices: AppSettings.localIntervals,
                  value: settings.localIntervalS,
                  onChanged: (v) {
                    settings.localIntervalS = v;
                    live.intervalChanged();
                  },
                ),
              _Row(
                label: 'Unterwegs über das Portal',
                value: credentials!.hasPortal ? credentials!.serial! : 'nicht eingerichtet',
              ),
              if (credentials!.hasPortal)
                _IntervalSlider(
                  choices: AppSettings.portalIntervals,
                  value: settings.portalIntervalS,
                  hint: 'Mindestens 5 Sekunden, um die Server von E3/DC zu schonen.',
                  onChanged: (v) {
                    settings.portalIntervalS = v;
                    live.intervalChanged();
                  },
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
              _Row(
                label: 'Ausrichtung',
                sub: settings.plant.complete ? 'Dachflächen je Tracker' : 'Für die Prognose nötig',
                value: settings.plant.complete
                    ? settings.plant.trackers.map((t) => '${t.direction} ${t.tilt}°').join(' · ')
                    : 'nicht eingerichtet',
              ),
              _Row(
                label: 'Anlage einrichten',
                trailing: TextButton(onPressed: () => _openPlant(context), child: const Text('Öffnen')),
              ),
            ],
          ),
        if (history != null && credentials != null)
          _Section(
            title: 'Verlauf',
            children: [_HistoryPreload(repo: history!)],
          ),
        _Section(
          title: 'Benachrichtigungen',
          children: [RulesSection(settings: settings, service: notifications)],
        ),
        _Section(
          title: 'Tarif & Kosten',
          children: [
            _Row(
              label: 'Strompreis',
              sub: 'für Netzbezug und die Ersparnis',
              value: settings.priceCt == null ? 'nicht eingetragen' : '${fmt(settings.priceCt!, 2)} ct/kWh',
              trailing: TextButton(
                onPressed: () => _editCt(context, 'Strompreis', settings.priceCt, (v) => settings.priceCt = v),
                child: const Text('Ändern'),
              ),
            ),
            _Row(
              label: 'Einspeisevergütung',
              value: settings.feedInCt == null ? 'nicht eingetragen' : '${fmt(settings.feedInCt!, 2)} ct/kWh',
              trailing: TextButton(
                onPressed: () =>
                    _editCt(context, 'Einspeisevergütung', settings.feedInCt, (v) => settings.feedInCt = v),
                child: const Text('Ändern'),
              ),
            ),
          ],
        ),
        if (forecast != null)
          _Section(
            title: 'Prognose',
            children: [
              _Row(
                label: 'Anbieter',
                value: settings.forecastProvider == 'sc' ? 'Solcast · eigener API-Key' : 'Open-Meteo · ohne Konto',
              ),
              _Row(
                label: 'Korrekturfaktor',
                sub: 'aus den Messwerten des S10 gelernt',
                value: !settings.correctionEnabled
                    ? 'aus'
                    : forecast!.correction.ready
                    ? '${fmt(forecast!.correction.overall, 2)} · ${forecast!.correction.days} Tage'
                    : 'lernt · ${forecast!.correction.days} von 7 Tagen',
              ),
              if (forecast!.correction.rawError != null)
                _Row(
                  label: 'Genauigkeit Tagesertrag',
                  value:
                      '± ${fmt(forecast!.correction.correctedError! * 100, 0)} % statt ± ${fmt(forecast!.correction.rawError! * 100, 0)} %',
                ),
              _Row(
                label: 'Prognose einstellen',
                trailing: TextButton(
                  onPressed: () =>
                      Navigator.of(context)
                          .push(MaterialPageRoute<void>(builder: (_) => ForecastPage(service: forecast!))),
                  child: const Text('Öffnen'),
                ),
              ),
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

/// Refresh interval as a slider with fixed stops; shows the chosen value next to the label.
class _IntervalSlider extends StatelessWidget {
  final List<int> choices;
  final int value;
  final String? hint;
  final ValueChanged<int> onChanged;
  const _IntervalSlider({required this.choices, required this.value, required this.onChanged, this.hint});

  @override
  Widget build(BuildContext context) {
    final c = context.wb;
    final i = choices.indexOf(value).clamp(0, choices.length - 1);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Aktualisierung', style: TextStyle(fontSize: 13, color: c.muted)),
              ),
              Text(
                'alle ${choices[i]} Sek.',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.fg),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: c.accent,
              thumbColor: c.accent,
              inactiveTrackColor: c.sep,
              overlayShape: SliderComponentShape.noOverlay,
            ),
            child: Slider(
              value: i.toDouble(),
              max: (choices.length - 1).toDouble(),
              divisions: choices.length - 1,
              label: '${choices[i]} Sek.',
              semanticFormatterCallback: (v) => 'alle ${choices[v.round()]} Sekunden',
              onChanged: (v) {
                final next = choices[v.round()];
                if (next != value) onChanged(next);
              },
            ),
          ),
          // Labels centred under the stops; the track is inset by the thumb radius on both sides.
          LayoutBuilder(
            builder: (context, box) {
              const inset = 10.0, w = 28.0;
              final step = (box.maxWidth - 2 * inset) / (choices.length - 1);
              return SizedBox(
                height: 14,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    for (final (j, s) in choices.indexed)
                      Positioned(
                        left: inset + j * step - w / 2,
                        width: w,
                        child: Text(
                          '$s',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 11, color: c.muted),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
          if (hint != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(hint!, style: TextStyle(fontSize: 12, color: c.muted)),
            ),
        ],
      ),
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
          // Long values wrap instead of pushing the row off screen (large text, narrow phones).
          if (value != null)
            Flexible(
              child: Text(
                value!,
                textAlign: TextAlign.right,
                style: TextStyle(fontSize: 14, color: c.muted, fontFeatures: const [FontFeature.tabularFigures()]),
              ),
            ),
          ?trailing,
        ],
      ),
    );
  }
}

/// Shows what the history cache holds and loads the last months in advance.
class _HistoryPreload extends StatefulWidget {
  final HistoryRepository repo;
  const _HistoryPreload({required this.repo});

  @override
  State<_HistoryPreload> createState() => _HistoryPreloadState();
}

class _HistoryPreloadState extends State<_HistoryPreload> {
  int _months = 12;
  bool _hours = false, _running = false, _cancel = false;
  int _done = 0, _total = 0;
  String? _error;
  ({int months, int days, int bytes})? _stats;

  @override
  void initState() {
    super.initState();
    _refreshStats();
  }

  @override
  void didUpdateWidget(_HistoryPreload old) {
    super.didUpdateWidget(old);
    if (!identical(old.repo, widget.repo)) _refreshStats();
  }

  Future<void> _refreshStats() async {
    final s = await widget.repo.cache.stats();
    if (mounted) setState(() => _stats = s);
  }

  Future<void> _run() async {
    setState(() {
      _running = true;
      _cancel = false;
      _error = null;
      _done = 0;
      _total = 0;
    });
    try {
      await widget.repo.preload(
        months: _months,
        withHours: _hours,
        onProgress: (d, t) {
          if (mounted) {
            setState(() {
              _done = d;
              _total = t;
            });
          }
        },
        cancelled: () => _cancel || !mounted,
      );
    } catch (e) {
      if (mounted) setState(() => _error = 'Abgebrochen: $e');
    } finally {
      if (mounted) setState(() => _running = false);
      await _refreshStats();
    }
  }

  Future<void> _clear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Zwischenspeicher löschen?'),
        content: const Text('Die Diagramme laden die Daten danach wieder vom Hauskraftwerk.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Löschen')),
        ],
      ),
    );
    if (ok != true) return;
    await widget.repo.cache.clear();
    await _refreshStats();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.wb;
    final st = _stats;
    final size = st == null
        ? ''
        : (st.bytes < 1024 * 1024 ? '${fmt(st.bytes / 1024, 0)} KB' : '${fmt(st.bytes / 1024 / 1024, 1)} MB');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Row(
          label: 'Gespeichert',
          sub: 'Abgeschlossene Zeiträume, bleiben auf dem Gerät',
          value: st == null ? '…' : '${st.months} Monate · ${st.days} Tage · $size',
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: Text('Vorladen', style: TextStyle(fontSize: 15, color: c.fg)),
            ),
            DropdownButton<int>(
              value: _months,
              underline: const SizedBox(),
              items: [
                for (final m in const [3, 6, 12, 24, 36]) DropdownMenuItem(value: m, child: Text('letzte $m Monate')),
              ],
              onChanged: _running ? null : (v) => setState(() => _months = v!),
            ),
          ],
        ),
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Mit Stundenwerten', style: TextStyle(fontSize: 15, color: c.fg)),
                  Text(
                    'Für die Tagesansicht; eine Abfrage je Tag, dauert länger',
                    style: TextStyle(fontSize: 12, color: c.muted),
                  ),
                ],
              ),
            ),
            Switch(
              value: _hours,
              activeTrackColor: c.accent,
              onChanged: _running ? null : (v) => setState(() => _hours = v),
            ),
          ],
        ),
        if (_running) ...[
          const SizedBox(height: 8),
          LinearProgressIndicator(value: _total == 0 ? null : _done / _total, color: c.accent, backgroundColor: c.sep),
          const SizedBox(height: 4),
          Text('$_done von $_total geladen', style: TextStyle(fontSize: 12, color: c.muted)),
        ],
        if (_error != null) Text(_error!, style: TextStyle(fontSize: 12, color: c.crit)),
        Row(
          children: [
            TextButton(
              onPressed: _running ? () => setState(() => _cancel = true) : _run,
              child: Text(_running ? 'Abbrechen' : 'Jetzt laden'),
            ),
            const Spacer(),
            TextButton(onPressed: _running ? null : _clear, child: const Text('Löschen')),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            'Bereits geladene Zeiträume fragt die App nie wieder ab. Vorladen füllt den Speicher im Voraus, '
            'damit Wochen-, Monats- und Jahresansichten sofort erscheinen.',
            style: TextStyle(fontSize: 12, color: c.muted),
          ),
        ),
      ],
    );
  }
}

/// Price entry. Owns its text controller, so the controller lives until the dialog has finished
/// its closing animation; disposing it earlier broke the still visible text field.
class _CtDialog extends StatefulWidget {
  final String title, initial;
  const _CtDialog({required this.title, required this.initial});

  @override
  State<_CtDialog> createState() => _CtDialogState();
}

class _CtDialogState extends State<_CtDialog> {
  late final _ctl = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: TextField(
      controller: _ctl,
      autofocus: true,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: const InputDecoration(suffixText: 'ct/kWh', hintText: 'z. B. 31,2'),
      onSubmitted: (t) => Navigator.pop(context, t),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Abbrechen')),
      FilledButton(onPressed: () => Navigator.pop(context, _ctl.text), child: const Text('Übernehmen')),
    ],
  );
}
