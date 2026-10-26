import 'package:flutter/material.dart';

import '../../data/app_settings.dart';
import '../../data/notification_service.dart';
import '../../data/notifications.dart';
import '../../format.dart';
import '../../theme/tokens.dart';

/// Einstellungen › Benachrichtigungen: the rules with a switch each, an editor and the last alerts.
class RulesSection extends StatelessWidget {
  final AppSettings settings;
  final NotificationService? service;
  const RulesSection({super.key, required this.settings, this.service});

  void _save(List<NotificationRule> rules) => settings.rules = rules;

  Future<void> _edit(BuildContext context, NotificationRule r, {bool isNew = false}) async {
    final result = await showModalBottomSheet<_EditResult>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _RuleEditor(rule: r, isNew: isNew),
    );
    if (result == null) return;
    final rules = [...settings.rules];
    final i = rules.indexWhere((x) => x.id == r.id);
    if (result.delete) {
      if (i >= 0) rules.removeAt(i);
    } else if (i >= 0) {
      rules[i] = result.rule!;
    } else {
      rules.add(result.rule!);
    }
    _save(rules);
  }

  Future<void> _add(BuildContext context) async {
    final kind = await showModalBottomSheet<RuleKind>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (k, label) in const [
              (RuleKind.socBelow, 'Batterie unter …'),
              (RuleKind.socAbove, 'Batterie voll'),
              (RuleKind.purchaseAbove, 'Netzbezug über …'),
              (RuleKind.feedInAbove, 'Einspeisung über …'),
              (RuleKind.offline, 'Anlage nicht erreichbar'),
            ])
              ListTile(title: Text(label), onTap: () => Navigator.pop(context, k)),
          ],
        ),
      ),
    );
    if (kind == null || !context.mounted) return;
    final r = NotificationRule(
      id: '${kind.name}-${DateTime.now().millisecondsSinceEpoch}',
      kind: kind,
      threshold: switch (kind) {
        RuleKind.socBelow => 20,
        RuleKind.socAbove => 100,
        RuleKind.purchaseAbove => 2,
        RuleKind.feedInAbove => 6,
        RuleKind.offline => 0,
      },
      holdFor: kind == RuleKind.offline || kind == RuleKind.purchaseAbove ? const Duration(minutes: 5) : Duration.zero,
    );
    await _edit(context, r, isNew: true);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.wb;
    final rules = settings.rules;
    final last = service?.recent.isNotEmpty ?? false ? service!.recent.first : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final r in rules)
          InkWell(
            onTap: () => _edit(context, r),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(r.title, style: TextStyle(fontSize: 15, color: c.fg)),
                        Text(r.detail, style: TextStyle(fontSize: 12, color: c.muted)),
                      ],
                    ),
                  ),
                  Switch(
                    value: r.enabled,
                    activeTrackColor: c.accent,
                    onChanged: (v) => _save([for (final x in rules) x.id == r.id ? x.copyWith(enabled: v) : x]),
                  ),
                ],
              ),
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => _add(context),
            icon: const Icon(Icons.add),
            label: const Text('Regel hinzufügen'),
          ),
        ),
        if (last != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              'Zuletzt: ${last.title} · ${last.at.hour.toString().padLeft(2, '0')}:${last.at.minute.toString().padLeft(2, '0')}',
              style: TextStyle(fontSize: 12, color: c.fg),
            ),
          ),
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            [
              'Hinweise kommen, solange die App läuft${service?.systemAvailable ?? false ? ', auch als Systembenachrichtigung' : ', als Banner in der App'}.',
              'Im Hintergrund braucht es die Bridge, die später folgt; iOS lässt Apps nicht dauerhaft im Hintergrund abfragen.',
            ].join(' '),
            style: TextStyle(fontSize: 12, color: c.muted),
          ),
        ),
      ],
    );
  }
}

class _EditResult {
  final NotificationRule? rule;
  final bool delete;
  const _EditResult(this.rule, {this.delete = false});
}

class _RuleEditor extends StatefulWidget {
  final NotificationRule rule;
  final bool isNew;
  const _RuleEditor({required this.rule, required this.isNew});

  @override
  State<_RuleEditor> createState() => _RuleEditorState();
}

class _RuleEditorState extends State<_RuleEditor> {
  late NotificationRule r = widget.rule;

  static const _holds = [0, 1, 5, 10, 15, 30, 60];

  bool get _isSoc => r.kind == RuleKind.socBelow || r.kind == RuleKind.socAbove;

  Future<int?> _pickMinute(int initial, String help) async {
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: initial ~/ 60, minute: initial % 60),
      helpText: help,
      builder: (context, child) =>
          MediaQuery(data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true), child: child!),
    );
    return t == null ? null : t.hour * 60 + t.minute;
  }

  String _hm(int m) => '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final c = context.wb;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(r.title, style: sora(18, color: c.fg)),
            const SizedBox(height: 12),
            if (r.kind != RuleKind.offline) ...[
              Text(_isSoc ? 'Schwelle in %' : 'Schwelle in kW', style: TextStyle(fontSize: 13, color: c.muted)),
              Slider(
                value: r.threshold.clamp(_isSoc ? 0 : 0.1, _isSoc ? 100 : 15).toDouble(),
                min: _isSoc ? 0 : 0.1,
                max: _isSoc ? 100 : 15,
                divisions: _isSoc ? 100 : 149,
                label: _isSoc ? '${fmt(r.threshold, 0)} %' : '${fmt(r.threshold, 1)} kW',
                onChanged: (v) =>
                    setState(() => r = r.copyWith(threshold: _isSoc ? v.roundToDouble() : (v * 10).round() / 10)),
              ),
            ],
            Text('Meldet, wenn die Bedingung anhält', style: TextStyle(fontSize: 13, color: c.muted)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final m in _holds)
                  ChoiceChip(
                    label: Text(m == 0 ? 'sofort' : '$m Min.'),
                    selected: r.holdFor.inMinutes == m,
                    onSelected: (_) => setState(() => r = r.copyWith(holdFor: Duration(minutes: m))),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Nur zu bestimmten Zeiten'),
              subtitle: r.hasWindow ? Text('${_hm(r.fromMinute!)}–${_hm(r.toMinute!)} Uhr') : null,
              value: r.hasWindow,
              onChanged: (v) => setState(
                () => r = v ? r.copyWith(fromMinute: 18 * 60, toMinute: 23 * 60) : r.copyWith(clearWindow: true),
              ),
            ),
            if (r.hasWindow)
              Row(
                children: [
                  TextButton(
                    onPressed: () async {
                      final m = await _pickMinute(r.fromMinute!, 'Von');
                      if (m != null) setState(() => r = r.copyWith(fromMinute: m));
                    },
                    child: Text('von ${_hm(r.fromMinute!)}'),
                  ),
                  TextButton(
                    onPressed: () async {
                      final m = await _pickMinute(r.toMinute!, 'Bis');
                      if (m != null) setState(() => r = r.copyWith(toMinute: m));
                    },
                    child: Text('bis ${_hm(r.toMinute!)}'),
                  ),
                ],
              ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Auch über die Bridge senden'),
              subtitle: const Text('Folgt mit der Bridge; dann auch bei geschlossener App'),
              value: r.viaBridge,
              onChanged: null,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                if (!widget.isNew)
                  TextButton(
                    onPressed: () => Navigator.pop(context, const _EditResult(null, delete: true)),
                    style: TextButton.styleFrom(foregroundColor: c.crit),
                    child: const Text('Löschen'),
                  ),
                const Spacer(),
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Abbrechen')),
                FilledButton(
                  onPressed: () => Navigator.pop(context, _EditResult(r)),
                  child: Text(widget.isNew ? 'Hinzufügen' : 'Speichern'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
