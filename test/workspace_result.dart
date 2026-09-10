import 'package:miracle/miracle.dart';

/// A `GET_WORKSPACES` entry, through `miracle.dart`'s own decoder.
///
/// Built from JSON rather than by calling the constructor, so a test that reads
/// one also fails when the reply shape stops being the one the library produces.
/// [policy] is left absent by default, which is what a miracle older than the
/// per-workspace policy sends.
WorkspaceResult workspaceResult({
  required int? num,
  String? name,
  String output = 'DP-1',
  bool focused = true,
  bool urgent = false,
  String? policy,
}) =>
    WorkspaceResult.fromJson({
      'num': num,
      'name': name,
      'visible': true,
      'focused': focused,
      'urgent': urgent,
      'output': output,
      'policy': ?policy,
      'rect': {'x': 0, 'y': 0, 'width': 1920, 'height': 1080},
    });

/// A `GET_OUTPUTS` entry, through `miracle.dart`'s own decoder, for the same
/// reason.
OutputResult outputResult({
  required String name,
  String make = 'Unknown',
  String model = 'Unknown',
  bool active = true,
  bool power = true,
}) =>
    OutputResult.fromJson({
      'name': name,
      'make': make,
      'model': model,
      'serial': 'Unknown',
      'active': active,
      'dpms': power,
      'power': power,
      'primary': false,
      'scale': 1.0,
      'current_workspace': '1',
      'modes': <Object>[],
      'rect': {'x': 0, 'y': 0, 'width': 1920, 'height': 1080},
    });
