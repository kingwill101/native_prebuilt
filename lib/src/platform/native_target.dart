import 'package:code_assets/code_assets.dart';

/// Canonical representation of a native build target.
///
/// Uses the official `code_assets` platform types directly.
final class NativeTarget {
  const NativeTarget({
    required this.os,
    required this.architecture,
    this.iOSSdk,
  });

  /// The target operating system.
  final OS os;

  /// The target CPU architecture.
  final Architecture architecture;

  /// The iOS SDK, when targeting iOS.
  final IOSSdk? iOSSdk;

  /// A canonical platform label like `linux-x64`, `macos-arm64`,
  /// or `ios-sim-arm64`.
  String get label {
    if (os == OS.iOS && iOSSdk == IOSSdk.iPhoneSimulator) {
      return 'ios-sim-${architecture.name}';
    }
    return '${os.name}-${architecture.name}';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NativeTarget &&
          os == other.os &&
          architecture == other.architecture &&
          iOSSdk == other.iOSSdk;

  @override
  int get hashCode => Object.hash(os, architecture, iOSSdk);

  @override
  String toString() =>
      'NativeTarget($label'
      '${iOSSdk != null ? ', iOSSdk: $iOSSdk' : ''})';
}
