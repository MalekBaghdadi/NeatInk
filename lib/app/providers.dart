import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../storage/notebook_repository.dart';

/// App-wide singletons. They are created in `main()` before `runApp` and
/// injected with `ProviderScope(overrides: [...])`; tests override them with
/// fakes.

final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('Override in main()'),
);

final notebookRepositoryProvider = Provider<NotebookRepository>(
  (ref) => throw UnimplementedError('Override in main()'),
);

/// Wall clock. Used by time-based logic (app-lock timeout, PIN cooldowns) so
/// tests can override it with a fake clock.
final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);
