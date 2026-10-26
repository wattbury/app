import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:openrscp/openrscp.dart';

import '../../data/app_settings.dart';
import '../../data/live_controller.dart';
import '../../format.dart';
import '../../theme/tokens.dart';
import '../widgets/cards.dart';

/// Energiefluss (decided 24.10.2026, variant 3): the home power station as hub, solar on top, battery
/// below, grid left, house right, wallbox bottom right when present. One value and one direction per
/// line, shown by chevrons in the participant's colour; idle lines stay as a grey track.
class FlowPage extends StatelessWidget {
  final LiveController live;
  final AppSettings settings;
  const FlowPage({super.key, required this.live, required this.settings});

  bool get _showWallbox => switch (settings.wallboxMode) {
    WallboxMode.show => true,
    WallboxMode.hide => false,
    WallboxMode.auto => live.wallboxes.isNotEmpty,
  };

  @override
  Widget build(BuildContext context) {
    final s = live.live;
    final c = context.wb;
    if (s == null) {
      return Center(child: CircularProgressIndicator(color: c.accent));
    }
    final surplus = s.gridW < -10;
    return ListView(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 16),
      children: [
        WhiteCard(
          title: 'Jetzt',
          trailing: surplus ? 'Überschuss' : (s.gridW > 10 ? 'Netzbezug' : null),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(_sentence(s), style: TextStyle(fontSize: 12, color: c.muted)),
              ),
              const SizedBox(height: 8),
              _Hub(snapshot: s, showWallbox: _showWallbox, trackers: live.trackers.length),
            ],
          ),
        ),
        const SizedBox(height: 10),
        WhiteCard(
          title: 'Heute',
          trailing: 'seit 00:00 · kWh',
          child: live.today == null
              ? Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text('Tageswerte werden geladen …', style: TextStyle(fontSize: 13, color: c.muted)),
                )
              : _Ledger(today: live.today!),
        ),
      ],
    );
  }

  static String _sentence(LiveSnapshot s) {
    String p(int w) => '${power(w).value} ${power(w).unit}';
    final parts = <String>[];
    if (s.solarW > 10) {
      parts.add('Die Sonne liefert ${p(s.solarW)}.');
    } else {
      parts.add('Gerade kommt kein Solarstrom.');
    }
    if (s.batteryW > 10) parts.add('Die Batterie lädt mit ${p(s.batteryW)}.');
    if (s.batteryW < -10) parts.add('Die Batterie gibt ${p(-s.batteryW)} ab.');
    if (s.gridW < -10) parts.add('${p(-s.gridW)} gehen ins Netz.');
    if (s.gridW > 10) parts.add('${p(s.gridW)} kommen aus dem Netz.');
    return parts.join(' ');
  }
}

/// Positions in a 360 × 332 box, as in design/clickdummy.html.
class _Arm {
  final List<Offset> pts;
  final double kw;
  final Color color;
  const _Arm(this.pts, this.kw, this.color);
}

class _Hub extends StatefulWidget {
  final LiveSnapshot snapshot;
  final bool showWallbox;
  final int trackers;
  const _Hub({required this.snapshot, required this.showWallbox, required this.trackers});

  @override
  State<_Hub> createState() => _HubState();
}

class _HubState extends State<_Hub> with SingleTickerProviderStateMixin {
  late final AnimationController _anim = AnimationController(vsync: this, duration: const Duration(seconds: 60))
    ..repeat();

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.wb;
    final s = widget.snapshot;
    final still = MediaQuery.of(context).disableAnimations;
    final nodes = <String, _Node>{
      'solar': _Node(
        'Solar',
        Icons.wb_sunny_outlined,
        s.solarW,
        s.solarW > 10 ? (widget.trackers > 1 ? '${widget.trackers} Tracker' : 'erzeugt') : 'keine Sonne',
        c.solar,
        const Offset(180, 44),
      ),
      'netz': _Node(
        'Netz',
        Icons.electrical_services,
        s.gridW,
        s.gridW < -10 ? 'Einspeisung' : (s.gridW > 10 ? 'Bezug' : 'ausgeglichen'),
        c.grid,
        const Offset(52, 166),
      ),
      'haus': _Node('Haus', Icons.home_outlined, s.houseW, 'Verbrauch', c.house, const Offset(308, 166)),
      'batt': _Node(
        'Batterie',
        Icons.battery_5_bar_outlined,
        s.batteryW,
        '${s.batteryW > 10 ? 'lädt' : (s.batteryW < -10 ? 'entlädt' : 'Ruhe')} · ${s.soc} %',
        c.battery,
        const Offset(180, 288),
      ),
      if (widget.showWallbox)
        'wb': _Node(
          'Wallbox',
          Icons.ev_station_outlined,
          s.wallboxW,
          s.wallboxW > 10 ? 'lädt' : 'bereit',
          c.wallbox,
          const Offset(308, 288),
        ),
    };
    // Base direction: solar and grid towards the hub, the others away from it; a negative value flips it.
    final arms = <_Arm>[
      _Arm(const [Offset(180, 75), Offset(180, 136)], s.solarW / 1000, c.solar),
      _Arm(const [Offset(98, 166), Offset(150, 166)], s.gridW / 1000, c.grid),
      _Arm(const [Offset(180, 196), Offset(180, 257)], s.batteryW / 1000, c.battery),
      _Arm(const [Offset(210, 166), Offset(262, 166)], s.houseW / 1000, c.house),
      if (widget.showWallbox) _Arm(_bezier(), s.wallboxW / 1000, c.wallbox),
    ];
    final label =
        'Energiefluss jetzt: ${nodes.values.map((n) => '${n.title} ${power(n.w).value} ${power(n.w).unit} ${n.sub}').join(', ')}';
    return Semantics(
      label: label,
      child: AspectRatio(
        aspectRatio: 360 / 332,
        child: AnimatedBuilder(
          animation: _anim,
          builder: (context, _) => CustomPaint(
            painter: _HubPainter(
              nodes: nodes.values.toList(),
              arms: arms,
              seconds: still ? null : _anim.value * 60,
              track: c.fg.withValues(alpha: .09),
              hubColor: c.info,
              base: DefaultTextStyle.of(context).style,
            ),
          ),
        ),
      ),
    );
  }

  static List<Offset> _bezier() {
    const p0 = Offset(201, 187), p1 = Offset(230, 216), p2 = Offset(232, 288), p3 = Offset(262, 288);
    return [
      for (var i = 0; i <= 40; i++)
        () {
          final t = i / 40, u = 1 - t;
          return p0 * (u * u * u) + p1 * (3 * u * u * t) + p2 * (3 * u * t * t) + p3 * (t * t * t);
        }(),
    ];
  }
}

class _Node {
  final String title, sub;
  final IconData icon;
  final int w;
  final Color color;
  final Offset at;
  const _Node(this.title, this.icon, this.w, this.sub, this.color, this.at);
}

class _HubPainter extends CustomPainter {
  final List<_Node> nodes;
  final List<_Arm> arms;

  /// Animation clock in seconds; null draws the chevrons at rest (reduced motion).
  final double? seconds;
  final Color track, hubColor;

  /// Body text style of the app, so labels inside the canvas use the same font as the rest.
  final TextStyle base;
  _HubPainter({
    required this.base,
    required this.nodes,
    required this.arms,
    required this.seconds,
    required this.track,
    required this.hubColor,
  });

  static const _nodeW = 92.0, _nodeH = 62.0, _spacing = 15.0;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 360);
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 10;
    for (final a in arms) {
      final path = Path()..addPolygon(a.pts, false);
      canvas.drawPath(path, line..color = track);
      if (a.kw.abs() > .01) canvas.drawPath(path, line..color = a.color.withValues(alpha: .22));
    }
    for (final a in arms) {
      if (a.kw.abs() > .01) _chevrons(canvas, a);
    }
    for (final n in nodes) {
      _node(canvas, n);
    }
    const hub = Offset(180, 166);
    canvas.drawCircle(hub, 30, Paint()..color = hubColor);
    canvas.drawCircle(
      hub,
      25,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = Colors.white.withValues(alpha: .25),
    );
    _text(canvas, 'S10', sora(13, color: Colors.white), hub, center: true);
  }

  void _chevrons(Canvas canvas, _Arm a) {
    final pts = a.kw < 0 ? a.pts.reversed.toList() : a.pts;
    final dist = <double>[0];
    for (var i = 1; i < pts.length; i++) {
      dist.add(dist.last + (pts[i] - pts[i - 1]).distance);
    }
    final total = dist.last;
    final speed = math.min(70.0, 18 + a.kw.abs() * 12);
    final off = seconds == null ? _spacing / 2 : (seconds! * speed) % _spacing;
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    for (var d = off; d <= total; d += _spacing) {
      var i = 1;
      while (i < dist.length - 1 && dist[i] < d) {
        i++;
      }
      final f = (d - dist[i - 1]) / ((dist[i] - dist[i - 1]).abs() < 1e-9 ? 1 : dist[i] - dist[i - 1]);
      final pos = Offset.lerp(pts[i - 1], pts[i], f)!;
      final dir = pts[i] - pts[i - 1];
      final fade = (math.min(d, total - d) / 8).clamp(0.0, 1.0);
      canvas.save();
      canvas.translate(pos.dx, pos.dy);
      canvas.rotate(math.atan2(dir.dy, dir.dx));
      canvas.drawPath(
        Path()
          ..moveTo(-2.5, -3.6)
          ..lineTo(1.8, 0)
          ..lineTo(-2.5, 3.6),
        p..color = a.color.withValues(alpha: fade),
      );
      canvas.restore();
    }
  }

  void _node(Canvas canvas, _Node n) {
    final r = Rect.fromCenter(center: n.at, width: _nodeW, height: _nodeH);
    canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(16)), Paint()..color = n.color);
    _text(
      canvas,
      String.fromCharCode(n.icon.codePoint),
      TextStyle(fontFamily: n.icon.fontFamily, package: n.icon.fontPackage, fontSize: 14, color: Colors.white),
      r.topLeft + const Offset(9, 8),
    );
    _text(canvas, n.title, const TextStyle(fontSize: 10.5, color: Color(0xD9FFFFFF)), r.topLeft + const Offset(27, 9));
    final p = power(n.w);
    _rich(canvas, [
      TextSpan(
        text: p.value,
        style: sora(17, color: Colors.white),
      ),
      TextSpan(
        text: ' ${p.unit}',
        style: sora(10, weight: 500, color: Colors.white),
      ),
    ], r.topLeft + const Offset(10, 25));
    _text(
      canvas,
      n.sub,
      const TextStyle(fontSize: 9.5, color: Color(0xCCFFFFFF)),
      r.topLeft + const Offset(10, 45),
      maxWidth: _nodeW - 14,
    );
  }

  void _text(Canvas canvas, String s, TextStyle style, Offset at, {bool center = false, double? maxWidth}) => _rich(
    canvas,
    [TextSpan(text: s, style: style)],
    at,
    center: center,
    maxWidth: maxWidth,
  );

  void _rich(Canvas canvas, List<TextSpan> spans, Offset at, {bool center = false, double? maxWidth}) {
    final tp = TextPainter(
      text: TextSpan(style: base, children: spans),
      textDirection: ui.TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: maxWidth ?? 200);
    tp.paint(canvas, center ? at - Offset(tp.width / 2, tp.height / 2) : at);
  }

  @override
  bool shouldRepaint(_HubPainter old) => true;
}

/// Two balance bars for today: where the solar energy went and where the consumption came from.
class _Ledger extends StatelessWidget {
  final DbSummary today;
  const _Ledger({required this.today});

  @override
  Widget build(BuildContext context) {
    final c = context.wb;
    final t = today;
    final direct = math.max(0.0, t.solarWh - t.batteryInWh - t.gridFeedInWh);
    Widget bar(String title, double totalWh, String dir, List<(String, double, Color)> parts) {
      final sum = parts.fold<double>(0, (a, p) => a + p.$2);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text('$title ${kwh(totalWh)} kWh', style: sora(14, color: c.fg)),
              const Spacer(),
              Text(dir, style: TextStyle(fontSize: 12, color: c.muted)),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(7),
            child: SizedBox(
              height: 14,
              child: Row(
                children: [
                  for (final (i, p) in parts.indexed)
                    if (p.$2 > 0)
                      Flexible(
                        flex: math.max(1, (p.$2 / (sum == 0 ? 1 : sum) * 1000).round()),
                        child: Container(
                          margin: EdgeInsets.only(left: i == 0 ? 0 : 2),
                          color: p.$3,
                        ),
                      ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 12,
            runSpacing: 3,
            children: [
              for (final p in parts)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(color: p.$3, borderRadius: BorderRadius.circular(3)),
                    ),
                    const SizedBox(width: 5),
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(text: '${p.$1} '),
                          TextSpan(
                            text: kwh(p.$2),
                            style: TextStyle(color: c.fg, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                      style: TextStyle(fontSize: 12, color: c.muted),
                    ),
                  ],
                ),
            ],
          ),
        ],
      );
    }

    Widget row(String l, String v) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        children: [
          Expanded(
            child: Text(l, style: TextStyle(fontSize: 15, color: c.fg)),
          ),
          Text(
            v,
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.fg),
          ),
        ],
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          bar('Solar', t.solarWh, 'wohin die Sonne ging', [
            ('Haus', direct, c.house),
            ('Batterie', t.batteryInWh, c.battery),
            ('Netz', t.gridFeedInWh, c.grid),
          ]),
          const SizedBox(height: 12),
          bar('Haus', t.houseWh, 'woher der Verbrauch kam', [
            ('Solar', direct, c.solar),
            ('Batterie', t.batteryOutWh, c.battery),
            ('Netz', t.gridPurchaseWh, c.grid),
          ]),
          const SizedBox(height: 4),
          row('Autarkie', '${fmt(t.autarkyPct)} %'),
          Divider(height: 1, color: c.sep),
          row('Eigenverbrauch', '${fmt(t.consumedProductionPct)} %'),
        ],
      ),
    );
  }
}
