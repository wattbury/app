import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/tokens.dart';

const double kCardRadius = 22;
const double kChamfer = 26;

/// Rounded card with the cut top-right corner, the signature shape of the design.
class ChamferClipper extends CustomClipper<Path> {
  final double radius, chamfer;
  const ChamferClipper({this.radius = kCardRadius, this.chamfer = kChamfer});

  @override
  Path getClip(Size s) {
    final r = Radius.circular(radius);
    return Path()
      ..moveTo(0, radius)
      ..arcToPoint(Offset(radius, 0), radius: r)
      ..lineTo(s.width - chamfer, 0)
      ..lineTo(s.width, chamfer)
      ..lineTo(s.width, s.height - radius)
      ..arcToPoint(Offset(s.width - radius, s.height), radius: r)
      ..lineTo(radius, s.height)
      ..arcToPoint(Offset(0, s.height - radius), radius: r)
      ..close();
  }

  @override
  bool shouldReclip(ChamferClipper old) => old.radius != radius || old.chamfer != chamfer;
}

/// Full-colour card with white text, a title and a large pale watermark icon bottom right.
class ColorCard extends StatelessWidget {
  final Color color;
  final Color? color2;
  final String title;
  final IconData watermark;
  final Widget child;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool half;

  const ColorCard({
    super.key,
    required this.color,
    required this.title,
    required this.watermark,
    required this.child,
    this.color2,
    this.trailing,
    this.onTap,
    this.half = false,
  });

  @override
  Widget build(BuildContext context) {
    final card = ClipPath(
      clipper: const ChamferClipper(),
      child: Container(
        decoration: BoxDecoration(
          color: color2 == null ? color : null,
          gradient: color2 == null
              ? null
              : LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [color2!, color],
                  stops: const [0, .7],
                ),
        ),
        child: Stack(
          children: [
            Positioned(
              right: half ? -8 : -6,
              bottom: half ? -8 : -10,
              child: Icon(watermark, size: half ? 70 : 92, color: Colors.white.withValues(alpha: .14)),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(half ? 12 : 14, 14, half ? 12 : 14, 14),
              child: DefaultTextStyle.merge(
                style: const TextStyle(color: WbColors.on),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(right: kChamfer),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(title, style: sora(half ? 18 : 19, color: WbColors.on)),
                          ),
                          ?trailing,
                        ],
                      ),
                    ),
                    child,
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
    if (onTap == null) return card;
    return GestureDetector(onTap: onTap, behavior: HitTestBehavior.opaque, child: card);
  }
}

/// White statistics card with the same chamfer.
class WhiteCard extends StatelessWidget {
  final String title;
  final String? trailing;

  /// Widget at the right of the title instead of [trailing], e.g. navigation buttons.
  final Widget? action;
  final Widget child;
  const WhiteCard({super.key, required this.title, required this.child, this.trailing, this.action});

  @override
  Widget build(BuildContext context) {
    final c = context.wb;
    return ClipPath(
      clipper: const ChamferClipper(),
      child: Container(
        color: c.card,
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(right: kChamfer),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Expanded(
                    child: Text(title, style: sora(18, color: c.fg)),
                  ),
                  if (trailing != null) Text(trailing!, style: TextStyle(fontSize: 13, color: c.muted)),
                  ?action,
                ],
              ),
            ),
            child,
          ],
        ),
      ),
    );
  }
}

/// Big number with a small unit, e.g. "3,42 kW".
class BigValue extends StatelessWidget {
  final String value, unit;
  final double size;
  final Color color;
  const BigValue(this.value, this.unit, {super.key, this.size = 36, this.color = WbColors.on});

  @override
  Widget build(BuildContext context) => Text.rich(
    TextSpan(
      children: [
        TextSpan(
          text: value,
          style: sora(size, weight: 500, color: color, letterSpacing: -size * .03, height: 1.05),
        ),
        TextSpan(
          text: ' $unit',
          style: TextStyle(fontSize: size * .45, color: color),
        ),
      ],
    ),
    maxLines: 1,
    softWrap: false,
    overflow: TextOverflow.fade,
  );
}

/// Translucent sub-tile on a colour card with a light accent edge on the left.
class SubTile extends StatelessWidget {
  final IconData? icon;
  final String label, value, unit;
  const SubTile({super.key, this.icon, required this.label, required this.value, required this.unit});

  @override
  Widget build(BuildContext context) {
    final c = context.wb;
    return Container(
      decoration: BoxDecoration(
        color: c.sub,
        borderRadius: BorderRadius.circular(14),
        border: Border(left: BorderSide(color: c.sub2, width: 3)),
      ),
      padding: const EdgeInsets.fromLTRB(11, 8, 10, 8),
      child: Column(
        children: [
          Row(
            children: [
              if (icon != null) ...[Icon(icon, size: 13, color: WbColors.onDim), const SizedBox(width: 5)],
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: WbColors.onDim),
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: value,
                  style: sora(18, color: WbColors.on),
                ),
                TextSpan(
                  text: ' $unit',
                  style: const TextStyle(fontSize: 12, color: WbColors.on),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Thin horizontal bar made of segments; each fraction is drawn in a shade of white.
class Meter extends StatelessWidget {
  final List<double> parts;
  final bool track;
  const Meter(this.parts, {super.key, this.track = true});

  static const _shades = [Colors.white, Color(0x99FFFFFF), Color(0x5CFFFFFF)];

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: SizedBox(
        height: 6,
        child: LayoutBuilder(
          builder: (context, box) {
            final gaps = math.max(0, parts.length - 1) * 2.0;
            return Container(
              color: track ? const Color(0x42FFFFFF) : null,
              child: Row(
                children: [
                  for (var i = 0; i < parts.length; i++) ...[
                    if (i > 0) const SizedBox(width: 2),
                    Container(width: math.max(0, (box.maxWidth - gaps) * parts[i].clamp(0, 1)), color: _shades[i % 3]),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// State of charge as an open ring (270°), value in the middle.
class SocRing extends StatelessWidget {
  final int soc;
  final String? caption;
  const SocRing({super.key, required this.soc, this.caption});

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 104,
    height: 104,
    child: CustomPaint(
      painter: _RingPainter(soc / 100),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '$soc',
                    style: sora(28, color: WbColors.on, letterSpacing: -.8, height: 1),
                  ),
                  const TextSpan(
                    text: '%',
                    style: TextStyle(fontSize: 12, color: WbColors.on),
                  ),
                ],
              ),
            ),
            if (caption != null) Text(caption!, style: const TextStyle(fontSize: 10.5, color: WbColors.onDim)),
          ],
        ),
      ),
    ),
  );
}

class _RingPainter extends CustomPainter {
  final double f;
  _RingPainter(this.f);

  @override
  void paint(Canvas canvas, Size s) {
    final rect = Rect.fromCircle(center: s.center(Offset.zero), radius: 44);
    const start = math.pi * .75, sweep = math.pi * 1.5;
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, start, sweep, false, p..color = Colors.white.withValues(alpha: .22));
    if (f > 0) canvas.drawArc(rect, start, sweep * f.clamp(0, 1), false, p..color = Colors.white);
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.f != f;
}

/// Small coloured KPI tile on a white card: dot, label, value.
class KpiTile extends StatelessWidget {
  final Color background, dot;
  final String label, value, unit;
  const KpiTile({
    super.key,
    required this.background,
    required this.dot,
    required this.label,
    required this.value,
    required this.unit,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.wb;
    return Container(
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(14)),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: c.muted),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 12, top: 2),
            // Large totals shrink instead of wrapping the unit onto a second line.
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: value,
                      style: sora(22, color: c.fg, height: 1.1),
                    ),
                    TextSpan(
                      text: ' $unit',
                      style: TextStyle(fontSize: 12, color: c.muted),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
