import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:neatink/document/paper.dart';
import 'package:neatink/document/pdf_margins.dart';
import 'package:neatink/pdf/pdf_engine.dart';
import 'package:neatink/pdf/pdf_import.dart';
import 'package:neatink/storage/notebook_repository.dart' show PdfPageSize;

import '../fakes/in_memory_repository.dart';

class _Doc implements PdfEngineDocument {
  @override
  int get pageCount => 2;
  @override
  List<PdfPageSize> get pageSizes => const [PdfPageSize(600, 800), PdfPageSize(800, 600)];
  @override
  Future<String> extractText(int pageIndex) async => 'page $pageIndex';
  @override
  Future<List<PdfWordBox>> words(int pageIndex) async => const [];
  @override
  Future<ui.Image?> render(int pageIndex, PdfRenderRegion region, {PdfRenderCancelToken? cancel}) async => null;
  @override
  Future<void> close() async {}
}

class _Engine implements PdfEngine {
  @override
  Future<PdfEngineDocument> open(String path) async => _Doc();
}

void main() {
  late File pdf;

  setUp(() async {
    final dir = await Directory.systemTemp.createTemp('neatink_margins_');
    pdf = File('${dir.path}/Slides.pdf')..writeAsBytesSync([37, 80, 68, 70]);
    addTearDown(() => dir.delete(recursive: true));
  });

  test('importing with margins gives every page lined writing space', () async {
    final repo = InMemoryNotebookRepository();
    final meta = await importPdfNotebook(repo, pdf.path, engine: _Engine(), margins: PdfMargins.narrow);
    expect([for (final p in meta.pages) (p.width, p.marginLeft, p.marginRight)],
        [(900.0, 150.0, 150.0), (1200.0, 200.0, 200.0)]);
    expect(meta.pages.every((p) => p.paper.type == PaperType.lined), isTrue);
    final stored = (await repo.loadMeta(meta.id))!;
    expect(stored.pages.first.marginLeft, 150);
  });

  test('without margins the pages keep the PDF size', () async {
    final repo = InMemoryNotebookRepository();
    final meta = await importPdfNotebook(repo, pdf.path, engine: _Engine());
    expect([for (final p in meta.pages) (p.width, p.hasMargins)], [(600.0, false), (800.0, false)]);
  });
}
