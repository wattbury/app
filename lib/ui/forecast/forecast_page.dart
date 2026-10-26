import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../data/forecast.dart';
import '../../format.dart';
import '../../theme/tokens.dart';
import '../widgets/cards.dart';

/// Einstellungen › Prognose: provider, the learned correction per hour and how much it helps.
class ForecastPage extends StatelessWidget {
  final ForecastService service;
  const ForecastPage({super.key, required this.service});

  @override
  Widget build(BuildContext context) {
    final c = context.wb;
    return ListenableBuilder(
      listenable: Listenable.merge([service, service.settings]),
      builder: (context, _) {
        final corr = service.correction;
        final s = service.settings;
        return Scaffold(
          appBar: AppBar(
            title: Text('Prognose', style: sora(17, color: c.fg)),
            backgroundColor: c.appBg,
            surfaceTintColor: Colors.transparent,
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 24),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 4, 4, 10),
                child: Text(
                  'Die Prognose rechnet je Tracker mit Ausrichtung, Neigung und kWp aus „Anlage“ und gleicht sich mit den Messwerten des S10 ab.',
                  style: TextStyle(fontSize: 12, color: c.muted),
                ),
              ),
              WhiteCard(
                title: 'Anbieter',
                trailing: 'Open-Meteo',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const _Row('Konto', 'keins nötig · kostenlos'),
                    const _Row('Abfrage', 'Einstrahlung, Temperatur je Tracker'),
                    const _Row('Auflösung', '15 Min. · 3 Tage'),
                    _Row(
                      'Zuletzt geladen',
                      service.rawForecast == null
                          ? (service.error == null ? '–' : 'Fehler')
                          : '${service.rawForecast!.fetchedAt.hour.toString().padLeft(2, '0')}:${service.rawForecast!.fetchedAt.minute.toString().padLeft(2, '0')} Uhr',
                    ),
                    if (service.error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(service.error!, style: TextStyle(fontSize: 12, color: c.crit)),
                      ),
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        'Open-Meteo liefert die Einstrahlung auf die geneigte Fläche, keine Leistung. Wattbury rechnet daraus mit den kWp je Tracker, '
                        'der Modultemperatur und Systemverlusten die Leistung aus. Übertragen werden nur Standort, Ausrichtung und Neigung.',
                        style: TextStyle(fontSize: 12, color: c.muted),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              WhiteCard(
                title: 'Korrekturfaktor',
                action: Switch(
                  value: s.correctionEnabled,
                  activeTrackColor: c.accent,
                  onChanged: (v) => s.correctionEnabled = v,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (!corr.ready)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          'Lernt noch: ${corr.days} von ${_minDays()} Tagen. Bis dahin zeigt die App die Prognose unkorrigiert. '
                          'Jeden Tag vergleicht sie, was vorhergesagt war, mit dem gemessenen Ertrag aus der S10-Datenbank.',
                          style: TextStyle(fontSize: 12, color: c.muted),
                        ),
                      )
                    else ...[
                      Row(
                        children: [
                          Expanded(
                            child: Text('gesamt, aus ${corr.days} Tagen', style: TextStyle(fontSize: 14, color: c.fg)),
                          ),
                          Text(fmt(corr.overall, 2), style: sora(22, color: c.fg)),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text('Faktor je Stunde · 1,0 = Prognose stimmt', style: TextStyle(fontSize: 12, color: c.muted)),
                      const SizedBox(height: 4),
                      _HourChart(factors: corr.hourly),
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          'Unter 1,0 liefert die Anlage weniger als berechnet, etwa durch Verschattung am Morgen. '
                          'Der Faktor fängt das ab, ebenso Verschmutzung, Alterung und Leitungsverluste.',
                          style: TextStyle(fontSize: 12, color: c.muted),
                        ),
                      ),
                    ],
                    const SizedBox(height: 4),
                    _Row('Grundlage', '${corr.days} von 30 Tagen'),
                    _Row(
                      'Nicht gezählt',
                      [
                        if (corr.excludedDays > 0) '${corr.excludedDays} × Schnee/Ausfall',
                        if (corr.curtailedDays > 0) '${corr.curtailedDays} × Abregelung (Stunden)',
                      ].join(' · ').ifEmpty('nichts'),
                    ),
                    _Row(
                      'Zuletzt gelernt',
                      service.learnedAt == null
                          ? 'noch nicht'
                          : '${service.learnedAt!.day}.${service.learnedAt!.month}. ${service.learnedAt!.hour.toString().padLeft(2, '0')}:${service.learnedAt!.minute.toString().padLeft(2, '0')}',
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        onPressed: corr.days == 0
                            ? null
                            : () async {
                                final ok = await showDialog<bool>(
                                  context: context,
                                  builder: (context) => AlertDialog(
                                    title: const Text('Gelerntes zurücksetzen?'),
                                    content: const Text(
                                      'Die App lernt danach neu und zeigt die Prognose so lange unkorrigiert.',
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.pop(context, false),
                                        child: const Text('Abbrechen'),
                                      ),
                                      FilledButton(
                                        onPressed: () => Navigator.pop(context, true),
                                        child: const Text('Zurücksetzen'),
                                      ),
                                    ],
                                  ),
                                );
                                if (ok == true) await service.resetLearning();
                              },
                        child: const Text('Gelerntes zurücksetzen'),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              WhiteCard(
                title: 'Genauigkeit',
                trailing: 'Tagesertrag',
                child: corr.rawError == null
                    ? Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          'Erscheint, sobald es Vergleichstage gibt.',
                          style: TextStyle(fontSize: 12, color: c.muted),
                        ),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const SizedBox(height: 8),
                          _ErrorBar(label: 'ohne Korrektur', value: corr.rawError!, color: c.muted),
                          const SizedBox(height: 6),
                          _ErrorBar(label: 'mit Korrektur', value: corr.correctedError!, color: c.solar),
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              'Mittlere Abweichung der Prognose vom gemessenen Tagesertrag. Bei wechselhaftem Wetter bleibt ein Rest, den kein Faktor ausgleicht.',
                              style: TextStyle(fontSize: 12, color: c.muted),
                            ),
                          ),
                        ],
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  static int _minDays() => 7;
}

extension on String {
  String ifEmpty(String other) => isEmpty ? other : this;
}

class _Row extends StatelessWidget {
  final String label, value;
  const _Row(this.label, this.value);
  @override
  Widget build(BuildContext context) {
    final c = context.wb;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(label, style: TextStyle(fontSize: 14, color: c.fg)),
          ),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(fontSize: 14, color: c.muted),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorBar extends StatelessWidget {
  final String label;
  final double value;
  final Color color;
  const _ErrorBar({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    final c = context.wb;
    return Row(
      children: [
        SizedBox(
          width: 110,
          child: Text(label, style: TextStyle(fontSize: 13, color: c.fg)),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: (value / .5).clamp(0, 1),
              minHeight: 8,
              color: color,
              backgroundColor: c.fg.withValues(alpha: .09),
            ),
          ),
        ),
        SizedBox(
          width: 56,
          child: Text(
            '± ${fmt(value * 100, 0)} %',
            textAlign: TextAlign.right,
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.fg),
          ),
        ),
      ],
    );
  }
}

/// Bars around 1.0 for the daylight hours; down means the plant delivers less than computed.
class _HourChart extends StatefulWidget {
  final List<double> factors;
  const _HourChart({required this.factors});

  @override
  State<_HourChart> createState() => _HourChartState();
}

class _HourChartState extends State<_HourChart> {
  int? _sel;

  @override
  Widget build(BuildContext context) {
    final c = context.wb;
    var first = 0, last = 23;
    while (first < 23 && widget.factors[first] == 1) {
      first++;
    }
    while (last > first && widget.factors[last] == 1) {
      last--;
    }
    if (last - first < 5) {
      first = math.max(0, first - 2);
      last = math.min(23, last + 2);
    }
    final hours = [for (var h = first; h <= last; h++) h];
    return LayoutBuilder(
      builder: (context, box) {
        int? at(Offset o) {
          final slot = (box.maxWidth - 28) / hours.length;
          final i = ((o.dx - 28) / slot).floor();
          return i >= 0 && i < hours.length ? i : null;
        }

        return GestureDetector(
          onTapDown: (e) => setState(() => _sel = at(e.localPosition)),
          onHorizontalDragUpdate: (e) => setState(() => _sel = at(e.localPosition)),
          child: MouseRegion(
            onHover: (e) => setState(() => _sel = at(e.localPosition)),
            onExit: (_) => setState(() => _sel = null),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Semantics(
                  label:
                      'Korrekturfaktor je Stunde von ${fmt(hours.map((h) => widget.factors[h]).reduce(math.min), 2)} bis ${fmt(hours.map((h) => widget.factors[h]).reduce(math.max), 2)}',
                  child: CustomPaint(
                    size: Size(box.maxWidth, 104),
                    painter: _HourPainter(hours, widget.factors, c, _sel, DefaultTextStyle.of(context).style),
                  ),
                ),
                if (_sel != null)
                  Positioned(
                    left: (28 + (box.maxWidth - 28) / hours.length * (_sel! + .5) - 60).clamp(0, box.maxWidth - 120),
                    top: 0,
                    width: 120,
                    child: IgnorePointer(
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(color: c.fg, borderRadius: BorderRadius.circular(7)),
                        child: Text(
                          '${hours[_sel!].toString().padLeft(2, '0')}–${(hours[_sel!] + 1).toString().padLeft(2, '0')} Uhr\nFaktor ${fmt(widget.factors[hours[_sel!]], 2)}',
                          style: TextStyle(fontSize: 11, color: c.appBg),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _HourPainter extends CustomPainter {
  final List<int> hours;
  final List<double> factors;
  final WbColors c;
  final int? sel;
  final TextStyle base;
  _HourPainter(this.hours, this.factors, this.c, this.sel, this.base);

  @override
  void paint(Canvas canvas, Size size) {
    const left = 28.0, top = 6.0, bottom = 16.0, lo = .6, hi = 1.2;
    final ih = size.height - top - bottom;
    double y(double v) => top + (hi - v.clamp(lo, hi)) / (hi - lo) * ih;
    final text = base.copyWith(fontSize: 9, color: c.ink3);
    void label(String s, Offset at, {bool right = false, bool center = false}) {
      final tp = TextPainter(
        text: TextSpan(text: s, style: text),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(
        canvas,
        Offset(right ? at.dx - tp.width : (center ? at.dx - tp.width / 2 : at.dx), at.dy - tp.height / 2),
      );
    }

    for (final v in [.8, 1.0, 1.2]) {
      canvas.drawLine(Offset(left, y(v)), Offset(size.width, y(v)), Paint()..color = v == 1 ? c.axis : c.grid1);
      label(fmt(v, 1), Offset(left - 4, y(v)), right: true);
    }
    final slot = (size.width - left) / hours.length, bw = math.min(16.0, slot * .62);
    for (final (i, h) in hours.indexed) {
      final x = left + slot * i + (slot - bw) / 2;
      final f = factors[h];
      final r = Rect.fromLTRB(x, math.min(y(f), y(1)), x + bw, math.max(y(f), y(1)) + (f == 1 ? 1 : 0));
      canvas.drawRRect(
        RRect.fromRectAndRadius(r, const Radius.circular(2)),
        Paint()..color = sel == i ? c.solar.withValues(alpha: .7) : c.solar,
      );
      if (i % 2 == 0) label(h.toString().padLeft(2, '0'), Offset(x + bw / 2, size.height - 6), center: true);
    }
  }

  @override
  bool shouldRepaint(_HourPainter old) => old.sel != sel || old.factors != factors || old.c != c;
}
