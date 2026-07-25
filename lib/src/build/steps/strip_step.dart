import 'dart:async';
import 'dart:io' show ProcessException;

import 'package:path/path.dart' as p;

import '../fingerprint.dart';
import '../native_build_context.dart';
import '../native_build_recipe.dart';
import '../process_runner.dart';
import '../../source/resolved_source.dart';

/// Strip debug symbols from a binary.
final class StripStep implements NativeBuildStep {
  const StripStep({
    required this.id,
    required this.inputPath,
    required this.outputPath,
    this.stripAll = false,
    this.runner,
  });

  @override
  final String id;

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
  Future<NativeStepFingerprint> fingerprint(NativeStepContext context) async {
    return NativeStepFingerprint(
      id: id,
      hash: fingerprintHash('${inputPath}_$outputPath'),
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
    final input = p.isAbsolute(inputPath)
        ? inputPath
        : p.join(source.directory.path, inputPath);
    final output = p.isAbsolute(outputPath)
        ? outputPath
        : p.join(context.directories.work.path, outputPath);

    final args = <String>[];
    if (stripAll) {
      args.add('-s');
    }
    args.addAll(['-o', output, input]);

    // Try system strip first, fall back to llvm-strip
    try {
      await r.runStreaming('strip', args);
    } on ProcessException {
      logger?.info('[strip] System strip failed, trying llvm-strip');
      await r.runStreaming('llvm-strip', args);
    }
    logger?.info('[strip] Stripped: $outputPath');

    return const NativeStepResult();
  }
}
