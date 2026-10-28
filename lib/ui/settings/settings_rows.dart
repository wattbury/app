import 'package:flutter/material.dart';

import '../../theme/tokens.dart';

/// Rows of the settings page on one grid: label (and caption) on the left, the value right-aligned
/// in the middle, and a fixed slot on the right for a chevron, a status dot or a switch. Every value
/// therefore ends at the same edge, whatever the row holds.
///
/// Rows mix in [SettingsRowLike], so a section can draw dividers between them.
mixin SettingsRowLike on Widget {}

/// Width of the right slot; a switch is wider and takes the value's place instead.
const _slot = 22.0;
const _rowPadding = EdgeInsets.symmetric(vertical: 11);

/// Label with optional caption, used by all row types.
class _Label extends StatelessWidget {
  final String label;
  final String? sub;
  final Color? color;
  const _Label(this.label, this.sub, {this.color});

  @override
  Widget build(BuildContext context) {
    final c = context.wb;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 15, color: color ?? c.fg)),
        if (sub != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(sub!, style: TextStyle(fontSize: 12, color: c.muted)),
          ),
      ],
    );
  }
}

/// Label, value and, when [onTap] is set, a chevron; the whole row is the tap target.
class SettingsRow extends StatelessWidget with SettingsRowLike {
  final String label;
  final String? sub, value;

  /// Replaces the chevron, e.g. a status dot.
  final Widget? indicator;
  final VoidCallback? onTap;
  const SettingsRow({super.key, required this.label, this.sub, this.value, this.indicator, this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.wb;
    final row = Padding(
      padding: _rowPadding,
      child: LayoutBuilder(
        builder: (context, box) => Row(
          children: [
            Expanded(child: _Label(label, sub)),
            if (value != null)
              ConstrainedBox(
                // Long values wrap within half the row instead of squeezing the label.
                constraints: BoxConstraints(maxWidth: box.maxWidth * 0.5),
                child: Padding(
                  padding: const EdgeInsets.only(left: 12),
                  child: Text(
                    value!,
                    textAlign: TextAlign.right,
                    style: TextStyle(fontSize: 14, color: c.muted, fontFeatures: const [FontFeature.tabularFigures()]),
                  ),
                ),
              ),
            SizedBox(
              width: _slot,
              child: Align(
                alignment: Alignment.centerRight,
                child: indicator ?? (onTap != null ? Icon(Icons.chevron_right, size: 20, color: c.muted) : null),
              ),
            ),
          ],
        ),
      ),
    );
    return onTap == null ? row : InkWell(onTap: onTap, child: row);
  }
}

/// Label and a switch at the right edge.
class SettingsSwitchRow extends StatelessWidget with SettingsRowLike {
  final String label;
  final String? sub;
  final bool value;
  final ValueChanged<bool>? onChanged;

  /// Tapping the text (not the switch), e.g. to edit a rule.
  final VoidCallback? onTap;
  const SettingsSwitchRow({
    super.key,
    required this.label,
    this.sub,
    required this.value,
    required this.onChanged,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.wb;
    final row = Padding(
      // The switch is taller than a line of text; less padding keeps the row height of the others.
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: _Label(label, sub)),
          const SizedBox(width: 12),
          Switch(value: value, activeTrackColor: c.accent, onChanged: onChanged),
        ],
      ),
    );
    return onTap == null ? row : InkWell(onTap: onTap, child: row);
  }
}

/// A command as a row: the label in the accent colour, or red for destructive ones.
class SettingsActionRow extends StatelessWidget with SettingsRowLike {
  final String label;
  final String? sub;
  final IconData? icon;
  final bool destructive;
  final VoidCallback? onTap;
  const SettingsActionRow({
    super.key,
    required this.label,
    this.sub,
    this.icon,
    this.destructive = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.wb;
    final color = onTap == null ? c.muted : (destructive ? c.crit : c.accent);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: _rowPadding,
        child: Row(
          children: [
            if (icon != null)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Icon(icon, size: 20, color: color),
              ),
            Expanded(child: _Label(label, sub, color: color)),
          ],
        ),
      ),
    );
  }
}

/// Small explanatory text below the rows of a section.
class SettingsNote extends StatelessWidget {
  final String text;
  final Color? color;
  const SettingsNote(this.text, {super.key, this.color});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 4, bottom: 10),
    child: Text(text, style: TextStyle(fontSize: 12, color: color ?? context.wb.muted)),
  );
}

/// Picks one of [options] in a simple dialog; returns the chosen key or null.
Future<T?> pickOption<T>(BuildContext context, String title, Map<T, String> options, T current) => showDialog<T>(
  context: context,
  builder: (context) => SimpleDialog(
    title: Text(title),
    children: [
      for (final MapEntry(:key, :value) in options.entries)
        ListTile(
          title: Text(value),
          trailing: key == current ? Icon(Icons.check, color: context.wb.accent) : null,
          onTap: () => Navigator.pop(context, key),
        ),
    ],
  ),
);

/// Inserts a divider between neighbouring rows.
List<Widget> withDividers(BuildContext context, List<Widget> children) {
  final out = <Widget>[];
  for (var i = 0; i < children.length; i++) {
    if (i > 0 && children[i] is SettingsRowLike && children[i - 1] is SettingsRowLike) {
      out.add(Divider(height: 1, color: context.wb.sep));
    }
    out.add(children[i]);
  }
  return out;
}
