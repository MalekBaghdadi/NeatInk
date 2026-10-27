import '../../../../beautify/tidy_config.dart';
import '../../../settings/app_settings.dart';
import '../../../settings/settings_controller.dart';
import '../../editor_integrations.dart';
import 'tidy_session.dart';

export 'tidy_session.dart' show TidySession, tidyPipelineVersion;

/// "Tidy as you write" (docs/beautify-spec.md): about half a second after a
/// word is finished it is gently straightened, put on the line and evened
/// out, with a 180 ms animation and one undo step ("Tidy"). Undo restores the
/// handwriting as written and locks the word against being tidied again.
///
/// Controlled by the app settings (on/off toggle in the tool row, strength,
/// slant mode, debug overlay).
final EditorIntegration tidyIntegration = createTidyIntegration();

/// [tidyIntegration] with injectable pieces, for tests: the monotonic clock
/// (milliseconds), the tuning constants and the reduce-motion check.
EditorIntegration createTidyIntegration({
  TidyConfig config = const TidyConfig(),
  int Function()? nowMs,
  bool Function()? reduceMotion,
}) {
  return (controller, ref) {
    final watch = Stopwatch()..start();
    final session = TidySession(
      controller: controller,
      readSettings: () => ref.read(settingsProvider),
      nowMs: nowMs ?? () => watch.elapsedMilliseconds,
      config: config,
      reduceMotion: reduceMotion,
    );
    final subscription = ref.listenManual<AppSettings>(
      settingsProvider,
      (previous, next) => session.onSettingsChanged(previous, next),
    );
    session.install();
    controller.addDisposeCallback(() {
      subscription.close();
      session.dispose();
    });
  };
}
