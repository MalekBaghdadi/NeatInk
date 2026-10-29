import '../editor/integrations/convert/convert_style_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_info.dart';
import '../debug/pointer_debug_screen.dart';
import '../tips/tips_screen.dart';
import 'app_settings.dart';
import 'my_words_screen.dart';
import 'settings_controller.dart';
import 'widgets/backup_settings.dart';
import 'widgets/paper_defaults_editor.dart';
import 'widgets/security_settings.dart';
import 'widgets/diagnostics_tile.dart';
import 'widgets/kept_corrections_settings.dart';
import 'widgets/settings_section.dart';

/// Settings: appearance, writing, new-notebook defaults, export, security,
/// developer tools and about. Every change is saved immediately.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final controller = ref.read(settingsProvider.notifier);
    void change(AppSettings Function(AppSettings) edit) =>
        controller.update(edit);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: SafeArea(
        top: false,
        child: ListView(
          key: const ValueKey('settings-list'),
          padding: const EdgeInsets.symmetric(vertical: 12),
          children: [
            SettingsSection(
              title: 'Appearance',
              icon: Icons.palette_outlined,
              children: [
                SettingsChoiceTile<AppThemeMode>(
                  key: const ValueKey('settings-theme'),
                  title: 'Theme',
                  value: settings.themeMode,
                  choices: const [
                    (AppThemeMode.system, 'System'),
                    (AppThemeMode.light, 'Light'),
                    (AppThemeMode.dark, 'Dark'),
                  ],
                  onChanged: (v) => change((s) => s.copyWith(themeMode: v)),
                ),
              ],
            ),
            SettingsSection(
              title: 'Writing',
              icon: Icons.edit_outlined,
              children: [
                SwitchListTile(
                  key: const ValueKey('settings-shape-snap'),
                  secondary: const Icon(Icons.category_outlined),
                  title: const Text('Hold to snap shapes'),
                  subtitle: const Text(
                      'Hold the pen still at the end of a stroke to turn it '
                      'into a straight line, arrow, rectangle, ellipse or '
                      'triangle.'),
                  value: settings.shapeSnapEnabled,
                  onChanged: (v) =>
                      change((s) => s.copyWith(shapeSnapEnabled: v)),
                ),
                SwitchListTile(
                  key: const ValueKey('settings-tidy-highlighter'),
                  secondary: const Icon(Icons.format_color_fill_outlined),
                  title: const Text('Tidy highlighter'),
                  subtitle: const Text(
                      'A highlight drawn over writing, typed text or a PDF '
                      'becomes a straight band that fits the line.'),
                  value: settings.tidyHighlighter,
                  onChanged: (v) =>
                      change((s) => s.copyWith(tidyHighlighter: v)),
                ),
                SwitchListTile(
                  key: const ValueKey('settings-scribble-delete'),
                  secondary: const Icon(Icons.gesture),
                  title: const Text('Scribble to delete'),
                  subtitle: const Text(
                      'Scribble over handwriting or typed text with the pen '
                      'to delete it.'),
                  value: settings.scribbleToDelete,
                  onChanged: (v) =>
                      change((s) => s.copyWith(scribbleToDelete: v)),
                ),
                SwitchListTile(
                  key: const ValueKey('settings-auto-convert'),
                  secondary: const Icon(Icons.auto_awesome_outlined),
                  title: const Text('Auto-convert handwriting'),
                  subtitle: const Text(
                      'A moment after you lift the pen, your writing turns '
                      'into text by itself.'),
                  value: settings.autoConvert,
                  onChanged: (v) => change((s) => s.copyWith(autoConvert: v)),
                ),
                SettingsSliderTile(
                  key: const ValueKey('settings-auto-convert-delay'),
                  title: 'Wait before converting',
                  subtitle: 'How long auto-convert waits after you lift the '
                      'pen. Longer lets you pause in the middle of a sentence.',
                  value: settings.autoConvertDelayMs / 1000,
                  min: AppSettings.minAutoConvertDelayMs / 1000,
                  max: AppSettings.maxAutoConvertDelayMs / 1000,
                  divisions: (AppSettings.maxAutoConvertDelayMs -
                          AppSettings.minAutoConvertDelayMs) ~/
                      500,
                  label: formatSeconds,
                  enabled: settings.autoConvert,
                  onChanged: (v) => change((s) =>
                      s.copyWith(autoConvertDelayMs: (v * 1000).round())),
                ),
                SwitchListTile(
                  key: const ValueKey('settings-autocorrect'),
                  secondary: const Icon(Icons.auto_fix_high_outlined),
                  title: const Text('Autocorrect'),
                  subtitle: const Text(
                      'Fixes spelling and small grammar slips as handwriting '
                      'becomes text. Corrected words are underlined: tap one '
                      'to get your word back. Off: fixes are only suggested '
                      'in the review sheet.'),
                  value: settings.autocorrect,
                  onChanged: (v) =>
                      change((s) => s.copyWith(autocorrect: v)),
                ),
                ListTile(
                  key: const ValueKey('settings-typed-text'),
                  leading: const Icon(Icons.text_fields),
                  title: const Text('Typed text'),
                  subtitle: const Text(
                      'Font, size and colour of converted handwriting, and '
                      'joining lines into sentences.'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => showConvertStyleSheet(context),
                ),
                ListTile(
                  key: const ValueKey('settings-my-words'),
                  leading: const Icon(Icons.spellcheck_outlined),
                  title: const Text('My words'),
                  subtitle: const Text(
                      'Names and words the handwriting reader should know, '
                      'like your family names.'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => MyWordsScreen.open(context),
                ),
                const KeptCorrectionsSettings(),
                SwitchListTile(
                  key: const ValueKey('settings-search-handwriting'),
                  secondary: const Icon(Icons.manage_search),
                  title: const Text('Search handwriting'),
                  subtitle: const Text(
                      'While a notebook is open and you pause, its handwriting '
                      'is read in the background so search can find it. '
                      'Nothing on the page changes.'),
                  value: settings.searchHandwriting,
                  onChanged: (v) =>
                      change((s) => s.copyWith(searchHandwriting: v)),
                ),
                SwitchListTile(
                  key: const ValueKey('settings-draw-with-finger'),
                  secondary: const Icon(Icons.touch_app_outlined),
                  title: const Text('Draw with finger'),
                  subtitle: const Text(
                      'Off: only the pen writes, and fingers scroll and '
                      'zoom, so a palm resting on the screen never leaves '
                      'marks (palm rejection). Turn on if your pen is not '
                      'recognised as a stylus (check with Developer › '
                      'Pointer test).'),
                  value: settings.drawWithFinger,
                  onChanged: (v) => change((s) => s.copyWith(drawWithFinger: v)),
                ),
                SwitchListTile(
                  key: const ValueKey('settings-pen-button-erases'),
                  secondary: const Icon(Icons.auto_fix_normal_outlined),
                  title: const Text('Pen button erases'),
                  subtitle: const Text(
                      "Erase with the pen's eraser end or side button, if it "
                      'has one.'),
                  value: settings.stylusButtonErases,
                  onChanged: (v) =>
                      change((s) => s.copyWith(stylusButtonErases: v)),
                ),
              ],
            ),
            SettingsSection(
              title: 'New notebooks',
              icon: Icons.note_add_outlined,
              children: [
                PaperDefaultsEditor(
                  key: const ValueKey('settings-default-paper'),
                  paper: settings.defaultPaper,
                  onChanged: (p) => change((s) => s.copyWith(defaultPaper: p)),
                ),
              ],
            ),
            SettingsSection(
              title: 'Export',
              icon: Icons.picture_as_pdf_outlined,
              children: [
                SwitchListTile(
                  key: const ValueKey('settings-export-lines'),
                  secondary: const Icon(Icons.grid_on_outlined),
                  title: const Text('Draw paper lines in exported PDFs'),
                  subtitle: const Text(
                      'Include the lines, grid or dots of your pages. '
                      'Imported PDF pages are always exported as they are.'),
                  value: settings.exportPaperLines,
                  onChanged: (v) =>
                      change((s) => s.copyWith(exportPaperLines: v)),
                ),
              ],
            ),
            const BackupSettings(),
            const SecuritySettings(),
            SettingsSection(
              title: 'Developer',
              icon: Icons.developer_mode_outlined,
              children: [
                ListTile(
                  key: const ValueKey('settings-pointer-test'),
                  leading: const Icon(Icons.gesture_outlined),
                  title: const Text('Pointer test'),
                  subtitle: const Text(
                      'Check that your pen is reported as a stylus, with '
                      'pressure, tilt and hover.'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => PointerDebugScreen.open(context),
                ),
              ],
            ),
            const _AboutSection(),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class _AboutSection extends StatelessWidget {
  const _AboutSection();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SettingsSection(
      title: 'About',
      icon: Icons.info_outline_rounded,
      children: [
        ListTile(
          leading: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.edit_note_rounded,
                color: scheme.onPrimaryContainer),
          ),
          title: const Text(AppInfo.name),
          subtitle: const Text('Version ${AppInfo.displayVersion}'),
        ),
        ListTile(
          key: const ValueKey('settings-tips'),
          leading: const Icon(Icons.lightbulb_outline_rounded),
          title: const Text('Tips'),
          subtitle: const Text('Pen and fingers, typed text, shapes, PDFs and backups.'),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => TipsScreen.open(context),
        ),
        const DiagnosticsTile(),
        const ListTile(
          leading: Icon(Icons.wifi_off_rounded),
          title: Text(AppInfo.offlineStatement),
        ),
        ListTile(
          key: const ValueKey('settings-licenses'),
          leading: const Icon(Icons.description_outlined),
          title: const Text('Open-source licenses'),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => showLicensePage(
            context: context,
            applicationName: AppInfo.name,
            applicationVersion: AppInfo.displayVersion,
            applicationLegalese: AppInfo.legalese,
          ),
        ),
      ],
    );
  }
}

/// `2 s`, `2.5 s`: a delay in seconds as the settings show it.
String formatSeconds(double seconds) {
  final halves = (seconds * 2).round();
  return halves.isEven ? '${halves ~/ 2} s' : '${(halves / 2).toStringAsFixed(1)} s';
}
