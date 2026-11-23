import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neatink/features/editor/editor_extensions.dart';
import 'package:neatink/features/editor/editor_integrations.dart';

import 'canvas_harness.dart';

/// Records what the document view tells the touch interceptor.
class FakeInterceptor implements TouchInterceptor {
  /// Decides whether a finger is claimed; claims everything by default.
  bool Function(PointerDownEvent e)? claimWhen;

  final List<PointerDownEvent> downs = [];
  final List<bool> fingerDrawsSeen = [];
  final List<PointerMoveEvent> moves = [];
  final List<PointerUpEvent> ups = [];
  final List<PointerCancelEvent> cancels = [];

  @override
  bool onPointerDown(PointerDownEvent e, {required bool fingerDraws}) {
    downs.add(e);
    fingerDrawsSeen.add(fingerDraws);
    return claimWhen?.call(e) ?? true;
  }

  @override
  void onPointerMove(PointerMoveEvent e) => moves.add(e);

  @override
  void onPointerUp(PointerUpEvent e) => ups.add(e);

  @override
  void onPointerCancel(PointerCancelEvent e) => cancels.add(e);
}

EditorIntegration interceptorIntegration(TouchInterceptor? interceptor) =>
    (controller, ref) => controller.extensions.touchInterceptor = interceptor;

void main() {
  /// A finger drag long enough to scroll the page, in view-local positions.
  const from = Offset(500, 700);
  const to = Offset(500, 500);

  Future<void> fingerDrag(CanvasHarness h, {Offset a = from, Offset b = to}) async {
    final g = await h.down(a, kind: PointerDeviceKind.touch);
    for (var i = 1; i <= 8; i++) {
      await h.moveTo(g, Offset.lerp(a, b, i / 8)!);
    }
    await g.up();
    await h.tester.pump();
  }

  group('a claimed finger', () {
    testWidgets('moves the interceptor, not the page', (tester) async {
      final fake = FakeInterceptor();
      final h = await CanvasHarness.open(tester,
          integrations: [interceptorIntegration(fake)]);
      final before = h.controller.viewport.offset;
      await fingerDrag(h);

      expect(h.controller.viewport.offset, before, reason: 'the page did not scroll');
      expect(fake.downs.length, 1);
      expect(fake.moves.length, 8);
      expect(fake.ups.length, 1);
      expect(fake.cancels, isEmpty);
      await h.close();
    });

    testWidgets('gets positions in the document view\'s space', (tester) async {
      final fake = FakeInterceptor();
      final h = await CanvasHarness.open(tester,
          integrations: [interceptorIntegration(fake)]);
      await fingerDrag(h);
      expect(fake.downs.single.localPosition, from);
      expect(fake.moves.last.localPosition, to);
      expect(fake.ups.single.localPosition, to);
      // Ordinary pointer events: global is local plus the view's offset.
      expect(fake.downs.single.position, h.global(from));
      await h.close();
    });

    testWidgets('does not draw even when the finger draws', (tester) async {
      final fake = FakeInterceptor();
      final h = await CanvasHarness.open(tester,
          integrations: [interceptorIntegration(fake)]);
      h.controller.applySettings(
          h.controller.settings.copyWith(drawWithFinger: true));
      await fingerDrag(h);
      expect(fake.fingerDrawsSeen, [true]);
      expect(h.strokes, isEmpty);
      expect(h.controller.inkTool.active, isNull);
      await h.close();
    });

    testWidgets('is told when the system cancels it', (tester) async {
      final fake = FakeInterceptor();
      final h = await CanvasHarness.open(tester,
          integrations: [interceptorIntegration(fake)]);
      final g = await h.down(from, kind: PointerDeviceKind.touch);
      await h.moveTo(g, to);
      await g.cancel();
      await tester.pump();
      expect(fake.cancels.length, 1);
      expect(fake.ups, isEmpty);
      await h.close();
    });

    testWidgets('is released when it lifts: the next finger is offered afresh',
        (tester) async {
      final fake = FakeInterceptor();
      final h = await CanvasHarness.open(tester,
          integrations: [interceptorIntegration(fake)]);
      await fingerDrag(h);
      await fingerDrag(h);
      expect(fake.downs.length, 2);
      expect(fake.ups.length, 2);
      await h.close();
    });
  });

  group('a finger the interceptor declines', () {
    testWidgets('scrolls the page as it always did', (tester) async {
      final fake = FakeInterceptor()..claimWhen = (e) => false;
      final h = await CanvasHarness.open(tester,
          integrations: [interceptorIntegration(fake)]);
      final before = h.controller.viewport.offset;
      await fingerDrag(h);
      expect(fake.downs.length, 1, reason: 'it was offered');
      expect(fake.moves, isEmpty, reason: 'but never sees the moves');
      expect(fake.ups, isEmpty);
      expect(h.controller.viewport.offset.dy, lessThan(before.dy));
      await h.close();
    });

    testWidgets('draws when the finger draws', (tester) async {
      final fake = FakeInterceptor()..claimWhen = (e) => false;
      final h = await CanvasHarness.open(tester,
          integrations: [interceptorIntegration(fake)]);
      h.controller.applySettings(
          h.controller.settings.copyWith(drawWithFinger: true));
      await tester.pump(const Duration(seconds: 1));
      await fingerDrag(h);
      expect(fake.fingerDrawsSeen, [true]);
      expect(h.strokes.length, 1);
      await h.close();
    });
  });

  group('who is offered', () {
    testWidgets('only fingers: not the pen, not the mouse', (tester) async {
      final fake = FakeInterceptor();
      final h = await CanvasHarness.open(tester,
          integrations: [interceptorIntegration(fake)]);
      await h.drag([const Offset(200, 300), const Offset(300, 320)]);
      await h.drag([const Offset(200, 400), const Offset(300, 420)],
          kind: PointerDeviceKind.mouse);
      expect(fake.downs, isEmpty);
      expect(h.strokes.length, 2, reason: 'both drew');
      await h.close();
    });

    testWidgets('not a finger the palm rejection ignores', (tester) async {
      final fake = FakeInterceptor();
      final h = await CanvasHarness.open(tester,
          integrations: [interceptorIntegration(fake)]);
      // The pen draws (pointer times are 0 in the test), and a finger lands
      // 100 ms later: inside the palm window.
      await h.drag([const Offset(200, 300), const Offset(300, 320)]);
      final palm = await tester.createGesture(kind: PointerDeviceKind.touch);
      await palm.down(h.global(from), timeStamp: const Duration(milliseconds: 100));
      await palm.up(timeStamp: const Duration(milliseconds: 150));
      await tester.pump();
      expect(fake.downs, isEmpty);

      // Long after the pen, a finger is offered.
      final finger = await tester.createGesture(kind: PointerDeviceKind.touch);
      await finger.down(h.global(from), timeStamp: const Duration(seconds: 3));
      await finger.up(timeStamp: const Duration(seconds: 3, milliseconds: 50));
      await tester.pump();
      expect(fake.downs.length, 1);
      await h.close();
    });

    testWidgets('nothing happens without an interceptor', (tester) async {
      final h = await CanvasHarness.open(tester);
      final before = h.controller.viewport.offset;
      await fingerDrag(h);
      expect(h.controller.viewport.offset.dy, lessThan(before.dy));
      await h.close();
    });

    testWidgets('an interceptor set while the editor shows is used',
        (tester) async {
      final h = await CanvasHarness.open(tester);
      final fake = FakeInterceptor();
      h.controller.extensions.touchInterceptor = fake;
      await fingerDrag(h);
      expect(fake.downs.length, 1);
      h.controller.extensions.touchInterceptor = null;
      await fingerDrag(h);
      expect(fake.downs.length, 1);
      await h.close();
    });
  });

  group('two fingers', () {
    testWidgets('a finger joining a claimed one is offered and can be claimed',
        (tester) async {
      final fake = FakeInterceptor();
      final h = await CanvasHarness.open(tester,
          integrations: [interceptorIntegration(fake)]);
      final before = h.controller.viewport;
      final zoom = before.zoom;
      final a = await h.down(const Offset(300, 500), kind: PointerDeviceKind.touch);
      final b = await h.down(const Offset(700, 500), kind: PointerDeviceKind.touch);
      await h.moveTo(a, const Offset(250, 500));
      await h.moveTo(b, const Offset(750, 500));
      await a.up();
      await b.up();
      await tester.pump();
      expect(fake.downs.length, 2);
      expect(fake.moves.length, 2);
      expect(fake.ups.length, 2);
      // Moving apart would have zoomed the page if it had been a pinch.
      expect(h.controller.viewport.zoom, zoom);
      await h.close();
    });

    testWidgets('a finger that lands while another navigates is not offered',
        (tester) async {
      // The first finger lands off the interceptor's target and pans; a
      // second one landing on the target would be a pinch, not a ruler move.
      final fake = FakeInterceptor()..claimWhen = (e) => e.localPosition.dx > 800;
      final h = await CanvasHarness.open(tester,
          integrations: [interceptorIntegration(fake)]);
      final a = await h.down(const Offset(300, 500), kind: PointerDeviceKind.touch);
      await h.moveTo(a, const Offset(300, 450));
      final b = await h.down(const Offset(900, 500), kind: PointerDeviceKind.touch);
      expect(fake.downs.length, 1, reason: 'only the first finger was offered');
      await h.moveTo(b, const Offset(900, 450));
      expect(fake.moves, isEmpty);
      await a.up();
      await b.up();
      await tester.pump();
      await h.close();
    });

    testWidgets('a finger that lands while another draws is not offered',
        (tester) async {
      final fake = FakeInterceptor()..claimWhen = (e) => e.localPosition.dx > 800;
      final h = await CanvasHarness.open(tester,
          integrations: [interceptorIntegration(fake)]);
      h.controller.applySettings(
          h.controller.settings.copyWith(drawWithFinger: true));
      await tester.pump(const Duration(seconds: 1));
      final a = await h.down(const Offset(300, 500), kind: PointerDeviceKind.touch);
      await h.moveTo(a, const Offset(350, 500));
      final b = await h.down(const Offset(900, 500), kind: PointerDeviceKind.touch);
      expect(fake.downs.length, 1);
      await a.up();
      await b.up();
      await tester.pump();
      await h.close();
    });
  });

  group('when the pen lands', () {
    testWidgets('a claimed finger is cancelled and then ignored',
        (tester) async {
      final fake = FakeInterceptor();
      final h = await CanvasHarness.open(tester,
          integrations: [interceptorIntegration(fake)]);
      final palm = await h.down(const Offset(600, 600), kind: PointerDeviceKind.touch);
      await h.moveTo(palm, const Offset(610, 640));
      expect(fake.moves.length, 1);

      // The pen lands: the finger was a resting palm.
      final pen = await h.down(const Offset(300, 300));
      expect(fake.cancels.length, 1);
      final cancel = fake.cancels.single;
      expect(cancel.pointer, fake.downs.single.pointer);
      expect(cancel.kind, PointerDeviceKind.touch);
      expect(cancel.position, h.global(const Offset(610, 640)));
      expect(cancel.localPosition, const Offset(610, 640));

      // It gets nothing more, however it moves or lifts.
      await h.moveTo(palm, const Offset(650, 700));
      await palm.up();
      await h.moveTo(pen, const Offset(400, 320));
      await pen.up();
      await tester.pump();
      expect(fake.moves.length, 1);
      expect(fake.ups, isEmpty);
      expect(fake.cancels.length, 1);
      // And the pen draws as usual.
      expect(h.strokes.length, 1);
      await h.close();
    });

    testWidgets('both fingers of a gesture are cancelled', (tester) async {
      final fake = FakeInterceptor();
      final h = await CanvasHarness.open(tester,
          integrations: [interceptorIntegration(fake)]);
      final a = await h.down(const Offset(300, 600), kind: PointerDeviceKind.touch);
      final b = await h.down(const Offset(500, 600), kind: PointerDeviceKind.touch);
      final pen = await h.down(const Offset(300, 300));
      expect(fake.cancels.length, 2);
      expect({for (final c in fake.cancels) c.pointer},
          {for (final d in fake.downs) d.pointer});
      await pen.up();
      await a.up();
      await b.up();
      await tester.pump();
      expect(fake.ups, isEmpty);
      await h.close();
    });

    testWidgets('a finger that landed after the pen is ignored as before',
        (tester) async {
      final fake = FakeInterceptor();
      final h = await CanvasHarness.open(tester,
          integrations: [interceptorIntegration(fake)]);
      final pen = await h.down(const Offset(300, 300));
      final palm = await h.down(const Offset(600, 600), kind: PointerDeviceKind.touch);
      expect(fake.downs, isEmpty);
      await pen.up();
      await palm.up();
      await tester.pump();
      await h.close();
    });
  });

  group('when the view goes away', () {
    testWidgets('a claimed finger is cancelled', (tester) async {
      final fake = FakeInterceptor();
      final h = await CanvasHarness.open(tester,
          integrations: [interceptorIntegration(fake)]);
      await h.down(const Offset(600, 600), kind: PointerDeviceKind.touch);
      expect(fake.cancels, isEmpty);
      await h.close();
      expect(fake.cancels.length, 1);
    });

    testWidgets('nothing is cancelled when no finger was claimed',
        (tester) async {
      final fake = FakeInterceptor();
      final h = await CanvasHarness.open(tester,
          integrations: [interceptorIntegration(fake)]);
      await h.close();
      expect(fake.cancels, isEmpty);
    });
  });
}
