import 'package:flutter_test/flutter_test.dart';

import 'package:graceful_shell/capture/capture_flow.dart';
import 'package:graceful_shell/capture/capture_store.dart';
import 'package:graceful_shell/capture/selection_controller.dart';

/// Ask, wait for the surfaces to go, then capture.
void main() {
  const target =
      OutputCapture(connector: 'DP-1', outputSize: CaptureSize(1920, 1080));
  const noSettle = Duration.zero;

  ({CaptureStore store, List<CaptureNotice> notices}) buildStore() {
    final notices = <CaptureNotice>[];
    final store = CaptureStore.forTesting()
      ..notify = notices.add
      ..home = '/tmp/graceful-shell-test-home';
    store.connect = () => null;
    addTearDown(store.dispose);
    return (store: store, notices: notices);
  }

  test('nothing listening declines immediately and captures nothing', () async {
    // `RequestController`'s rule, and the one that keeps a headless run — or
    // this very test — from awaiting a window that will never appear.
    final controller = CaptureSelectionController.forTesting();
    addTearDown(controller.dispose);
    final (:store, :notices) = buildStore();

    await runCaptureFlow(
      CaptureKind.screenshot,
      SelectionMode.output,
      store: store,
      controller: controller,
      settle: noSettle,
    );

    expect(notices, isEmpty, reason: 'no shutter, so nothing to report');
    expect(store.error, isNull);
  });

  test('a cancelled selection does nothing at all', () async {
    final controller = CaptureSelectionController.forTesting();
    addTearDown(controller.dispose);
    controller.addListener(controller.cancel);
    final (:store, :notices) = buildStore();

    await runCaptureFlow(
      CaptureKind.screenshot,
      SelectionMode.area,
      store: store,
      controller: controller,
      settle: noSettle,
    );

    expect(notices, isEmpty);
  });

  test('an answered selection is handed to the shutter', () async {
    final controller = CaptureSelectionController.forTesting();
    addTearDown(controller.dispose);
    SelectionRequest? asked;
    controller.addListener(() {
      final pending = controller.pending;
      if (pending == null) return;
      asked = pending;
      controller.complete(target);
    });
    final (:store, :notices) = buildStore();

    await runCaptureFlow(
      CaptureKind.screenshot,
      SelectionMode.window,
      store: store,
      controller: controller,
      settle: noSettle,
    );

    expect(asked?.kind, CaptureKind.screenshot);
    expect(asked?.mode, SelectionMode.window);
    // There is no compositor behind a widget test, so the shutter fails — but
    // it *ran*, which is what this is pinning.
    expect(notices, hasLength(1));
    expect(notices.single.failed, isTrue);
  });

  test('a video selection starts a recording rather than a shutter', () async {
    final controller = CaptureSelectionController.forTesting();
    addTearDown(controller.dispose);
    controller.addListener(() {
      if (controller.pending != null) controller.complete(target);
    });
    final (:store, :notices) = buildStore();

    await runCaptureFlow(
      CaptureKind.video,
      SelectionMode.output,
      store: store,
      controller: controller,
      settle: noSettle,
    );

    expect(notices.single.summary, 'Recording failed');
    expect(store.recording, isFalse);
  });

  test('the settle is waited out before the shutter, not after the click',
      () async {
    // A layer-shell surface is not gone when its controller is destroyed, and
    // nothing in the stack reports when it is; the wait is what keeps the
    // dimmed selection surface out of the picture.
    final controller = CaptureSelectionController.forTesting();
    addTearDown(controller.dispose);
    controller.addListener(() {
      if (controller.pending != null) controller.complete(target);
    });
    final (:store, :notices) = buildStore();

    var settled = false;
    final flow = runCaptureFlow(
      CaptureKind.screenshot,
      SelectionMode.output,
      store: store,
      controller: controller,
      settle: const Duration(milliseconds: 40),
    ).then((_) => settled = true);

    await Future<void>.delayed(const Duration(milliseconds: 5));
    expect(notices, isEmpty, reason: 'still settling');
    expect(settled, isFalse);

    await flow;
    expect(notices, hasLength(1));
  });
}
