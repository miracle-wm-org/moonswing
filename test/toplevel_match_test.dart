import 'package:flutter_test/flutter_test.dart';

import 'package:moonswing/capture/toplevel_match.dart';

/// Joining miracle's view of a window to the compositor's capture handle for
/// it. The rule under test is mostly the *refusal*: an ambiguous pair answers
/// null and the caller falls back to cropping the output, because recording
/// somebody's other window is worse than recording a fixed rectangle.
ToplevelDescriptor _t(String id, String appId, String title) =>
    ToplevelDescriptor(identifier: id, appId: appId, title: title);

void main() {
  test('matches on the app id and the title together', () {
    final toplevels = [
      _t('a', 'firefox', 'Inbox — Mozilla Firefox'),
      _t('b', 'firefox', 'Docs — Mozilla Firefox'),
    ];
    expect(
      matchToplevel(toplevels,
          appId: 'firefox', title: 'Docs — Mozilla Firefox'),
      'b',
    );
  });

  test('two identical windows are a refusal, not a coin toss', () {
    final toplevels = [
      _t('a', 'firefox', 'Mozilla Firefox'),
      _t('b', 'firefox', 'Mozilla Firefox'),
    ];
    expect(matchToplevel(toplevels, appId: 'firefox', title: 'Mozilla Firefox'),
        isNull);
  });

  test('falls back to the title when the app ids disagree', () {
    // The XWayland case: miracle reports the WM class, the toplevel list
    // reports something else or nothing.
    final toplevels = [
      _t('a', '', 'GIMP'),
      _t('b', 'org.gnome.Nautilus', 'Home'),
    ];
    expect(matchToplevel(toplevels, appId: 'Gimp-2.10', title: 'GIMP'), 'a');
  });

  test('falls back to the app id when the title has moved on', () {
    // A browser tab switched between the tree read and the pick.
    final toplevels = [
      _t('a', 'org.gnome.Nautilus', 'Downloads'),
      _t('b', 'firefox', 'Something else entirely'),
    ];
    expect(
      matchToplevel(toplevels, appId: 'org.gnome.Nautilus', title: 'Home'),
      'a',
    );
  });

  test('the app id comparison ignores case', () {
    final toplevels = [_t('a', 'Firefox', 'Inbox')];
    expect(matchToplevel(toplevels, appId: 'firefox', title: 'Gone'), 'a');
  });

  test('an unidentifiable toplevel is never the answer', () {
    // A handle with no identifier cannot be captured, so matching it would be
    // an answer the caller has to discard anyway.
    final toplevels = [_t('', 'firefox', 'Inbox')];
    expect(matchToplevel(toplevels, appId: 'firefox', title: 'Inbox'), isNull);
  });

  test('an empty list, and empty fields, answer null', () {
    expect(matchToplevel(const [], appId: 'firefox', title: 'Inbox'), isNull);
    expect(
      matchToplevel([_t('a', 'firefox', 'Inbox')], appId: '', title: ''),
      isNull,
    );
  });
}
