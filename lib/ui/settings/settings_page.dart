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
import 'settings_rows.dart';

/// Commit the build was made from (set by the deploy workflow), to tell which version is running.
const _build = String.fromEnvironment('BUILD', defaultValue: 'dev');

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
    void openForecast() =>
        Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ForecastPage(service: forecast!)));
    return ListView(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 16),
      children: [
        _Section(
          title: 'Verbindung',
          children: [
            SettingsRow(
              label: online ? 'Verbunden über ${live.source.label}' : 'Nicht verbunden',
              sub: credentials == null ? 'Beispieldaten, keine echte Anlage' : credentials!.username,
              indicator: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: online ? c.good : c.crit, shape: BoxShape.circle),
              ),
            ),
            if (credentials != null) ...[
              if (!kIsWeb)
                SettingsRow(
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
              SettingsRow(
                label: kIsWeb ? 'Über das Portal' : 'Unterwegs über das Portal',
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
              SettingsRow(label: 'Verbindung ändern', onTap: onEditConnection),
            ],
            if (credentials == null)
              SettingsRow(label: 'Echte Anlage verbinden', onTap: onSignOut)
            else
              SettingsActionRow(
                label: 'Abmelden',
                sub: 'Löscht die Zugangsdaten von diesem Gerät',
                destructive: true,
                onTap: onSignOut,
              ),
          ],
        ),
        _Section(
          title: 'Geräte am Hauskraftwerk',
          children: [
            SettingsRow(
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
              SettingsRow(
                label: 'PV-Leistung',
                sub: 'aus dem S10',
                value: '${fmt(sys.installedPeakPowerW / 1000, 2)} kWp',
              ),
              SettingsRow(label: 'Firmware', value: sys.swRelease),
              SettingsRow(label: 'Tracker', sub: 'mit Messwerten', value: '${live.trackers.length}'),
              SettingsRow(
                label: 'Ausrichtung',
                sub: settings.plant.complete ? 'Dachflächen je Tracker' : 'Für die Prognose nötig',
                value: settings.plant.complete
                    ? settings.plant.trackers.map((t) => '${t.direction} ${t.tilt}°').join(' · ')
                    : 'nicht eingerichtet',
                onTap: () => _openPlant(context),
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
            SettingsRow(
              label: 'Strompreis',
              sub: 'für Netzbezug und die Ersparnis',
              value: settings.priceCt == null ? 'nicht eingetragen' : '${fmt(settings.priceCt!, 2)} ct/kWh',
              onTap: () => _editCt(context, 'Strompreis', settings.priceCt, (v) => settings.priceCt = v),
            ),
            SettingsRow(
              label: 'Einspeisevergütung',
              value: settings.feedInCt == null ? 'nicht eingetragen' : '${fmt(settings.feedInCt!, 2)} ct/kWh',
              onTap: () => _editCt(context, 'Einspeisevergütung', settings.feedInCt, (v) => settings.feedInCt = v),
            ),
          ],
        ),
        if (forecast != null)
          _Section(
            title: 'Prognose',
            children: [
              SettingsRow(
                label: 'Anbieter',
                sub: settings.forecastProvider == 'sc' ? 'mit eigenem API-Key' : 'ohne Konto',
                value: settings.forecastProvider == 'sc' ? 'Solcast' : 'Open-Meteo',
                onTap: openForecast,
              ),
              SettingsRow(
                label: 'Korrekturfaktor',
                sub: 'aus Messwerten gelernt',
                value: !settings.correctionEnabled
                    ? 'aus'
                    : forecast!.correction.ready
                    ? '${fmt(forecast!.correction.overall, 2)} · ${forecast!.correction.days} Tage'
                    : 'lernt · ${forecast!.correction.days} von 7 Tagen',
                onTap: openForecast,
              ),
              if (forecast!.correction.rawError != null)
                SettingsRow(
                  label: 'Genauigkeit Tagesertrag',
                  value:
                      '± ${fmt(forecast!.correction.correctedError! * 100, 0)} % statt ± ${fmt(forecast!.correction.rawError! * 100, 0)} %',
                ),
            ],
          ),
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Text(
            'Wattbury 0.1 ($_build) · Open Source · Zugangsdaten nur ${kIsWeb ? 'in diesem Browser' : 'im Schlüsselbund'}',
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
    final rows = withDividers(context, children);
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
      decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              title,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: c.fg),
            ),
          ),
          ...rows,
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
        ...withDividers(context, [
          SettingsRow(
            label: 'Gespeichert',
            sub: 'Abgeschlossene Zeiträume, bleiben auf dem Gerät',
            value: st == null ? '…' : '${st.months} Monate · ${st.days} Tage · $size',
          ),
          SettingsRow(
            label: 'Vorladen',
            value: 'letzte $_months Monate',
            onTap: _running
                ? null
                : () async {
                    final m = await pickOption(context, 'Vorladen', {
                      for (final m in const [3, 6, 12, 24, 36]) m: 'letzte $m Monate',
                    }, _months);
                    if (m != null) setState(() => _months = m);
                  },
          ),
          SettingsSwitchRow(
            label: 'Mit Stundenwerten',
            sub: 'Für die Tagesansicht; eine Abfrage je Tag, dauert länger',
            value: _hours,
            onChanged: _running ? null : (v) => setState(() => _hours = v),
          ),
          SettingsActionRow(
            label: _running ? 'Abbrechen' : 'Jetzt laden',
            icon: _running ? Icons.stop_circle_outlined : Icons.download_outlined,
            onTap: _running ? () => setState(() => _cancel = true) : _run,
          ),
        ]),
        if (_running) ...[
          LinearProgressIndicator(value: _total == 0 ? null : _done / _total, color: c.accent, backgroundColor: c.sep),
          const SizedBox(height: 4),
          Text('$_done von $_total geladen', style: TextStyle(fontSize: 12, color: c.muted)),
        ],
        if (_error != null) SettingsNote(_error!, color: c.crit),
        const SettingsNote(
          'Bereits geladene Zeiträume fragt die App nie wieder ab. Vorladen füllt den Speicher im Voraus, '
          'damit Wochen-, Monats- und Jahresansichten sofort erscheinen.',
        ),
        Divider(height: 1, color: c.sep),
        SettingsActionRow(
          label: 'Zwischenspeicher löschen',
          icon: Icons.delete_outline,
          destructive: true,
          onTap: _running ? null : _clear,
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
