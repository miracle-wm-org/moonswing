import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:graceful_shell/system/input_devices.dart';

/// A fake `/proc` and `/sys` in a temp directory, so no test reads the real
/// machine's devices.
///
/// The `B:` bitmask fixtures are real dumps or built from
/// linux/input-event-codes.h, because they are the whole of the classifier's
/// input: a fixture with a plausible name and made-up bits would pass while
/// telling us nothing.
void main() {
  const keyboardBlock = '''
I: Bus=0011 Vendor=0001 Product=0001 Version=ab41
N: Name="AT Translated Set 2 keyboard"
P: Phys=isa0060/serio0/input0
S: Sysfs=/devices/platform/i8042/serio0/input/input3
U: Uniq=
H: Handlers=sysrq kbd event3 leds
B: PROP=0
B: EV=120013
B: KEY=402000000 3803078f800d001 feffffdfffefffff fffffffffffffffe
B: MSC=10
B: LED=7
''';

  const mouseBlock = '''
I: Bus=0003 Vendor=046d Product=c52b Version=0111
N: Name="Logitech USB Receiver Mouse"
P: Phys=usb-0000:00:14.0-1/input2:1
S: Sysfs=/devices/pci0000:00/0000:00:14.0/usb1/1-1/input/input8
U: Uniq=
H: Handlers=mouse1 event8
B: PROP=0
B: EV=17
B: KEY=ffff0000 0 0 0 0
B: REL=1943
B: MSC=10
''';

  const touchpadBlock = '''
I: Bus=0011 Vendor=0002 Product=0007 Version=01b1
N: Name="SynPS/2 Synaptics TouchPad"
P: Phys=isa0060/serio1/input0
S: Sysfs=/devices/platform/i8042/serio1/input/input6
U: Uniq=
H: Handlers=mouse0 event6
B: PROP=5
B: EV=b
B: KEY=6420 10000 0 0 0 0
B: ABS=260800011000003
''';

  const touchscreenBlock = '''
I: Bus=0018 Vendor=04f3 Product=2818 Version=0100
N: Name="ELAN Touchscreen"
P: Phys=i2c-ELAN0001:00
S: Sysfs=/devices/pci0000:00/i2c-9/i2c-ELAN0001:00/0018:04F3:2818.0001/input/input12
U: Uniq=
H: Handlers=event12
B: PROP=2
B: EV=b
B: KEY=400 0 0 0 0 0
B: ABS=2608000 1000003
''';

  const tabletBlock = '''
I: Bus=0003 Vendor=056a Product=033c Version=0110
N: Name="Wacom Intuos S Pen"
P: Phys=usb-0000:00:14.0-3/input0
S: Sysfs=/devices/pci0000:00/0000:00:14.0/usb1/1-3/input/input20
U: Uniq=
H: Handlers=mouse2 event20
B: PROP=1
B: EV=b
B: KEY=c03 0 0 0 0 0
B: ABS=10003
''';

  const gamepadBlock = '''
I: Bus=0003 Vendor=045e Product=028e Version=0114
N: Name="Microsoft X-Box 360 pad"
P: Phys=usb-0000:00:14.0-4/input0
S: Sysfs=/devices/pci0000:00/0000:00:14.0/usb1/1-4/input/input24
U: Uniq=
H: Handlers=js0 event24
B: PROP=0
B: EV=20000b
B: KEY=7cdb000000000000 0 0 0 0
B: ABS=3003f
B: FF=107030000 0
''';

  /// The three shapes that make up most of a real file and none of which the
  /// user owns as a device: the ACPI buttons, one jack-detection switch per
  /// audio jack (named "…Mic", which is why names are not classified on), and
  /// the PC speaker, which is an output.
  const noiseBlocks = '''
I: Bus=0019 Vendor=0000 Product=0001 Version=0000
N: Name="Power Button"
P: Phys=PNP0C0C/button/input0
S: Sysfs=/devices/LNXSYSTM:00/LNXSYBUS:00/PNP0C0C:00/input/input1
U: Uniq=
H: Handlers=kbd event1
B: PROP=0
B: EV=3
B: KEY=10000000000000 0

I: Bus=0000 Vendor=0000 Product=0000 Version=0000
N: Name="HDA Intel PCH Mic"
P: Phys=ALSA
S: Sysfs=/devices/pci0000:00/0000:00:1f.3/sound/card0/input14
U: Uniq=
H: Handlers=event14
B: PROP=0
B: EV=21
B: SW=10

I: Bus=0010 Vendor=001f Product=0001 Version=0100
N: Name="PC Speaker"
P: Phys=isa0061/input0
S: Sysfs=/devices/platform/pcspkr/input/input5
U: Uniq=
H: Handlers=kbd event5
B: PROP=0
B: EV=40001
B: SND=6
''';

  group('parseProcInputDevices', () {
    test('classifies each device from its capability bits', () {
      final devices = parseProcInputDevices(
        [
          keyboardBlock,
          mouseBlock,
          touchpadBlock,
          touchscreenBlock,
          tabletBlock,
          gamepadBlock,
        ].join('\n'),
      );

      expect(
        devices,
        containsAll(const [
          InputDevice(
            kind: InputDeviceKind.keyboard,
            name: 'AT Translated Set 2 keyboard',
          ),
          InputDevice(
            kind: InputDeviceKind.mouse,
            name: 'Logitech USB Receiver Mouse',
          ),
          InputDevice(
            kind: InputDeviceKind.touchpad,
            name: 'SynPS/2 Synaptics TouchPad',
          ),
          InputDevice(
            kind: InputDeviceKind.touchscreen,
            name: 'ELAN Touchscreen',
          ),
          InputDevice(
            kind: InputDeviceKind.tablet,
            name: 'Wacom Intuos S Pen',
          ),
          InputDevice(
            kind: InputDeviceKind.gamepad,
            name: 'Microsoft X-Box 360 pad',
          ),
        ]),
      );
      expect(devices, hasLength(6));
    });

    test('the kernel bookkeeping nodes classify as other', () {
      final devices = parseProcInputDevices(noiseBlocks);

      expect(devices.map((d) => d.name), [
        'Power Button',
        'HDA Intel PCH Mic',
        'PC Speaker',
      ]);
      expect(
        devices.every((d) => d.kind == InputDeviceKind.other),
        isTrue,
        reason: 'a jack-detection switch named "…Mic" is not a microphone',
      );
    });

    test('a block with no name produces nothing', () {
      expect(parseProcInputDevices('I: Bus=0011\nB: EV=120013\n'), isEmpty);
    });

    test('an empty file produces nothing', () {
      expect(parseProcInputDevices(''), isEmpty);
    });

    test('a block is not carried into the next one', () {
      // The second block declares the same event types as the mouse and no key
      // bitmask of its own. If the mouse's buttons leaked across the blank
      // line it would read as a second mouse.
      final devices = parseProcInputDevices(
        '$mouseBlock\n'
        'N: Name="Nameless Thing"\n'
        'H: Handlers=event30\n'
        'B: EV=17\n',
      );

      expect(devices, hasLength(2));
      expect(devices.first.kind, InputDeviceKind.mouse);
      expect(devices.last.kind, InputDeviceKind.other);
    });
  });

  group('parseInputBitmask', () {
    test('rebuilds one word per 64 bits, most significant first', () {
      // Two words: the low one carries bit 0, the high one bit 64.
      expect(parseInputBitmask('1 1'), BigInt.two.pow(64) + BigInt.one);
    });

    test('is unaffected by a word printed without leading zeroes', () {
      expect(parseInputBitmask('0 8000000000000000'), BigInt.two.pow(63));
    });

    test('an unparseable word costs the whole mask', () {
      expect(parseInputBitmask('nonsense 1'), BigInt.zero);
    });

    test('an empty field is zero', () {
      expect(parseInputBitmask(''), BigInt.zero);
    });
  });

  group('classifyEvdevDevice', () {
    InputDeviceKind classify({
      List<String> handlers = const [],
      String ev = '0',
      String key = '0',
      String prop = '0',
    }) {
      return classifyEvdevDevice(
        handlers: handlers,
        evBits: parseInputBitmask(ev),
        keyBits: parseInputBitmask(key),
        propBits: parseInputBitmask(prop),
      );
    }

    test('a gamepad is recognised by its buttons, without a js handler', () {
      expect(
        classify(ev: '20000b', key: '7cdb000000000000 0 0 0 0'),
        InputDeviceKind.gamepad,
      );
    });

    test('a js handler alone is enough', () {
      expect(classify(handlers: const ['js0', 'event3']),
          InputDeviceKind.gamepad);
    });

    test('a buttonpad with no tool button is still a touchpad', () {
      expect(classify(ev: 'b', prop: '4'), InputDeviceKind.touchpad);
    });

    test('a pointing stick is not a mouse', () {
      // TrackPoints report relative motion and buttons like any mouse; the
      // property bit is the only thing that separates them.
      expect(
        classify(ev: '17', key: 'ffff0000 0 0 0 0', prop: '20'),
        InputDeviceKind.pointingStick,
      );
    });

    test('a device with keys but no alphabet is not a keyboard', () {
      // KEY_POWER and nothing else — the ACPI button, which carries EV_KEY and
      // a `kbd` handler exactly like a keyboard does.
      expect(
        classify(handlers: const ['kbd', 'event1'], ev: '3',
            key: '10000000000000 0'),
        InputDeviceKind.other,
      );
    });

    test('a device that emits nothing is other', () {
      expect(classify(), InputDeviceKind.other);
    });
  });

  group('parseAlsaCardNames', () {
    const cards = '''
 0 [PCH            ]: HDA-Intel - HDA Intel PCH
                      HDA Intel PCH at 0xf7f10000 irq 145
 1 [C920           ]: USB-Audio - Logitech Webcam C920
                      Logitech Webcam C920 at usb-0000:00:14.0-2, high speed
''';

    test('takes the name after the driver', () {
      expect(parseAlsaCardNames(cards), {
        0: 'HDA Intel PCH',
        1: 'Logitech Webcam C920',
      });
    });

    test('falls back to the whole remainder when there is no driver', () {
      expect(parseAlsaCardNames(' 0 [Dummy ]: Dummy Card\n'), {
        0: 'Dummy Card',
      });
    });

    test('an empty file is an empty map', () {
      expect(parseAlsaCardNames(''), isEmpty);
    });
  });

  group('parseAlsaCaptureDevices', () {
    const pcm = '''
00-00: ALC257 Analog : ALC257 Analog : playback 1 : capture 1
00-03: HDMI 0 : HDMI 0 : playback 1
01-00: USB Audio : USB Audio : capture 1
''';

    test('lists the capture-capable PCMs and nothing else', () {
      final mics = parseAlsaCaptureDevices(pcm, const {
        0: 'HDA Intel PCH',
        1: 'Logitech Webcam C920',
      });

      expect(mics, const [
        InputDevice(
          kind: InputDeviceKind.microphone,
          name: 'HDA Intel PCH — ALC257 Analog',
        ),
        InputDevice(
          kind: InputDeviceKind.microphone,
          name: 'Logitech Webcam C920 — USB Audio',
        ),
      ]);
    });

    test('does not say the same name twice', () {
      expect(
        parseAlsaCaptureDevices(
          '00-00: HDA Intel PCH : HDA Intel PCH : capture 1\n',
          const {0: 'HDA Intel PCH'},
        ).single.name,
        'HDA Intel PCH',
      );
    });

    test('an unknown card leaves the PCM name alone', () {
      expect(
        parseAlsaCaptureDevices(
          '07-00: Some Mic : Some Mic : capture 1\n',
          const {},
        ).single.name,
        'Some Mic',
      );
    });

    test('a playback-only machine has no microphones', () {
      expect(
        parseAlsaCaptureDevices('00-03: HDMI 0 : HDMI 0 : playback 1\n', const {}),
        isEmpty,
      );
    });
  });

  group('InputDeviceReader.read', () {
    late Directory proc;
    late Directory sys;

    setUp(() {
      proc = Directory.systemTemp.createTempSync('input_devices_proc');
      sys = Directory.systemTemp.createTempSync('input_devices_sys');
    });

    tearDown(() {
      proc.deleteSync(recursive: true);
      sys.deleteSync(recursive: true);
    });

    void write(Directory root, String path, String contents) {
      final file = File('${root.path}/$path');
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(contents);
    }

    InputDeviceReader reader() =>
        InputDeviceReader(procRoot: proc.path, sysRoot: sys.path);

    test('gathers every source, ordered by kind, noise dropped', () {
      write(
        proc,
        'bus/input/devices',
        [mouseBlock, noiseBlocks, keyboardBlock, gamepadBlock].join('\n'),
      );
      write(proc, 'asound/cards',
          ' 0 [PCH            ]: HDA-Intel - HDA Intel PCH\n');
      write(proc, 'asound/pcm',
          '00-00: ALC257 Analog : ALC257 Analog : playback 1 : capture 1\n');
      write(sys, 'class/video4linux/video0/name', 'Integrated Camera\n');

      final devices = reader().read();

      expect(devices.map((d) => '${d.kind.name}:${d.name}'), [
        'keyboard:AT Translated Set 2 keyboard',
        'mouse:Logitech USB Receiver Mouse',
        'gamepad:Microsoft X-Box 360 pad',
        'microphone:HDA Intel PCH — ALC257 Analog',
        'camera:Integrated Camera',
      ]);
    });

    test('the same device reported twice is listed once', () {
      write(proc, 'bus/input/devices', [keyboardBlock, keyboardBlock].join('\n'));

      expect(reader().read(), hasLength(1));
    });

    test('two keyboards keep the order the kernel enumerated them', () {
      final second = keyboardBlock.replaceAll(
        'AT Translated Set 2 keyboard',
        'Keychron K2',
      );
      write(proc, 'bus/input/devices', [second, keyboardBlock].join('\n'));

      expect(
        reader().read().map((d) => d.name),
        ['Keychron K2', 'AT Translated Set 2 keyboard'],
      );
    });

    test("a camera's metadata node does not double it", () {
      write(sys, 'class/video4linux/video0/name', 'Integrated Camera\n');
      write(sys, 'class/video4linux/video1/name', 'Integrated Camera\n');

      expect(reader().read(), const [
        InputDevice(kind: InputDeviceKind.camera, name: 'Integrated Camera'),
      ]);
    });

    test('a machine that reports nothing is empty, not an error', () {
      expect(reader().read(), isEmpty);
    });
  });
}
