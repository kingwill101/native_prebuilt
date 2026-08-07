import 'dart:async';
import 'dart:io' show ProcessException;

import 'package:path/path.dart' as p;

import '../fingerprint.dart';
import '../native_build_context.dart';
import '../native_build_recipe.dart';
import '../process_runner.dart';
import '../recipe_value_expansion.dart';
import '../toolchains/toolchain_registry.dart';
import '../../source/resolved_source.dart';

/// Strip debug symbols from a binary.
final class StripStep implements NativeBuildStep {
  const StripStep({
    required this.id,
    this.execution = 'target',
    required this.inputPath,
    required this.outputPath,
    this.stripAll = false,
    this.runner,
  });

  @override
  final String id;

  @override
  final String execution;


  /// Source file to strip (relative to work dir or absolute).
  final String inputPath;

  /// Output file path (relative to work dir or absolute).
  final String outputPath;

  /// Whether to strip all symbols (not just debug).
  final bool stripAll;

  /// Optional process runner.
  final ProcessRunnerInterface? runner;

  /// Creates a [StripStep] from a YAML-derived map.
  factory StripStep.fromMap(Map<String, dynamic> map) {
    return StripStep(
      id: map['id'] as String,
      inputPath: map['input_path'] as String,
      outputPath: map['output_path'] as String,
      stripAll: map['strip_all'] as bool? ?? false,
    );
  }

  /// Serializes this step to a map suitable for YAML output.
  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'type': 'strip',
      'id': id,
      'input_path': inputPath,
      'output_path': outputPath,
      if (stripAll) 'strip_all': stripAll,
    };
  }

  @override
  Map<String, dynamic> toJson() => toMap();

  @override
  Future<NativeStepFingerprint> fingerprint(NativeStepContext context) async {
    return NativeStepFingerprint(
      id: id,
      hash: fingerprintHash(
        '$id:${expandRecipeValue(inputPath, context.buildContext, context.source)}_'
        '${expandRecipeValue(outputPath, context.buildContext, context.source)}',
      ),
    );
  }

  @override
  Future<NativeStepResult> execute(
    NativeBuildContext context,
    ResolvedSource source,
  ) async {
    final logger = context.logger;
    logger?.info('[strip] Stripping binary');
    final r = runner ?? ProcessRunner(logger: logger);
    final resolvedInputPath = expandRecipeValue(inputPath, context, source);
    final resolvedOutputPath = expandRecipeValue(outputPath, context, source);
    final input = p.isAbsolute(resolvedInputPath)
        ? resolvedInputPath
        : p.join(context.directories.work.path, resolvedInputPath);
    final output = p.isAbsolute(resolvedOutputPath)
        ? resolvedOutputPath
        : p.join(context.directories.work.path, resolvedOutputPath);

    final resolver = const NativeToolchainResolver();
    final stripCmd = resolver.stripCommand(context.target);
    final args = <String>[];
    if (stripAll) {
      args.add('-s');
    }
    // xcrun strip needs `xcrun strip ...`, plain strip is `strip ...`
    final resolvedArgs = stripCmd.length > 1
        ? [...stripCmd.sublist(1), ...args, '-o', output, input]
        : [...args, '-o', output, input];
    final exe = stripCmd.first;
    try {
      await r.runStreaming(exe, resolvedArgs);
    } on ProcessException {
      // Fallback chain: try llvm-strip then system strip
      if (exe != 'llvm-strip') {
        logger?.info('[strip] $exe failed, trying llvm-strip');
        try {
          await r.runStreaming('llvm-strip', [...args, '-o', output, input]);
        } on ProcessException {
          logger?.info('[strip] llvm-strip failed, trying strip');
          await r.runStreaming('strip', [...args, '-o', output, input]);
        }
      } else {
        logger?.info('[strip] llvm-strip failed, trying strip');
        await r.runStreaming('strip', [...args, '-o', output, input]);
      }
    }
    logger?.info('[strip] Stripped: $outputPath');

    return const NativeStepResult();
  }
}
