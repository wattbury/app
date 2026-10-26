import 'package:openrscp/openrscp.dart';

import '../format.dart';

/// What a rule watches.
enum RuleKind {
  /// State of charge below [NotificationRule.threshold] percent.
  socBelow,

  /// Battery full (state of charge at or above [NotificationRule.threshold] percent).
  socAbove,

  /// Grid purchase above [NotificationRule.threshold] kW.
  purchaseAbove,

  /// Feed-in above [NotificationRule.threshold] kW, e.g. near a feed-in limit.
  feedInAbove,

  /// No connection to the unit.
  offline,
}

/// One notification rule: a condition, how long it must hold, and when it may speak.
class NotificationRule {
  final String id;
  final RuleKind kind;
  final bool enabled;

  /// Percent for the battery rules, kW for the power rules; unused for [RuleKind.offline].
  final double threshold;

  /// The condition must hold this long before the rule fires.
  final Duration holdFor;

  /// Optional window of the day in minutes since midnight; may wrap past midnight (22:00–06:00).
  final int? fromMinute, toMinute;

  /// Prepared for the bridge, which can send while the app is closed. Unused until a bridge exists.
  final bool viaBridge;

  const NotificationRule({
    required this.id,
    required this.kind,
    this.enabled = true,
    this.threshold = 0,
    this.holdFor = Duration.zero,
    this.fromMinute,
    this.toMinute,
    this.viaBridge = false,
  });

  /// Sensible starting points, also used for a fresh install.
  static List<NotificationRule> defaults() => const [
    NotificationRule(id: 'soc-low', kind: RuleKind.socBelow, threshold: 10, fromMinute: 18 * 60, toMinute: 23 * 60),
    NotificationRule(
      id: 'purchase-high',
      kind: RuleKind.purchaseAbove,
      enabled: false,
      threshold: 2,
      holdFor: Duration(minutes: 10),
    ),
    NotificationRule(id: 'offline', kind: RuleKind.offline, holdFor: Duration(minutes: 5)),
  ];

  bool get hasWindow => fromMinute != null && toMinute != null;

  bool inWindow(DateTime t) {
    if (!hasWindow) return true;
    final m = t.hour * 60 + t.minute;
    return fromMinute! <= toMinute! ? m >= fromMinute! && m < toMinute! : m >= fromMinute! || m < toMinute!;
  }

  /// Short title, e.g. "Batterie unter 10 %".
  String get title => switch (kind) {
    RuleKind.socBelow => 'Batterie unter ${fmt(threshold, 0)} %',
    RuleKind.socAbove => 'Batterie voll (ab ${fmt(threshold, 0)} %)',
    RuleKind.purchaseAbove => 'Netzbezug über ${fmt(threshold, 1)} kW',
    RuleKind.feedInAbove => 'Einspeisung über ${fmt(threshold, 1)} kW',
    RuleKind.offline => 'Anlage nicht erreichbar',
  };

  /// One line under the title: duration and window.
  String get detail {
    String hm(int m) => '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';
    final parts = [
      if (holdFor > Duration.zero) 'länger als ${holdFor.inMinutes} Min.',
      if (hasWindow) 'nur ${hm(fromMinute!)}–${hm(toMinute!)}',
    ];
    return parts.isEmpty ? 'sofort, rund um die Uhr' : parts.join(' · ');
  }

  NotificationRule copyWith({
    bool? enabled,
    double? threshold,
    Duration? holdFor,
    int? fromMinute,
    int? toMinute,
    bool clearWindow = false,
    bool? viaBridge,
  }) => NotificationRule(
    id: id,
    kind: kind,
    enabled: enabled ?? this.enabled,
    threshold: threshold ?? this.threshold,
    holdFor: holdFor ?? this.holdFor,
    fromMinute: clearWindow ? null : (fromMinute ?? this.fromMinute),
    toMinute: clearWindow ? null : (toMinute ?? this.toMinute),
    viaBridge: viaBridge ?? this.viaBridge,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'kind': kind.name,
    'enabled': enabled,
    'threshold': threshold,
    'holdSec': holdFor.inSeconds,
    'from': fromMinute,
    'to': toMinute,
    'bridge': viaBridge,
  };

  static NotificationRule fromJson(Map<String, dynamic> j) => NotificationRule(
    id: j['id'] as String,
    kind: RuleKind.values.byName(j['kind'] as String),
    enabled: j['enabled'] as bool? ?? true,
    threshold: (j['threshold'] as num?)?.toDouble() ?? 0,
    holdFor: Duration(seconds: (j['holdSec'] as num?)?.toInt() ?? 0),
    fromMinute: (j['from'] as num?)?.toInt(),
    toMinute: (j['to'] as num?)?.toInt(),
    viaBridge: j['bridge'] as bool? ?? false,
  );
}

/// A message to show, produced by [RuleEngine].
class Alert {
  final String ruleId, title, body;
  final DateTime at;
  const Alert({required this.ruleId, required this.title, required this.body, required this.at});
}

/// Evaluates rules on every poll. A rule fires once when its condition has held for its duration
/// inside its window, and arms again only after the condition has cleared with some margin, so a
/// value hovering around the threshold does not produce a stream of messages.
class RuleEngine {
  final _since = <String, DateTime>{};
  final _fired = <String>{};

  /// Margin before a fired rule re-arms: 2 percentage points or 0.2 kW past the threshold.
  static const _socMargin = 2.0, _kwMargin = 0.2;

  List<Alert> evaluate(
    List<NotificationRule> rules, {
    required LiveSnapshot? live,
    required bool online,
    required DateTime now,
  }) {
    final out = <Alert>[];
    for (final r in rules) {
      if (!r.enabled) {
        _since.remove(r.id);
        _fired.remove(r.id);
        continue;
      }
      final (holds, cleared, body) = _check(r, live, online);
      if (cleared) {
        _since.remove(r.id);
        _fired.remove(r.id);
        continue;
      }
      if (!holds) {
        _since.remove(r.id);
        continue;
      }
      final since = _since.putIfAbsent(r.id, () => now);
      if (_fired.contains(r.id) || now.difference(since) < r.holdFor || !r.inWindow(now)) continue;
      _fired.add(r.id);
      out.add(Alert(ruleId: r.id, title: r.title, body: body, at: now));
    }
    return out;
  }

  /// Whether the condition holds, whether it has cleared past the margin, and the message text.
  (bool, bool, String) _check(NotificationRule r, LiveSnapshot? s, bool online) {
    if (r.kind == RuleKind.offline) {
      return (!online, online, 'Keine Verbindung zum Hauskraftwerk.');
    }
    if (s == null || !online) return (false, false, '');
    final kwPurchase = s.gridW > 0 ? s.gridW / 1000 : 0.0, kwFeed = s.gridW < 0 ? -s.gridW / 1000 : 0.0;
    return switch (r.kind) {
      RuleKind.socBelow => (s.soc < r.threshold, s.soc >= r.threshold + _socMargin, 'Ladestand ${s.soc} %.'),
      RuleKind.socAbove => (s.soc >= r.threshold, s.soc < r.threshold - _socMargin, 'Ladestand ${s.soc} %.'),
      RuleKind.purchaseAbove => (
        kwPurchase > r.threshold,
        kwPurchase <= r.threshold - _kwMargin,
        'Das Haus bezieht ${fmt(kwPurchase, 2)} kW aus dem Netz.',
      ),
      RuleKind.feedInAbove => (
        kwFeed > r.threshold,
        kwFeed <= r.threshold - _kwMargin,
        'Einspeisung ${fmt(kwFeed, 2)} kW.',
      ),
      RuleKind.offline => (false, false, ''),
    };
  }
}
