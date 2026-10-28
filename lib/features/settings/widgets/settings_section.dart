import 'package:flutter/material.dart';

/// Widest the settings content grows on a tablet; wider looks sparse.
const double settingsMaxWidth = 760;

/// Centres [child] and limits it to [settingsMaxWidth].
class SettingsWidth extends StatelessWidget {
  const SettingsWidth({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: settingsMaxWidth),
          child: child,
        ),
      );
}

/// A titled group of settings in a rounded card.
class SettingsSection extends StatelessWidget {
  const SettingsSection({
    super.key,
    required this.title,
    required this.icon,
    required this.children,
  });

  final String title;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return SettingsWidth(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
              child: Row(
                children: [
                  Icon(icon, size: 20, color: scheme.primary),
                  const SizedBox(width: 10),
                  Text(
                    title,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(color: scheme.primary),
                  ),
                ],
              ),
            ),
            Card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < children.length; i++) ...[
                    if (i > 0) const Divider(indent: 20, endIndent: 20),
                    children[i],
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A setting with a title, an explanation and a row of mutually exclusive
/// choices (a full-width [SegmentedButton]).
class SettingsChoiceTile<T> extends StatelessWidget {
  const SettingsChoiceTile({
    super.key,
    required this.title,
    required this.value,
    required this.choices,
    required this.onChanged,
    this.subtitle,
    this.enabled = true,
  });

  final String title;
  final String? subtitle;
  final T value;

  /// Value → label, in display order.
  final List<(T, String)> choices;
  final ValueChanged<T> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final titleColor =
        enabled ? scheme.onSurface : scheme.onSurface.withValues(alpha: 0.38);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title,
              style: theme.textTheme.bodyLarge?.copyWith(color: titleColor)),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(
              subtitle!,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
          const SizedBox(height: 12),
          SegmentedButton<T>(
            showSelectedIcon: false,
            segments: [
              for (final (v, label) in choices)
                ButtonSegment<T>(value: v, label: Text(label)),
            ],
            selected: {value},
            onSelectionChanged:
                enabled ? (selection) => onChanged(selection.first) : null,
          ),
        ],
      ),
    );
  }
}

/// A setting picked on a slider: [title] with the current value's [label]
/// on the right, [subtitle] under it. The value is shown while dragging and
/// handed to [onChanged] once, when the drag ends.
class SettingsSliderTile extends StatefulWidget {
  const SettingsSliderTile({
    super.key,
    required this.title,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.label,
    required this.onChanged,
    this.subtitle,
    this.enabled = true,
  });

  final String title;
  final String? subtitle;
  final double value;
  final double min;
  final double max;
  final int divisions;

  /// Text of a value (e.g. `2.5 s`).
  final String Function(double value) label;
  final ValueChanged<double> onChanged;
  final bool enabled;

  @override
  State<SettingsSliderTile> createState() => _SettingsSliderTileState();
}

class _SettingsSliderTileState extends State<SettingsSliderTile> {
  double? _dragging;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final value = (_dragging ?? widget.value).clamp(widget.min, widget.max).toDouble();
    final titleColor =
        widget.enabled ? scheme.onSurface : scheme.onSurface.withValues(alpha: 0.38);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(widget.title,
                    style: theme.textTheme.bodyLarge?.copyWith(color: titleColor)),
              ),
              Text(widget.label(value),
                  style: theme.textTheme.titleSmall?.copyWith(color: titleColor)),
            ],
          ),
          if (widget.subtitle != null) ...[
            const SizedBox(height: 2),
            Text(
              widget.subtitle!,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
          Slider(
            value: value,
            min: widget.min,
            max: widget.max,
            divisions: widget.divisions,
            label: widget.label(value),
            onChanged: widget.enabled ? (v) => setState(() => _dragging = v) : null,
            onChangeEnd: widget.enabled
                ? (v) {
                    setState(() => _dragging = null);
                    widget.onChanged(v);
                  }
                : null,
          ),
        ],
      ),
    );
  }
}
