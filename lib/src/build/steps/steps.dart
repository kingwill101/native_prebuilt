import 'dart:async';
import 'dart:io';


import 'package:path/path.dart' as p;

import '../native_build_context.dart';
import '../native_build_recipe.dart';
import '../process_runner.dart';
import '../../source/resolved_source.dart';

/// Compute a hash for the given directories and source.
Future<String> computeHash(Directory directory, Directory source) async {
  // Simple hash based on directory paths and modification times
  final buffer = StringBuffer();
  buffer.write(directory.path);
  buffer.write(source.path);

  if (directory.existsSync()) {
    await for (final entity in directory.list(recursive: true)) {
      if (entity is File) {
        final stat = entity.statSync();
        buffer.write(entity.path);
        buffer.write(stat.modified);
      }
    }
  }

  return buffer.toString().hashCode.toString();
}

/// Generic command execution step.
///
/// Runs one or more commands with arguments, optionally in a working directory.
final class CommandStep implements NativeBuildStep {
  const CommandStep({
    required this.id,
    required this.commands,
    this.workingDirectory,
    this.environment,
    this.runner,
  });

  /// Step identifier.
  @override
  final String id;

  /// Commands to execute in order. Each entry is [executable, ...args].
  final List<List<String>> commands;

  /// Working directory for all commands.
  final String? workingDirectory;

  /// Environment variables to pass to the process.
  final Map<String, String>? environment;

  /// Optional process runner.
  final ProcessRunnerInterface? runner;

  @override
  Future<NativeStepFingerprint> fingerprint(NativeStepContext context) async {
    final buffer = StringBuffer();
    buffer.write(id);
    for (final cmd in commands) {
      buffer.write(cmd.join(' '));
    }
    if (workingDirectory != null) buffer.write(workingDirectory);
    return NativeStepFingerprint(
      id: id,
      hash: buffer.toString().hashCode.toRadixString(16),
    );
  }

  @override
  Future<void> execute(
    NativeBuildContext context,
    ResolvedSource source,
  ) async {
    final r = runner ?? const ProcessRunner();
    final workDir = workingDirectory != null
        ? Directory(workingDirectory!)
        : context.directories.work;

    for (final cmd in commands) {
      if (cmd.isEmpty) continue;
      await r.run(
        cmd.first,
        cmd.skip(1).toList(),
        workingDirectory: workDir,
        environment: environment,
      );
    }
  }
}

/// CMake configuration step for native builds.
///
/// Sets up the build environment and generates CMake configuration files.
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

  /// Path to the build directory. Defaults to `<source>/build`.
  final String? buildDirectory;

  /// CMake defines (e.g., `-DCMAKE_BUILD_TYPE=Release`).
  final Map<String, String> defines;

  /// CMake generator (e.g., `Ninja`, `Unix Makefiles`).
  final String? generator;

  /// Path to a CMake toolchain file.
  final String? toolchainFile;

  /// Optional process runner.
  final ProcessRunnerInterface? runner;

  @override
  Future<NativeStepFingerprint> fingerprint(NativeStepContext context) async {
    final buffer = StringBuffer();
    buffer.write('cmake_configure');
    buffer.write(sourceDirectory);
    buffer.write(defines);
    buffer.write(generator);
    buffer.write(toolchainFile);
    return NativeStepFingerprint(
      id: id,
      hash: buffer.toString().hashCode.toRadixString(16),
    );
  }

  @override
  Future<void> execute(
    NativeBuildContext context,
    ResolvedSource source,
  ) async {
    final r = runner ?? const ProcessRunner();
    final srcDir = p.isAbsolute(sourceDirectory)
        ? sourceDirectory
        : p.join(source.directory.path, sourceDirectory);
    final buildDir = buildDirectory != null
        ? (p.isAbsolute(buildDirectory!)
              ? buildDirectory!
              : p.join(source.directory.path, buildDirectory!))
        : p.join(srcDir, 'build');

    Directory(buildDir).createSync(recursive: true);

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

    await r.run('cmake', args);
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

  @override
  Future<NativeStepFingerprint> fingerprint(NativeStepContext context) async {
    final buffer = StringBuffer();
    buffer.write('cmake_build');
    buffer.write(buildDirectory);
    buffer.write(targets);
    return NativeStepFingerprint(
      id: id,
      hash: buffer.toString().hashCode.toRadixString(16),
    );
  }

  @override
  Future<void> execute(
    NativeBuildContext context,
    ResolvedSource source,
  ) async {
    final r = runner ?? const ProcessRunner();
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

    await r.run(
      'cmake',
      args,
      workingDirectory: Directory(buildDir),
      environment: environment,
    );
  }
}

/// Artifact export step for native builds.
///
/// Locates the built artifact and copies it to the output directory.
final class ExportArtifactStep implements NativeBuildStep {
  const ExportArtifactStep({required this.artifactPath, this.outputName});

  /// Step identifier.
  @override
  String get id => 'export_artifact';

  /// Path to the built artifact (relative to build directory or absolute).
  final String artifactPath;

  /// Output filename. If null, uses the original filename.
  final String? outputName;

  @override
  Future<NativeStepFingerprint> fingerprint(NativeStepContext context) async {
    return NativeStepFingerprint(
      id: id,
      hash: artifactPath.hashCode.toRadixString(16),
    );
  }

  @override
  Future<void> execute(
    NativeBuildContext context,
    ResolvedSource source,
  ) async {
    final srcPath = p.isAbsolute(artifactPath)
        ? artifactPath
        : p.join(source.directory.path, artifactPath);
    final srcFile = File(srcPath);

    if (!srcFile.existsSync()) {
      throw StateError('Artifact not found: $srcPath');
    }

    final outputFileName = outputName ?? p.basename(srcPath);
    final destFile = File(
      p.join(context.directories.output.path, outputFileName),
    );
    destFile.parent.createSync(recursive: true);
    srcFile.copySync(destFile.path);
  }
}

/// Download and extract an archive step.
final class DownloadArchiveStep implements NativeBuildStep {
  const DownloadArchiveStep({
    required this.id,
    required this.url,
    this.sha256,
    this.outputDirectory,
    this.runner,
  });

  @override
  final String id;

  /// URL of the archive to download.
  final String url;

  /// Expected SHA-256 hash for verification.
  final String? sha256;

  /// Directory to extract into. Defaults to `<work>/<id>`.
  final String? outputDirectory;

  /// Optional process runner.
  final ProcessRunnerInterface? runner;

  @override
  Future<NativeStepFingerprint> fingerprint(NativeStepContext context) async {
    return NativeStepFingerprint(
      id: id,
      hash: '${url}_${sha256 ?? "none"}'.hashCode.toRadixString(16),
    );
  }

  @override
  Future<void> execute(
    NativeBuildContext context,
    ResolvedSource source,
  ) async {
    final r = runner ?? const ProcessRunner();
    final outDir = outputDirectory ?? p.join(context.directories.work.path, id);
    Directory(outDir).createSync(recursive: true);

    final archivePath = p.join(outDir, p.basename(Uri.parse(url).path));

    // Download if not cached
    if (!File(archivePath).existsSync()) {
      await r.run('curl', ['-#', '-L', url, '-o', archivePath]);
    }

    // Extract
    if (archivePath.endsWith('.tar.gz') || archivePath.endsWith('.tgz')) {
      await r.run('tar', [
        'xzf',
        archivePath,
      ], workingDirectory: Directory(outDir));
    } else if (archivePath.endsWith('.zip')) {
      await r.run('unzip', [
        '-o',
        archivePath,
      ], workingDirectory: Directory(outDir));
    }
  }
}

/// Git checkout step.
final class GitCheckoutStep implements NativeBuildStep {
  const GitCheckoutStep({
    required this.id,
    required this.repository,
    required this.revision,
    this.directory,
    this.submodules = false,
    this.runner,
  });

  @override
  final String id;

  /// Git repository URL.
  final String repository;

  /// Commit SHA or tag to checkout.
  final String revision;

  /// Directory to clone into. Defaults to `<work>/<id>`.
  final String? directory;

  /// Whether to initialize submodules.
  final bool submodules;

  /// Optional process runner.
  final ProcessRunnerInterface? runner;

  @override
  Future<NativeStepFingerprint> fingerprint(NativeStepContext context) async {
    return NativeStepFingerprint(
      id: id,
      hash: '${repository}_$revision'.hashCode.toRadixString(16),
    );
  }

  @override
  Future<void> execute(
    NativeBuildContext context,
    ResolvedSource source,
  ) async {
    final r = runner ?? const ProcessRunner();
    final cloneDir = directory ?? p.join(context.directories.work.path, id);
    final dir = Directory(cloneDir);

    if (!dir.existsSync()) {
      await r.run('git', ['clone', '--depth', '1', repository, cloneDir]);
    }

    await r.run('git', ['checkout', revision], workingDirectory: dir);
    await r.run('git', ['reset', '--hard'], workingDirectory: dir);

    if (submodules) {
      await r.run('git', [
        'submodule',
        'update',
        '--init',
        '--recursive',
      ], workingDirectory: dir);
    }
  }
}

/// Strip debug symbols from a native library.
final class StripStep implements NativeBuildStep {
  const StripStep({
    required this.id,
    required this.inputPath,
    this.outputPath,
    this.stripDebug = true,
    this.stripUnneeded = true,
    this.runner,
  });

  @override
  final String id;

  /// Path to the input library.
  final String inputPath;

  /// Path for the output library. If null, overwrites input.
  final String? outputPath;

  /// Whether to strip debug symbols.
  final bool stripDebug;

  /// Whether to strip unneeded symbols.
  final bool stripUnneeded;

  /// Optional process runner.
  final ProcessRunnerInterface? runner;

  @override
  Future<NativeStepFingerprint> fingerprint(NativeStepContext context) async {
    return NativeStepFingerprint(
      id: id,
      hash: inputPath.hashCode.toRadixString(16),
    );
  }

  @override
  Future<void> execute(
    NativeBuildContext context,
    ResolvedSource source,
  ) async {
    final r = runner ?? const ProcessRunner();
    final input = p.isAbsolute(inputPath)
        ? inputPath
        : p.join(source.directory.path, inputPath);
    final output = outputPath ?? input;

    final args = <String>[];
    if (stripDebug) args.add('--strip-debug');
    if (stripUnneeded) args.add('--strip-unneeded');
    args.addAll([input, '-o', output]);

    // Try llvm-strip first (from NDK), then system strip
    try {
      await r.run('llvm-strip', args, requireSuccess: false);
    } catch (_) {
      await r.run('strip', args);
    }
  }
}

/// Find a built artifact by name in a directory tree.
final class FindArtifactStep implements NativeBuildStep {
  const FindArtifactStep({
    required this.id,
    this.fileName,
    this.libraryStem,
    this.searchDirectory,
  });

  @override
  final String id;

  /// Exact filename to find (e.g., `libtdjson.so`).
  final String? fileName;

  /// Library stem to search for (e.g., `tdjson`). Will match platform variants.
  final String? libraryStem;

  /// Directory to search in. Defaults to the build output directory.
  final String? searchDirectory;

  @override
  Future<NativeStepFingerprint> fingerprint(NativeStepContext context) async {
    return NativeStepFingerprint(
      id: id,
      hash: (fileName ?? libraryStem ?? 'unknown').hashCode.toRadixString(16),
    );
  }

  @override
  Future<void> execute(
    NativeBuildContext context,
    ResolvedSource source,
  ) async {
    final searchDir = searchDirectory ?? source.directory.path;
    final target = fileName ?? _platformLibraryName(libraryStem ?? 'unknown');

    final found = _findFile(Directory(searchDir), target);
    if (found == null) {
      throw StateError('Could not find $target in $searchDir');
    }

    // Copy to output
    final outputFile = File(p.join(context.directories.output.path, target));
    outputFile.parent.createSync(recursive: true);
    File(found).copySync(outputFile.path);
  }

  String? _findFile(Directory dir, String name) {
    if (!dir.existsSync()) return null;
    for (final entity in dir.listSync(recursive: true)) {
      if (entity is File &&
          p.basename(entity.path).toLowerCase() == name.toLowerCase()) {
        return entity.path;
      }
    }
    return null;
  }

  String _platformLibraryName(String stem) {
    if (Platform.isWindows) return '$stem.dll';
    if (Platform.isMacOS || Platform.isIOS) return 'lib$stem.dylib';
    return 'lib$stem.so';
  }
}

/// Apply a git patch to a directory.
final class GitApplyPatchStep implements NativeBuildStep {
  const GitApplyPatchStep({
    required this.id,
    required this.patchPath,
    this.targetDirectory,
    this.runner,
  });

  @override
  final String id;

  /// Path to the patch file.
  final String patchPath;

  /// Directory to apply the patch to. Defaults to the work directory.
  final String? targetDirectory;

  /// Optional process runner.
  final ProcessRunnerInterface? runner;

  @override
  Future<NativeStepFingerprint> fingerprint(NativeStepContext context) async {
    return NativeStepFingerprint(
      id: id,
      hash: patchPath.hashCode.toRadixString(16),
    );
  }

  @override
  Future<void> execute(
    NativeBuildContext context,
    ResolvedSource source,
  ) async {
    final logger = context.logger;
    logger?.info('[git_apply_patch] Applying patch');
    final r = runner ?? const ProcessRunner();
    final patch = p.isAbsolute(patchPath)
        ? patchPath
        : p.join(source.directory.path, patchPath);
    final target = targetDirectory ?? context.directories.work.path;

    logger?.info('[git_apply_patch] Patch: $patch');
    logger?.info('[git_apply_patch] Target: $target');
    await r.run('git', ['apply', patch], workingDirectory: Directory(target));
    logger?.info('[git_apply_patch] Patch applied');
  }
}

/// Copy files or directories.
final class CopyStep implements NativeBuildStep {
  const CopyStep({
    required this.id,
    required this.sourcePath,
    required this.destinationPath,
    this.recursive = true,
  });

  @override
  final String id;

  /// Source file or directory path.
  final String sourcePath;

  /// Destination path.
  final String destinationPath;

  /// Whether to copy directories recursively.
  final bool recursive;

  @override
  Future<NativeStepFingerprint> fingerprint(NativeStepContext context) async {
    return NativeStepFingerprint(
      id: id,
      hash: '${sourcePath}_$destinationPath'.hashCode.toRadixString(16),
    );
  }

  @override
  Future<void> execute(
    NativeBuildContext context,
    ResolvedSource source,
  ) async {
    final logger = context.logger;
    logger?.info('[copy] Copying files');
    final src = p.isAbsolute(sourcePath)
        ? sourcePath
        : p.join(source.directory.path, sourcePath);
    final dest = p.isAbsolute(destinationPath)
        ? destinationPath
        : p.join(context.directories.work.path, destinationPath);

    logger?.info('[copy] Source: $src');
    logger?.info('[copy] Destination: $dest');
    final srcEntity = FileSystemEntity.typeSync(src);
    if (srcEntity == FileSystemEntityType.directory) {
      await _copyDirectory(Directory(src), Directory(dest));
    } else if (srcEntity == FileSystemEntityType.file) {
      Directory(p.dirname(dest)).createSync(recursive: true);
      File(src).copySync(dest);
    }
    logger?.info('[copy] Copy completed');
  }

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
