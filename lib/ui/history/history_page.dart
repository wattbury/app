import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../../data/history.dart';
import '../../format.dart';
import '../../theme/tokens.dart';
import '../widgets/cards.dart';

/// One chart series: sources stack upwards, sinks downwards.
class _Series {
  final String key, label;
  final bool source;
  final double Function(HistoryPoint) value;
  final Color Function(WbColors) color;
  const _Series(this.key, this.label, this.source, this.value, this.color);
}

final _series = <_Series>[
  _Series('solar', 'Solar', true, (p) => p.solar, (c) => c.sSolar),
  _Series('purchase', 'Netzbezug', true, (p) => p.purchase, (c) => c.sPurchase),
  _Series('batteryOut', 'Batterie entladen', true, (p) => p.batteryOut, (c) => c.sBatteryOut),
  _Series('house', 'Verbrauch', false, (p) => p.house, (c) => c.sHouse),
  _Series('feedIn', 'Einspeisung', false, (p) => p.feedIn, (c) => c.sFeedIn),
  _Series('batteryIn', 'Batterie laden', false, (p) => p.batteryIn, (c) => c.sBatteryIn),
];

/// Diagramme: day, week, month and year from the unit's database as stacked bars,
/// with the balance of the period below.
class HistoryPage extends StatefulWidget {
  final HistoryRepository repo;
  const HistoryPage({super.key, required this.repo});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  HistoryRange _range = HistoryRange.week;
  DateTime _anchor = DateTime.now();
  final _hidden = <String>{};
  Future<HistoryData>? _data;
  int? _selected;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(HistoryPage old) {
    super.didUpdateWidget(old);
    if (!identical(old.repo, widget.repo)) _load();
  }

  void _load() {
    _selected = null;
    _data = widget.repo.load(_range, _anchor);
  }

  bool get _canForward {
    final (start, _) = HistoryRepository.bounds(_range, HistoryRepository.shift(_range, _anchor, 1));
    return !start.isAfter(DateTime.now());
  }

  void _step(int d) => setState(() {
    _anchor = HistoryRepository.shift(_range, _anchor, d);
    _load();
  });

  String _title(DateTime start, DateTime end) {
    final last = end.subtract(const Duration(days: 1));
    return switch (_range) {
      HistoryRange.day => DateFormat('EEE, d. MMM y', 'de_DE').format(start),
      HistoryRange.week =>
        start.month == last.month
            ? '${start.day}. – ${DateFormat('d. MMM y', 'de_DE').format(last)}'
            : '${DateFormat('d. MMM', 'de_DE').format(start)} – ${DateFormat('d. MMM y', 'de_DE').format(last)}',
      HistoryRange.month => DateFormat('MMMM y', 'de_DE').format(start),
      HistoryRange.year => '${start.year}',
    };
  }

  @override
  Widget build(BuildContext context) {
    final c = context.wb;
    final (start, end) = HistoryRepository.bounds(_range, _anchor);
    return ListView(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 16),
      children: [
        SegmentedButton<HistoryRange>(
          segments: const [
            ButtonSegment(value: HistoryRange.day, label: Text('Tag')),
            ButtonSegment(value: HistoryRange.week, label: Text('Woche')),
            ButtonSegment(value: HistoryRange.month, label: Text('Monat')),
            ButtonSegment(value: HistoryRange.year, label: Text('Jahr')),
          ],
          selected: {_range},
          showSelectedIcon: false,
          onSelectionChanged: (s) => setState(() {
            _range = s.first;
            _anchor = DateTime.now();
            _load();
          }),
        ),
        const SizedBox(height: 10),
        FutureBuilder<HistoryData>(
          future: _data,
          builder: (context, snap) {
            // FutureBuilder keeps the previous result while a new period loads; show the loader instead.
            final d = snap.connectionState == ConnectionState.done ? snap.data : null;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                WhiteCard(
                  title: _title(start, end),
                  action: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        onPressed: () => _step(-1),
                        icon: const Icon(Icons.chevron_left),
                        tooltip: 'Zurück',
                        visualDensity: VisualDensity.compact,
                      ),
                      IconButton(
                        onPressed: _canForward ? () => _step(1) : null,
                        icon: const Icon(Icons.chevron_right),
                        tooltip: 'Weiter',
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: snap.hasError
                        ? _Message(text: 'Daten konnten nicht geladen werden: ${snap.error}')
                        : d == null
                        ? SizedBox(
                            height: 220,
                            child: Center(child: CircularProgressIndicator(color: c.accent)),
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _Chart(
                                data: d,
                                hidden: _hidden,
                                selected: _selected,
                                onSelect: (i) => setState(() => _selected = i),
                              ),
                              const SizedBox(height: 8),
                              _Legend(
                                hidden: _hidden,
                                onToggle: (k) =>
                                    setState(() => _hidden.contains(k) ? _hidden.remove(k) : _hidden.add(k)),
                              ),
                            ],
                          ),
                  ),
                ),
                if (d != null) ...[const SizedBox(height: 10), _Balance(data: d)],
              ],
            );
          },
        ),
      ],
    );
  }
}

class _Message extends StatelessWidget {
  final String text;
  const _Message({required this.text});
  @override
  Widget build(BuildContext context) => SizedBox(
    height: 120,
    child: Center(
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 13, color: context.wb.muted),
      ),
    ),
  );
}

class _Chart extends StatelessWidget {
  final HistoryData data;
  final Set<String> hidden;
  final int? selected;
  final ValueChanged<int?> onSelect;
  const _Chart({required this.data, required this.hidden, required this.selected, required this.onSelect});

  String _label(HistoryPoint p) => switch (data.range) {
    HistoryRange.day => '${p.start.hour.toString().padLeft(2, '0')}:00',
    HistoryRange.week || HistoryRange.month => DateFormat('EEE, d. MMM', 'de_DE').format(p.start),
    HistoryRange.year => DateFormat('MMMM', 'de_DE').format(p.start),
  };

  @override
  Widget build(BuildContext context) {
    final c = context.wb;
    final visible = _series.where((s) => !hidden.contains(s.key)).toList();
    return LayoutBuilder(
      builder: (context, box) {
        const h = 210.0;
        final painter = _BarPainter(
          data: data,
          series: visible,
          c: c,
          selected: selected,
          base: DefaultTextStyle.of(context).style,
        );
        int? hit(Offset o) {
          final i = painter.indexAt(o.dx, box.maxWidth);
          return (i != null && i >= 0 && i < data.points.length) ? i : null;
        }

        final sel = selected;
        return MouseRegion(
          onHover: (e) => onSelect(hit(e.localPosition)),
          onExit: (_) => onSelect(null),
          child: GestureDetector(
            onTapDown: (e) => onSelect(hit(e.localPosition)),
            onHorizontalDragUpdate: (e) => onSelect(hit(e.localPosition)),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Semantics(
                  label: 'Gestapeltes Balkendiagramm: oben Quellen, unten Verbrauch, in kWh',
                  child: CustomPaint(size: Size(box.maxWidth, h), painter: painter),
                ),
                if (sel != null)
                  Positioned(
                    left: (painter.barCenter(sel, box.maxWidth) - 80).clamp(0, box.maxWidth - 160),
                    top: 0,
                    width: 160,
                    child: IgnorePointer(
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
                        decoration: BoxDecoration(color: c.fg, borderRadius: BorderRadius.circular(7)),
                        child: DefaultTextStyle(
                          style: TextStyle(fontSize: 11, color: c.appBg, height: 1.35),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(_label(data.points[sel]), style: const TextStyle(fontWeight: FontWeight.w600)),
                              for (final s in visible)
                                Row(
                                  children: [
                                    Container(
                                      width: 8,
                                      height: 8,
                                      margin: const EdgeInsets.only(right: 5),
                                      decoration: BoxDecoration(
                                        color: s.color(c),
                                        borderRadius: BorderRadius.circular(2),
                                      ),
                                    ),
                                    Expanded(child: Text(s.label)),
                                    Text('${kwh(s.value(data.points[sel]), 2)} kWh'),
                                  ],
                                ),
                            ],
                          ),
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

class _BarPainter extends CustomPainter {
  final HistoryData data;
  final List<_Series> series;
  final WbColors c;
  final int? selected;

  /// App body text style, so axis labels use the app font.
  final TextStyle base;
  _BarPainter({required this.data, required this.series, required this.c, required this.selected, required this.base});

  static const _left = 30.0, _right = 4.0, _top = 18.0, _bottom = 18.0;

  double _slot(double width) => (width - _left - _right) / data.points.length;
  double barCenter(int i, double width) => _left + _slot(width) * (i + .5);
  int? indexAt(double x, double width) => x < _left ? null : ((x - _left) / _slot(width)).floor();

  /// 1, 2 or 5 times a power of ten, at least [v].
  static double _nice(double v) {
    if (v <= 0) return 1;
    final e = math.pow(10, (math.log(v) / math.ln10).floor()).toDouble();
    final f = v / e;
    return (f <= 1
            ? 1
            : f <= 2
            ? 2
            : f <= 5
            ? 5
            : 10) *
        e;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final pts = data.points;
    double up(HistoryPoint p) => series.where((s) => s.source).fold(0, (a, s) => a + s.value(p) / 1000);
    double down(HistoryPoint p) => series.where((s) => !s.source).fold(0, (a, s) => a + s.value(p) / 1000);
    final maxUp = pts.fold<double>(0, (a, p) => math.max(a, up(p)));
    final maxDown = pts.fold<double>(0, (a, p) => math.max(a, down(p)));
    final top = _nice(maxUp), bot = maxDown > 0 ? _nice(maxDown) : 0.0;
    final ih = size.height - _top - _bottom;
    final scale = ih / (top + bot);
    final y0 = _top + top * scale;
    final text = base.copyWith(fontSize: 9, color: c.ink3, fontFeatures: const [FontFeature.tabularFigures()]);

    // Recessive grid and the zero line.
    final ticks = <double>[top, top / 2, 0, if (bot > 0) -bot / 2, if (bot > 0) -bot];
    for (final t in ticks) {
      final y = y0 - t * scale;
      canvas.drawLine(
        Offset(_left, y),
        Offset(size.width - _right, y),
        Paint()
          ..color = t == 0 ? c.axis : c.grid1
          ..strokeWidth = 1,
      );
      final label = t.abs() < 1 && t != 0 ? fmt(t.abs(), 1) : fmt(t.abs(), 0);
      _text(canvas, label, text, Offset(_left - 4, y), alignRight: true);
    }
    _text(canvas, 'kWh', text, const Offset(0, 5));

    final slot = _slot(size.width);
    final bw = math.max(3.0, math.min(26.0, slot * .62));
    const gap = 2.0;
    for (var i = 0; i < pts.length; i++) {
      final p = pts[i];
      final x = _left + slot * i + (slot - bw) / 2;
      if (selected == i) {
        canvas.drawRect(Rect.fromLTWH(_left + slot * i, _top, slot, ih), Paint()..color = c.fg.withValues(alpha: .05));
      }
      var yu = y0, yd = y0;
      for (final s in series) {
        final h = s.value(p) / 1000 * scale;
        if (h < .5) continue;
        final paint = Paint()..color = s.color(c);
        if (s.source) {
          final r = Rect.fromLTWH(x, yu - h, bw, math.max(0, h - gap));
          canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(1.5)), paint);
          yu -= h;
        } else {
          final r = Rect.fromLTWH(x, yd + gap, bw, math.max(0, h - gap));
          canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(1.5)), paint);
          yd += h;
        }
      }
      final every = switch (data.range) {
        HistoryRange.day => 3,
        HistoryRange.month => 5,
        _ => 1,
      };
      if (i % every == 0 || (data.range == HistoryRange.month && i == 0)) {
        final l = switch (data.range) {
          HistoryRange.day => p.start.hour.toString().padLeft(2, '0'),
          HistoryRange.week => const ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'][p.start.weekday - 1],
          HistoryRange.month => '${p.start.day}',
          HistoryRange.year => 'JFMAMJJASOND'[p.start.month - 1],
        };
        _text(canvas, l, text, Offset(x + bw / 2, size.height - 6), center: true);
      }
    }
  }

  void _text(Canvas canvas, String s, TextStyle style, Offset at, {bool alignRight = false, bool center = false}) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    final dx = alignRight ? at.dx - tp.width : (center ? at.dx - tp.width / 2 : at.dx);
    tp.paint(canvas, Offset(dx, at.dy - tp.height / 2));
  }

  @override
  bool shouldRepaint(_BarPainter old) =>
      old.data != data || old.selected != selected || old.series.length != series.length || old.c != c;
}

class _Legend extends StatelessWidget {
  final Set<String> hidden;
  final ValueChanged<String> onToggle;
  const _Legend({required this.hidden, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    final c = context.wb;
    return Wrap(
      spacing: 12,
      runSpacing: 4,
      children: [
        for (final s in _series)
          Semantics(
            button: true,
            toggled: !hidden.contains(s.key),
            child: InkWell(
              onTap: () => onToggle(s.key),
              borderRadius: BorderRadius.circular(6),
              child: Opacity(
                opacity: hidden.contains(s.key) ? .4 : 1,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(color: s.color(c), borderRadius: BorderRadius.circular(3)),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      s.label,
                      style: TextStyle(
                        fontSize: 11,
                        color: c.muted,
                        decoration: hidden.contains(s.key) ? TextDecoration.lineThrough : null,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _Balance extends StatelessWidget {
  final HistoryData data;
  const _Balance({required this.data});

  @override
  Widget build(BuildContext context) {
    final c = context.wb;
    final s = data.sum;
    return WhiteCard(
      title: 'Bilanz',
      trailing: switch (data.range) {
        HistoryRange.day => 'Tag',
        HistoryRange.week => 'Woche',
        HistoryRange.month => 'Monat',
        HistoryRange.year => 'Jahr',
      },
      child: Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: KpiTile(
                    background: c.pastelGreen,
                    dot: c.battery,
                    label: 'Autarkie',
                    value: fmt(s.autarkyPct),
                    unit: '%',
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: KpiTile(
                    background: c.pastelYellow,
                    dot: c.solar,
                    label: 'Eigenverbrauch',
                    value: fmt(s.consumedProductionPct),
                    unit: '%',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: KpiTile(
                    background: c.pastelYellow,
                    dot: c.sSolar,
                    label: 'Solar',
                    value: kwh(s.solarWh, s.solarWh >= 100000 ? 0 : 1),
                    unit: 'kWh',
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: KpiTile(
                    background: c.pastelGrey,
                    dot: c.sPurchase,
                    label: 'Netzbezug',
                    value: kwh(s.gridPurchaseWh, s.gridPurchaseWh >= 100000 ? 0 : 1),
                    unit: 'kWh',
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: KpiTile(
                    background: c.pastelBlue,
                    dot: c.sFeedIn,
                    label: 'Einspeisung',
                    value: kwh(s.gridFeedInWh, s.gridFeedInWh >= 100000 ? 0 : 1),
                    unit: 'kWh',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
