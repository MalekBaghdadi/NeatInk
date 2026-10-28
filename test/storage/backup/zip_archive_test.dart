import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:neatink/storage/backup/zip_archive.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('zip_test_');
  });

  tearDown(() async {
    await tmp.delete(recursive: true);
  });

  Uint8List randomBytes(int n, [int seed = 1]) {
    final r = Random(seed);
    return Uint8List.fromList(List.generate(n, (_) => r.nextInt(256)));
  }

  test('CRC-32 matches the standard check value', () {
    expect(Crc32.of(utf8.encode('123456789')), 0xCBF43926);
    final c = Crc32()
      ..add(utf8.encode('12345'))
      ..add(utf8.encode('6789'));
    expect(c.value, 0xCBF43926);
    expect(Crc32.of(const []), 0);
  });

  test('round trip: deflated, stored and streamed entries', () async {
    final json = utf8.encode(jsonEncode({
      'strokes': [for (var i = 0; i < 2000; i++) [i, i * 2, 0.5]]
    }));
    final noise = randomBytes(5000);
    final big = File(p.join(tmp.path, 'big.pdf'))
      ..writeAsBytesSync(randomBytes(3 * 1024 * 1024 + 17, 2));
    final zipFile = File(p.join(tmp.path, 'out.zip'));

    final w = await ZipWriter.create(zipFile, modified: DateTime(2026, 10, 28, 14, 30, 12));
    await w.addBytes('notebooks/a/pages/p1.json', json);
    await w.addBytes('noise.bin', noise); // does not shrink: stored
    await w.addBytes('empty.json', const []);
    await w.addFile('notebooks/a/source.pdf', big);
    await w.addBytes('notes/ünïcödé ✓.json', utf8.encode('{"ok":true}'));
    await w.close();

    final r = await ZipReader.open(zipFile);
    addTearDown(r.close);
    expect(r.entries.map((e) => e.name), [
      'notebooks/a/pages/p1.json',
      'noise.bin',
      'empty.json',
      'notebooks/a/source.pdf',
      'notes/ünïcödé ✓.json',
    ]);
    final jsonEntry = r.entry('notebooks/a/pages/p1.json')!;
    expect(jsonEntry.compressedSize, lessThan(json.length ~/ 3));
    expect(await r.readBytes(jsonEntry), json);
    expect(r.entry('noise.bin')!.compressedSize, noise.length);
    expect(await r.readBytes(r.entry('noise.bin')!), noise);
    expect(await r.readBytes(r.entry('empty.json')!), isEmpty);
    final out = File(p.join(tmp.path, 'x', 'source.pdf'));
    await r.extractTo(r.entry('notebooks/a/source.pdf')!, out);
    expect(out.readAsBytesSync(), big.readAsBytesSync());
    expect(utf8.decode(await r.readBytes(r.entry('notes/ünïcödé ✓.json')!)),
        '{"ok":true}');
  });

  test('a damaged entry fails its checksum instead of restoring garbage', () async {
    final zipFile = File(p.join(tmp.path, 'out.zip'));
    final w = await ZipWriter.create(zipFile);
    final data = randomBytes(4000, 3);
    await w.addBytes('a.bin', data, compress: false);
    await w.close();
    final bytes = zipFile.readAsBytesSync();
    bytes[30 + 'a.bin'.length + 100] ^= 0xFF; // flip a byte of the data
    zipFile.writeAsBytesSync(bytes);

    final r = await ZipReader.open(zipFile);
    addTearDown(r.close);
    await expectLater(r.readBytes(r.entries.single), throwsA(isA<ZipException>()));
    final target = File(p.join(tmp.path, 'a.bin'));
    await expectLater(
        r.extractTo(r.entries.single, target), throwsA(isA<ZipException>()));
    expect(target.existsSync(), isFalse);
  });

  test('not an archive, or cut short', () async {
    final notZip = File(p.join(tmp.path, 'x.zip'))..writeAsStringSync('hello, not a zip');
    await expectLater(ZipReader.open(notZip), throwsA(isA<ZipException>()));

    final zipFile = File(p.join(tmp.path, 'out.zip'));
    final w = await ZipWriter.create(zipFile);
    await w.addBytes('a.json', utf8.encode('{"a":1}'));
    await w.close();
    final cut = File(p.join(tmp.path, 'cut.zip'))
      ..writeAsBytesSync(zipFile.readAsBytesSync().sublist(0, 20));
    await expectLater(ZipReader.open(cut), throwsA(isA<ZipException>()));
  });

  test('unsafe and duplicate names are refused when writing', () async {
    final w = await ZipWriter.create(File(p.join(tmp.path, 'out.zip')));
    addTearDown(w.abort);
    for (final bad in ['../x', '/abs', 'a//b', r'a\b', 'c:/x', 'a/./b', '']) {
      await expectLater(w.addBytes(bad, const [1]), throwsA(isA<ZipException>()),
          reason: bad);
    }
    await w.addBytes('a', const [1]);
    await expectLater(w.addBytes('a', const [2]), throwsA(isA<ZipException>()));
  });

  test('isSafeZipPath', () {
    expect(isSafeZipPath('notebooks/abc/pages/p.json'), isTrue);
    expect(isSafeZipPath('a..b/c'), isTrue);
    expect(isSafeZipPath('notebooks/../x'), isFalse);
    expect(isSafeZipPath('notebooks/'), isFalse);
  });

  test('abort deletes the unfinished archive', () async {
    final f = File(p.join(tmp.path, 'out.zip'));
    final w = await ZipWriter.create(f);
    await w.addBytes('a', const [1, 2, 3]);
    await w.abort();
    expect(f.existsSync(), isFalse);
  });

  // Other tools must be able to open a backup (and we must read theirs).
  final python = Process.runSync('which', ['python3']).exitCode == 0;
  test('interoperates with Python\'s zipfile', () async {
    final ours = File(p.join(tmp.path, 'ours.zip'));
    final w = await ZipWriter.create(ours);
    await w.addBytes('a/b.json', utf8.encode('{"x": "${'y' * 500}"}'));
    await w.addFile('c.pdf', File(p.join(tmp.path, 'c.pdf'))..writeAsBytesSync(randomBytes(70000)));
    await w.close();
    final test = Process.runSync('python3', ['-I', '-m', 'zipfile', '-t', ours.path]);
    expect(test.exitCode, 0, reason: '${test.stdout}${test.stderr}');

    final theirs = File(p.join(tmp.path, 'theirs.zip'));
    final made = Process.runSync('python3', [
      '-I',
      '-c',
      'import sys, zipfile\n'
          'with zipfile.ZipFile(sys.argv[1], "w", zipfile.ZIP_DEFLATED) as z:\n'
          '    z.writestr("n/é.json", "{\\"v\\": " + "1" * 300 + "}")\n'
          '    z.writestr("s.bin", bytes(range(256)), compress_type=zipfile.ZIP_STORED)\n',
      theirs.path,
    ]);
    expect(made.exitCode, 0, reason: '${made.stderr}');
    final r = await ZipReader.open(theirs);
    addTearDown(r.close);
    expect(utf8.decode(await r.readBytes(r.entry('n/é.json')!)), startsWith('{"v": 111'));
    expect(await r.readBytes(r.entry('s.bin')!), List.generate(256, (i) => i));
  }, skip: python ? false : 'python3 not installed');
}
