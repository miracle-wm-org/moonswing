// What miracle's configuration enums are *called* in the settings UI, and how a
// key binding reads back as a shortcut.
//
// `package:miracle` gives every enum a `wireName` — the spelling in the
// configuration file — which is the wrong string to put in front of a person:
// it is snake_case, it is occasionally misspelled on purpose
// (`Acceleration.adapative`, faithful to the C library), and it names things as
// the compositor thinks of them rather than as the user does (`meta` is the
// Super key).
//
// Deliberately Flutter-free, so the ordering and the shortcut formatting are a
// plain unit test rather than a widget one.
library;

import 'package:miracle/miracle.dart';

/// What the user calls [modifier].
///
/// [Modifier.primary] is miracle's sentinel for "whatever the Action Key is set
/// to", and the wiki calls that the Action Key, so that is what it is called
/// here — a binding written against it follows the Action Key when the user
/// changes it, which "Primary" would not convey.
String modifierLabel(Modifier modifier) => switch (modifier) {
  Modifier.primary => 'Action Key',
  Modifier.alt => 'Alt',
  Modifier.altLeft => 'Left Alt',
  Modifier.altRight => 'Right Alt',
  Modifier.shift => 'Shift',
  Modifier.shiftLeft => 'Left Shift',
  Modifier.shiftRight => 'Right Shift',
  Modifier.ctrl => 'Ctrl',
  Modifier.ctrlLeft => 'Left Ctrl',
  Modifier.ctrlRight => 'Right Ctrl',
  Modifier.meta => 'Super',
  Modifier.metaLeft => 'Left Super',
  Modifier.metaRight => 'Right Super',
  Modifier.sym => 'Sym',
  Modifier.function => 'Fn',
  Modifier.capsLock => 'Caps Lock',
  Modifier.numLock => 'Num Lock',
  Modifier.scrollLock => 'Scroll Lock',
};

/// The order modifiers are *written* in, lowest first.
///
/// A shortcut reads the way a keyboard shortcut is conventionally written —
/// Ctrl before Alt before Shift before Super — rather than in the order of
/// [Modifier]'s bit values, which would put Alt first and Super last. The Action
/// Key leads, because a miracle binding is read as "Action Key and then".
int _modifierRank(Modifier modifier) => switch (modifier) {
  Modifier.primary => 0,
  Modifier.ctrl || Modifier.ctrlLeft || Modifier.ctrlRight => 1,
  Modifier.alt || Modifier.altLeft || Modifier.altRight => 2,
  Modifier.shift || Modifier.shiftLeft || Modifier.shiftRight => 3,
  Modifier.meta || Modifier.metaLeft || Modifier.metaRight => 4,
  _ => 5,
};

/// The modifiers a binding editor offers, in the order it offers them.
///
/// Every modifier miracle knows, because a configuration may already name any
/// of them and an editor that hid one would silently drop it on save. The
/// generic bits come first: binding to `ctrl_left` means the shortcut stops
/// working on the right-hand Control key, which is a choice to scroll to rather
/// than to trip over.
final List<Modifier> kModifiersInDisplayOrder = () {
  final modifiers = [...Modifier.values];
  modifiers.sort((a, b) {
    final byRank = _modifierRank(a).compareTo(_modifierRank(b));
    if (byRank != 0) return byRank;
    return a.index.compareTo(b.index);
  });
  return List<Modifier>.unmodifiable(modifiers);
}();

/// [modifiers] in the order a shortcut is written, e.g. Action Key then Shift.
List<Modifier> sortModifiers(Iterable<Modifier> modifiers) {
  final sorted = [...modifiers];
  sorted.sort((a, b) {
    final byRank = _modifierRank(a).compareTo(_modifierRank(b));
    if (byRank != 0) return byRank;
    return a.index.compareTo(b.index);
  });
  return sorted;
}

/// A binding as a person would write it: `Action Key + Shift + R`.
///
/// [keyLabel] is passed in rather than looked up, so this file stays
/// independent of the key-code table and both can be tested on their own.
String describeShortcut(Set<Modifier> modifiers, String keyLabel) {
  final parts = [
    for (final modifier in sortModifiers(modifiers)) modifierLabel(modifier),
    keyLabel,
  ];
  return parts.join(' + ');
}

/// What the user calls [button].
String mouseButtonLabel(MouseButton button) => switch (button) {
  MouseButton.primary => 'Primary (left)',
  MouseButton.secondary => 'Secondary (right)',
  MouseButton.tertiary => 'Middle',
  MouseButton.back => 'Back',
  MouseButton.forward => 'Forward',
  MouseButton.side => 'Side',
  MouseButton.extra => 'Extra',
  MouseButton.task => 'Task',
};

/// Which key event a binding fires on.
String keyboardActionLabel(KeyboardAction action) => switch (action) {
  KeyboardAction.down => 'Key down',
  KeyboardAction.up => 'Key up',
  KeyboardAction.repeat => 'Key repeat',
};

/// What one of miracle's built-in commands does.
String builtInCommandLabel(BuiltInKeyCommand command) => switch (command) {
  BuiltInKeyCommand.terminal => 'Open a terminal',
  BuiltInKeyCommand.requestVerticalLayout => 'Split vertically',
  BuiltInKeyCommand.requestHorizontalLayout => 'Split horizontally',
  BuiltInKeyCommand.toggleResize => 'Toggle resize mode',
  BuiltInKeyCommand.resizeUp => 'Resize up',
  BuiltInKeyCommand.resizeDown => 'Resize down',
  BuiltInKeyCommand.resizeLeft => 'Resize left',
  BuiltInKeyCommand.resizeRight => 'Resize right',
  BuiltInKeyCommand.moveUp => 'Move window up',
  BuiltInKeyCommand.moveDown => 'Move window down',
  BuiltInKeyCommand.moveLeft => 'Move window left',
  BuiltInKeyCommand.moveRight => 'Move window right',
  BuiltInKeyCommand.selectUp => 'Focus the window above',
  BuiltInKeyCommand.selectDown => 'Focus the window below',
  BuiltInKeyCommand.selectLeft => 'Focus the window to the left',
  BuiltInKeyCommand.selectRight => 'Focus the window to the right',
  BuiltInKeyCommand.quitActiveWindow => 'Close the focused window',
  BuiltInKeyCommand.quitCompositor => 'Quit miracle',
  BuiltInKeyCommand.fullscreen => 'Toggle fullscreen',
  BuiltInKeyCommand.toggleFloating => 'Toggle floating',
  BuiltInKeyCommand.togglePinnedToWorkspace => 'Toggle pinned to workspace',
  BuiltInKeyCommand.toggleTabbing => 'Toggle tabbed layout',
  BuiltInKeyCommand.toggleStacking => 'Toggle stacked layout',
  BuiltInKeyCommand.magnifierOn => 'Turn the magnifier on',
  BuiltInKeyCommand.magnifierOff => 'Turn the magnifier off',
  BuiltInKeyCommand.magnifierIncreaseSize => 'Grow the magnifier',
  BuiltInKeyCommand.magnifierDecreaseSize => 'Shrink the magnifier',
  BuiltInKeyCommand.magnifierIncreaseScale => 'Magnify further',
  BuiltInKeyCommand.magnifierDecreaseScale => 'Magnify less',
  BuiltInKeyCommand.reloadConfig => 'Reload the configuration',
  BuiltInKeyCommand.selectWorkspace1 => 'Go to workspace 1',
  BuiltInKeyCommand.selectWorkspace2 => 'Go to workspace 2',
  BuiltInKeyCommand.selectWorkspace3 => 'Go to workspace 3',
  BuiltInKeyCommand.selectWorkspace4 => 'Go to workspace 4',
  BuiltInKeyCommand.selectWorkspace5 => 'Go to workspace 5',
  BuiltInKeyCommand.selectWorkspace6 => 'Go to workspace 6',
  BuiltInKeyCommand.selectWorkspace7 => 'Go to workspace 7',
  BuiltInKeyCommand.selectWorkspace8 => 'Go to workspace 8',
  BuiltInKeyCommand.selectWorkspace9 => 'Go to workspace 9',
  BuiltInKeyCommand.selectWorkspace0 => 'Go to workspace 10',
  BuiltInKeyCommand.moveToWorkspace1 => 'Move the window to workspace 1',
  BuiltInKeyCommand.moveToWorkspace2 => 'Move the window to workspace 2',
  BuiltInKeyCommand.moveToWorkspace3 => 'Move the window to workspace 3',
  BuiltInKeyCommand.moveToWorkspace4 => 'Move the window to workspace 4',
  BuiltInKeyCommand.moveToWorkspace5 => 'Move the window to workspace 5',
  BuiltInKeyCommand.moveToWorkspace6 => 'Move the window to workspace 6',
  BuiltInKeyCommand.moveToWorkspace7 => 'Move the window to workspace 7',
  BuiltInKeyCommand.moveToWorkspace8 => 'Move the window to workspace 8',
  BuiltInKeyCommand.moveToWorkspace9 => 'Move the window to workspace 9',
  BuiltInKeyCommand.moveToWorkspace0 => 'Move the window to workspace 10',
};

/// What one animation part moves.
String animationTypeLabel(AnimationType type) => switch (type) {
  AnimationType.disabled => 'None',
  AnimationType.slide => 'Slide',
  AnimationType.grow => 'Grow',
  AnimationType.shrink => 'Shrink',
  AnimationType.fade => 'Fade',
};

/// The name of an easing curve, as <https://easings.net/> writes it.
///
/// Derived from [EaseFunction.wireName] rather than spelled out thirty-one
/// times: the names there are already the canonical ones, and a hand-written
/// table of them would be thirty-one chances to mistype "easeInOutElastic".
String easeFunctionLabel(EaseFunction function) {
  if (function == EaseFunction.linear) return 'Linear';
  final words = function.wireName.split('_');
  return [
    for (final word in words) word[0].toUpperCase() + word.substring(1),
  ].join(' ');
}

/// Which hand the pointer is set up for.
String handednessLabel(Handedness handedness) => switch (handedness) {
  Handedness.right => 'Right-handed',
  Handedness.left => 'Left-handed',
};

/// How pointer movement is filtered.
String accelerationLabel(Acceleration acceleration) => switch (acceleration) {
  Acceleration.none => 'Flat (no acceleration)',
  Acceleration.adaptive => 'Adaptive',
};

/// How a touchpad reports button presses.
String touchpadClickModeLabel(TouchpadClickMode mode) => switch (mode) {
  TouchpadClickMode.none => 'No clicks',
  TouchpadClickMode.areaToClick => 'By area (bottom corners)',
  TouchpadClickMode.fingerCount => 'By finger count',
};

/// How a touchpad reports scrolling.
String touchpadScrollModeLabel(TouchpadScrollMode mode) => switch (mode) {
  TouchpadScrollMode.none => 'No scrolling',
  TouchpadScrollMode.twoFingerScroll => 'Two fingers',
  TouchpadScrollMode.edgeScroll => 'Along the edge',
  TouchpadScrollMode.buttonDownScroll => 'While a button is held',
};

/// Whether the pointer focuses a window by moving over it or by clicking it.
String cursorFocusModeLabel(CursorFocusMode mode) => switch (mode) {
  CursorFocusMode.hover => 'On hover',
  CursorFocusMode.click => 'On click',
};

/// The animateable event names miracle ships, humanised.
///
/// The names come *from* the compositor (`AnimateableEvent.name` cannot be
/// changed), so this is a lookup with a fallback rather than an enum: a miracle
/// that grows a new event renders it under its own name instead of vanishing
/// from the page.
String animateableEventLabel(String name) => switch (name) {
  'window_open' => 'A window opens',
  'window_close' => 'A window closes',
  'window_move' => 'A window moves',
  'window_workspace_hidden' => 'A window is hidden with its workspace',
  'window_workspace_visible' => 'A window returns with its workspace',
  _ => _humanise(name),
};

String _humanise(String name) {
  final words = name.split('_').where((word) => word.isNotEmpty).toList();
  if (words.isEmpty) return name;
  return [
    words.first[0].toUpperCase() + words.first.substring(1),
    ...words.skip(1),
  ].join(' ');
}

/// The default binding for [BuiltInKeyCommand.reloadConfig] — what miracle
/// ships with, and what the save notice tells the user to press.
const String kDefaultReloadShortcut = 'Action Key + Shift + R';

/// How to make miracle re-read the file that was just written.
///
/// Miracle does not watch its configuration, so a save is only half the job;
/// this is the other half, and it is read off the configuration rather than
/// hard-coded because the user may have rebound it. [overrides] is
/// `MiracleConfig.builtInKeyCommandOverrides`; [keyLabel] resolves an override's
/// keysym, which is `miracleKeyLabel` at every call site that is not a test.
String reloadShortcutLabel(
  List<KeyCommandOverride> overrides,
  String Function(int keysym) keyLabel,
) {
  for (final override in overrides) {
    if (override.command != BuiltInKeyCommand.reloadConfig) continue;
    return describeShortcut(override.modifiers, keyLabel(override.key));
  }
  return kDefaultReloadShortcut;
}
