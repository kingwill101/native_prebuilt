import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../fingerprint.dart';
import '../native_build_context.dart';
import '../native_build_recipe.dart';
import '../process_runner.dart';
import '../recipe_value_expansion.dart';
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
    buffer.write(
      expandRecipeValue(repository, context.buildContext, context.source),
    );
    buffer.write(
      expandRecipeValue(revision, context.buildContext, context.source),
    );
    buffer.write(submodules);
    if (targetDirectory != null) {
      buffer.write(
        expandRecipeValue(
          targetDirectory!,
          context.buildContext,
          context.source,
        ),
      );
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
    logger?.info('[git_checkout] Cloning repository');
    final r = runner ?? ProcessRunner(logger: logger);
    final resolvedRepository = expandRecipeValue(repository, context, source);
    final resolvedRevision = expandRecipeValue(revision, context, source);
    final resolvedTargetDirectory = targetDirectory == null
        ? p.join(context.directories.work.path, id)
        : expandRecipeValue(targetDirectory!, context, source);
    final targetDir = p.isAbsolute(resolvedTargetDirectory)
        ? resolvedTargetDirectory
        : p.join(context.directories.work.path, resolvedTargetDirectory);

    Directory(targetDir).createSync(recursive: true);

    await r.runStreaming('git', ['init', targetDir]);
    final existingOrigin = await r.runStreaming('git', [
      '-C',
      targetDir,
      'remote',
      'get-url',
      'origin',
    ], requireSuccess: false);
    if (existingOrigin.exitCode == 0) {
      await r.runStreaming('git', [
        '-C',
        targetDir,
        'remote',
        'set-url',
        'origin',
        resolvedRepository,
      ]);
    } else {
      await r.runStreaming('git', [
        '-C',
        targetDir,
        'remote',
        'add',
        'origin',
        resolvedRepository,
      ]);
    }
    await r.runStreaming('git', [
      '-C',
      targetDir,
      'fetch',
      '--depth=1',
      'origin',
      resolvedRevision,
    ]);
    await r.runStreaming('git', [
      '-C',
      targetDir,
      'checkout',
      '--detach',
      'FETCH_HEAD',
    ]);

    if (submodules) {
      await _runGit(r, [
        'submodule',
        'update',
        '--init',
        '--recursive',
        '--depth=1',
      ], workingDirectory: Directory(targetDir));
    }

    return const NativeStepResult();
  }

  Future<void> _runGit(
    ProcessRunnerInterface runner,
    List<String> args, {
    Directory? workingDirectory,
  }) async {
    await runner.runStreaming('git', args, workingDirectory: workingDirectory);
  }
}

/// Apply a git patch.
final class GitApplyPatchStep implements NativeBuildStep {
  const GitApplyPatchStep({
    this.id = 'git_apply_patch',
    required this.patchPath,
    this.targetDirectory,
    this.runner,
  });

  @override
  final String id;

  /// Path to the patch file (relative to source or absolute).
  final String patchPath;

  /// Target directory to apply patch (relative to work dir or absolute).
  final String? targetDirectory;

  /// Optional process runner.
  final ProcessRunnerInterface? runner;

  /// Creates a [GitApplyPatchStep] from a YAML-derived map.
  factory GitApplyPatchStep.fromMap(Map<String, dynamic> map) {
    return GitApplyPatchStep(
      id: map['id'] as String? ?? 'git_apply_patch',
      patchPath: map['patch_path'] as String,
      targetDirectory: map['target_directory'] as String?,
    );
  }

  /// Serializes this step to a map suitable for YAML output.
  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'type': 'git_apply_patch',
      'id': id,
      'patch_path': patchPath,
      if (targetDirectory != null) 'target_directory': targetDirectory,
    };
  }

  @override
  Map<String, dynamic> toJson() => toMap();

  @override
  Future<NativeStepFingerprint> fingerprint(NativeStepContext context) async {
    return NativeStepFingerprint(
      id: id,
      hash: fingerprintHash(
        '$id:${expandRecipeValue(patchPath, context.buildContext, context.source)}:'
        '${expandRecipeValue(targetDirectory ?? '', context.buildContext, context.source)}',
      ),
    );
  }

  @override
  Future<NativeStepResult> execute(
    NativeBuildContext context,
    ResolvedSource source,
  ) async {
    final logger = context.logger;
    logger?.info('[git_apply_patch] Applying patch');
    final r = runner ?? ProcessRunner(logger: logger);
    final resolvedPatchPath = expandRecipeValue(patchPath, context, source);
    final patch = p.isAbsolute(resolvedPatchPath)
        ? resolvedPatchPath
        : p.join(source.directory.path, resolvedPatchPath);
    final resolvedTargetDirectory = targetDirectory == null
        ? context.directories.work.path
        : expandRecipeValue(targetDirectory!, context, source);
    final target = p.isAbsolute(resolvedTargetDirectory)
        ? resolvedTargetDirectory
        : p.join(context.directories.work.path, resolvedTargetDirectory);

    logger?.info('[git_apply_patch] Patch: $patch');
    logger?.info('[git_apply_patch] Target: $target');
    await r.runStreaming('git', [
      'apply',
      patch,
    ], workingDirectory: Directory(target));
    logger?.info('[git_apply_patch] Patch applied');

    return const NativeStepResult();
  }
}
