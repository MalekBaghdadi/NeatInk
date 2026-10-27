import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../lock/auto_lock_suspension.dart';

/// Hands a handwriting samples file to the system share sheet, behind an
/// interface so the review sheet can be tested with a fake.
abstract interface class SampleShareService {
  /// Writes [json] to a file called [fileName] in the app cache and opens
  /// the share sheet for it. False when the user dismissed the sheet.
  Future<bool> share({required String fileName, required String json});
}

/// Writes into `<cache>/samples/` and shares with share_plus, exactly like the
/// PDF export does. No storage or network permission is involved, and the
/// user picks where the file goes.
class DefaultSampleShareService implements SampleShareService {
  const DefaultSampleShareService();

  @override
  Future<bool> share({required String fileName, required String json}) async {
    final dir =
        Directory(p.join((await getTemporaryDirectory()).path, 'samples'));
    await dir.create(recursive: true);
    await _deleteStale(dir);
    final file = File(p.join(dir.path, fileName));
    await file.writeAsString(json, flush: true);
    // The share sheet sends the app to the background; keep the app lock
    // from engaging while the user is in it.
    final result = await AutoLockSuspension.during(
      () => SharePlus.instance.share(ShareParams(
        files: [XFile(file.path, mimeType: 'application/json')],
        subject: "Mariam's Notes handwriting samples",
        title: "Mariam's Notes handwriting samples",
      )),
    );
    return result.status != ShareResultStatus.dismissed;
  }

  /// Removes sample files more than a day old (the receiving app has copied
  /// the file long before). Never throws.
  static Future<void> _deleteStale(Directory dir) async {
    try {
      final cutoff = DateTime.now().subtract(const Duration(days: 1));
      for (final entity in dir.listSync()) {
        if (entity is File && entity.lastModifiedSync().isBefore(cutoff)) {
          entity.deleteSync();
        }
      }
    } catch (e) {
      debugPrint('NeatInk: cleaning old sample files failed: $e');
    }
  }
}

/// The service the review sheet shares samples with. Tests override it.
final sampleShareServiceProvider = Provider<SampleShareService>(
    (ref) => const DefaultSampleShareService());
