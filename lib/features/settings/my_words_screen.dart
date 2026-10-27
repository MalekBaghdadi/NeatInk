import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../recognition/htr_channel.dart';
import '../../recognition/user_lexicon.dart';

/// The personal dictionary the handwriting recogniser uses (Settings >
/// My words). Names and unusual words that the recogniser gets wrong live
/// here; it also fills itself from the corrections made in the Convert
/// review sheet.
final myWordsLexiconProvider =
    Provider<UserLexicon>((ref) => HtrRecognizer.instance.userLexicon);

class MyWordsScreen extends ConsumerStatefulWidget {
  const MyWordsScreen({super.key});

  static Future<void> open(BuildContext context) => Navigator.of(context)
      .push(MaterialPageRoute<void>(builder: (_) => const MyWordsScreen()));

  @override
  ConsumerState<MyWordsScreen> createState() => _MyWordsScreenState();
}

class _MyWordsScreenState extends ConsumerState<MyWordsScreen> {
  final _field = TextEditingController();
  bool _loaded = false;
  String? _error;

  UserLexicon get _lexicon => ref.read(myWordsLexiconProvider);

  @override
  void initState() {
    super.initState();
    _lexicon.load().whenComplete(() {
      if (mounted) setState(() => _loaded = true);
    });
  }

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  void _add() {
    final text = _field.text.trim();
    if (text.isEmpty) return;
    // Several names can be typed at once, separated by spaces or commas.
    final changed = _lexicon.learn(text);
    setState(() {
      if (changed == 0) {
        _error = UserLexicon.normalize(text) == null
            ? 'Use letters only (A-Z, a-z).'
            : 'Already in your words.';
      } else {
        _error = null;
        _field.clear();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final words = [..._lexicon.words]
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return Scaffold(
      appBar: AppBar(title: const Text('My words')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Text(
            'Add names and words that your handwriting is hard to read, such '
            'as the names of your family. The recogniser prefers them when '
            'it is unsure. It also learns by itself from the words you '
            'correct when you convert.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  key: const ValueKey('my-words-field'),
                  controller: _field,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.done,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(
                    labelText: 'Add a name or word',
                    errorText: _error,
                    border: const OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _add(),
                ),
              ),
              const SizedBox(width: 12),
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: FilledButton(
                  key: const ValueKey('my-words-add'),
                  onPressed: _add,
                  child: const Text('Add'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (!_loaded)
            const Center(child: CircularProgressIndicator())
          else if (words.isEmpty)
            Padding(
              key: const ValueKey('my-words-empty'),
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text('No words yet.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant)),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final w in words)
                  InputChip(
                    key: ValueKey('my-word-$w'),
                    label: Text(w),
                    onDeleted: () => setState(() => _lexicon.remove(w)),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
