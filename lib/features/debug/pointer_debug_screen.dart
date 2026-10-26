import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'pointer_debug_log.dart';
import 'pointer_trace_painter.dart';

/// Developer screen for checking what the pen and fingers report: input
/// kind, pressure (and its range), tilt, hover distance, buttons and the
/// event rate. This is how the owner verifies the Huawei M-Pencil.
class PointerDebugScreen extends StatefulWidget {
  const PointerDebugScreen({super.key});

  static const String routeName = '/pointer-debug';

  /// Pushes the screen; completes when it's closed. `AppRoutes` delegates
  /// here, and Settings calls it directly so the settings screen doesn't
  /// depend on every other screen of the app.
  static Future<void> open(BuildContext context) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => const PointerDebugScreen(),
        settings: const RouteSettings(name: routeName),
      ),
    );
  }

  @override
  State<PointerDebugScreen> createState() => _PointerDebugScreenState();
}

class _PointerDebugScreenState extends State<PointerDebugScreen> {
  final PointerDebugLog _log = PointerDebugLog();

  @override
  void dispose() {
    _log.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pointer test'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TextButton.icon(
              onPressed: _log.clear,
              icon: const Icon(Icons.clear_all_rounded),
              label: const Text('Clear'),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final surface = _TestSurface(log: _log);
            final panel = _InfoPanel(log: _log);
            final sidePanel = constraints.maxWidth > constraints.maxHeight ||
                constraints.maxWidth >= 1000;
            if (sidePanel) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: surface),
                  const VerticalDivider(width: 1),
                  SizedBox(
                    width: math.min(380, constraints.maxWidth * 0.45),
                    child: panel,
                  ),
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: surface),
                const Divider(height: 1),
                SizedBox(
                  height: math.min(460, constraints.maxHeight * 0.45),
                  child: panel,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// The area that records every pointer event (no gesture recognisers, so
/// nothing is swallowed or delayed).
class _TestSurface extends StatelessWidget {
  const _TestSurface({required this.log});

  final PointerDebugLog log;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Listener(
      key: const ValueKey('pointer-test-surface'),
      behavior: HitTestBehavior.opaque,
      onPointerDown: log.record,
      onPointerMove: log.record,
      onPointerUp: log.record,
      onPointerCancel: log.record,
      onPointerHover: log.record,
      child: ClipRect(
        child: CustomPaint(
          painter: PointerTracePainter(log),
          child: ListenableBuilder(
            listenable: log,
            builder: (context, _) => log.summary.eventCount > 0
                ? const SizedBox.expand()
                : Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(
                        'Draw here with the pen, then with a finger.\n'
                        'Try light and hard pressure, tilting the pen, '
                        'hovering just above the screen, and the pen button '
                        'or eraser end if it has one.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

class _InfoPanel extends StatelessWidget {
  const _InfoPanel({required this.log});

  final PointerDebugLog log;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: log,
      builder: (context, _) {
        final summary = log.summary;
        final last = log.last;
        return ListView(
          padding: const EdgeInsets.all(12),
          children: [
            _SummaryCard(summary: summary),
            const SizedBox(height: 12),
            _LastEventCard(sample: last, rateHz: summary.rateHz),
            const SizedBox(height: 12),
            _RecentEventsCard(samples: log.recent.take(12).toList()),
          ],
        );
      },
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.summary});

  final PointerSummary summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = summary;
    final pressure = s.stylusPressure;
    final tilt = s.maxStylusTilt;
    return _PanelCard(
      title: 'Summary',
      children: [
        Text(s.verdict, style: theme.textTheme.bodyMedium),
        const SizedBox(height: 12),
        _CheckRow(
          label: 'Pen reported as stylus',
          state: s.eventCount == 0 ? null : s.stylusSeen,
          detail: s.kindsSeen.isEmpty
              ? 'Not tested yet'
              : 'Seen: ${s.kindsSeen.map((k) => k.name).join(', ')}',
        ),
        _CheckRow(
          label: 'Pressure varies',
          state: s.pressureVaries,
          detail: pressure == null
              ? 'Draw with the pen'
              : '${pressure.min.toStringAsFixed(2)} – '
                  '${pressure.max.toStringAsFixed(2)}',
        ),
        _CheckRow(
          label: 'Eraser end (inverted stylus)',
          state: s.invertedStylusSeen ? true : null,
          detail: s.invertedStylusSeen
              ? 'Seen'
              : 'Not seen (many pens have no eraser end)',
        ),
        _CheckRow(
          label: 'Tilt reported',
          state: tilt == null ? null : s.tiltReported,
          detail: tilt == null ? 'Draw with the pen' : 'Up to ${_deg(tilt)}',
        ),
        _CheckRow(
          label: 'Hover reported',
          state: s.hoverSeen ? true : null,
          detail: s.hoverSeen ? 'Seen' : 'Hold the pen just above the screen',
        ),
      ],
    );
  }
}

/// A ✓ / ✗ / – row. [state] null means "unknown yet".
class _CheckRow extends StatelessWidget {
  const _CheckRow({
    required this.label,
    required this.state,
    required this.detail,
  });

  final String label;
  final bool? state;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final (IconData icon, Color color) = switch (state) {
      true => (Icons.check_circle_rounded, Colors.green.shade600),
      false => (Icons.cancel_rounded, scheme.error),
      null => (Icons.remove_circle_outline_rounded, scheme.outline),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: theme.textTheme.bodyMedium),
                Text(
                  detail,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LastEventCard extends StatelessWidget {
  const _LastEventCard({required this.sample, required this.rateHz});

  final PointerSample? sample;
  final double? rateHz;

  @override
  Widget build(BuildContext context) {
    final s = sample;
    if (s == null) {
      return const _PanelCard(
        title: 'Last event',
        children: [Text('No events yet.')],
      );
    }
    final rows = <(String, String)>[
      ('Event', s.type),
      ('Kind', s.kind.name),
      ('Device', '${s.device}'),
      ('Pressure', s.pressure.toStringAsFixed(3)),
      ('Pressure min / max',
          '${s.pressureMin.toStringAsFixed(2)} / ${s.pressureMax.toStringAsFixed(2)}'),
      ('Tilt', _deg(s.tilt)),
      ('Orientation', _deg(s.orientation)),
      ('Distance',
          '${s.distance.toStringAsFixed(2)} (max ${s.distanceMax.toStringAsFixed(2)})'),
      ('Radius major / minor',
          '${s.radiusMajor.toStringAsFixed(1)} / ${s.radiusMinor.toStringAsFixed(1)}'),
      ('Buttons', describeButtons(s.buttons, s.kind)),
      ('Position',
          '${s.position.dx.toStringAsFixed(1)}, ${s.position.dy.toStringAsFixed(1)}'),
      ('Event rate', rateHz == null ? '–' : '${rateHz!.round()} Hz'),
    ];
    final theme = Theme.of(context);
    return _PanelCard(
      title: 'Last event',
      children: [
        for (final (label, value) in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                Text(
                  value,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _RecentEventsCard extends StatelessWidget {
  const _RecentEventsCard({required this.samples});

  /// Newest first.
  final List<PointerSample> samples;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.bodySmall?.copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return _PanelCard(
      title: 'Recent events',
      children: [
        if (samples.isEmpty) const Text('No events yet.'),
        for (final s in samples)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 1),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    color: colorForPointerKind(s.kind),
                    shape: BoxShape.circle,
                  ),
                ),
                Expanded(
                  child: Text(
                    '${s.type.padRight(6)} ${s.kind.name}  '
                    'p ${s.pressure.toStringAsFixed(2)}  '
                    'tilt ${_deg(s.tilt)}  '
                    'd ${s.distance.toStringAsFixed(1)}  '
                    'btn ${s.buttons}',
                    style: style,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _PanelCard extends StatelessWidget {
  const _PanelCard({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            ...children,
          ],
        ),
      ),
    );
  }
}

String _deg(double radians) => '${(radians * 180 / math.pi).toStringAsFixed(1)}°';

/// Names the pressed buttons, e.g. "0x03 (contact, pen button)".
@visibleForTesting
String describeButtons(int buttons, PointerDeviceKind kind) {
  if (buttons == 0) return '0 (none)';
  final names = <String>[];
  final isPen = kind == PointerDeviceKind.stylus ||
      kind == PointerDeviceKind.invertedStylus;
  final isMouse = kind == PointerDeviceKind.mouse;
  if (buttons & kPrimaryButton != 0) names.add(isMouse ? 'left' : 'contact');
  if (buttons & kSecondaryButton != 0) {
    names.add(isPen ? 'pen button' : (isMouse ? 'right' : 'secondary'));
  }
  if (buttons & kTertiaryButton != 0) {
    names.add(isPen ? 'pen button 2' : (isMouse ? 'middle' : 'tertiary'));
  }
  final known = kPrimaryButton | kSecondaryButton | kTertiaryButton;
  if (buttons & ~known != 0) names.add('other');
  final hex = '0x${buttons.toRadixString(16).padLeft(2, '0')}';
  return '$hex (${names.join(', ')})';
}
