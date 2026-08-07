import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../fingerprint.dart';
import '../native_build_context.dart';
import '../native_build_recipe.dart';
import '../process_runner.dart';
import '../recipe_value_expansion.dart';
import '../../source/resolved_source.dart';

/// Generic command execution step.
///
/// Runs one or more commands with arguments, optionally in a working directory.
final class CommandStep implements NativeBuildStep {
  const CommandStep({
    required this.id,
    this.execution = 'target',
    required this.commands,
    this.workingDirectory,
    this.environment,
    this.runner,
  });

  /// Step identifier.
  @override
  final String id;

  @override
  final String execution;


  /// Commands to execute in order. Each entry is [executable, ...args].
  final List<List<String>> commands;

  /// Working directory for all commands.
  final String? workingDirectory;

  /// Environment variables to pass to the process.
  final Map<String, String>? environment;

  /// Optional process runner.
  final ProcessRunnerInterface? runner;

  /// Creates a [CommandStep] from a YAML-derived map.
  factory CommandStep.fromMap(Map<String, dynamic> map) {
    return CommandStep(
      id: map['id'] as String,
      commands: (map['commands'] as List<dynamic>)
          .map(
            (cmd) => (cmd as List<dynamic>).map((e) => e.toString()).toList(),
          )
          .toList(),
      workingDirectory: map['working_directory'] as String?,
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
      'type': 'command',
      'id': id,
      'commands': commands,
      if (workingDirectory != null) 'working_directory': workingDirectory,
      if (environment != null) 'environment': environment,
    };
  }

  @override
  Map<String, dynamic> toJson() => toMap();

  @override
  Future<NativeStepFingerprint> fingerprint(NativeStepContext context) async {
    final buffer = StringBuffer();
    buffer.write(id);
    for (final cmd in expandRecipeCommands(
      commands,
      context.buildContext,
      context.source,
    )) {
      buffer.write(cmd.join(' '));
    }
    if (workingDirectory != null) {
      buffer.write(
        expandRecipeValue(
          workingDirectory!,
          context.buildContext,
          context.source,
        ),
      );
    }
    if (environment != null) {
      buffer.write(
        expandRecipeStringMap(
          environment!,
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
    logger?.info('[$id] Starting command step');
    final r = runner ?? ProcessRunner(logger: logger);
    final workDirPath = workingDirectory == null
        ? context.directories.work.path
        : expandRecipeValue(workingDirectory!, context, source);
    final workDir = Directory(
      p.isAbsolute(workDirPath)
          ? workDirPath
          : p.join(context.directories.work.path, workDirPath),
    );
    final env = environment == null
        ? null
        : expandRecipeStringMap(environment!, context, source);

    for (final cmd in expandRecipeCommands(commands, context, source)) {
      logger?.info('[$id] Running: ${cmd.join(' ')}');
      await r.runStreaming(
        cmd[0],
        cmd.sublist(1),
        workingDirectory: workDir,
        environment: env,
      );
      logger?.info('[$id] Command completed');
    }

    return const NativeStepResult();
  }
}
