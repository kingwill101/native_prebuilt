import 'package:hooks/hooks.dart';
import 'package:logging/logging.dart';

import 'resolved_source.dart';

/// Compiles source code into a native library.
///
/// Implement this interface for each build system (Rust, CMake, Zig, etc.).
/// The builder receives a resolved source directory and must produce
/// a native library compatible with the hooks output.
abstract interface class SourceBuilder {
  /// Build the native library from [source].
  ///
  /// The builder should:
  /// 1. Compile the source in [source.directory].
  /// 2. Add the resulting [CodeAsset] to [output].
  Future<void> build({
    required ResolvedSource source,
    required BuildInput input,
    required BuildOutputBuilder output,
    required Logger? logger,
  });
}

/// A callback-based source builder for one-off build logic.
///
/// This is the simplest way to integrate a custom build step
/// without implementing the full [SourceBuilder] interface.
final class CallbackSourceBuilder implements SourceBuilder {
  const CallbackSourceBuilder({
    required this.callback,
  });

  final Future<void> Function({
    required ResolvedSource source,
    required BuildInput input,
    required BuildOutputBuilder output,
    required Logger? logger,
  }) callback;

  @override
  Future<void> build({
    required ResolvedSource source,
    required BuildInput input,
    required BuildOutputBuilder output,
    required Logger? logger,
  }) async {
    await callback(
      source: source,
      input: input,
      output: output,
      logger: logger,
    );
  }
}
