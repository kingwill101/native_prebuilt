import 'dart:async';

import '../source/resolved_source.dart';
import 'native_build_context.dart';
import 'native_build_result.dart';

/// Abstract interface for building native libraries from source code.
///
/// Implement this interface for each build system (CMake, Rust, Zig, etc.).
/// The builder receives a resolved source directory and must produce
/// a native library compatible with the hooks output.
abstract interface class NativeSourceBuilder {
  /// Build the native library from [source].
  ///
  /// The builder should:
  /// 1. Compile the source in [source.directory].
  /// 2. Return the built [NativeBuildResult] containing the artifacts.
  Future<NativeBuildResult> build(
    NativeBuildContext context,
    ResolvedSource source,
  );
}
