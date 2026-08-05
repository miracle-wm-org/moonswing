import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:graceful_shell/pipewire/spa_constants.dart';
import 'package:graceful_shell/pipewire/spa_pod.dart';

/// Reads the pods back the way PipeWire's own parser does, so a builder that
/// drifts from the wire layout fails here rather than as a silent
/// negotiation failure at runtime.
({int type, int objectType, int objectId, Map<int, (int, int, int)> props})
    _walkObject(Uint8List bytes) {
  final b = ByteData.view(bytes.buffer, bytes.offsetInBytes, bytes.length);
  final bodySize = b.getUint32(0, Endian.little);
  final type = b.getUint32(4, Endian.little);
  final objectType = b.getUint32(8, Endian.little);
  final objectId = b.getUint32(12, Endian.little);

  // key -> (valueType, valueSize, valueOffset)
  final props = <int, (int, int, int)>{};
  var o = 16;
  while (o + 16 <= 8 + bodySize) {
    final key = b.getUint32(o, Endian.little);
    final size = b.getUint32(o + 8, Endian.little);
    final valueType = b.getUint32(o + 12, Endian.little);
    props[key] = (valueType, size, o + 16);
    o += 16 + ((size + 7) & ~7);
  }
  return (type: type, objectType: objectType, objectId: objectId, props: props);
}

void main() {
  group('pod framing', () {
    test('an object pod is 8-byte aligned and self-describing', () {
      final pod = buildVideoEnumFormat(
          videoFormat: spaVideoFormatBGRx,
          width: 1920,
          height: 1080,
          maxFrameRate: 60);

      expect(pod.length % 8, 0, reason: 'pods pad to 8 bytes');
      final b = ByteData.view(pod.buffer);
      // The declared body size must account for every byte but the header,
      // modulo the trailing pad.
      final bodySize = b.getUint32(0, Endian.little);
      expect(pod.length, 8 + ((bodySize + 7) & ~7));

      final parsed = _walkObject(pod);
      expect(parsed.type, spaTypeObject);
      expect(parsed.objectType, spaTypeObjectFormat);
      expect(parsed.objectId, spaParamEnumFormat);
    });
  });

  group('EnumFormat', () {
    final pod = buildVideoEnumFormat(
        videoFormat: spaVideoFormatBGRA,
        width: 1280,
        height: 1011,
        maxFrameRate: 60);
    final parsed = _walkObject(pod);
    final b = ByteData.view(pod.buffer);

    test('declares video/raw', () {
      final (mediaType, _, mtOffset) = parsed.props[spaFormatMediaType]!;
      expect(mediaType, spaTypeId);
      expect(b.getUint32(mtOffset, Endian.little), spaMediaTypeVideo);

      final (subType, _, stOffset) = parsed.props[spaFormatMediaSubtype]!;
      expect(subType, spaTypeId);
      expect(b.getUint32(stOffset, Endian.little), spaMediaSubtypeRaw);
    });

    test('carries the format and a fixed size rectangle', () {
      final (fmtType, _, fmtOffset) = parsed.props[spaFormatVideoFormat]!;
      expect(fmtType, spaTypeId);
      expect(b.getUint32(fmtOffset, Endian.little), spaVideoFormatBGRA);

      final (sizeType, sizeBytes, sizeOffset) =
          parsed.props[spaFormatVideoSize]!;
      expect(sizeType, spaTypeRectangle);
      expect(sizeBytes, 8);
      expect(b.getUint32(sizeOffset, Endian.little), 1280);
      expect(b.getUint32(sizeOffset + 4, Endian.little), 1011);
    });

    test('framerate is variable, maxFramerate is a range choice', () {
      // 0/1 means "driven by content changes" — the compositor only produces
      // a frame when the screen actually changed.
      final (frType, _, frOffset) = parsed.props[spaFormatVideoFramerate]!;
      expect(frType, spaTypeFraction);
      expect(b.getUint32(frOffset, Endian.little), 0);
      expect(b.getUint32(frOffset + 4, Endian.little), 1);

      final (maxType, _, maxOffset) =
          parsed.props[spaFormatVideoMaxFramerate]!;
      expect(maxType, spaTypeChoice);
      expect(b.getUint32(maxOffset, Endian.little), spaChoiceRange);
      // Choice body: {choiceType, flags}, child header, then default/min/max.
      final childSize = b.getUint32(maxOffset + 8, Endian.little);
      final childType = b.getUint32(maxOffset + 12, Endian.little);
      expect(childType, spaTypeFraction);
      expect(childSize, 8);
      final values = maxOffset + 16;
      expect(b.getUint32(values, Endian.little), 60); // default
      expect(b.getUint32(values + childSize, Endian.little), 1); // min
      expect(b.getUint32(values + childSize * 2, Endian.little), 60); // max
    });

    test('an absurd frame rate cap falls back rather than emitting 0/1 max',
        () {
      final zeroCap = buildVideoEnumFormat(
          videoFormat: spaVideoFormatBGRx,
          width: 640,
          height: 480,
          maxFrameRate: 0);
      final p = _walkObject(zeroCap);
      final view = ByteData.view(zeroCap.buffer);
      final (_, _, offset) = p.props[spaFormatVideoMaxFramerate]!;
      expect(view.getUint32(offset + 16, Endian.little), 60);
    });
  });

  group('Buffers', () {
    final pod = buildVideoBuffers(width: 800, height: 600);
    final parsed = _walkObject(pod);
    final b = ByteData.view(pod.buffer);

    test('is a ParamBuffers object', () {
      expect(parsed.objectType, spaTypeObjectParamBuffers);
      expect(parsed.objectId, spaParamBuffers);
    });

    test('size and stride match a 4-byte-per-pixel image', () {
      final (_, _, sizeOffset) = parsed.props[spaParamBuffersSize]!;
      expect(b.getInt32(sizeOffset, Endian.little), 800 * 600 * 4);
      final (_, _, strideOffset) = parsed.props[spaParamBuffersStride]!;
      expect(b.getInt32(strideOffset, Endian.little), 800 * 4);
      final (_, _, blocksOffset) = parsed.props[spaParamBuffersBlocks]!;
      expect(b.getInt32(blocksOffset, Endian.little), 1);
    });

    test('asks for MemFd data as a flags choice', () {
      final (type, _, offset) = parsed.props[spaParamBuffersDataType]!;
      expect(type, spaTypeChoice);
      expect(b.getUint32(offset, Endian.little), spaChoiceFlags);
      expect(b.getInt32(offset + 16, Endian.little), 1 << spaDataMemFd);
    });
  });

  group('parseSpaFormat', () {
    test('reads back a fixed format object', () {
      final pod = buildSpaObject(spaTypeObjectFormat, spaParamFormat, const [
        SpaProp(spaFormatMediaType, SpaId(spaMediaTypeVideo)),
        SpaProp(spaFormatMediaSubtype, SpaId(spaMediaSubtypeRaw)),
        SpaProp(spaFormatVideoFormat, SpaId(spaVideoFormatBGRx)),
        SpaProp(spaFormatVideoSize, SpaRectangle(3840, 2160)),
        SpaProp(spaFormatVideoFramerate, SpaFraction(30, 1)),
      ]);

      final parsed = parseSpaFormat(pod);
      expect(parsed, isNotNull);
      expect(parsed!.format, spaVideoFormatBGRx);
      expect(parsed.width, 3840);
      expect(parsed.height, 2160);
      expect(parsed.framerateNum, 30);
      expect(parsed.framerateDenom, 1);
    });

    test('unwraps choice-wrapped values, as PipeWire may send them', () {
      final pod = buildSpaObject(spaTypeObjectFormat, spaParamFormat, const [
        SpaProp(spaFormatMediaType, SpaId(spaMediaTypeVideo)),
        SpaProp(spaFormatMediaSubtype, SpaId(spaMediaSubtypeRaw)),
        SpaProp(spaFormatVideoFormat,
            SpaChoice(spaChoiceNone, [SpaId(spaVideoFormatBGRA)])),
        SpaProp(spaFormatVideoSize,
            SpaChoice(spaChoiceNone, [SpaRectangle(1024, 768)])),
      ]);

      final parsed = parseSpaFormat(pod);
      expect(parsed, isNotNull);
      expect(parsed!.format, spaVideoFormatBGRA);
      expect(parsed.width, 1024);
      expect(parsed.height, 768);
      // Absent framerate defaults to 0/1 rather than dividing by zero.
      expect(parsed.framerateNum, 0);
      expect(parsed.framerateDenom, 1);
    });

    test('rejects a non-video object rather than guessing', () {
      final audio = buildSpaObject(spaTypeObjectFormat, spaParamFormat, const [
        SpaProp(spaFormatMediaType, SpaId(1)), // audio
        SpaProp(spaFormatMediaSubtype, SpaId(spaMediaSubtypeRaw)),
      ]);
      expect(parseSpaFormat(audio), isNull);
      expect(parseSpaFormat(Uint8List(0)), isNull);
      expect(parseSpaFormat(Uint8List(12)), isNull);
    });
  });

  group('spaVideoFormatForShm', () {
    test('maps the wl_shm formats the capture path negotiates', () {
      // XRGB8888/ARGB8888 are byte-identical to BGRx/BGRA little-endian,
      // which is what makes the frame path a straight memcpy.
      expect(spaVideoFormatForShm(1), spaVideoFormatBGRx);
      expect(spaVideoFormatForShm(0), spaVideoFormatBGRA);
      expect(spaVideoFormatForShm(0x34324258), spaVideoFormatRGBx);
      expect(spaVideoFormatForShm(0x34324241), spaVideoFormatRGBA);
    });

    test('returns null for a format with no SPA equivalent', () {
      expect(spaVideoFormatForShm(0x3132564e), isNull); // NV12
    });
  });
}
