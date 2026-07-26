import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../fingerprint.dart';
import '../native_build_context.dart';
import '../native_build_recipe.dart';
import '../process_runner.dart';
import '../../source/resolved_source.dart';

/// CMake configure step.
///
/// Configures a CMake project with specified options.
final class CmakeConfigureStep implements NativeBuildStep {
  const CmakeConfigureStep({
    required this.sourceDirectory,
    this.buildDirectory,
    this.defines = const {},
    this.generator,
    this.toolchainFile,
    this.runner,
  });

  /// Step identifier.
  @override
  String get id => 'cmake_configure';

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

  /// Optional process runner.
  final ProcessRunnerInterface? runner;

  /// Creates a [CmakeConfigureStep] from a YAML-derived map.
  factory CmakeConfigureStep.fromMap(Map<String, dynamic> map) {
    return CmakeConfigureStep(
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
    );
  }

  /// Serializes this step to a map suitable for YAML output.
  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'type': 'cmake_configure',
      'source_directory': sourceDirectory,
      if (buildDirectory != null) 'build_directory': buildDirectory,
      if (defines.isNotEmpty) 'defines': defines,
      if (generator != null) 'generator': generator,
      if (toolchainFile != null) 'toolchain_file': toolchainFile,
    };
  }

  @override
  Map<String, dynamic> toJson() => toMap();

  @override
  Future<NativeStepFingerprint> fingerprint(NativeStepContext context) async {
    final buffer = StringBuffer();
    buffer.write('cmake_configure');
    buffer.write(sourceDirectory);
    buffer.write(buildDirectory);
    buffer.write(defines);
    buffer.write(generator);
    buffer.write(toolchainFile);

    // Include source file hashes for invalidation
    buffer.write(_sourceFilesHash(context.source.directory));

    return NativeStepFingerprint(
      id: 'cmake_configure',
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
    final srcDir = p.isAbsolute(sourceDirectory)
        ? sourceDirectory
        : p.join(source.directory.path, sourceDirectory);
    final buildDir = buildDirectory != null
        ? (p.isAbsolute(buildDirectory!)
              ? buildDirectory!
              : p.join(source.directory.path, buildDirectory!))
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
      args.addAll(['-G', generator!]);
    }
    if (toolchainFile != null) {
      args.addAll(['-DCMAKE_TOOLCHAIN_FILE=$toolchainFile']);
    }
    for (final entry in defines.entries) {
      args.add('-D${entry.key}=${entry.value}');
    }

    logger?.info('[cmake_configure] Running: cmake ${args.join(' ')}');
    await r.runStreaming('cmake', args, workingDirectory: Directory(buildDir));

    return const NativeStepResult();
  }
}

/// CMake build step for native libraries.
///
/// Executes the actual build process using CMake.
final class CmakeBuildStep implements NativeBuildStep {
  const CmakeBuildStep({
    required this.buildDirectory,
    this.targets = const [],
    this.parallel = true,
    this.environment,
    this.runner,
  });

  /// Step identifier.
  @override
  String get id => 'cmake_build';

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
    buffer.write('cmake_build');
    buffer.write(buildDirectory);
    buffer.write(targets.join(','));
    if (environment != null) {
      final envEntries = environment!.entries.toList()
        ..sort((a, b) => a.key.compareTo(b.key));
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
    logger?.info('[cmake_build] Starting build step');
    final r = runner ?? ProcessRunner(logger: logger);
    final buildDir = p.isAbsolute(buildDirectory)
        ? buildDirectory
        : p.join(source.directory.path, buildDirectory);

    final args = <String>['--build', buildDir];
    if (targets.isNotEmpty) {
      for (final target in targets) {
        args.addAll(['--target', target]);
      }
    }
    if (parallel) {
      args.addAll(['--parallel', Platform.numberOfProcessors.toString()]);
    }

    logger?.info('[cmake_build] Running: cmake ${args.join(' ')}');
    await r.runStreaming(
      'cmake',
      args,
      workingDirectory: Directory(buildDir),
      environment: environment,
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
