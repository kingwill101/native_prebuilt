import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;

import '../binary/library_name.dart';
import '../manifest/prebuilt_artifact.dart';
import '../manifest/prebuilt_manifest.dart';
import '../platform/target_resolver.dart';
import '../resolution/prebuilt_resolver.dart';
import '../resolution/resolution_result.dart';
import '../source/source_fallback.dart';

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
/// 5. Fallback to source [Builder] (e.g. `RustBuilder`, `CallbackBuilder`)
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
///       fallback: const RustBuilder(
///         assetName: 'my_bindings_generated.dart',
///       ),
///     ).run(input: input, output: output, logger: null);
///   });
/// }
/// ```
final class PrebuiltCodeAssetBuilder implements Builder {
  const PrebuiltCodeAssetBuilder({
    required this.assetName,
    required this.libraryStem,
    required this.manifest,
    required this.linkModeResolver,
    this.fallback,
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

  /// Optional fallback [Builder] invoked if no prebuilt is found
  /// and no [sourceFallback] is configured.
  ///
  /// This could be `RustBuilder`, `CallbackBuilder`, or any other
  /// [Builder] implementation.
  final Builder? fallback;

  /// Optional source-based fallback when no prebuilt is available.
  ///
  /// When configured, this runs before [fallback]. It resolves source
  /// from local, archive, or git sources, applies preparation steps,
  /// and builds using the configured [SourceBuilder].
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
    if (!input.config.buildCodeAssets) return;

    final target = targetFromCodeConfig(code);
    final linkMode = linkModeResolver(code);
    final payload = _payloadForLinkMode(linkMode);

    final context = PrebuiltResolutionContext(
      input: input,
      manifest: manifest,
      target: target,
      libraryStem: libraryStem,
      payload: payload,
      localSearchRoot: Directory.fromUri(input.outputDirectory),
    );

    final chain = resolvers ?? [
      UserDefinePrebuiltResolver(),
      LocalPrebuiltResolver(directoryName: localDirectoryName),
      SharedCacheResolver(),
    ];

    ResolvedPrebuilt? result;
    for (final resolver in chain) {
      result = await resolver.resolve(context);
      if (result != null) break;
    }

    if (result is ResolvedPrebuiltFound) {
      final libraryName = canonicalLibraryName(
        target: target,
        libraryStem: libraryStem,
        payload: payload,
      );
      final bundledLibUri = input.outputDirectory.resolve(libraryName);

      await File(result.file.path).copy(
        File.fromUri(bundledLibUri).path,
      );

      output.assets.code.add(CodeAsset(
        package: input.packageName,
        name: assetName,
        linkMode: linkMode,
        file: bundledLibUri,
      ));

      _info(
        'Using prebuilt $libraryStem for ${target.label} '
        '(from ${result.source.label})',
      );
      return;
    }

    // Fall through to source fallback.
    if (sourceFallback != null) {
      _info(
        'No prebuilt available for ${target.label}, '
        'attempting source fallback.',
      );

      try {
        final sourceResult = await SourceFallbackResolver().resolve(
          fallback: sourceFallback!,
          packageRoot: Directory.fromUri(input.packageRoot),
          sourceCacheRoot: Directory(
            p.join(input.outputDirectoryShared.toFilePath(), 'native_prebuilt', 'sources'),
          ),
          input: input,
          output: output,
          logger: logger,
        );

        if (sourceResult != null) {
          _info(
            'Source build completed for ${target.label} '
            '(from ${sourceResult.source.origin.label})',
          );
          return;
        }
      } catch (e) {
        _warn('Source fallback failed: $e');
      }
    }

    // Fall through to legacy fallback builder.
    if (fallback != null) {
      _info(
        'No prebuilt available for ${target.label}, '
        'falling back to source build.',
      );
      await fallback!.run(input: input, output: output, logger: logger);
    } else if (sourceFallback == null) {
      _warn(
        'No fallback builder configured. '
        'Unable to provide $libraryStem for ${target.label}.',
      );
    }
  }

  ArtifactPayload _payloadForLinkMode(LinkMode linkMode) {
    if (linkMode is StaticLinking) {
      return StaticLibraryPayload(libraryStem: libraryStem);
    }
    return DynamicLibraryPayload(libraryStem: libraryStem);
  }

  void _info(String message) => stdout.writeln(message);
  void _warn(String message) => stdout.writeln('Warning: $message');
}
