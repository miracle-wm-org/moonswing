import 'package:flutter_test/flutter_test.dart';

import 'package:graceful_shell/capture/capture_config.dart';
import 'package:graceful_shell/capture/capture_store.dart';
import 'package:graceful_shell/capture/capture_targets.dart';

/// The state the two bar modules render, and the one path a test with no
/// compositor behind it can drive end to end: the connection that is not
/// there.
void main() {
  const target =
      OutputCapture(connector: 'DP-1', outputSize: CaptureSize(1920, 1080));

  CaptureStore build(List<CaptureNotice> notices, {void Function()? shutter}) {
    final store = CaptureStore.forTesting()
      ..notify = notices.add
      ..shutter = shutter ?? () {}
      ..home = '/tmp/graceful-shell-test-home';
    // Its own statement: `= () => null` followed by a cascade would put the
    // cascade on the null rather than on the store.
    store.connect = () => null;
    addTearDown(store.dispose);
    return store;
  }

  test('an idle store is holding nothing', () {
    final store = build([]);
    expect(store.recording, isFalse);
    expect(store.stopping, isFalse);
    expect(store.busy, isFalse);
    expect(store.error, isNull);
    expect(store.recordingElapsed, Duration.zero);
  });

  test('a capture with no compositor fails visibly rather than silently',
      () async {
    final notices = <CaptureNotice>[];
    final store = build(notices);

    await store.capture(target);

    expect(store.error, isNotNull);
    expect(notices, hasLength(1));
    expect(notices.single.failed, isTrue,
        reason: 'a failure has to stay on screen until it is dismissed');
    expect(store.busy, isFalse, reason: 'the shutter is released either way');
  });

  test('a capture that failed makes no shutter noise', () async {
    // The sound says a photograph exists. A failed capture already has a
    // notification and a reason on the icon, and a shutter over the top of it
    // would be the shell telling the user it took a shot it did not take.
    var shutters = 0;
    final store = build([], shutter: () => shutters++);

    await store.capture(target);

    expect(store.error, isNotNull);
    expect(shutters, 0);
  });

  test('a recording that cannot start leaves nothing running', () async {
    final notices = <CaptureNotice>[];
    final store = build(notices);

    await store.startRecording(target);

    expect(store.recording, isFalse);
    expect(store.recordingTarget, isNull);
    expect(store.error, isNotNull);
    expect(notices.single.failed, isTrue);
  });

  test('stopping when nothing is recording does nothing at all', () async {
    final notices = <CaptureNotice>[];
    final store = build(notices);
    await store.stopRecording();
    expect(notices, isEmpty);
    expect(store.error, isNull);
  });

  test('configure notifies only when the options actually moved', () {
    final store = build([]);
    var notifications = 0;
    store.addListener(() => notifications++);

    store.configureScreenshot(const ScreenshotConfig(delaySeconds: 2));
    expect(notifications, 1);
    // `Module.loadAll` pushes a fresh object on every sweep and the settings UI
    // notifies on every keystroke anywhere in it; without this guard every one
    // of those would wake every bar on every monitor.
    store.configureScreenshot(const ScreenshotConfig(delaySeconds: 2));
    expect(notifications, 1);
    store.configureRecorder(const RecorderConfig(fps: 60));
    expect(notifications, 2);
    store.configureRecorder(const RecorderConfig(fps: 60));
    expect(notifications, 2);
  });

  group('formatRecordingElapsed', () {
    test('is minutes and seconds, unpadded, until an hour', () {
      expect(formatRecordingElapsed(Duration.zero), '0:00');
      expect(formatRecordingElapsed(const Duration(seconds: 9)), '0:09');
      expect(formatRecordingElapsed(const Duration(minutes: 4, seconds: 7)),
          '4:07');
      expect(formatRecordingElapsed(const Duration(minutes: 59, seconds: 59)),
          '59:59');
    });

    test('grows an hours field rather than counting to 600 minutes', () {
      expect(formatRecordingElapsed(const Duration(hours: 1)), '1:00:00');
      expect(
        formatRecordingElapsed(
            const Duration(hours: 2, minutes: 3, seconds: 4)),
        '2:03:04',
      );
    });
  });
}
