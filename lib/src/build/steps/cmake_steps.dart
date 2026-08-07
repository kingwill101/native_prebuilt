import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../fingerprint.dart';
import '../native_build_context.dart';
import '../native_build_recipe.dart';
import '../process_runner.dart';
import '../recipe_value_expansion.dart';
import '../toolchains/toolchain_registry.dart';
import '../../source/resolved_source.dart';

/// CMake configure step.
///
/// Configures a CMake project with specified options.
final class CmakeConfigureStep implements NativeBuildStep {
  const CmakeConfigureStep({
    this.id = 'cmake_configure',
    this.execution = 'target',
    required this.sourceDirectory,
    this.buildDirectory,
    this.defines = const {},
    this.generator,
    this.toolchainFile,
    this.expectTargets = const [],
    this.runner,
  });

  /// Step identifier.
  @override
  final String id;

  @override
  final String execution;


  /// Path to the source directory (relative to source root or absolute).
  final String sourceDirectory;

  /// Path to the build directory (relative to source or absolute).
  final String? buildDirectory;

  /// CMake defines (e.g., `-DCMAKE_BUILD_TYPE=Release`).
  final Map<String, String> defines;

  /// CMake generator (e.g., `Ninja`, `Unix Makefiles`).
  final String? generator;

  /// Path to a CMake toolchain file.
  final String? toolchainFile;

  /// Expected CMake targets (e.g., tdjson). If non-empty, validated after configure.
  final List<String> expectTargets;

  /// Optional process runner.
  final ProcessRunnerInterface? runner;

  /// Creates a [CmakeConfigureStep] from a YAML-derived map.
  factory CmakeConfigureStep.fromMap(Map<String, dynamic> map) {
    final expect = map['expect'];
    List<String> expectTargets = const [];
    if (expect is Map && expect['targets'] is List) {
      expectTargets = (expect['targets'] as List).map((e) => e.toString()).toList();
    } else if (map['expect_targets'] is List) {
      expectTargets = (map['expect_targets'] as List).map((e) => e.toString()).toList();
    }
    return CmakeConfigureStep(
      id: map['id'] as String? ?? 'cmake_configure',
      execution: map['execution'] as String? ?? 'target',
      sourceDirectory: map['source_directory'] as String,
      buildDirectory: map['build_directory'] as String?,
      defines: map['defines'] is Map
          ? Map<String, String>.from(
              (map['defines'] as Map).map(
                (k, v) => MapEntry(k.toString(), v.toString()),
              ),
            )
          : const {},
      generator: map['generator'] as String?,
      toolchainFile: map['toolchain_file'] as String?,
      expectTargets: expectTargets,
    );
  }

  /// Serializes this step to a map suitable for YAML output.
  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'type': 'cmake_configure',
      'id': id,
      if (execution != 'target') 'execution': execution,
      'source_directory': sourceDirectory,
      if (buildDirectory != null) 'build_directory': buildDirectory,
      if (defines.isNotEmpty) 'defines': defines,
      if (generator != null) 'generator': generator,
      if (toolchainFile != null) 'toolchain_file': toolchainFile,
      if (expectTargets.isNotEmpty) 'expect': {'targets': expectTargets},
    };
  }

  @override
  Map<String, dynamic> toJson() => toMap();

  @override
  Future<NativeStepFingerprint> fingerprint(NativeStepContext context) async {
    final buffer = StringBuffer();
    buffer.write(id);
    buffer.write(
      expandRecipeValue(sourceDirectory, context.buildContext, context.source),
    );
    buffer.write(
      buildDirectory == null
          ? null
          : expandRecipeValue(
              buildDirectory!,
              context.buildContext,
              context.source,
            ),
    );
    buffer.write(
      defines.map(
        (key, value) => MapEntry(
          key,
          expandRecipeValue(value, context.buildContext, context.source),
        ),
      ),
    );
    buffer.write(generator);
    buffer.write(
      toolchainFile == null
          ? null
          : expandRecipeValue(
              toolchainFile!,
              context.buildContext,
              context.source,
            ),
    );
    buffer.write(execution);
    buffer.write(expectTargets.join(','));

    // Include source file hashes for invalidation
    buffer.write(_sourceFilesHash(context.source.directory));

    return NativeStepFingerprint(
      id: id,
      hash: fingerprintHash(buffer.toString()),
    );
  }

  @override
  Future<NativeStepResult> execute(
    NativeBuildContext context,
    ResolvedSource source,
  ) async {
    final logger = context.logger;
    final r = runner ?? ProcessRunner(logger: logger);
    final expandedSourceDirectory = expandRecipeValue(
      sourceDirectory,
      context,
      source,
    );
    final srcDir = p.isAbsolute(expandedSourceDirectory)
        ? expandedSourceDirectory
        : p.join(source.directory.path, expandedSourceDirectory);
    final buildDir = buildDirectory != null
        ? (() {
            final expandedBuildDirectory = expandRecipeValue(
              buildDirectory!,
              context,
              source,
            );
            return p.isAbsolute(expandedBuildDirectory)
                ? expandedBuildDirectory
                : p.join(source.directory.path, expandedBuildDirectory);
          })()
        : p.join(srcDir, 'build');

    final buildDirEntity = Directory(buildDir);
    buildDirEntity.createSync(recursive: true);

    // Detect stale CMakeCache.txt from a previous source path
    final cacheFile = File(p.join(buildDir, 'CMakeCache.txt'));
    if (cacheFile.existsSync()) {
      final cacheContent = cacheFile.readAsStringSync();
      final homeDirMatch = RegExp(
        r'CMAKE_HOME_DIRECTORY:INTERNAL=(.+)',
      ).firstMatch(cacheContent);
      if (homeDirMatch != null) {
        final cachedSource = homeDirMatch.group(1);
        if (cachedSource != srcDir) {
          logger?.info(
            '[cmake_configure] Stale cache detected '
            '(cached source: $cachedSource, current: $srcDir). '
            'Cleaning build directory.',
          );
          buildDirEntity.deleteSync(recursive: true);
          buildDirEntity.createSync(recursive: true);
        }
      }
    }

    final args = <String>['-S', srcDir, '-B', buildDir];

    if (generator != null) {
      args.addAll(['-G', expandRecipeValue(generator!, context, source)]);
    }
    String? effectiveToolchain = toolchainFile;
    // Host execution must not use target toolchain
    final isHost = execution == 'host';
    if (effectiveToolchain == null && !isHost) {
      final resolver = const NativeToolchainResolver();
      effectiveToolchain = resolver.cmakeToolchainFile(context.target);
      if (effectiveToolchain != null) {
        logger?.info('[$id] Auto toolchain: $effectiveToolchain');
      }
    }
    if (effectiveToolchain != null) {
      final expandedToolchain = expandRecipeValue(
        effectiveToolchain,
        context,
        source,
      );
      args.addAll(['-DCMAKE_TOOLCHAIN_FILE=$expandedToolchain']);
    }
    // Auto-inject Android defaults when target is Android and not overridden.
    // Skip for host execution — host code generators run on the host compiler.
    if (!isHost && context.target.os.name == 'android') {
      final arch = context.target.architecture;
      final resolver = const NativeToolchainResolver();
      final abi = NativeToolchainResolver.androidAbiFor(arch);
      if (!defines.containsKey('ANDROID_ABI')) {
        args.add('-DANDROID_ABI=$abi');
      }
      if (!defines.containsKey('ANDROID_PLATFORM')) {
        args.add('-DANDROID_PLATFORM=android-24');
      }
      if (!defines.containsKey('ANDROID_STL')) {
        args.add('-DANDROID_STL=c++_static');
      }
      // OPENSSL_ROOT_DIR auto if not set and resolver knows NDK layout?
      if (!defines.containsKey('OPENSSL_ROOT_DIR') &&
          resolver.hasAndroidNdk) {
        // Leave to recipe's {{ dependencies.openssl.prefix }} if present;
        // no default injection to avoid false paths.
      }
    }
    for (final entry in defines.entries) {
      args.add(
        '-D${entry.key}=${expandRecipeValue(entry.value, context, source)}',
      );
    }

    logger?.info('[$id] Running: cmake ${args.join(' ')}');
    await r.runStreaming('cmake', args, workingDirectory: Directory(buildDir));

    // Validate expected targets immediately after configure
    if (expectTargets.isNotEmpty) {
      // Check that CMakeCache mentions those targets or that the build files were generated
      // We do a lightweight check: look for build.ninja or Makefile that would contain the target
      final buildNinja = File(p.join(buildDir, 'build.ninja'));
      final makefile = File(p.join(buildDir, 'Makefile'));
      String? buildFileContent;
      if (buildNinja.existsSync()) {
        buildFileContent = buildNinja.readAsStringSync();
      } else if (makefile.existsSync()) {
        buildFileContent = makefile.readAsStringSync();
      }
      if (buildFileContent != null) {
        for (final t in expectTargets) {
          if (!buildFileContent.contains(t)) {
            throw StateError(
              'CMake configuration completed but required target "$t" was not generated.\n'
              'Relevant dependency errors may be in the log above.\n'
              'Possible missing configuration: OPENSSL_ROOT_DIR or toolchain.',
            );
          }
        }
        logger?.info('[$id] Verified expected targets: ${expectTargets.join(', ')}');
      } else {
        logger?.warning('[$id] Could not verify expected targets ${expectTargets.join(', ')}: no build.ninja/Makefile found at $buildDir');
      }
    }

    return const NativeStepResult();
  }
}

/// CMake build step for native libraries.
///
/// Executes the actual build process using CMake.
final class CmakeBuildStep implements NativeBuildStep {
  const CmakeBuildStep({
    this.id = 'cmake_build',
    this.execution = 'target',
    required this.buildDirectory,
    this.targets = const [],
    this.parallel = true,
    this.environment,
    this.runner,
  });

  /// Step identifier.
  @override
  final String id;

  @override
  final String execution;


  /// Path to the build directory (where CMakeCache.txt is).
  final String buildDirectory;

  /// Specific targets to build. Empty means build all.
  final List<String> targets;

  /// Whether to build in parallel.
  final bool parallel;

  /// Environment variables for the build process.
  final Map<String, String>? environment;

  /// Optional process runner.
  final ProcessRunnerInterface? runner;

  /// Creates a [CmakeBuildStep] from a YAML-derived map.
  factory CmakeBuildStep.fromMap(Map<String, dynamic> map) {
    return CmakeBuildStep(
      id: map['id'] as String? ?? 'cmake_build',
      buildDirectory: map['build_directory'] as String,
      targets: map['targets'] is List
          ? (map['targets'] as List).map((e) => e.toString()).toList()
          : const [],
      parallel: map['parallel'] as bool? ?? true,
      environment: map['environment'] is Map
          ? Map<String, String>.from(
              (map['environment'] as Map).map(
                (k, v) => MapEntry(k.toString(), v.toString()),
              ),
            )
          : null,
    );
  }

  /// Serializes this step to a map suitable for YAML output.
  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'type': 'cmake_build',
      'id': id,
      'build_directory': buildDirectory,
      if (targets.isNotEmpty) 'targets': targets,
      if (parallel != true) 'parallel': parallel,
      if (environment != null) 'environment': environment,
    };
  }

  @override
  Map<String, dynamic> toJson() => toMap();

  @override
  Future<NativeStepFingerprint> fingerprint(NativeStepContext context) async {
    final buffer = StringBuffer();
    buffer.write(id);
    buffer.write(
      expandRecipeValue(buildDirectory, context.buildContext, context.source),
    );
    buffer.write(
      expandRecipeValues(
        targets,
        context.buildContext,
        context.source,
      ).join(','),
    );
    if (environment != null) {
      final envEntries = expandRecipeStringMap(
        environment!,
        context.buildContext,
        context.source,
      ).entries.toList()..sort((a, b) => a.key.compareTo(b.key));
      buffer.write(envEntries.map((e) => '${e.key}=${e.value}').join('|'));
    }
    return NativeStepFingerprint(
      id: id,
      hash: fingerprintHash(buffer.toString()),
    );
  }

  @override
  Future<NativeStepResult> execute(
    NativeBuildContext context,
    ResolvedSource source,
  ) async {
    final logger = context.logger;
    logger?.info('[$id] Starting build step');
    final r = runner ?? ProcessRunner(logger: logger);
    final expandedBuildDirectory = expandRecipeValue(
      buildDirectory,
      context,
      source,
    );
    final buildDir = p.isAbsolute(expandedBuildDirectory)
        ? expandedBuildDirectory
        : p.join(source.directory.path, expandedBuildDirectory);

    final args = <String>['--build', buildDir];
    if (targets.isNotEmpty) {
      for (final target in expandRecipeValues(targets, context, source)) {
        args.addAll(['--target', target]);
      }
    }
    if (parallel) {
      args.addAll(['--parallel', Platform.numberOfProcessors.toString()]);
    }

    logger?.info('[$id] Running: cmake ${args.join(' ')}');
    await r.runStreaming(
      'cmake',
      args,
      workingDirectory: Directory(buildDir),
      environment: environment == null
          ? null
          : expandRecipeStringMap(environment!, context, source),
    );

    return const NativeStepResult();
  }
}

/// Compute a hash of key source files for cache invalidation.
///
/// Hashes CMakeLists.txt and all .c/.cpp/.h/.hpp files in the source directory.
String _sourceFilesHash(Directory sourceDir) {
  final files = <File>[];
  final cmakeFile = File(p.join(sourceDir.path, 'CMakeLists.txt'));
  if (cmakeFile.existsSync()) {
    files.add(cmakeFile);
  }

  try {
    for (final entity in sourceDir.listSync(recursive: true)) {
      if (entity is File) {
        final ext = p.extension(entity.path);
        if (ext == '.c' || ext == '.cpp' || ext == '.h' || ext == '.hpp') {
          files.add(entity);
        }
      }
    }
  } catch (_) {}

  final buffer = StringBuffer();
  final sortedFiles = files.toList()..sort((a, b) => a.path.compareTo(b.path));
  for (final file in sortedFiles) {
    final relative = p.relative(file.path, from: sourceDir.path);
    buffer.write('$relative:${fingerprintHash(file.readAsStringSync())}|');
  }

  return fingerprintHash(buffer.toString());
}
