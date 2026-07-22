import 'package:hooks/hooks.dart';
import 'package:logging/logging.dart';

/// A [Builder] that delegates to a callback function.
///
/// Use this to wrap package-specific source build logic (Zig, CMake, etc.)
/// as a [Builder] that can be passed as the `fallback` to
/// [PrebuiltCodeAssetBuilder].
///
/// Example:
///
/// ```dart
/// await PrebuiltCodeAssetBuilder(
///   assetName: 'my_bindings.dart',
///   libraryStem: 'my_lib',
///   manifest: myManifest,
///   linkModeResolver: (code) => DynamicLoadingBundled(),
///   fallback: CallbackBuilder((input, output) async {
///     // Custom Zig/CMake build logic here
///     await _buildFromSource(input, output);
///   }),
/// ).run(input: input, output: output, logger: null);
/// ```
final class CallbackBuilder implements Builder {
  const CallbackBuilder(this.callback);

  /// The build callback to invoke.
  final BuildCallback callback;

  @override
  Future<void> run({
    required BuildInput input,
    required BuildOutputBuilder output,
    required Logger? logger,
  }) {
    return callback(input, output);
  }
}

/// The signature of a build callback.
typedef BuildCallback = Future<void> Function(
  BuildInput input,
  BuildOutputBuilder output,
);
