import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:openrscp/openrscp.dart';

import '../../data/energy_source.dart';
import '../../data/forecast.dart';
import '../../data/plant.dart';
import '../../format.dart';
import '../../theme/tokens.dart';
import '../widgets/cards.dart';

/// "Anlage": what the unit knows is prefilled; per tracker the user enters the roof face
/// (azimuth, tilt) and the strings (modules × Wp). Tracker count comes from the device.
class PlantPage extends StatefulWidget {
  final PlantConfig initial;
  final List<PvTracker> trackers;
  final SystemInfo? system;
  final EnergySource source;
  final OpenMeteo? geocoder;
  final ValueChanged<PlantConfig> onSave;

  const PlantPage({
    super.key,
    required this.initial,
    required this.trackers,
    required this.system,
    required this.source,
    required this.onSave,
    this.geocoder,
  });

  @override
  State<PlantPage> createState() => _PlantPageState();
}

class _PlantPageState extends State<PlantPage> {
  late List<TrackerConfig> _trackers;
  double? _lat, _lon;
  String? _place;
  String _postcode = '', _city = '', _country = 'DE';
  bool _locating = false;
  String? _locError;
  late final OpenMeteo _geo = widget.geocoder ?? OpenMeteo();

  @override
  void initState() {
    super.initState();
    final p = widget.initial;
    _lat = p.latitude;
    _lon = p.longitude;
    _place = p.place;
    // One card per tracker the device reports; keep earlier entries, add defaults for new ones.
    final device = widget.trackers.isEmpty
        ? p.trackers.map((t) => (t.pvi, t.index)).toList()
        : widget.trackers.map((t) => (t.pviIndex, t.index)).toList();
    _trackers = [
      for (final (i, (pvi, idx)) in device.indexed)
        p.tracker(pvi, idx) ??
            TrackerConfig(
              pvi: pvi,
              index: idx,
              name: 'Tracker ${i + 1}',
              azimuth: 180,
              tilt: 30,
              strings: const [PvString(modules: 10, wp: 400)],
            ),
    ];
    _loadFacility();
  }

  Future<void> _loadFacility() async {
    try {
      final f = await widget.source.facilityLocation();
      if (!mounted) return;
      setState(() {
        _postcode = f.postcode;
        _city = f.city;
        if (f.country.length == 2) _country = f.country;
      });
      if (_lat == null && (_postcode.isNotEmpty || _city.isNotEmpty)) await _locate();
    } catch (_) {
      // Not every unit or firmware reports the address; the location can be entered by hand.
    }
  }

  Future<void> _locate() async {
    setState(() {
      _locating = true;
      _locError = null;
    });
    try {
      final r = await _geo.locate(_postcode, _city, country: _country);
      if (!mounted) return;
      setState(() {
        if (r == null) {
          _locError = 'Ort nicht gefunden. Bitte Koordinaten eintragen.';
        } else {
          _lat = r.lat;
          _lon = r.lon;
          _place = r.label;
        }
      });
    } catch (e) {
      if (mounted) setState(() => _locError = 'Ortssuche fehlgeschlagen: $e');
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  PvTracker? _live(TrackerConfig t) {
    for (final x in widget.trackers) {
      if (x.pviIndex == t.pvi && x.index == t.index) return x;
    }
    return null;
  }

  void _update(int i, TrackerConfig t) => setState(() => _trackers[i] = t);

  @override
  Widget build(BuildContext context) {
    final c = context.wb;
    final sys = widget.system;
    final sum = _trackers.fold<double>(0, (a, t) => a + t.kwp);
    final s10 = (sys?.installedPeakPowerW ?? 0) / 1000;
    final ok = _lat != null && _lon != null && _trackers.isNotEmpty && _trackers.every((t) => t.kwp > 0);
    return Scaffold(
      appBar: AppBar(
        title: Text('Anlage', style: sora(17, color: c.fg)),
        backgroundColor: c.appBg,
        surfaceTintColor: Colors.transparent,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(10, 0, 10, 24),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 10),
            child: Text(
              'Was das Hauskraftwerk selbst weiß, ist vorbelegt. Wie die Module auf dem Dach liegen, kennt es nicht. Das braucht die Prognose.',
              style: TextStyle(fontSize: 12, color: c.muted),
            ),
          ),
          WhiteCard(
            title: 'Vom Hauskraftwerk',
            trailing: 'per RSCP',
            child: Column(
              children: [
                _Info('PV-Spitzenleistung', s10 > 0 ? '${fmt(s10, 2)} kWp' : '–'),
                _Info('Tracker mit Messwerten', '${widget.trackers.length}'),
                _Info('Firmware', sys?.swRelease ?? '–'),
              ],
            ),
          ),
          const SizedBox(height: 10),
          WhiteCard(
            title: 'Standort',
            trailing: 'für die Prognose',
            child: _LocationEditor(
              lat: _lat,
              lon: _lon,
              place: _place,
              postcode: _postcode,
              city: _city,
              busy: _locating,
              error: _locError,
              onAddress: (p, cty) => setState(() {
                _postcode = p;
                _city = cty;
              }),
              onLocate: _locate,
              onCoordinates: (la, lo) => setState(() {
                _lat = la;
                _lon = lo;
                _place = 'manuell';
              }),
            ),
          ),
          for (final (i, t) in _trackers.indexed) ...[
            const SizedBox(height: 10),
            _TrackerCard(tracker: t, live: _live(t), onChanged: (n) => _update(i, n)),
          ],
          const SizedBox(height: 10),
          WhiteCard(
            title: 'Summe',
            action: s10 <= 0
                ? null
                : Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: ((sum - s10).abs() < .005 ? c.good : c.warn).withValues(alpha: .2),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      (sum - s10).abs() < .005
                          ? '✓ passt zum S10'
                          : '${fmt((sum - s10).abs(), 2)} kWp ${sum < s10 ? 'weniger' : 'mehr'} als im S10',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: c.fg),
                    ),
                  ),
            child: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${_trackers.map((t) => fmt(t.kwp, 2)).join(' + ')} kWp',
                          style: TextStyle(fontSize: 14, color: c.fg),
                        ),
                      ),
                      Text(
                        s10 > 0 ? '${fmt(sum, 2)} von ${fmt(s10, 2)} kWp' : '${fmt(sum, 2)} kWp',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.fg),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Der Wert im S10 kann veraltet sein oder weitere Erzeuger enthalten, deshalb nur ein Hinweis. '
                    'Zuordnung: Morgens liefert ein östlicher Tracker mehr, abends ein westlicher.',
                    style: TextStyle(fontSize: 12, color: c.muted),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: ok
                ? () {
                    widget.onSave(PlantConfig(latitude: _lat, longitude: _lon, place: _place, trackers: _trackers));
                    Navigator.of(context).pop();
                  }
                : null,
            style: FilledButton.styleFrom(
              backgroundColor: c.accent,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Speichern', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          ),
          if (!ok)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Zum Speichern braucht es einen Standort und je Tracker mindestens einen String.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: c.muted),
              ),
            ),
        ],
      ),
    );
  }
}

class _Info extends StatelessWidget {
  final String label, value;
  const _Info(this.label, this.value);
  @override
  Widget build(BuildContext context) {
    final c = context.wb;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: TextStyle(fontSize: 14, color: c.fg)),
          ),
          Text(value, style: TextStyle(fontSize: 14, color: c.muted)),
        ],
      ),
    );
  }
}

InputDecoration _deco(BuildContext context, String label, {String? suffix}) {
  final c = context.wb;
  return InputDecoration(
    labelText: label,
    suffixText: suffix,
    isDense: true,
    filled: true,
    fillColor: c.appBg,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(9),
      borderSide: BorderSide(color: c.sep),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(9),
      borderSide: BorderSide(color: c.sep),
    ),
  );
}

double? _num(String s) => double.tryParse(s.trim().replaceAll(',', '.'));

class _LocationEditor extends StatefulWidget {
  final double? lat, lon;
  final String? place, error;
  final String postcode, city;
  final bool busy;
  final void Function(String postcode, String city) onAddress;
  final VoidCallback onLocate;
  final void Function(double lat, double lon) onCoordinates;
  const _LocationEditor({
    required this.lat,
    required this.lon,
    required this.place,
    required this.postcode,
    required this.city,
    required this.busy,
    required this.error,
    required this.onAddress,
    required this.onLocate,
    required this.onCoordinates,
  });

  @override
  State<_LocationEditor> createState() => _LocationEditorState();
}

class _LocationEditorState extends State<_LocationEditor> {
  late final _plz = TextEditingController(text: widget.postcode), _city = TextEditingController(text: widget.city);
  bool _manual = false;
  late final _lat = TextEditingController(text: widget.lat?.toStringAsFixed(4) ?? '');
  late final _lon = TextEditingController(text: widget.lon?.toStringAsFixed(4) ?? '');

  @override
  void didUpdateWidget(_LocationEditor old) {
    super.didUpdateWidget(old);
    if (old.postcode != widget.postcode && _plz.text.isEmpty) _plz.text = widget.postcode;
    if (old.city != widget.city && _city.text.isEmpty) _city.text = widget.city;
    if (!_manual && (old.lat != widget.lat || old.lon != widget.lon)) {
      _lat.text = widget.lat?.toStringAsFixed(4) ?? '';
      _lon.text = widget.lon?.toStringAsFixed(4) ?? '';
    }
  }

  @override
  void dispose() {
    for (final c in [_plz, _city, _lat, _lon]) {
      c.dispose();
    }
    super.dispose();
  }

  void _coords() {
    final la = _num(_lat.text), lo = _num(_lon.text);
    if (la != null && lo != null && la.abs() <= 90 && lo.abs() <= 180) widget.onCoordinates(la, lo);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.wb;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        Row(
          children: [
            SizedBox(
              width: 96,
              child: TextField(
                controller: _plz,
                decoration: _deco(context, 'PLZ'),
                keyboardType: TextInputType.number,
                onChanged: (v) => widget.onAddress(v.trim(), _city.text.trim()),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _city,
                decoration: _deco(context, 'Ort'),
                onChanged: (v) => widget.onAddress(_plz.text.trim(), v.trim()),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Text(
                widget.lat == null
                    ? 'Noch kein Standort'
                    : '${fmt(widget.lat!, 4)}° N · ${fmt(widget.lon!, 4)}° O${widget.place == null ? '' : ' (${widget.place})'}',
                style: TextStyle(fontSize: 13, color: c.fg),
              ),
            ),
            TextButton(
              onPressed: widget.busy ? null : widget.onLocate,
              child: widget.busy
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Suchen'),
            ),
          ],
        ),
        if (widget.error != null) Text(widget.error!, style: TextStyle(fontSize: 12, color: c.crit)),
        TextButton(
          style: TextButton.styleFrom(alignment: Alignment.centerLeft, padding: EdgeInsets.zero),
          onPressed: () => setState(() => _manual = !_manual),
          child: Text(_manual ? 'Koordinaten ausblenden' : 'Koordinaten selbst eintragen'),
        ),
        if (_manual)
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _lat,
                  decoration: _deco(context, 'Breite', suffix: '°'),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                  onChanged: (_) => _coords(),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _lon,
                  decoration: _deco(context, 'Länge', suffix: '°'),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                  onChanged: (_) => _coords(),
                ),
              ),
            ],
          ),
        Text(
          'Die Ortssuche läuft über Open-Meteo. Für die Prognose reicht der Ort, die Adresse wird nicht übertragen.',
          style: TextStyle(fontSize: 12, color: c.muted),
        ),
      ],
    );
  }
}

class _TrackerCard extends StatefulWidget {
  final TrackerConfig tracker;
  final PvTracker? live;
  final ValueChanged<TrackerConfig> onChanged;
  const _TrackerCard({required this.tracker, required this.live, required this.onChanged});

  @override
  State<_TrackerCard> createState() => _TrackerCardState();
}

class _TrackerCardState extends State<_TrackerCard> {
  late final _name = TextEditingController(text: widget.tracker.name);
  late final _az = TextEditingController(text: '${widget.tracker.azimuth}');
  late final _tilt = TextEditingController(text: '${widget.tracker.tilt}');

  TrackerConfig get t => widget.tracker;

  @override
  void didUpdateWidget(_TrackerCard old) {
    super.didUpdateWidget(old);
    // Keep fields in sync when the compass or the slider changed the value.
    if ('${t.azimuth}' != _az.text && _num(_az.text)?.round() != t.azimuth) _az.text = '${t.azimuth}';
    if ('${t.tilt}' != _tilt.text && _num(_tilt.text)?.round() != t.tilt) _tilt.text = '${t.tilt}';
  }

  @override
  void dispose() {
    _name.dispose();
    _az.dispose();
    _tilt.dispose();
    super.dispose();
  }

  void _setAz(int a) {
    final v = ((a % 360) + 360) % 360;
    widget.onChanged(t.copyWith(azimuth: v));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.wb;
    const dirs = ['Nord', 'Nordost', 'Ost', 'Südost', 'Süd', 'Südwest', 'West', 'Nordwest'];
    final dirLong = dirs[((t.azimuth % 360) / 45).round() % 8];
    final live = widget.live?.powerW;
    return WhiteCard(
      title: '',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _name,
                  style: sora(16, color: c.fg),
                  decoration: const InputDecoration(isDense: true, border: InputBorder.none, hintText: 'Name'),
                  onChanged: (v) => widget.onChanged(t.copyWith(name: v)),
                ),
              ),
              if (live != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: c.good.withValues(alpha: .18),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    'live ${power(live).value} ${power(live).unit}',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: c.good),
                  ),
                ),
            ],
          ),
          Text('Dachfläche', style: TextStyle(fontSize: 12, color: c.muted)),
          const SizedBox(height: 8),
          Row(
            children: [
              _Compass(azimuth: t.azimuth, onChanged: _setAz),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Ausrichtung', style: TextStyle(fontSize: 12, color: c.muted)),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        SizedBox(
                          width: 72,
                          child: TextField(
                            controller: _az,
                            decoration: _deco(context, '', suffix: '°'),
                            keyboardType: TextInputType.number,
                            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                            onChanged: (v) {
                              final n = int.tryParse(v);
                              if (n != null && n >= 0 && n < 360) widget.onChanged(t.copyWith(azimuth: n));
                            },
                          ),
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(dirLong, style: TextStyle(fontSize: 13, color: c.muted)),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        IconButton(
                          onPressed: () => _setAz(t.azimuth - 1),
                          icon: const Icon(Icons.remove),
                          tooltip: '1 Grad gegen den Uhrzeigersinn',
                          visualDensity: VisualDensity.compact,
                        ),
                        IconButton(
                          onPressed: () => _setAz(t.azimuth + 1),
                          icon: const Icon(Icons.add),
                          tooltip: '1 Grad im Uhrzeigersinn',
                          visualDensity: VisualDensity.compact,
                        ),
                      ],
                    ),
                    Text('0° = Nord, 180° = Süd', style: TextStyle(fontSize: 11, color: c.muted)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text('Neigung', style: TextStyle(fontSize: 14, color: c.fg)),
              ),
              SizedBox(
                width: 72,
                child: TextField(
                  controller: _tilt,
                  decoration: _deco(context, '', suffix: '°'),
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onChanged: (v) {
                    final n = int.tryParse(v);
                    if (n != null && n <= 90) widget.onChanged(t.copyWith(tilt: n));
                  },
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context)
                .copyWith(activeTrackColor: c.solar, thumbColor: c.solar, inactiveTrackColor: c.sep),
            child: Slider(
              value: t.tilt.toDouble(),
              max: 90,
              divisions: 90,
              label: '${t.tilt}°',
              onChanged: (v) => widget.onChanged(t.copyWith(tilt: v.round())),
            ),
          ),
          Divider(color: c.sep),
          Row(
            children: [
              Expanded(
                child: Text('Strings an diesem Tracker', style: TextStyle(fontSize: 14, color: c.fg)),
              ),
              Text(
                '${fmt(t.kwp, 2)} kWp',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.fg),
              ),
            ],
          ),
          for (final (j, s) in t.strings.indexed)
            _StringRow(
              number: j + 1,
              string: s,
              removable: t.strings.length > 1,
              onChanged: (n) => widget.onChanged(t.copyWith(strings: [...t.strings]..[j] = n)),
              onRemove: () => widget.onChanged(t.copyWith(strings: [...t.strings]..removeAt(j))),
            ),
          TextButton.icon(
            onPressed: () => widget.onChanged(t.copyWith(strings: [...t.strings, t.strings.last])),
            icon: const Icon(Icons.add),
            label: const Text('String hinzufügen'),
          ),
          Text(
            'Parallele Strings am selben Tracker misst das S10 nur gemeinsam. Für die Prognose zählt die Summe.',
            style: TextStyle(fontSize: 12, color: c.muted),
          ),
        ],
      ),
    );
  }
}

class _StringRow extends StatefulWidget {
  final int number;
  final PvString string;
  final bool removable;
  final ValueChanged<PvString> onChanged;
  final VoidCallback onRemove;
  const _StringRow({
    required this.number,
    required this.string,
    required this.removable,
    required this.onChanged,
    required this.onRemove,
  });

  @override
  State<_StringRow> createState() => _StringRowState();
}

class _StringRowState extends State<_StringRow> {
  late final _mod = TextEditingController(text: '${widget.string.modules}');
  late final _wp = TextEditingController(text: '${widget.string.wp}');

  @override
  void dispose() {
    _mod.dispose();
    _wp.dispose();
    super.dispose();
  }

  void _changed() {
    final m = int.tryParse(_mod.text), w = int.tryParse(_wp.text);
    if (m != null && m > 0 && m <= 60 && w != null && w >= 50 && w <= 1000) {
      widget.onChanged(PvString(modules: m, wp: w));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.wb;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          SizedBox(
            width: 64,
            child: Text('String ${widget.number}', style: TextStyle(fontSize: 13, color: c.muted)),
          ),
          SizedBox(
            width: 80,
            child: TextField(
              controller: _mod,
              decoration: _deco(context, 'Module'),
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onChanged: (_) => _changed(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text('×', style: TextStyle(color: c.muted)),
          ),
          Expanded(
            child: TextField(
              controller: _wp,
              decoration: _deco(context, 'Wp je Modul'),
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onChanged: (_) => _changed(),
            ),
          ),
          if (widget.removable)
            IconButton(
              onPressed: widget.onRemove,
              icon: const Icon(Icons.close),
              tooltip: 'String ${widget.number} entfernen',
              visualDensity: VisualDensity.compact,
            )
          else
            const SizedBox(width: 40),
        ],
      ),
    );
  }
}

/// Drag the needle to set the azimuth; snaps to 5 degrees.
class _Compass extends StatelessWidget {
  final int azimuth;
  final ValueChanged<int> onChanged;
  const _Compass({required this.azimuth, required this.onChanged});

  void _at(Offset p) {
    const c = Offset(55, 55);
    final d = p - c;
    final a = (math.atan2(d.dx, -d.dy) * 180 / math.pi + 360) % 360;
    onChanged(((a / 5).round() * 5) % 360);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.wb;
    return Semantics(
      label: 'Kompass, Ausrichtung $azimuth Grad',
      child: GestureDetector(
        onPanDown: (e) => _at(e.localPosition),
        onPanUpdate: (e) => _at(e.localPosition),
        child: CustomPaint(
          size: const Size(110, 110),
          painter: _CompassPainter(azimuth, c, DefaultTextStyle.of(context).style),
        ),
      ),
    );
  }
}

class _CompassPainter extends CustomPainter {
  final int azimuth;
  final WbColors c;
  final TextStyle base;
  _CompassPainter(this.azimuth, this.c, this.base);

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    const r = 44.0;
    Offset pt(double a, double rr) {
      final t = (a - 90) * math.pi / 180;
      return center + Offset(math.cos(t) * rr, math.sin(t) * rr);
    }

    canvas.drawCircle(center, r, Paint()..color = c.appBg);
    canvas.drawCircle(
      center,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..color = c.sep
        ..strokeWidth = 1.5,
    );
    for (var a = 0; a < 360; a += 30) {
      canvas.drawLine(pt(a.toDouble(), r - 4), pt(a.toDouble(), r), Paint()..color = c.muted);
    }
    for (final (t, a) in [('N', 0.0), ('O', 90.0), ('S', 180.0), ('W', 270.0)]) {
      final tp = TextPainter(
        text: TextSpan(
          text: t,
          style: base.copyWith(fontSize: 10, fontWeight: FontWeight.w600, color: c.muted),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, pt(a, r - 13) - Offset(tp.width / 2, tp.height / 2));
    }
    final tip = pt(azimuth.toDouble(), r - 8);
    canvas.drawLine(
      center,
      tip,
      Paint()
        ..color = c.solar
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(tip, 6, Paint()..color = c.solar);
    canvas.drawCircle(
      tip,
      6,
      Paint()
        ..style = PaintingStyle.stroke
        ..color = c.card
        ..strokeWidth = 2,
    );
    canvas.drawCircle(center, 3, Paint()..color = c.fg);
  }

  @override
  bool shouldRepaint(_CompassPainter old) => old.azimuth != azimuth || old.c != c;
}
