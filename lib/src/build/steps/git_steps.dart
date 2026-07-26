import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../fingerprint.dart';
import '../native_build_context.dart';
import '../native_build_recipe.dart';
import '../process_runner.dart';
import '../../source/resolved_source.dart';

/// Git checkout step.
///
/// Clones a git repository at a specific revision.
final class GitCheckoutStep implements NativeBuildStep {
  const GitCheckoutStep({
    required this.id,
    required this.repository,
    required this.revision,
    this.targetDirectory,
    this.submodules = false,
    this.runner,
  });

  /// Step identifier.
  @override
  final String id;

  /// Repository URL (e.g., https://github.com/org/repo.git).
  final String repository;

  /// Revision to checkout (commit SHA, tag, or branch).
  final String revision;

  /// Target directory (relative to work directory or absolute).
  final String? targetDirectory;

  /// Whether to initialize and update submodules.
  final bool submodules;

  /// Optional process runner.
  final ProcessRunnerInterface? runner;

  /// Creates a [GitCheckoutStep] from a YAML-derived map.
  factory GitCheckoutStep.fromMap(Map<String, dynamic> map) {
    return GitCheckoutStep(
      id: map['id'] as String,
      repository: map['repository'] as String,
      revision: map['revision'] as String,
      targetDirectory: map['target_directory'] as String?,
      submodules: map['submodules'] as bool? ?? false,
    );
  }

  /// Serializes this step to a map suitable for YAML output.
  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'type': 'git_checkout',
      'id': id,
      'repository': repository,
      'revision': revision,
      if (targetDirectory != null) 'target_directory': targetDirectory,
      if (submodules) 'submodules': submodules,
    };
  }

  @override
  Map<String, dynamic> toJson() => toMap();

  @override
  Future<NativeStepFingerprint> fingerprint(NativeStepContext context) async {
    final buffer = StringBuffer();
    buffer.write('git_checkout');
    buffer.write(repository);
    buffer.write(revision);
    if (targetDirectory != null) buffer.write(targetDirectory);
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
    logger?.info('[git_checkout] Cloning repository');
    final r = runner ?? ProcessRunner(logger: logger);
    final targetDir = targetDirectory != null
        ? (p.isAbsolute(targetDirectory!)
              ? targetDirectory!
              : p.join(context.directories.work.path, targetDirectory!))
        : p.join(context.directories.work.path, id);

    Directory(targetDir).createSync(recursive: true);

    await r.runStreaming('git', ['init', targetDir]);
    await r.runStreaming('git', [
      '-C',
      targetDir,
      'remote',
      'add',
      'origin',
      repository,
    ]);
    await r.runStreaming('git', [
      '-C',
      targetDir,
      'fetch',
      '--depth=1',
      'origin',
      revision,
    ]);
    await r.runStreaming('git', ['-C', targetDir, 'checkout', '--detach', 'FETCH_HEAD']);

    if (submodules) {
      await _runGit([
        'submodule',
        'update',
        '--init',
        '--recursive',
        '--depth=1',
      ], workingDirectory: Directory(targetDir));
    }

    return const NativeStepResult();
  }

  Future<void> _runGit(List<String> args, {Directory? workingDirectory}) async {
    final r = ProcessRunner();
    await r.runStreaming('git', args, workingDirectory: workingDirectory);
  }
}

/// Apply a git patch.
final class GitApplyPatchStep implements NativeBuildStep {
  const GitApplyPatchStep({
    required this.patchPath,
    this.targetDirectory,
    this.runner,
  });

  @override
  final String id = 'git_apply_patch';

  /// Path to the patch file (relative to source or absolute).
  final String patchPath;

  /// Target directory to apply patch (relative to work dir or absolute).
  final String? targetDirectory;

  /// Optional process runner.
  final ProcessRunnerInterface? runner;

  /// Creates a [GitApplyPatchStep] from a YAML-derived map.
  factory GitApplyPatchStep.fromMap(Map<String, dynamic> map) {
    return GitApplyPatchStep(
      patchPath: map['patch_path'] as String,
      targetDirectory: map['target_directory'] as String?,
    );
  }

  /// Serializes this step to a map suitable for YAML output.
  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'type': 'git_apply_patch',
      'patch_path': patchPath,
      if (targetDirectory != null) 'target_directory': targetDirectory,
    };
  }

  @override
  Map<String, dynamic> toJson() => toMap();

  @override
  Future<NativeStepFingerprint> fingerprint(NativeStepContext context) async {
    return NativeStepFingerprint(id: id, hash: fingerprintHash(patchPath));
  }

  @override
  Future<NativeStepResult> execute(
    NativeBuildContext context,
    ResolvedSource source,
  ) async {
    final logger = context.logger;
    logger?.info('[git_apply_patch] Applying patch');
    final r = runner ?? ProcessRunner(logger: logger);
    final patch = p.isAbsolute(patchPath)
        ? patchPath
        : p.join(source.directory.path, patchPath);
    final target = targetDirectory ?? context.directories.work.path;

    logger?.info('[git_apply_patch] Patch: $patch');
    logger?.info('[git_apply_patch] Target: $target');
    await r.runStreaming('git', ['apply', patch], workingDirectory: Directory(target));
    logger?.info('[git_apply_patch] Patch applied');

    return const NativeStepResult();
  }
}
