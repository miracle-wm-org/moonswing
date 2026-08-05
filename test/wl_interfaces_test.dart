import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:graceful_shell/wayland_ffi/wl_interfaces.dart';
import 'package:graceful_shell/wayland_ffi/wl_types.dart';
import 'package:xml/xml.dart';

/// Diffs the hand-transcribed `wl_interface` tables in `wl_interfaces.dart`
/// against the protocol XMLs in `protocol/`.
///
/// This is the load-bearing test for the FFI layer: libwayland trusts those
/// structs completely when it marshals requests and dispatches events, so a
/// wrong signature or a missing event is memory corruption, not an exception.
/// Everything here is derived from the XML the same way `wayland-scanner`
/// derives its C output.

/// The scanner's signature encoding: one char per argument, prefixed by the
/// `since` version when it is greater than 1, plus `?` for nullable args.
String _signatureOf(XmlElement message) {
  final since = message.getAttribute('since');
  final buffer = StringBuffer();
  if (since != null && since != '1') buffer.write(since);
  for (final arg in message.findElements('arg')) {
    if (arg.getAttribute('allow-null') == 'true') buffer.write('?');
    buffer.write(switch (arg.getAttribute('type')) {
      'int' => 'i',
      'uint' => 'u',
      'fixed' => 'f',
      'string' => 's',
      'object' => 'o',
      'new_id' => 'n',
      'array' => 'a',
      'fd' => 'h',
      final other => throw StateError('unknown arg type $other'),
    });
  }
  return buffer.toString();
}

class _Message {
  _Message(this.name, this.signature, this.types);
  final String name;
  final String signature;

  /// Interface name per argument, empty where the argument is untyped.
  final List<String> types;
}

class _Interface {
  _Interface(this.name, this.version, this.requests, this.events);
  final String name;
  final int version;
  final List<_Message> requests;
  final List<_Message> events;
}

Map<String, _Interface> _parseProtocol(File file) {
  final doc = XmlDocument.parse(file.readAsStringSync());
  final result = <String, _Interface>{};
  for (final iface in doc.findAllElements('interface')) {
    List<_Message> read(String tag) => [
          for (final m in iface.findElements(tag))
            _Message(
              m.getAttribute('name')!,
              _signatureOf(m),
              [
                for (final a in m.findElements('arg'))
                  a.getAttribute('interface') ?? '',
              ],
            ),
        ];
    final name = iface.getAttribute('name')!;
    result[name] = _Interface(
      name,
      int.parse(iface.getAttribute('version')!),
      read('request'),
      read('event'),
    );
  }
  return result;
}

/// Reads back what was actually written into the calloc'd C structs.
({
  String name,
  int version,
  List<_Message> requests,
  List<_Message> events,
}) _readNative(ffi.Pointer<WlInterface> ptr) {
  List<_Message> messages(ffi.Pointer<WlMessage> array, int count) {
    final out = <_Message>[];
    for (var i = 0; i < count; i++) {
      final m = array + i;
      final signature = m.ref.signature.toDartString();
      final argCount =
          signature.split('').where((c) => !'0123456789?'.contains(c)).length;
      final types = <String>[];
      for (var j = 0; j < argCount; j++) {
        final t = m.ref.types[j];
        types.add(t == ffi.nullptr ? '' : t.ref.name.toDartString());
      }
      out.add(_Message(m.ref.name.toDartString(), signature, types));
    }
    return out;
  }

  return (
    name: ptr.ref.name.toDartString(),
    version: ptr.ref.version,
    requests: messages(ptr.ref.methods, ptr.ref.methodCount),
    events: messages(ptr.ref.events, ptr.ref.eventCount),
  );
}

void main() {
  final protocolDir = Directory('protocol');

  void checkInterface(
    String protocolFile,
    String interfaceName,
    ffi.Pointer<WlInterface> Function() native,
  ) {
    test('$interfaceName matches $protocolFile', () {
      final file = File('${protocolDir.path}/$protocolFile');
      if (!file.existsSync()) {
        markTestSkipped('$protocolFile not present');
        return;
      }
      final expected = _parseProtocol(file)[interfaceName];
      expect(expected, isNotNull,
          reason: '$interfaceName missing from $protocolFile');

      final actual = _readNative(native());
      expect(actual.name, expected!.name);
      expect(actual.version, expected.version,
          reason: 'interface version must match the XML');

      for (final (label, want, got) in [
        ('request', expected.requests, actual.requests),
        ('event', expected.events, actual.events),
      ]) {
        expect(got.length, want.length,
            reason: '$interfaceName ${label}s: opcode count differs — '
                'got ${got.map((m) => m.name)}, '
                'want ${want.map((m) => m.name)}');
        for (var i = 0; i < want.length; i++) {
          // Order is the opcode, so a name mismatch means every later
          // request/event is being sent or dispatched as the wrong one.
          expect(got[i].name, want[i].name,
              reason: '$interfaceName $label opcode $i');
          expect(got[i].signature, want[i].signature,
              reason: '$interfaceName $label ${want[i].name} signature');
          expect(got[i].types, want[i].types,
              reason: '$interfaceName $label ${want[i].name} arg interfaces');
        }
      }
    });
  }

  group('ext-image-capture-source-v1', () {
    final ifaces = WlProtocolInterfaces.instance;
    const xml = 'ext-image-capture-source-v1.xml';
    checkInterface(xml, 'ext_image_capture_source_v1', () => ifaces.captureSource);
    checkInterface(xml, 'ext_output_image_capture_source_manager_v1',
        () => ifaces.outputSourceManager);
    checkInterface(xml, 'ext_foreign_toplevel_image_capture_source_manager_v1',
        () => ifaces.toplevelSourceManager);
  });

  group('ext-image-copy-capture-v1', () {
    final ifaces = WlProtocolInterfaces.instance;
    const xml = 'ext-image-copy-capture-v1.xml';
    checkInterface(
        xml, 'ext_image_copy_capture_manager_v1', () => ifaces.copyCaptureManager);
    checkInterface(
        xml, 'ext_image_copy_capture_session_v1', () => ifaces.copyCaptureSession);
    checkInterface(
        xml, 'ext_image_copy_capture_frame_v1', () => ifaces.copyCaptureFrame);
    checkInterface(xml, 'ext_image_copy_capture_cursor_session_v1',
        () => ifaces.copyCaptureCursorSession);
  });

  group('ext-foreign-toplevel-list-v1', () {
    final ifaces = WlProtocolInterfaces.instance;
    const xml = 'ext-foreign-toplevel-list-v1.xml';
    checkInterface(xml, 'ext_foreign_toplevel_list_v1', () => ifaces.toplevelList);
    checkInterface(
        xml, 'ext_foreign_toplevel_handle_v1', () => ifaces.toplevelHandle);
  });
}
