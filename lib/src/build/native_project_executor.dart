import 'dart:convert';
import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import '../binary/library_name.dart';
import '../manifest/prebuilt_artifact.dart';
import 'native_build_context.dart';
import 'native_build_result.dart';
import 'native_project.dart';
import 'process_runner.dart';
import '../cache/build_cache.dart';
import '../source/resolved_source.dart';
import '../source/source_builder.dart';
import '../source/source_fallback.dart';

/// Shared build entry point for CLI, hooks, CI, and tests.
///
/// Orchestrates the complete native build pipeline:
/// 1. Resolves source when a declarative recipe needs it
/// 2. Resolves the recipe via [NativeBuildDefinition.recipeFor]
/// 3. Executes the recipe, or falls back to `hook/build.dart` when no recipe exists
/// 4. Stages the artifact bundle with role-based subdirectories
/// 5. Writes `native_prebuilt.json` metadata
/// 6. Returns [NativeBuildResult]
final class NativeProjectExecutor {
  const NativeProjectExecutor({
    required this.project,
    this.source,
    this.sourceFallback,
    this.cache,
    this.logger,
    this.runner,
  });

  /// The native project definition.
  final NativeProject project;

  /// The resolved source to build from.
  ///
  /// When provided, skips source resolution. When null, [sourceFallback]
  /// is used to resolve the source from the project's source specifications.
  final ResolvedSource? source;

  /// Source fallback configuration for resolving source when [source] is null.
  final SourceFallback? sourceFallback;

  /// Optional build cache for step-level caching.
  final BuildCache? cache;

  /// Optional logger for build output.
  final Logger? logger;

  /// Optional process runner used for hook/build.dart fallback.
  final ProcessRunnerInterface? runner;

  /// Build for a specific [target].
  ///
  /// [outputDir] is where artifacts are staged (e.g., `built-library/linux-x64/`).
  /// [workDir] is the working directory for build commands.
  Future<NativeBuildResult> build({
    required NativeTarget target,
    required Directory outputDir,
    Directory? workDir,
    LinkMode? linkMode,
  }) async {
    logger?.info('Building ${project.name} for ${target.label}...');

    // 1. Resolve recipe
    final recipe = project.build.recipeFor(target);
    if (recipe == null) {
      logger?.info('No declarative recipe found; invoking hook/build.dart.');
      return _buildViaHookCli(
        target: target,
        outputDir: outputDir,
        linkMode: linkMode ?? project.asset.linkMode,
        packageRoot: source?.directory ?? Directory.current,
      );
    }

    // 2. Resolve source if not provided
    var resolvedSource = source;
    if (resolvedSource == null) {
      // When no explicit source or sourceFallback is given, fall back
      // to project.sources so that CLI callers (and any executor user)
      // can build from the project's declared sources automatically.
      final effectiveFallback =
          sourceFallback ??
          (project.sources.isNotEmpty
              ? SourceFallback(
                  sources: project.sources,
                  builder: const NoOpSourceBuilder(),
                  preparation: [],
                )
              : null);
      if (effectiveFallback == null) {
        throw StateError(
          'No source provided and no source fallback configured for '
          '${project.name} on ${target.label}.',
        );
      }

      logger?.info('Resolving source...');
      final sourceResult = await SourceFallbackResolver().resolve(
        fallback: effectiveFallback,
        packageRoot: Directory.current,
        sourceCacheRoot: Directory(
          p.join(
            Directory.current.path,
            '.dart_tool',
            'native_prebuilt',
            'sources',
          ),
        ),
        input: _dummyInput(),
        output: _dummyOutput(),
        logger: logger,
      );

      if (sourceResult == null) {
        throw StateError(
          'Failed to resolve source for ${project.name} on ${target.label}.',
        );
      }

      resolvedSource = sourceResult.source;
      workDir ??= sourceResult.workDirectory;
    }

    // 3. Create build context
    final context = NativeBuildContext(
      target: target,
      hook: NativeHookConfiguration(
        packageName: project.name,
        assetName: project.asset.assetName,
        libraryStem: project.asset.libraryStem,
        linkMode: linkMode ?? project.asset.linkMode,
      ),
      directories: NativeBuildDirectories(
        source: resolvedSource.directory,
        output: outputDir,
        cache:
            workDir ??
            Directory(
              p.join(
                resolvedSource.directory.path,
                '.dart_tool',
                'native_prebuilt',
              ),
            ),
        work:
            workDir ??
            Directory(
              p.join(
                resolvedSource.directory.path,
                '.dart_tool',
                'native_prebuilt',
              ),
            ),
      ),
      toolchains: const ToolchainRegistry(),
      environment: Platform.environment,
      options: project.build.options,
      variables: project.build.variables,
      logger: logger,
    );

    // 4. Execute the recipe
    logger?.info('Executing recipe: ${recipe.runtimeType}...');

    // Inject cache into StepBuildRecipe if available
    NativeBuildRecipe effectiveRecipe = recipe;
    if (cache != null && recipe is StepBuildRecipe) {
      effectiveRecipe = StepBuildRecipe(
        steps: recipe.steps,
        needsById: recipe.needsById,
        cache: cache,
      );
    }

    final result = await effectiveRecipe.execute(context, resolvedSource);

    // 5. Stage artifact bundle
    await _stageArtifacts(context, result);

    // 6. Write metadata
    await _writeMetadata(context, result, target);

    logger?.info(
      'Build completed: ${result.artifacts.length} artifact(s) staged '
      'to ${outputDir.path}',
    );

    return result;
  }

  Future<NativeBuildResult> _buildViaHookCli({
    required NativeTarget target,
    required Directory outputDir,
    required LinkMode linkMode,
    required Directory packageRoot,
  }) async {
    final hookScript = File(p.join(packageRoot.path, 'hook', 'build.dart'));
    if (!hookScript.existsSync()) {
      throw StateError(
        'No declarative build recipe for ${project.name} on ${target.label}. '
        'This package may rely on a custom hook builder, but no '
        'hook/build.dart was found at ${hookScript.path}.',
      );
    }

    final outputDirectoryShared = Directory(
      p.join(outputDir.path, '.dart_tool', 'native_prebuilt', 'hook_runner'),
    )..createSync(recursive: true);

    final tempDir = await Directory.systemTemp.createTemp(
      'native_prebuilt_hook_',
    );
    try {
      final outputFile = tempDir.uri.resolve('output.json');
      final inputFile = File.fromUri(tempDir.uri.resolve('input.json'));
      final inputBuilder = BuildInputBuilder()
        ..setupShared(
          packageRoot: packageRoot.uri,
          packageName: project.name,
          outputFile: outputFile,
          outputDirectoryShared: outputDirectoryShared.uri,
          userDefines: _readWorkspaceUserDefines(packageRoot),
        )
        ..setupBuildInput()
        ..config.setupBuild(linkingEnabled: false);

      CodeAssetExtension(
        targetArchitecture: target.architecture,
        targetOS: target.os,
        linkModePreference: _linkModePreference(linkMode),
        android: target.os == OS.android
            ? AndroidCodeConfig(targetNdkApi: 30)
            : null,
        iOS: target.os == OS.iOS
            ? IOSCodeConfig(targetSdk: IOSSdk.iPhoneOS, targetVersion: 17)
            : null,
        macOS: target.os == OS.macOS
            ? MacOSCodeConfig(targetVersion: 13)
            : null,
      ).setupBuildInput(inputBuilder);

      final input = inputBuilder.build();
      await inputFile.writeAsString(
        const JsonEncoder.withIndent('  ').convert(input.json),
      );

      final processRunner = runner ?? ProcessRunner(logger: logger);
      await processRunner.runStreaming('dart', [
        'run',
        'hook/build.dart',
        '--config',
        inputFile.path,
      ], workingDirectory: packageRoot);

      final outputJson =
          jsonDecode(await File.fromUri(outputFile).readAsString())
              as Map<String, Object?>;
      final result = _nativeBuildResultFromHookOutput(
        target: target,
        outputDir: outputDir,
        buildOutput: BuildOutput(outputJson),
        manifestArtifact: project.prebuilts[target.label],
      );
      await _writeHookMetadata(outputDir, result, target);
      return result;
    } finally {
      await tempDir.delete(recursive: true);
    }
  }

  NativeBuildResult _nativeBuildResultFromHookOutput({
    required NativeTarget target,
    required Directory outputDir,
    required BuildOutput buildOutput,
    required PrebuiltArtifact? manifestArtifact,
  }) {
    final codeAssets = buildOutput.assets.code;
    if (codeAssets.isEmpty) {
      throw StateError('hook/build.dart did not emit any code assets.');
    }
    if (manifestArtifact != null && codeAssets.length != 1) {
      throw StateError(
        'hook/build.dart emitted ${codeAssets.length} code assets, but '
        'manifest entry ${manifestArtifact.archiveName} declares one payload.',
      );
    }

    final artifacts = <BuiltNativeArtifact>[];
    for (final asset in codeAssets) {
      final assetFile = asset.file;
      if (assetFile == null) {
        throw StateError('Code asset ${asset.id} did not include a file.');
      }

      final sourceFile = File.fromUri(assetFile);
      if (!sourceFile.existsSync()) {
        throw StateError('Code asset ${asset.id} points to a missing file.');
      }

      final payload =
          manifestArtifact?.payload ?? _payloadFromLinkMode(asset.linkMode);
      final libraryStem = switch (payload) {
        DynamicLibraryPayload(:final libraryStem) => libraryStem,
        StaticLibraryPayload(:final libraryStem) => libraryStem,
      };
      _validateHookAssetMatchesManifest(
        asset: asset,
        payload: payload,
        manifestArtifact: manifestArtifact,
      );
      final stagedFile = _stageHookArtifactFile(
        sourceFile,
        outputDir,
        canonicalName: canonicalLibraryName(
          target: target,
          libraryStem: libraryStem,
          payload: payload,
        ),
      );
      artifacts.add(
        BuiltNativeArtifact(
          id: asset.id,
          target: target,
          kind: payload is StaticLibraryPayload
              ? NativeArtifactKind.staticLibrary
              : NativeArtifactKind.dynamicLibrary,
          primary: NativeArtifactEntry.primary(
            source: stagedFile,
            path: p.relative(stagedFile.path, from: outputDir.path),
          ),
        ),
      );
    }

    return NativeBuildResult(artifacts: artifacts);
  }

  File _stageHookArtifactFile(
    File sourceFile,
    Directory outputDir, {
    required String canonicalName,
  }) {
    final stagedFile = File(p.join(outputDir.path, canonicalName));
    if (p.normalize(sourceFile.path) == p.normalize(stagedFile.path)) {
      return sourceFile;
    }

    stagedFile.parent.createSync(recursive: true);
    sourceFile.copySync(stagedFile.path);
    return stagedFile;
  }

  ArtifactPayload _payloadFromLinkMode(LinkMode linkMode) {
    return switch (linkMode) {
      StaticLinking() => StaticLibraryPayload(
        libraryStem: project.asset.libraryStem,
      ),
      _ => DynamicLibraryPayload(libraryStem: project.asset.libraryStem),
    };
  }

  void _validateHookAssetMatchesManifest({
    required CodeAsset asset,
    required ArtifactPayload payload,
    required PrebuiltArtifact? manifestArtifact,
  }) {
    final expectedStatic = payload is StaticLibraryPayload;
    final actualStatic = asset.linkMode is StaticLinking;
    if (expectedStatic != actualStatic) {
      throw StateError(
        manifestArtifact == null
            ? 'Code asset ${asset.id} link mode does not match the configured payload type.'
            : 'Code asset ${asset.id} link mode does not match manifest payload ${manifestArtifact.archiveName}.',
      );
    }
  }

  LinkModePreference _linkModePreference(LinkMode linkMode) {
    return switch (linkMode) {
      StaticLinking() => LinkModePreference.static,
      _ => LinkModePreference.dynamic,
    };
  }

  PackageUserDefines? _readWorkspaceUserDefines(Directory packageRoot) {
    final pubspecFile = File(p.join(packageRoot.path, 'pubspec.yaml'));
    if (!pubspecFile.existsSync()) {
      return null;
    }

    final yaml = loadYaml(pubspecFile.readAsStringSync());
    if (yaml is! YamlMap) {
      return null;
    }

    final hooks = yaml['hooks'];
    if (hooks is! YamlMap) {
      return null;
    }

    final userDefines = hooks['user_defines'];
    if (userDefines is! YamlMap) {
      return null;
    }

    final packageDefines = userDefines[project.name];
    if (packageDefines is! YamlMap) {
      return null;
    }

    return PackageUserDefines(
      workspacePubspec: PackageUserDefinesSource(
        defines: _yamlObjectToMap(packageDefines),
        basePath: packageRoot.uri,
      ),
    );
  }

  Map<String, Object?> _yamlObjectToMap(YamlMap map) => {
    for (final entry in map.entries)
      entry.key.toString(): _yamlValueToObject(entry.value),
  };

  Object? _yamlValueToObject(Object? value) {
    return switch (value) {
      YamlMap() => _yamlObjectToMap(value),
      YamlList() => value.map(_yamlValueToObject).toList(),
      _ => value,
    };
  }

  /// Create a minimal [BuildInput] for source resolution.
  BuildInput _dummyInput() {
    final builder = BuildInputBuilder()
      ..setupShared(
        packageRoot: Directory.current.uri,
        packageName: project.name,
        outputFile: Directory.systemTemp.uri.resolve('output.json'),
        outputDirectoryShared: Directory.systemTemp.uri.resolve(
          'output_shared/',
        ),
      )
      ..setupBuildInput()
      ..config.setupBuild(linkingEnabled: false)
      ..config.addBuildAssetTypes(['code_assets/code']);
    return builder.build();
  }

  /// Create a minimal [BuildOutputBuilder] for source resolution.
  BuildOutputBuilder _dummyOutput() {
    return BuildOutputBuilder();
  }

  /// Stage artifact entries to role-based subdirectories.
  Future<void> _stageArtifacts(
    NativeBuildContext context,
    NativeBuildResult result,
  ) async {
    for (final artifact in result.artifacts) {
      for (final entry in artifact.entries) {
        if (p.isAbsolute(entry.path)) {
          throw StateError(
            'Artifact ${artifact.id} has absolute path for ${entry.role.name}: ${entry.path}',
          );
        }
        final destDir = _destinationDirectory(entry.role, context);
        final entryDir = p.dirname(entry.path);
        final destSubDir = entryDir == '.' || entryDir == ''
            ? destDir
            : Directory(p.join(destDir.path, entryDir));
        destSubDir.createSync(recursive: true);
        final destPath = p.join(destSubDir.path, p.basename(entry.path));

        if (entry.source is File) {
          await (entry.source as File).copy(destPath);
        } else if (entry.source is Directory) {
          await _copyDirectory(entry.source as Directory, Directory(destPath));
        }

        context.logger?.fine(
          'Staged: ${entry.role.name} -> ${p.relative(destPath, from: context.directories.output.path)}',
        );
      }
    }
  }

  /// Determine the destination directory for an entry based on its role.
  Directory _destinationDirectory(
    NativeArtifactRole role,
    NativeBuildContext context,
  ) {
    final outputBase = context.directories.output.path;
    return switch (role) {
      NativeArtifactRole.primary ||
      NativeArtifactRole.runtimeDependency => Directory(outputBase),
      NativeArtifactRole.importLibrary => Directory(p.join(outputBase, 'link')),
      NativeArtifactRole.debugSymbols => Directory(
        p.join(outputBase, 'symbols'),
      ),
      NativeArtifactRole.resource => Directory(p.join(outputBase, 'resources')),
      NativeArtifactRole.license => Directory(p.join(outputBase, 'licenses')),
    };
  }

  /// Write `native_prebuilt.json` metadata file.
  Future<void> _writeMetadata(
    NativeBuildContext context,
    NativeBuildResult result,
    NativeTarget target,
  ) async {
    final metadataFile = File(
      p.join(context.directories.output.path, 'native_prebuilt.json'),
    );
    await _writeMetadataFile(metadataFile, result, target);
    logger?.fine('Wrote metadata to ${metadataFile.path}');
  }

  Future<void> _writeHookMetadata(
    Directory outputDir,
    NativeBuildResult result,
    NativeTarget target,
  ) async {
    final metadataFile = File(p.join(outputDir.path, 'native_prebuilt.json'));
    await _writeMetadataFile(metadataFile, result, target);
  }

  Future<void> _writeMetadataFile(
    File metadataFile,
    NativeBuildResult result,
    NativeTarget target,
  ) async {
    metadataFile.parent.createSync(recursive: true);
    final metadata = <String, dynamic>{
      'schemaVersion': 1,
      'project': project.name,
      'target': target.label,
      'artifacts': result.artifacts
          .map(
            (a) => {
              'id': a.id,
              'kind': a.kind.name,
              'primary': a.primary.path,
              'files': a.entries
                  .map(
                    (e) => {
                      'path': e.path,
                      'role': e.role.name,
                      'optional': e.optional,
                    },
                  )
                  .toList(),
            },
          )
          .toList(),
    };
    await metadataFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(metadata),
    );
  }

  /// Recursively copy a directory.
  Future<void> _copyDirectory(Directory source, Directory destination) async {
    destination.createSync(recursive: true);
    await for (final entity in source.list(recursive: true)) {
      if (entity is File) {
        final relativePath = p.relative(entity.path, from: source.path);
        final targetFile = File(p.join(destination.path, relativePath));
        targetFile.parent.createSync(recursive: true);
        await entity.copy(targetFile.path);
      }
    }
  }
}
