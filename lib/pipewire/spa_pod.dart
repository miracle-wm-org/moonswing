import 'dart:typed_data';

import 'spa_constants.dart';

/// SPA pod builder/parser over plain byte buffers — no FFI, fully unit-testable.
///
/// Wire layout: every pod is a `{u32 size, u32 type}` header followed by `size`
/// body bytes; the next pod starts at the body rounded up to 8. An Object body is
/// `{u32 objectType, u32 objectId}` followed by properties, each
/// `{u32 key, u32 flags}` + a nested pod. A Choice body is
/// `{u32 choiceType, u32 flags}` + a child pod header + packed child values.
int _pad8(int n) => (n + 7) & ~7;

sealed class SpaValue {
  const SpaValue();

  /// (bodySize, type) of the value pod.
  (int, int) get header;

  void writeBody(ByteData b, int offset);
}

class SpaId extends SpaValue {
  const SpaId(this.value);
  final int value;

  @override
  (int, int) get header => (4, spaTypeId);

  @override
  void writeBody(ByteData b, int offset) =>
      b.setUint32(offset, value, Endian.little);
}

class SpaInt extends SpaValue {
  const SpaInt(this.value);
  final int value;

  @override
  (int, int) get header => (4, spaTypeInt);

  @override
  void writeBody(ByteData b, int offset) =>
      b.setInt32(offset, value, Endian.little);
}

class SpaRectangle extends SpaValue {
  const SpaRectangle(this.width, this.height);
  final int width;
  final int height;

  @override
  (int, int) get header => (8, spaTypeRectangle);

  @override
  void writeBody(ByteData b, int offset) {
    b.setUint32(offset, width, Endian.little);
    b.setUint32(offset + 4, height, Endian.little);
  }
}

class SpaFraction extends SpaValue {
  const SpaFraction(this.num, this.denom);
  final int num;
  final int denom;

  @override
  (int, int) get header => (8, spaTypeFraction);

  @override
  void writeBody(ByteData b, int offset) {
    b.setUint32(offset, num, Endian.little);
    b.setUint32(offset + 4, denom, Endian.little);
  }
}

/// A choice pod: `{choiceType, flags}` + child header + values packed at the
/// child body size (no per-value padding; the whole pod pads at the end).
class SpaChoice extends SpaValue {
  const SpaChoice(this.choiceType, this.values);

  SpaChoice.range(SpaValue def, SpaValue min, SpaValue max)
      : this(spaChoiceRange, [def, min, max]);

  /// `SPA_POD_CHOICE_FLAGS_*` builds a Flags choice with the single value.
  SpaChoice.flags(SpaValue flagsValue) : this(spaChoiceFlags, [flagsValue]);

  final int choiceType;
  final List<SpaValue> values;

  @override
  (int, int) get header {
    final (childSize, _) = values.first.header;
    return (8 + 8 + childSize * values.length, spaTypeChoice);
  }

  @override
  void writeBody(ByteData b, int offset) {
    final (childSize, childType) = values.first.header;
    b.setUint32(offset, choiceType, Endian.little);
    b.setUint32(offset + 4, 0, Endian.little); // flags
    b.setUint32(offset + 8, childSize, Endian.little);
    b.setUint32(offset + 12, childType, Endian.little);
    var o = offset + 16;
    for (final v in values) {
      v.writeBody(b, o);
      o += childSize;
    }
  }
}

class SpaProp {
  const SpaProp(this.key, this.value);
  final int key;
  final SpaValue value;
}

/// Serializes one object pod (the only top-level shape the stream needs:
/// EnumFormat, Format, Buffers params).
Uint8List buildSpaObject(int objectType, int objectId, List<SpaProp> props) {
  var bodySize = 8; // objectType + objectId
  for (final p in props) {
    final (valueBody, _) = p.value.header;
    bodySize += 8 + 8 + _pad8(valueBody); // key/flags + value header + body
  }

  final bytes = Uint8List(8 + _pad8(bodySize));
  final b = ByteData.view(bytes.buffer);
  b.setUint32(0, bodySize, Endian.little);
  b.setUint32(4, spaTypeObject, Endian.little);
  b.setUint32(8, objectType, Endian.little);
  b.setUint32(12, objectId, Endian.little);

  var o = 16;
  for (final p in props) {
    final (valueBody, valueType) = p.value.header;
    b.setUint32(o, p.key, Endian.little);
    b.setUint32(o + 4, 0, Endian.little); // flags
    b.setUint32(o + 8, valueBody, Endian.little);
    b.setUint32(o + 12, valueType, Endian.little);
    p.value.writeBody(b, o + 16);
    o += 16 + _pad8(valueBody);
  }
  return bytes;
}

/// The video format parameters negotiated in a `Format` param.
class SpaVideoFormat {
  const SpaVideoFormat({
    required this.format,
    required this.width,
    required this.height,
    required this.framerateNum,
    required this.framerateDenom,
  });

  final int format;
  final int width;
  final int height;
  final int framerateNum;
  final int framerateDenom;

  @override
  String toString() =>
      'SpaVideoFormat(format=$format ${width}x$height @$framerateNum/$framerateDenom)';
}

/// Parses a Format object pod (from `param_changed`). Returns null if the
/// pod isn't a video/raw format object. Fixed values may still arrive
/// wrapped in a Choice — the first (default) value is taken.
SpaVideoFormat? parseSpaFormat(Uint8List bytes) {
  if (bytes.length < 16) return null;
  final b = ByteData.view(bytes.buffer, bytes.offsetInBytes, bytes.length);
  final bodySize = b.getUint32(0, Endian.little);
  final type = b.getUint32(4, Endian.little);
  if (type != spaTypeObject || bytes.length < 8 + bodySize) return null;
  if (b.getUint32(8, Endian.little) != spaTypeObjectFormat) return null;

  int? format;
  int? width;
  int? height;
  var framerateNum = 0;
  var framerateDenom = 1;
  int? mediaType;
  int? mediaSubtype;

  var o = 16;
  final end = 8 + bodySize;
  while (o + 16 <= end) {
    final key = b.getUint32(o, Endian.little);
    var valueSize = b.getUint32(o + 8, Endian.little);
    var valueType = b.getUint32(o + 12, Endian.little);
    var valueOffset = o + 16;

    // Unwrap a Choice: skip {choiceType, flags} + child header, take the
    // first (default) child value.
    if (valueType == spaTypeChoice && valueSize >= 16) {
      valueSize = b.getUint32(valueOffset + 8, Endian.little);
      valueType = b.getUint32(valueOffset + 12, Endian.little);
      valueOffset += 16;
    }

    switch (key) {
      case spaFormatMediaType:
        mediaType = b.getUint32(valueOffset, Endian.little);
      case spaFormatMediaSubtype:
        mediaSubtype = b.getUint32(valueOffset, Endian.little);
      case spaFormatVideoFormat:
        format = b.getUint32(valueOffset, Endian.little);
      case spaFormatVideoSize:
        width = b.getUint32(valueOffset, Endian.little);
        height = b.getUint32(valueOffset + 4, Endian.little);
      case spaFormatVideoFramerate:
        framerateNum = b.getUint32(valueOffset, Endian.little);
        framerateDenom = b.getUint32(valueOffset + 4, Endian.little);
    }

    final rawSize = b.getUint32(o + 8, Endian.little);
    o += 16 + _pad8(rawSize);
  }

  if (mediaType != spaMediaTypeVideo ||
      mediaSubtype != spaMediaSubtypeRaw ||
      format == null ||
      width == null ||
      height == null) {
    return null;
  }
  return SpaVideoFormat(
    format: format,
    width: width,
    height: height,
    framerateNum: framerateNum,
    framerateDenom: framerateDenom == 0 ? 1 : framerateDenom,
  );
}

/// The `EnumFormat` param advertised on stream connect: one fixed
/// format/size, variable framerate up to [maxFrameRate].
Uint8List buildVideoEnumFormat({
  required int videoFormat,
  required int width,
  required int height,
  required int maxFrameRate,
}) {
  final maxFps = maxFrameRate < 1 ? 60 : maxFrameRate;
  return buildSpaObject(spaTypeObjectFormat, spaParamEnumFormat, [
    const SpaProp(spaFormatMediaType, SpaId(spaMediaTypeVideo)),
    const SpaProp(spaFormatMediaSubtype, SpaId(spaMediaSubtypeRaw)),
    SpaProp(spaFormatVideoFormat, SpaId(videoFormat)),
    SpaProp(spaFormatVideoSize, SpaRectangle(width, height)),
    // Variable framerate (0/1): frames arrive when the screen changes.
    const SpaProp(spaFormatVideoFramerate, SpaFraction(0, 1)),
    SpaProp(
      spaFormatVideoMaxFramerate,
      SpaChoice.range(
        SpaFraction(maxFps, 1),
        const SpaFraction(1, 1),
        SpaFraction(maxFps, 1),
      ),
    ),
  ]);
}

/// The `Buffers` param answered to `param_changed(Format)`.
Uint8List buildVideoBuffers({
  required int width,
  required int height,
}) {
  final stride = width * 4;
  return buildSpaObject(spaTypeObjectParamBuffers, spaParamBuffers, [
    const SpaProp(
      spaParamBuffersBuffers,
      SpaChoice(spaChoiceRange, [SpaInt(4), SpaInt(2), SpaInt(8)]),
    ),
    const SpaProp(spaParamBuffersBlocks, SpaInt(1)),
    SpaProp(spaParamBuffersSize, SpaInt(stride * height)),
    SpaProp(spaParamBuffersStride, SpaInt(stride)),
    const SpaProp(spaParamBuffersAlign, SpaInt(16)),
    const SpaProp(
      spaParamBuffersDataType,
      SpaChoice(spaChoiceFlags, [SpaInt(1 << spaDataMemFd)]),
    ),
  ]);
}

/// The `Meta` param that gives every buffer a cursor: `spa_meta_cursor`, then
/// a `spa_meta_bitmap`, then the image. Sized for a cursor up to
/// [kCursorMetaMaxSide] square, as GNOME's is — a cursor theme at size 48 on a
/// scale-2 output is already 96 pixels, and an image that does not fit is
/// still sent as a position.
Uint8List buildCursorMeta() =>
    buildSpaObject(spaTypeObjectParamMeta, spaParamMeta, [
      const SpaProp(spaParamMetaType, SpaId(spaMetaCursor)),
      SpaProp(
        spaParamMetaSize,
        SpaChoice.range(
          SpaInt(cursorMetaSize(kCursorMetaMaxSide, kCursorMetaMaxSide)),
          SpaInt(cursorMetaSize(1, 1)),
          SpaInt(cursorMetaSize(kCursorMetaMaxSide, kCursorMetaMaxSide)),
        ),
      ),
    ]);

/// The largest cursor image the meta is sized for, per side.
const int kCursorMetaMaxSide = 384;

/// `sizeof(struct spa_meta_cursor)`: id, flags, position, hotspot,
/// bitmap_offset — seven 32-bit fields.
const int kSpaMetaCursorSize = 28;

/// `sizeof(struct spa_meta_bitmap)`: format, size, stride, offset.
const int kSpaMetaBitmapSize = 20;

int cursorMetaSize(int width, int height) =>
    kSpaMetaCursorSize + kSpaMetaBitmapSize + width * height * 4;

/// Fills one buffer's cursor meta ([target] is the whole `spa_meta.data`
/// region). A hidden cursor is `id` 0, which is how `spa_meta_cursor_is_valid`
/// reads "no cursor on this stream right now". The image goes in when it fits
/// and is sent on every buffer rather than only when it changes: a consumer
/// that joins late, or drops a buffer, would otherwise be left without one,
/// and at cursor sizes the copy is noise.
///
/// [image] is ARGB8888 in `wl_shm` byte order, which is SPA's BGRA.
void writeCursorMeta(
  Uint8List target, {
  required bool visible,
  required int x,
  required int y,
  required int hotspotX,
  required int hotspotY,
  Uint8List? image,
  int imageWidth = 0,
  int imageHeight = 0,
}) {
  if (target.length < kSpaMetaCursorSize) return;
  final b = ByteData.view(
      target.buffer, target.offsetInBytes, kSpaMetaCursorSize);
  b.setUint32(0, visible ? 1 : 0, Endian.little); // id
  b.setUint32(4, 0, Endian.little); // flags
  b.setInt32(8, x, Endian.little);
  b.setInt32(12, y, Endian.little);
  b.setInt32(16, hotspotX, Endian.little);
  b.setInt32(20, hotspotY, Endian.little);

  final imageBytes = imageWidth * imageHeight * 4;
  final fits = visible &&
      image != null &&
      imageWidth > 0 &&
      imageHeight > 0 &&
      image.length >= imageBytes &&
      target.length >= cursorMetaSize(imageWidth, imageHeight);
  // bitmap_offset 0 is "no bitmap in this buffer": the consumer keeps the
  // image it last had.
  b.setUint32(24, fits ? kSpaMetaCursorSize : 0, Endian.little);
  if (!fits) return;

  final bitmap = ByteData.view(target.buffer,
      target.offsetInBytes + kSpaMetaCursorSize, kSpaMetaBitmapSize);
  bitmap.setUint32(0, spaVideoFormatBGRA, Endian.little);
  bitmap.setUint32(4, imageWidth, Endian.little);
  bitmap.setUint32(8, imageHeight, Endian.little);
  bitmap.setInt32(12, imageWidth * 4, Endian.little); // stride
  bitmap.setUint32(16, kSpaMetaBitmapSize, Endian.little); // offset
  target.setRange(kSpaMetaCursorSize + kSpaMetaBitmapSize,
      kSpaMetaCursorSize + kSpaMetaBitmapSize + imageBytes, image);
}

/// Maps a negotiated `wl_shm` capture format to the SPA video format with the
/// identical little-endian byte layout.
int? spaVideoFormatForShm(int shmFormat) => switch (shmFormat) {
      1 => spaVideoFormatBGRx, // XRGB8888
      0 => spaVideoFormatBGRA, // ARGB8888
      0x34324258 => spaVideoFormatRGBx, // XBGR8888
      0x34324241 => spaVideoFormatRGBA, // ABGR8888
      _ => null,
    };
