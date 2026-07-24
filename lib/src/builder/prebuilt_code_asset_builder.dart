import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:logging/logging.dart';

import '../manifest/prebuilt_manifest.dart';
import '../resolution/prebuilt_resolver.dart';
import '../source/source_fallback.dart';
import 'native_project_builder.dart';

/// A declarative [Builder] that resolves prebuilt native libraries from
/// GitHub Releases.
///
/// This is the primary public API for consuming packages. It implements
/// the full resolution chain:
///
/// 1. User-defined override via `hooks.user_defines`
/// 2. Local `.prebuilt/` directory
/// 3. Shared cache (download from release)
/// 4. Source fallback (local/git/archive → prepare → build)
///
/// Example usage in `hook/build.dart`:
///
/// ```dart
/// import 'package:hooks/hooks.dart';
/// import 'package:native_prebuilt/hooks.dart';
/// import 'package:my_package/src/hook/prebuilts.g.dart';
///
/// void main(List<String> args) async {
///   await build(args, (input, output) async {
///     await PrebuiltCodeAssetBuilder(
///       assetName: 'my_bindings_generated.dart',
///       libraryStem: 'my_native_lib',
///       manifest: myPrebuilts,
///       linkModeResolver: (code) => DynamicLoadingBundled(),
///       sourceFallback: SourceFallback(
///         sources: [LocalSource(paths: ['.'])],
///         builder: CallbackSourceBuilder(
///           callback: ({
///             required source,
///             required input,
///             required output,
///             required logger,
///           }) async {
///             // build from source.directory
///           },
///         ),
///       ),
///     ).run(input: input, output: output, logger: null);
///   });
/// }
/// ```
///
/// For new packages, consider using [NativeProjectBuilder] directly with
/// a [NativeProject] definition for a more declarative approach.
final class PrebuiltCodeAssetBuilder implements Builder {
  const PrebuiltCodeAssetBuilder({
    required this.assetName,
    required this.libraryStem,
    required this.manifest,
    required this.linkModeResolver,
    this.sourceFallback,
    this.localDirectoryName = '.prebuilt',
    this.resolvers,
  });

  /// The asset name passed to [CodeAsset].
  ///
  /// Example: `'portable_pty_bindings_generated.dart'`.
  final String assetName;

  /// The library stem without platform prefix or extension.
  ///
  /// Example: `'portable_pty_rs'` resolves to `libportable_pty_rs.so`.
  final String libraryStem;

  /// The prebuilt manifest containing release and artifact metadata.
  final PrebuiltManifest manifest;

  /// Returns the [LinkMode] to use for the current build configuration.
  final LinkMode Function(CodeConfig code) linkModeResolver;

  /// Optional source-based fallback when no prebuilt is available.
  ///
  /// When configured, this resolves source from local, archive, or git
  /// sources, applies preparation steps, and builds using the configured
  /// [SourceBuilder].
  final SourceFallback? sourceFallback;

  /// Directory name for local prebuilt overrides.
  ///
  /// Defaults to `.prebuilt`.
  final String localDirectoryName;

  /// Custom resolver chain. If `null`, uses the default chain:
  /// [UserDefinePrebuiltResolver], [LocalPrebuiltResolver],
  /// [SharedCacheResolver].
  final List<PrebuiltResolver>? resolvers;

  @override
  Future<void> run({
    required BuildInput input,
    required BuildOutputBuilder output,
    required Logger? logger,
  }) async {
    final code = input.config.code;
    if (!input.config.buildCodeAssets) {
      _logInfo(
        logger,
        'Skipping native_prebuilt: buildCodeAssets is disabled.',
      );
      return;
    }

    // Delegate to NativeProjectBuilder for the actual work.
    // This ensures both PrebuiltCodeAssetBuilder and NativeProjectBuilder
    // use the same resolution and build logic.
    final builder = NativeProjectBuilder.fromLegacy(
      assetName: assetName,
      libraryStem: libraryStem,
      manifest: manifest,
      linkMode: linkModeResolver(code),
      sourceFallback: sourceFallback,
      resolvers: resolvers,
      localDirectoryName: localDirectoryName,
    );

    await builder.run(input: input, output: output, logger: logger);
  }

  void _logInfo(Logger? logger, String message) {
    if (logger != null) {
      logger.info(message);
    } else {
      stdout.writeln(message);
    }
  }
}
