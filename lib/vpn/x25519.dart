// X25519 (RFC 7748), for WireGuard's keys.
//
// WireGuard's identities are Curve25519 key pairs, and the half a user has to
// hand to the server's administrator is the *public* key — which NetworkManager
// derives internally and never reports back. So the pane derives it itself, to
// show beside the private key, and generates a fresh private key for someone
// setting a tunnel up from scratch. `wg genkey` would do both, but it is a
// separate package (wireguard-tools) that a NetworkManager-only machine does
// not have, and the arithmetic is a page.
//
// BigInt is not constant-time. That is acceptable here: the one scalar ever
// multiplied is the user's own key, once, on their own machine, in a process
// nobody else can time.
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

final BigInt _p = (BigInt.one << 255) - BigInt.from(19);
final BigInt _a24 = BigInt.from(121665);
final BigInt _mask255 = (BigInt.one << 255) - BigInt.one;

BigInt _decodeLittleEndian(List<int> bytes) {
  var n = BigInt.zero;
  for (var i = bytes.length - 1; i >= 0; i--) {
    n = (n << 8) | BigInt.from(bytes[i]);
  }
  return n;
}

Uint8List _encodeLittleEndian(BigInt n) {
  final out = Uint8List(32);
  var v = n;
  final byte = BigInt.from(0xff);
  for (var i = 0; i < 32; i++) {
    out[i] = (v & byte).toInt();
    v >>= 8;
  }
  return out;
}

/// The scalar [k] clamped as RFC 7748 §5 says, without touching [k].
Uint8List clampScalar(List<int> k) {
  final out = Uint8List.fromList(k);
  out[0] &= 248;
  out[31] &= 127;
  out[31] |= 64;
  return out;
}

/// `X25519(k, u)`: the scalar multiplication of RFC 7748 §5. Both are 32 bytes.
Uint8List x25519(List<int> scalar, List<int> uCoordinate) {
  if (scalar.length != 32 || uCoordinate.length != 32) {
    throw ArgumentError('X25519 takes 32-byte inputs');
  }
  final k = _decodeLittleEndian(clampScalar(scalar));
  final x1 = _decodeLittleEndian(uCoordinate) & _mask255;
  var x2 = BigInt.one;
  var z2 = BigInt.zero;
  var x3 = x1;
  var z3 = BigInt.one;
  var swap = 0;
  for (var t = 254; t >= 0; t--) {
    final kt = ((k >> t) & BigInt.one).toInt();
    swap ^= kt;
    if (swap == 1) {
      final tx = x2;
      x2 = x3;
      x3 = tx;
      final tz = z2;
      z2 = z3;
      z3 = tz;
    }
    swap = kt;
    final a = (x2 + z2) % _p;
    final aa = (a * a) % _p;
    final b = (x2 - z2) % _p;
    final bb = (b * b) % _p;
    final e = (aa - bb) % _p;
    final c = (x3 + z3) % _p;
    final d = (x3 - z3) % _p;
    final da = (d * a) % _p;
    final cb = (c * b) % _p;
    final sum = (da + cb) % _p;
    final diff = (da - cb) % _p;
    x3 = (sum * sum) % _p;
    z3 = (x1 * diff * diff) % _p;
    x2 = (aa * bb) % _p;
    z2 = (e * (aa + _a24 * e)) % _p;
  }
  if (swap == 1) {
    x2 = x3;
    z2 = z3;
  }
  final result = (x2 * z2.modPow(_p - BigInt.two, _p)) % _p;
  return _encodeLittleEndian(result);
}

final Uint8List _basePoint = Uint8List(32)..[0] = 9;

/// The public key of a private one, both 32 raw bytes.
Uint8List x25519PublicKey(List<int> privateKey) =>
    x25519(privateKey, _basePoint);

/// A key decoded from WireGuard's base64, or null for anything that is not
/// exactly 32 bytes of it.
Uint8List? decodeWireGuardKey(String text) {
  final t = text.trim();
  // 32 bytes is always 44 characters with one `=` of padding.
  if (t.length != 44 || !t.endsWith('=')) return null;
  try {
    final bytes = base64.decode(t);
    return bytes.length == 32 ? bytes : null;
  } on FormatException {
    return null;
  }
}

/// Whether [text] is a WireGuard key at all.
bool isWireGuardKey(String text) => decodeWireGuardKey(text) != null;

/// The base64 public key for a base64 private key, or null when the private key
/// is not one.
String? wireGuardPublicKey(String privateKey) {
  final bytes = decodeWireGuardKey(privateKey);
  if (bytes == null) return null;
  return base64.encode(x25519PublicKey(bytes));
}

/// A new private key in WireGuard's base64 form, already clamped, as
/// `wg genkey` prints one.
String generateWireGuardPrivateKey({Random? random}) {
  final rng = random ?? Random.secure();
  final bytes = Uint8List(32);
  for (var i = 0; i < 32; i++) {
    bytes[i] = rng.nextInt(256);
  }
  return base64.encode(clampScalar(bytes));
}
