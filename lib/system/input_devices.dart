import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:moonswing/system/file_read.dart';

/// What a device is, as far as a person reading the System Info page is
/// concerned.
///
/// Declaration order is display order: the things somebody types and points with
/// first, the things they are recorded by last. [other] is the honest answer for
/// a node this table cannot place.
enum InputDeviceKind {
  keyboard('Keyboard'),
  mouse('Mouse'),
  touchpad('Touchpad'),
  pointingStick('Pointing stick'),
  touchscreen('Touchscreen'),
  tablet('Drawing tablet'),
  gamepad('Game controller'),
  microphone('Microphone'),
  camera('Camera'),
  other('Other');

  const InputDeviceKind(this.label);

  /// The row label this kind is drawn under.
  final String label;
}

/// One device the machine can be driven or recorded by.
///
/// Value equality is what lets the reader de-duplicate: a keyboard very often
/// appears in `/proc/bus/input/devices` two or three times, and a card listing
/// the same keyboard three times is reporting on the kernel's bookkeeping.
@immutable
class InputDevice {
  const InputDevice({required this.kind, required this.name});

  final InputDeviceKind kind;
  final String name;

  @override
  bool operator ==(Object other) =>
      other is InputDevice && other.kind == kind && other.name == name;

  @override
  int get hashCode => Object.hash(kind, name);

  @override
  String toString() => 'InputDevice(${kind.name}, $name)';
}

// The event-type bits of `B: EV=`, from linux/input-event-codes.h.
const int _evKey = 0x01;
const int _evRel = 0x02;
const int _evAbs = 0x03;

// The device-property bits of `B: PROP=`.
const int _propDirect = 0x01;
const int _propButtonpad = 0x02;
const int _propPointingStick = 0x05;

// The key and button codes of `B: KEY=` that decide what a device is.
const int _keyQ = 16;
const int _keyA = 30;
const int _keySpace = 57;
const int _btnLeft = 0x110;
const int _btnSouth = 0x130;
const int _btnToolPen = 0x140;
const int _btnToolFinger = 0x145;
const int _btnTouch = 0x14a;
const int _btnStylus = 0x14b;

bool _bit(BigInt mask, int index) => (mask >> index).isOdd;

/// Reads one of the `B:` bitmask lines out of `/proc/bus/input/devices`.
///
/// The kernel prints these as space-separated hex words, **most significant
/// first**, one word per `unsigned long` — so a word carries 64 bits whatever its
/// printed width, and the value is rebuilt by shifting a full word per field
/// rather than by digit count. A word that will not parse costs the whole mask,
/// because a partially rebuilt one has every remaining bit in the wrong place.
BigInt parseInputBitmask(String field) {
  var value = BigInt.zero;
  for (final word in field.trim().split(RegExp(r'\s+'))) {
    if (word.isEmpty) continue;
    final parsed = BigInt.tryParse(word, radix: 16);
    if (parsed == null || parsed.isNegative) return BigInt.zero;
    value = (value << 64) | parsed;
  }
  return value;
}

/// Decides what an evdev node is, from what it can *emit* rather than what it is
/// called.
///
/// Names are the tempting input and the wrong one: `HDA Intel PCH Mic` is a
/// jack-detection switch, `Video Bus` is a set of brightness keys, and half the
/// keyboards on sale describe themselves as a receiver. The capability bits are
/// what the kernel and libinput key on.
///
/// The order of the tests is load-bearing, because the sets overlap: a pen tablet
/// reports `BTN_TOOL_FINGER` as well as `BTN_TOOL_PEN`, a touchpad reports
/// `BTN_TOUCH` as well as `BTN_TOOL_FINGER`, and a gamepad reports absolute axes
/// like both. Each test comes before the one whose set contains it.
InputDeviceKind classifyEvdevDevice({
  required List<String> handlers,
  required BigInt evBits,
  required BigInt keyBits,
  required BigInt propBits,
}) {
  final hasKey = _bit(evBits, _evKey);
  final hasRel = _bit(evBits, _evRel);
  final hasAbs = _bit(evBits, _evAbs);

  if (handlers.any((h) => h.startsWith('js')) ||
      (hasKey && _bit(keyBits, _btnSouth))) {
    return InputDeviceKind.gamepad;
  }
  if (hasAbs &&
      hasKey &&
      (_bit(keyBits, _btnStylus) || _bit(keyBits, _btnToolPen))) {
    return InputDeviceKind.tablet;
  }
  if (hasAbs && hasKey && _bit(keyBits, _btnToolFinger)) {
    return InputDeviceKind.touchpad;
  }
  if (_bit(propBits, _propButtonpad)) return InputDeviceKind.touchpad;
  // A touchscreen is the ABS device left over: it reports a touch and no tool.
  // `INPUT_PROP_DIRECT` is the definitive signal and plenty of panels omit it,
  // so it is taken as confirmation rather than required.
  if (hasAbs && hasKey && _bit(keyBits, _btnTouch)) {
    return InputDeviceKind.touchscreen;
  }
  if (_bit(propBits, _propDirect) && hasAbs) return InputDeviceKind.touchscreen;
  if (_bit(propBits, _propPointingStick)) return InputDeviceKind.pointingStick;
  if (hasRel && hasKey && _bit(keyBits, _btnLeft)) return InputDeviceKind.mouse;
  // A keyboard is a device somebody can write a sentence on. Testing for a
  // letter, another letter and the space bar is what separates one from the
  // power button, the lid switch and the consumer-control node a keyboard
  // itself publishes alongside its key matrix — all of which carry `EV_KEY`
  // and a `kbd` handler and none of which is a keyboard.
  if (hasKey &&
      _bit(keyBits, _keyQ) &&
      _bit(keyBits, _keyA) &&
      _bit(keyBits, _keySpace)) {
    return InputDeviceKind.keyboard;
  }
  return InputDeviceKind.other;
}

/// Parses `/proc/bus/input/devices` into one [InputDevice] per node, classified
/// but not yet filtered.
///
/// Blocks are separated by a blank line and only four of a block's lines are
/// read; an unrecognised one is skipped rather than refused, because this file
/// grows fields between kernel releases. A block with no `N: Name=` produces
/// nothing: there would be nothing to draw.
List<InputDevice> parseProcInputDevices(String contents) {
  final devices = <InputDevice>[];

  var name = '';
  var handlers = const <String>[];
  var propBits = BigInt.zero;
  var evBits = BigInt.zero;
  var keyBits = BigInt.zero;

  void flush() {
    if (name.isNotEmpty) {
      devices.add(
        InputDevice(
          kind: classifyEvdevDevice(
            handlers: handlers,
            evBits: evBits,
            keyBits: keyBits,
            propBits: propBits,
          ),
          name: name,
        ),
      );
    }
    name = '';
    handlers = const <String>[];
    propBits = BigInt.zero;
    evBits = BigInt.zero;
    keyBits = BigInt.zero;
  }

  String? after(String line, String prefix) =>
      line.startsWith(prefix) ? line.substring(prefix.length).trim() : null;

  for (final raw in contents.split('\n')) {
    final line = raw.trim();
    if (line.isEmpty) {
      flush();
      continue;
    }

    final rawName = after(line, 'N: Name=');
    if (rawName != null) {
      var value = rawName;
      if (value.length >= 2 && value.startsWith('"') && value.endsWith('"')) {
        value = value.substring(1, value.length - 1);
      }
      name = value.trim();
      continue;
    }

    final rawHandlers = after(line, 'H: Handlers=');
    if (rawHandlers != null) {
      handlers = rawHandlers
          .split(RegExp(r'\s+'))
          .where((h) => h.isNotEmpty)
          .toList(growable: false);
      continue;
    }

    final rawProp = after(line, 'B: PROP=');
    if (rawProp != null) {
      propBits = parseInputBitmask(rawProp);
      continue;
    }

    final rawEv = after(line, 'B: EV=');
    if (rawEv != null) {
      evBits = parseInputBitmask(rawEv);
      continue;
    }

    final rawKey = after(line, 'B: KEY=');
    if (rawKey != null) keyBits = parseInputBitmask(rawKey);
  }
  flush();

  return devices;
}

/// Parses `/proc/asound/cards` into card index → the card's human-readable
/// name, which is the half of a microphone's name that says which piece of
/// hardware it belongs to.
Map<int, String> parseAlsaCardNames(String contents) {
  final names = <int, String>{};
  final header = RegExp(r'^\s*(\d+)\s*\[([^\]]*)\]\s*:\s*(.*)$');

  for (final line in contents.split('\n')) {
    final match = header.firstMatch(line);
    if (match == null) continue;
    final index = int.tryParse(match.group(1)!);
    if (index == null) continue;

    // The remainder reads "HDA-Intel - HDA Intel PCH": the driver, then the
    // name worth showing. A card whose line carries no driver prefix is taken
    // whole, and one with nothing after the brackets falls back to the short
    // id inside them.
    final rest = match.group(3)!.trim();
    final dash = rest.indexOf(' - ');
    final name = dash >= 0 ? rest.substring(dash + 3).trim() : rest;
    final shortId = match.group(2)!.trim();
    if (name.isNotEmpty) {
      names[index] = name;
    } else if (shortId.isNotEmpty) {
      names[index] = shortId;
    }
  }

  return names;
}

/// Parses `/proc/asound/pcm` into one [InputDeviceKind.microphone] per
/// capture-capable PCM.
///
/// ALSA rather than PulseAudio, for two reasons. This page reports the *machine*,
/// and a sound server's source list is the machine seen through whatever is
/// running — a monitor source is not a microphone, and a server that is not
/// running is not an absence of microphones. And the page reads once and starts
/// no service, which a `PulseClient` would end.
List<InputDevice> parseAlsaCaptureDevices(
  String contents,
  Map<int, String> cardNames,
) {
  final devices = <InputDevice>[];
  final header = RegExp(r'^\s*(\d+)-(\d+):\s*(.*)$');

  for (final line in contents.split('\n')) {
    final match = header.firstMatch(line);
    if (match == null) continue;

    // "00-00: ALC257 Analog : ALC257 Analog : playback 1 : capture 1" — the id,
    // the name, and one field per direction the device supports. No `capture`
    // field means it plays only, which is not an input.
    final fields = match
        .group(3)!
        .split(':')
        .map((f) => f.trim())
        .toList(growable: false);
    if (!fields.any((f) => f.startsWith('capture'))) continue;

    final pcmName = fields.length > 1 && fields[1].isNotEmpty
        ? fields[1]
        : (fields.isNotEmpty ? fields.first : '');
    final card = int.tryParse(match.group(1)!);
    final name = _joinAudioName(card == null ? null : cardNames[card], pcmName);
    if (name.isEmpty) continue;

    devices.add(InputDevice(kind: InputDeviceKind.microphone, name: name));
  }

  return devices;
}

/// Names a capture device by its card and its PCM, without saying the same word
/// twice: on the common laptop both are `HDA Intel PCH`-ish, and
/// "HDA Intel PCH — HDA Intel PCH" is the joining showing through.
String _joinAudioName(String? cardName, String pcmName) {
  final card = cardName?.trim() ?? '';
  final pcm = pcmName.trim();
  if (card.isEmpty) return pcm;
  if (pcm.isEmpty) return card;
  final lowerCard = card.toLowerCase();
  final lowerPcm = pcm.toLowerCase();
  if (lowerCard.contains(lowerPcm)) return card;
  if (lowerPcm.contains(lowerCard)) return pcm;
  return '$card — $pcm';
}

/// Gathers what the machine can be typed on, pointed with, spoken into and seen
/// through, from `/proc` and `/sys`.
///
/// The roots are constructor parameters — [ProcReader]'s shape — so tests point
/// them at a temp directory. Every read is best-effort and synchronous: four
/// small files and one directory listing, read once.
class InputDeviceReader {
  InputDeviceReader({this.procRoot = '/proc', this.sysRoot = '/sys'});

  final String procRoot;
  final String sysRoot;

  /// Every device this machine reports, in [InputDeviceKind] order.
  ///
  /// [InputDeviceKind.other] is dropped rather than listed. Nearly all of that
  /// set is kernel bookkeeping the user has no device for — the power and sleep
  /// buttons, the lid switch, the PC speaker, one jack-detection node per audio
  /// jack — and a list two thirds of which is bookkeeping is not a list of
  /// somebody's input devices. The cost is that an exotic device the classifier
  /// cannot place goes unlisted, which is the right way round.
  ///
  /// De-duplicated and ordered by kind, keeping discovery order within a kind so
  /// two keyboards stay in the order the kernel enumerated them.
  List<InputDevice> read() {
    final devices = <InputDevice>[
      ...parseProcInputDevices(
        readStringOrNull('$procRoot/bus/input/devices') ?? '',
      ).where((d) => d.kind != InputDeviceKind.other),
      ...parseAlsaCaptureDevices(
        readStringOrNull('$procRoot/asound/pcm') ?? '',
        parseAlsaCardNames(readStringOrNull('$procRoot/asound/cards') ?? ''),
      ),
      ..._cameras(),
    ];

    // `toSet()` is insertion-ordered, and `List.sort` is not stable, so the
    // discovery index is carried along as the tiebreaker.
    final unique = devices.toSet().toList();
    final ordered = List<int>.generate(unique.length, (i) => i)
      ..sort((a, b) {
        final byKind = unique[a].kind.index.compareTo(unique[b].kind.index);
        return byKind != 0 ? byKind : a.compareTo(b);
      });
    return [for (final i in ordered) unique[i]];
  }

  /// The V4L2 capture nodes, from `/sys/class/video4linux/*/name`.
  ///
  /// A camera publishes more than one node — a metadata node beside the video one
  /// — carrying the same `name`, so de-duplicating on the name turns two nodes
  /// back into one webcam. The listing is sorted, because a directory read is in
  /// no particular order and the card should not reshuffle between visits.
  List<InputDevice> _cameras() {
    var entries = const <FileSystemEntity>[];
    try {
      final dir = Directory('$sysRoot/class/video4linux');
      if (!dir.existsSync()) return const [];
      entries = dir.listSync()..sort((a, b) => a.path.compareTo(b.path));
    } catch (_) {
      return const [];
    }

    final cameras = <InputDevice>[];
    for (final entry in entries) {
      final name = readStringOrNull('${entry.path}/name')?.trim();
      if (name == null || name.isEmpty) continue;
      cameras.add(InputDevice(kind: InputDeviceKind.camera, name: name));
    }
    return cameras;
  }
}
