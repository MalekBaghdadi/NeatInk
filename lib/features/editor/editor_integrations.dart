import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'editor_controller.dart';

/// Plugs a feature into the editor core (eraser, lasso, text boxes,
/// images, shapes, page navigator, tidy, PDF backgrounds and export).
///
/// It runs once per editor screen, right after the [EditorController] is
/// created and before the notebook is loaded, so the document isn't
/// available yet: register handlers, layers, overlays, hooks and actions on
/// `controller.extensions`, subscribe to `controller.strokeEvents`, and
/// read the document later (e.g. in handlers, or by listening to the
/// controller until `controller.isReady`). Release subscriptions and timers
/// with `controller.addDisposeCallback`; tool handlers are disposed by the
/// controller.
typedef EditorIntegration = void Function(
    EditorController controller, WidgetRef ref);

/// The integrations installed into every editor, in order.
///
/// The editor core needs none, so the list starts empty; each feature adds
/// its [EditorIntegration] here. Tests override this provider to install
/// fakes.
final editorIntegrationsProvider =
    Provider<List<EditorIntegration>>((ref) => const []);
