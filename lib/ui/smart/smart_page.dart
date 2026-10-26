import 'package:flutter/material.dart';
import 'package:openrscp/openrscp.dart';

import '../../data/energy_source.dart';
import '../../format.dart';
import '../../theme/tokens.dart';
import '../widgets/cards.dart';

const _days = ['Montag', 'Dienstag', 'Mittwoch', 'Donnerstag', 'Freitag', 'Samstag', 'Sonntag'];

String _hm(int h, int m) => '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';

/// Smart-Funktionen: charge/discharge power, weather-regulated charging, power save and lock periods.
/// Changes are collected as a draft; "Übernehmen" asks once, sends them and reads the unit back.
class SmartPage extends StatefulWidget {
  final EnergySource source;
  const SmartPage({super.key, required this.source});

  @override
  State<SmartPage> createState() => _SmartPageState();
}

class _SmartPageState extends State<SmartPage> {
  PowerSettings? _power, _powerDraft;
  List<IdlePeriod>? _idle, _idleDraft;
  Map<String, int> _specs = const {};
  IdleType _idleType = IdleType.discharge;
  bool _loading = true, _sending = false;
  String? _error, _result;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(SmartPage old) {
    super.didUpdateWidget(old);
    if (!identical(old.source, widget.source)) _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final power = await widget.source.powerSettings();
      final idle = await widget.source.idlePeriods();
      Map<String, int> specs = const {};
      try {
        specs = await widget.source.sysSpecs();
      } catch (_) {
        // Optional: without limits the sliders fall back to the current values.
      }
      if (!mounted) return;
      setState(() {
        _power = _powerDraft = power;
        _idle = idle..sort(_order);
        _idleDraft = List.of(_idle!);
        _specs = specs;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _loading = false;
        });
      }
    }
  }

  static int _order(IdlePeriod a, IdlePeriod b) =>
      a.type == b.type ? a.day.compareTo(b.day) : a.type.index.compareTo(b.type.index);

  bool get _powerDirty {
    final a = _power, b = _powerDraft;
    if (a == null || b == null) return false;
    return a.powerLimitsUsed != b.powerLimitsUsed ||
        a.maxChargePowerW != b.maxChargePowerW ||
        a.maxDischargePowerW != b.maxDischargePowerW ||
        a.dischargeStartPowerW != b.dischargeStartPowerW ||
        a.powerSaveEnabled != b.powerSaveEnabled ||
        a.weatherRegulatedChargeEnabled != b.weatherRegulatedChargeEnabled;
  }

  bool get _idleDirty {
    final a = _idle, b = _idleDraft;
    if (a == null || b == null) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return true;
    }
    return false;
  }

  void _editPower({
    bool? limitsUsed,
    int? maxCharge,
    int? maxDischarge,
    int? dischargeStart,
    bool? powerSave,
    bool? weather,
  }) {
    final p = _powerDraft!;
    setState(() {
      _result = null;
      _powerDraft = PowerSettings(
        powerLimitsUsed: limitsUsed ?? p.powerLimitsUsed,
        maxChargePowerW: maxCharge ?? p.maxChargePowerW,
        maxDischargePowerW: maxDischarge ?? p.maxDischargePowerW,
        dischargeStartPowerW: dischargeStart ?? p.dischargeStartPowerW,
        powerSaveEnabled: powerSave ?? p.powerSaveEnabled,
        weatherRegulatedChargeEnabled: weather ?? p.weatherRegulatedChargeEnabled,
      );
    });
  }

  void _editIdle(IdlePeriod p) {
    final i = _idleDraft!.indexWhere((x) => x.type == p.type && x.day == p.day);
    setState(() {
      _result = null;
      _idleDraft![i] = p;
    });
  }

  List<String> _changes() {
    final out = <String>[];
    final a = _power!, b = _powerDraft!;
    String w(int v) => '${fmt(v.toDouble(), 0)} W';
    if (a.powerLimitsUsed != b.powerLimitsUsed) out.add('Leistung begrenzen: ${b.powerLimitsUsed ? 'an' : 'aus'}');
    if (a.maxChargePowerW != b.maxChargePowerW) out.add('Max. Ladeleistung: ${w(b.maxChargePowerW)}');
    if (a.maxDischargePowerW != b.maxDischargePowerW) out.add('Max. Entladeleistung: ${w(b.maxDischargePowerW)}');
    if (a.dischargeStartPowerW != b.dischargeStartPowerW) out.add('Entladestart ab: ${w(b.dischargeStartPowerW)}');
    if (a.weatherRegulatedChargeEnabled != b.weatherRegulatedChargeEnabled) {
      out.add('Wetterabhängiges Laden: ${b.weatherRegulatedChargeEnabled ? 'an' : 'aus'}');
    }
    if (a.powerSaveEnabled != b.powerSaveEnabled) out.add('PowerSave: ${b.powerSaveEnabled ? 'an' : 'aus'}');
    for (var i = 0; i < _idle!.length; i++) {
      final x = _idle![i], y = _idleDraft![i];
      if (x == y) continue;
      final kind = y.type == IdleType.charge ? 'Ladesperre' : 'Entladesperre';
      out.add(
        '$kind ${_days[y.day]}: ${y.active ? 'aktiv' : 'inaktiv'}, '
        '${_hm(y.startHour, y.startMinute)}–${_hm(y.endHour, y.endMinute)}',
      );
    }
    return out;
  }

  Future<void> _apply() async {
    final changes = _changes();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('An das Hauskraftwerk senden?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [for (final c in changes) Text('• $c')],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Senden')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() {
      _sending = true;
      _result = null;
    });
    final notes = <String>[];
    try {
      if (_powerDirty) {
        final a = _power!, b = _powerDraft!;
        final r = await widget.source.setPowerSettings(
          limitsUsed: a.powerLimitsUsed != b.powerLimitsUsed ? b.powerLimitsUsed : null,
          maxChargePowerW: a.maxChargePowerW != b.maxChargePowerW ? b.maxChargePowerW : null,
          maxDischargePowerW: a.maxDischargePowerW != b.maxDischargePowerW ? b.maxDischargePowerW : null,
          dischargeStartPowerW: a.dischargeStartPowerW != b.dischargeStartPowerW ? b.dischargeStartPowerW : null,
          powerSave: a.powerSaveEnabled != b.powerSaveEnabled ? b.powerSaveEnabled : null,
          weatherRegulatedCharge: a.weatherRegulatedChargeEnabled != b.weatherRegulatedChargeEnabled
              ? b.weatherRegulatedChargeEnabled
              : null,
        );
        if (!r.ok) notes.add('Leistungswerte abgelehnt');
        if (r.adjusted) notes.add('Leistungswerte vom Hauskraftwerk angepasst');
      }
      if (_idleDirty && !await widget.source.setIdlePeriods(_idleDraft!)) {
        notes.add('Sperrzeiten nicht bestätigt');
      }
      // Read back so the screen shows what the unit really uses now.
      final wanted = _powerDraft!, wantedIdle = List.of(_idleDraft!);
      await _load();
      if (_powerDraft != null && _changedAgainst(wanted)) notes.add('Leistungswerte weichen nach dem Rücklesen ab');
      if (_idle != null && !_sameIdle(wantedIdle, _idle!)) notes.add('Sperrzeiten weichen nach dem Rücklesen ab');
      if (mounted) setState(() => _result = notes.isEmpty ? 'Übernommen und zurückgelesen ✓' : notes.join(' · '));
    } catch (e) {
      if (mounted) setState(() => _result = 'Senden fehlgeschlagen: $e');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  bool _changedAgainst(PowerSettings w) {
    final p = _power!;
    return p.powerLimitsUsed != w.powerLimitsUsed ||
        p.maxChargePowerW != w.maxChargePowerW ||
        p.maxDischargePowerW != w.maxDischargePowerW ||
        p.dischargeStartPowerW != w.dischargeStartPowerW ||
        p.powerSaveEnabled != w.powerSaveEnabled ||
        p.weatherRegulatedChargeEnabled != w.weatherRegulatedChargeEnabled;
  }

  static bool _sameIdle(List<IdlePeriod> a, List<IdlePeriod> b) {
    final x = List.of(a)..sort(_order), y = List.of(b)..sort(_order);
    if (x.length != y.length) return false;
    for (var i = 0; i < x.length; i++) {
      if (x[i] != y[i]) return false;
    }
    return true;
  }

  Future<void> _pickTimes(IdlePeriod p) async {
    final start = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: p.startHour, minute: p.startMinute),
      helpText: 'Beginn',
      builder: _h24,
    );
    if (start == null || !mounted) return;
    final end = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: p.endHour, minute: p.endMinute),
      helpText: 'Ende',
      builder: _h24,
    );
    if (end == null || !mounted) return;
    final next = p.copyWith(startHour: start.hour, startMinute: start.minute, endHour: end.hour, endMinute: end.minute);
    if (!next.isValid) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Das Ende muss nach dem Beginn am selben Tag liegen.')));
      return;
    }
    _editIdle(next);
  }

  static Widget _h24(BuildContext context, Widget? child) =>
      MediaQuery(data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true), child: child!);

  @override
  Widget build(BuildContext context) {
    final c = context.wb;
    if (_loading && _power == null) return Center(child: CircularProgressIndicator(color: c.accent));
    if (_error != null && _power == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Einstellungen konnten nicht gelesen werden.',
                style: sora(16, color: c.fg),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: c.muted),
              ),
              const SizedBox(height: 12),
              FilledButton(onPressed: _load, child: const Text('Erneut versuchen')),
            ],
          ),
        ),
      );
    }
    final p = _powerDraft!;
    final dirty = _powerDirty || _idleDirty;
    final maxCharge = _specs['maxBatChargePower'] ?? p.maxChargePowerW;
    final maxDischarge = _specs['maxBatDischargPower'] ?? _specs['maxBatDischargePower'] ?? p.maxDischargePowerW;
    const gap = SizedBox(height: 10);
    return ListView(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 16),
      children: [
        WhiteCard(
          title: 'Lade- / Entladeleistung',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _SwitchRow(
                label: 'Leistung begrenzen',
                sub: 'Sonst nutzt das Hauskraftwerk seine Standardwerte',
                value: p.powerLimitsUsed,
                onChanged: (v) => _editPower(limitsUsed: v),
              ),
              _PowerSlider(
                label: 'Max. Ladeleistung',
                recommendedMin: _specs['recommendedMinChargeLimit'],
                value: p.maxChargePowerW,
                min: 100,
                max: maxCharge,
                step: 100,
                enabled: p.powerLimitsUsed,
                onChanged: (v) => _editPower(maxCharge: v),
              ),
              _PowerSlider(
                label: 'Max. Entladeleistung',
                recommendedMin: _specs['recommendedMinDischargeLimit'],
                value: p.maxDischargePowerW,
                min: 100,
                max: maxDischarge,
                step: 100,
                enabled: p.powerLimitsUsed,
                onChanged: (v) => _editPower(maxDischarge: v),
              ),
              _PowerSlider(
                label: 'Entladestart ab',
                value: p.dischargeStartPowerW,
                min: 0,
                max: 500,
                step: 5,
                enabled: p.powerLimitsUsed,
                onChanged: (v) => _editPower(dischargeStart: v),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'Entladestart: Die Batterie entlädt erst, wenn das Haus mehr als diesen Wert aus dem Netz ziehen würde.',
                  style: TextStyle(fontSize: 12, color: c.muted),
                ),
              ),
            ],
          ),
        ),
        gap,
        WhiteCard(
          title: 'Laden',
          child: Column(
            children: [
              _SwitchRow(
                label: 'Wetterabhängiges Laden',
                sub: 'Lädt bei guter Prognose später, um Einspeisespitzen abzufangen',
                value: p.weatherRegulatedChargeEnabled,
                onChanged: (v) => _editPower(weather: v),
              ),
              _SwitchRow(
                label: 'PowerSave',
                sub: 'Schaltet den Wechselrichter bei Stillstand ab',
                value: p.powerSaveEnabled,
                onChanged: (v) => _editPower(powerSave: v),
              ),
            ],
          ),
        ),
        gap,
        WhiteCard(
          title: 'Sperrzeiten',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 8),
              SegmentedButton<IdleType>(
                segments: const [
                  ButtonSegment(value: IdleType.discharge, label: Text('Entladesperre')),
                  ButtonSegment(value: IdleType.charge, label: Text('Ladesperre')),
                ],
                selected: {_idleType},
                showSelectedIcon: false,
                onSelectionChanged: (s) => setState(() => _idleType = s.first),
              ),
              const SizedBox(height: 4),
              if (_idleDraft!.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Text(
                    'Das Hauskraftwerk meldet keine Sperrzeiten. Neuere Firmware verwaltet sie womöglich anders; '
                    'bis das geklärt ist, ändert die App hier nichts.',
                    style: TextStyle(fontSize: 13, color: c.fg),
                  ),
                ),
              for (final x in _idleDraft!.where((x) => x.type == _idleType))
                _IdleRow(
                  period: x,
                  onToggle: (v) => _editIdle(x.copyWith(active: v)),
                  onTap: () => _pickTimes(x),
                ),
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  _idleType == IdleType.discharge
                      ? 'In diesen Zeiten gibt die Batterie keinen Strom ab, z. B. nachts bei günstigem Netzstrom.'
                      : 'In diesen Zeiten lädt die Batterie nicht, z. B. um mittags Platz für Spitzen zu lassen.',
                  style: TextStyle(fontSize: 12, color: c.muted),
                ),
              ),
            ],
          ),
        ),
        gap,
        WhiteCard(
          title: 'Notstromreserve',
          trailing: 'folgt',
          child: Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'Kommt, sobald das Setzen an einer echten Anlage geprüft ist. Dafür gibt es noch keine erprobte Vorlage.',
              style: TextStyle(fontSize: 12, color: c.muted),
            ),
          ),
        ),
        if (_result != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 12, 4, 0),
            child: Text(_result!, style: TextStyle(fontSize: 13, color: _result!.endsWith('✓') ? c.good : c.crit)),
          ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: dirty && !_sending ? _apply : null,
          style: FilledButton.styleFrom(
            backgroundColor: c.accent,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: _sending
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : Text(dirty ? 'Änderungen übernehmen' : 'Keine Änderungen', style: const TextStyle(fontSize: 15)),
        ),
        if (dirty && !_sending)
          TextButton(
            onPressed: () => setState(() {
              _powerDraft = _power;
              _idleDraft = List.of(_idle!);
            }),
            child: const Text('Verwerfen'),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
          child: Text(
            'Erst „Übernehmen“ sendet die Werte an das Hauskraftwerk. Danach liest die App sie zurück und zeigt, was wirklich gilt.',
            style: TextStyle(fontSize: 12, color: c.muted),
          ),
        ),
      ],
    );
  }
}

class _SwitchRow extends StatelessWidget {
  final String label;
  final String? sub;
  final bool value;
  final ValueChanged<bool> onChanged;
  const _SwitchRow({required this.label, this.sub, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final c = context.wb;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
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
          Switch(value: value, onChanged: onChanged, activeTrackColor: c.accent),
        ],
      ),
    );
  }
}

class _PowerSlider extends StatelessWidget {
  final String label;
  final int value, min, max, step;

  /// Lower limit E3/DC recommends (system specs); below it the slider shows a warning.
  final int? recommendedMin;
  final bool enabled;
  final ValueChanged<int> onChanged;
  const _PowerSlider({
    required this.label,
    this.recommendedMin,
    required this.value,
    required this.min,
    required this.max,
    required this.step,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.wb;
    final hi = max < value ? value : max;
    final divisions = ((hi - min) / step).round();
    return Opacity(
      opacity: enabled ? 1 : .45,
      child: Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(label, style: TextStyle(fontSize: 13, color: c.fg)),
                ),
                Text(
                  '${fmt(value.toDouble(), 0)} W',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: c.fg,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
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
                value: value.clamp(min, hi).toDouble(),
                min: min.toDouble(),
                max: hi.toDouble(),
                divisions: divisions > 0 ? divisions : null,
                semanticFormatterCallback: (v) => '${v.round()} Watt',
                onChanged: enabled && divisions > 0 ? (v) => onChanged((v / step).round() * step) : null,
              ),
            ),
            if (enabled && recommendedMin != null && value < recommendedMin!)
              Text(
                'Unter der Empfehlung von E3/DC (${fmt(recommendedMin!.toDouble(), 0)} W).',
                style: TextStyle(fontSize: 12, color: c.crit),
              ),
          ],
        ),
      ),
    );
  }
}

class _IdleRow extends StatelessWidget {
  final IdlePeriod period;
  final ValueChanged<bool> onToggle;
  final VoidCallback onTap;
  const _IdleRow({required this.period, required this.onToggle, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.wb;
    final p = period;
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: c.sep)),
      ),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(
                  children: [
                    SizedBox(
                      width: 96,
                      child: Text(
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        p.day >= 0 && p.day < 7 ? _days[p.day] : 'Tag ${p.day}',
                        style: TextStyle(fontSize: 15, color: c.fg),
                      ),
                    ),
                    Flexible(
                      child: Text(
                        '${_hm(p.startHour, p.startMinute)} – ${_hm(p.endHour, p.endMinute)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          color: p.active ? c.fg : c.muted,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(Icons.edit_outlined, size: 14, color: c.muted),
                  ],
                ),
              ),
            ),
          ),
          Switch(value: p.active, onChanged: onToggle, activeTrackColor: c.accent),
        ],
      ),
    );
  }
}
