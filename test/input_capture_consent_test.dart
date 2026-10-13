import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:moonswing/config.dart';
import 'package:moonswing/input_capture/consent_controller.dart';
import 'package:moonswing/input_capture/consent_dialog.dart';
import 'package:moonswing/input_capture/eis_server.dart';
import 'package:moonswing/scopes.dart';

/// The input-capture consent prompt: what it says, that only *Allow* grants,
/// and that every other way out is a refusal.

const _request = InputCaptureConsentRequest(
  appId: 'org.deskflow.deskflow',
  capabilities: captureCapKeyboard | captureCapPointer,
);

Future<({List<String> answers, ValueNotifier<bool> closing})> _pump(
  WidgetTester tester, {
  InputCaptureConsentRequest request = _request,
}) async {
  final answers = <String>[];
  final closing = ValueNotifier(false);
  addTearDown(closing.dispose);
  await tester.pumpWidget(
    ThemeScope(
      theme: const ThemeConfig(),
      child: InputCaptureConsentDialog(
        request: request,
        closingNotifier: closing,
        onClosed: () => answers.add('closed'),
        onAllow: () => answers.add('allow'),
        onDeny: () => answers.add('deny'),
      ),
    ),
  );
  await tester.pump();
  return (answers: answers, closing: closing);
}

void main() {
  testWidgets('names the application, the devices and the way back',
      (tester) async {
    await _pump(tester);
    expect(find.text('Share your keyboard and mouse?'), findsOneWidget);
    expect(find.textContaining('org.deskflow.deskflow'), findsOneWidget);
    expect(find.textContaining(kInputCaptureEscapeChord), findsOneWidget);
  });

  testWidgets('a pointer-only request does not mention the keyboard',
      (tester) async {
    await _pump(tester,
        request: const InputCaptureConsentRequest(
            appId: '', capabilities: captureCapPointer));
    expect(find.text('Share your mouse?'), findsOneWidget);
    expect(find.textContaining('An application'), findsOneWidget);
  });

  testWidgets('Allow grants, and starts the exit', (tester) async {
    final host = await _pump(tester);
    await tester.tap(find.text('Allow'));
    expect(host.answers.first, 'allow');
    expect(host.answers, isNot(contains('deny')));
    expect(host.closing.value, isTrue);
  });

  testWidgets('Escape refuses; Enter does not allow', (tester) async {
    final host = await _pump(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(host.answers, isEmpty,
        reason: 'an Enter meant for something else must not hand over input');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    expect(host.answers.first, 'deny');
    expect(host.answers, isNot(contains('allow')));
  });

  testWidgets('Deny refuses', (tester) async {
    final host = await _pump(tester);
    await tester.tap(find.text('Deny'));
    expect(host.answers.first, 'deny');
    expect(host.answers, isNot(contains('allow')));
  });

  test('the controller says no when nothing is listening', () async {
    final controller = InputCaptureConsentController.forTesting();
    expect(await controller.ask(_request), isFalse);
  });

  test('the controller answers yes only for an explicit allow', () async {
    final controller = InputCaptureConsentController.forTesting();
    void listener() {}
    controller.addListener(listener);
    final allowed = controller.ask(_request);
    controller.complete(true);
    expect(await allowed, isTrue);
    final cancelled = controller.ask(_request);
    controller.cancel();
    expect(await cancelled, isFalse);
  });
}
