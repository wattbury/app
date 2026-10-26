import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:openrscp/openrscp.dart';

import '../../data/app_settings.dart';
import '../../data/live_controller.dart';
import '../../format.dart';
import '../../theme/tokens.dart';
import '../widgets/cards.dart';

/// Energiemonitor: stacked colour cards as in design/clickdummy.html.
class MonitorPage extends StatelessWidget {
  final LiveController live;
  final AppSettings settings;
  const MonitorPage({super.key, required this.live, required this.settings});

  bool get _showWallbox => switch (settings.wallboxMode) {
    WallboxMode.show => true,
    WallboxMode.hide => false,
    WallboxMode.auto => live.wallboxes.isNotEmpty,
  };

  @override
  Widget build(BuildContext context) {
    final s = live.live;
    if (s == null) return _Waiting(live: live);
    final c = context.wb;
    final t = live.today;
    const gap = SizedBox(height: 10);
    return ListView(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 16),
      children: [
        _SolarCard(snapshot: s, today: t, trackers: live.trackers),
        gap,
        _BatteryCard(snapshot: s, today: t),
        gap,
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _GridCard(snapshot: s, today: t),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _HouseCard(snapshot: s, today: t),
              ),
            ],
          ),
        ),
        if (_showWallbox) ...[gap, _WallboxCard(snapshot: s)],
        gap,
        _TodayCard(today: t),
        if (live.system != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              [
                'S10',
                if (live.system!.installedPeakPowerW > 0) '${fmt(live.system!.installedPeakPowerW / 1000, 2)} kWp',
                if (live.system!.swRelease.isNotEmpty) 'Firmware ${live.system!.swRelease}',
              ].join(' · '),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: c.muted),
            ),
          ),
      ],
    );
  }
}

class _Waiting extends StatelessWidget {
  final LiveController live;
  const _Waiting({required this.live});

  @override
  Widget build(BuildContext context) {
    final c = context.wb;
    final failed = live.state == ConnState.offline;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!failed)
              CircularProgressIndicator(color: c.accent)
            else
              Icon(Icons.cloud_off, size: 40, color: c.muted),
            const SizedBox(height: 16),
            Text(failed ? 'Keine Verbindung' : 'Verbinde mit dem Hauskraftwerk …', style: sora(16, color: c.fg)),
            if (failed && live.error != null) ...[
              const SizedBox(height: 8),
              Text(
                live.error!,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: c.muted),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Small uppercase label above a value column.
Widget _eyebrow(String s) => Text(
  s.toUpperCase(),
  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: .9, color: WbColors.onDim),
);

Widget _caption(List<Widget> children) => DefaultTextStyle.merge(
  style: const TextStyle(fontSize: 12, color: WbColors.onDim, fontFeatures: [FontFeature.tabularFigures()]),
  child: Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [for (final w in children) Flexible(child: w)],
  ),
);

TextSpan _b(String s) => TextSpan(
  text: s,
  style: const TextStyle(color: WbColors.on, fontWeight: FontWeight.w600),
);

class _SolarCard extends StatelessWidget {
  final LiveSnapshot snapshot;
  final DbSummary? today;
  final List<PvTracker> trackers;
  const _SolarCard({required this.snapshot, required this.today, required this.trackers});

  @override
  Widget build(BuildContext context) {
    final c = context.wb;
    final now = power(snapshot.solarW);
    final trk = trackers.where((t) => (t.powerW ?? 0) >= 0).toList();
    final sum = trk.fold<double>(0, (a, t) => a + (t.powerW ?? 0));
    // Column structure stays fixed (label, value, bar, caption) so both halves line up.
    Widget col(List<Widget> rows) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        rows[0],
        const SizedBox(height: 4),
        rows[1],
        const SizedBox(height: 10),
        rows[2],
        const SizedBox(height: 4),
        rows[3],
      ],
    );
    return ColorCard(
      color: c.solar,
      color2: c.solar2,
      title: 'Solar',
      watermark: Icons.wb_sunny_outlined,
      child: Padding(
        padding: const EdgeInsets.only(top: 12),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 14),
                  child: col([
                    _eyebrow('Jetzt'),
                    BigValue(now.value, now.unit),
                    Meter(
                      trk.length > 1 && sum > 0
                          ? [for (final t in trk) (t.powerW ?? 0) / sum]
                          : [snapshot.solarW > 0 ? 1 : 0],
                      track: true,
                    ),
                    _caption(
                      trk.length > 1
                          ? [
                              for (final t in trk)
                                Text.rich(
                                  TextSpan(
                                    children: [
                                      TextSpan(text: 'T${t.index + 1} '),
                                      _b(power(t.powerW ?? 0).value),
                                      TextSpan(text: ' ${power(t.powerW ?? 0).unit}'),
                                    ],
                                  ),
                                ),
                            ]
                          : [Text(trk.length == 1 ? '1 Tracker' : '')],
                    ),
                  ]),
                ),
              ),
              Container(width: 1, color: c.sub2),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(left: 14),
                  child: col([
                    _eyebrow('Heute'),
                    BigValue(today == null ? '–' : kwh(today!.solarWh), 'kWh'),
                    const Meter([0]),
                    _caption([const Text('Prognose folgt')]),
                  ]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BatteryCard extends StatelessWidget {
  final LiveSnapshot snapshot;
  final DbSummary? today;
  const _BatteryCard({required this.snapshot, required this.today});

  @override
  Widget build(BuildContext context) {
    final c = context.wb;
    final w = snapshot.batteryW;
    final p = power(w);
    final sign = w > 10 ? '+' : (w < -10 ? '−' : '');
    final state = w > 10
        ? (snapshot.solarW > 0 ? 'Ladung aus Solar' : 'lädt')
        : w < -10
        ? 'Entladung ins Haus'
        : 'Ruhe';
    return ColorCard(
      color: c.battery,
      title: 'Batterie',
      watermark: Icons.battery_5_bar_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 6),
          Row(
            children: [
              SocRing(soc: snapshot.soc),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    BigValue('$sign${p.value}', p.unit, size: 38),
                    Text(state, style: const TextStyle(fontSize: 14, color: WbColors.onDim)),
                    const SizedBox(height: 6),
                    Text(
                      'Autarkie jetzt ${fmt(snapshot.autarkyPct, 0)} %',
                      style: const TextStyle(fontSize: 12.5, color: WbColors.onDim),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: SubTile(
                  icon: Icons.arrow_circle_up_outlined,
                  label: 'Heute geladen',
                  value: today == null ? '–' : kwh(today!.batteryInWh, 2),
                  unit: 'kWh',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SubTile(
                  icon: Icons.arrow_circle_down_outlined,
                  label: 'Heute entladen',
                  value: today == null ? '–' : kwh(today!.batteryOutWh, 2),
                  unit: 'kWh',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// "Heute" sub-tile with two values side by side, used by the grid and house cards.
class _TodayPair extends StatelessWidget {
  final String l1, v1, l2, v2;
  const _TodayPair(this.l1, this.v1, this.l2, this.v2);

  @override
  Widget build(BuildContext context) {
    final c = context.wb;
    Widget cell(String l, String v) => Column(
      children: [
        Text(l, style: const TextStyle(fontSize: 11, color: WbColors.onDim)),
        Text(v, style: sora(17, color: WbColors.on)),
        const Text('kWh', style: TextStyle(fontSize: 11, color: WbColors.on, height: 1)),
      ],
    );
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.fromLTRB(6, 8, 6, 8),
      decoration: BoxDecoration(color: c.sub, borderRadius: BorderRadius.circular(14)),
      child: Column(
        children: [
          const Text(
            'Heute',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: WbColors.on),
          ),
          const SizedBox(height: 4),
          IntrinsicHeight(
            child: Row(
              children: [
                Expanded(child: cell(l1, v1)),
                Container(width: 1, color: Colors.white.withValues(alpha: .3)),
                Expanded(child: cell(l2, v2)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GridCard extends StatelessWidget {
  final LiveSnapshot snapshot;
  final DbSummary? today;
  const _GridCard({required this.snapshot, required this.today});

  @override
  Widget build(BuildContext context) {
    final w = snapshot.gridW;
    final p = power(w);
    return ColorCard(
      color: context.wb.grid,
      title: 'Netz',
      watermark: Icons.electrical_services,
      half: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 10),
          BigValue(p.value, p.unit, size: 34),
          Text(
            w > 10 ? 'Bezug' : (w < -10 ? 'Einspeisung' : 'ausgeglichen'),
            style: const TextStyle(fontSize: 14, color: WbColors.onDim),
          ),
          _TodayPair(
            'Bezug',
            today == null ? '–' : kwh(today!.gridPurchaseWh, 2),
            'Einspeisung',
            today == null ? '–' : kwh(today!.gridFeedInWh, 2),
          ),
        ],
      ),
    );
  }
}

class _HouseCard extends StatelessWidget {
  final LiveSnapshot snapshot;
  final DbSummary? today;
  const _HouseCard({required this.snapshot, required this.today});

  @override
  Widget build(BuildContext context) {
    final p = power(snapshot.houseW);
    final t = today;
    // Solar used directly = production minus what went into the battery or the grid.
    final direct = t == null ? null : math.max(0.0, t.solarWh - t.batteryInWh - t.gridFeedInWh);
    return ColorCard(
      color: context.wb.house,
      title: 'Haus',
      watermark: Icons.home_outlined,
      half: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 10),
          BigValue(p.value, p.unit, size: 34),
          const Text('Verbrauch', style: TextStyle(fontSize: 14, color: WbColors.onDim)),
          _TodayPair('Direkt', direct == null ? '–' : kwh(direct, 2), 'Gesamt', t == null ? '–' : kwh(t.houseWh, 2)),
        ],
      ),
    );
  }
}

class _WallboxCard extends StatelessWidget {
  final LiveSnapshot snapshot;
  const _WallboxCard({required this.snapshot});

  @override
  Widget build(BuildContext context) {
    final p = power(snapshot.wallboxW);
    final share = snapshot.wallboxW > 0 ? snapshot.wallboxSolarW / snapshot.wallboxW * 100 : null;
    return ColorCard(
      color: context.wb.wallbox,
      title: 'Wallbox',
      watermark: Icons.ev_station_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 4),
          BigValue(p.value, p.unit),
          Text(
            share == null ? 'lädt nicht' : 'lädt · ${fmt(share, 0)} % Solar',
            style: const TextStyle(fontSize: 14, color: WbColors.onDim),
          ),
        ],
      ),
    );
  }
}

class _TodayCard extends StatelessWidget {
  final DbSummary? today;
  const _TodayCard({required this.today});

  @override
  Widget build(BuildContext context) {
    final c = context.wb;
    final t = today;
    return WhiteCard(
      title: 'Heute',
      trailing: DateFormat('EEE, d. MMM', 'de_DE').format(DateTime.now()),
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
                    value: t == null ? '–' : fmt(t.autarkyPct),
                    unit: '%',
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: KpiTile(
                    background: c.pastelYellow,
                    dot: c.solar,
                    label: 'Eigenverbrauch',
                    value: t == null ? '–' : fmt(t.consumedProductionPct),
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
                    dot: c.solar,
                    label: 'Solar',
                    value: t == null ? '–' : kwh(t.solarWh),
                    unit: 'kWh',
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: KpiTile(
                    background: c.pastelGrey,
                    dot: c.grid,
                    label: 'Bezug',
                    value: t == null ? '–' : kwh(t.gridPurchaseWh),
                    unit: 'kWh',
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: KpiTile(
                    background: c.pastelBlue,
                    dot: c.grid,
                    label: 'Einspeisung',
                    value: t == null ? '–' : kwh(t.gridFeedInWh),
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
