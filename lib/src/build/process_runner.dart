import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:logging/logging.dart';

/// Result of a process execution.
final class ProcessResult {
  const ProcessResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });

  /// The exit code of the process.
  final int exitCode;

  /// The standard output of the process.
  final String stdout;

  /// The standard error of the process.
  final String stderr;

  /// Whether the process completed successfully.
  bool get isSuccess => exitCode == 0;
}

/// Abstract interface for running external processes.
///
/// This interface allows testing build steps with fake process runners.
abstract interface class ProcessRunnerInterface {
  /// Run a command and stream output in real-time.
  Future<ProcessResult> runStreaming(
    String executable,
    List<String> arguments, {
    Directory? workingDirectory,
    Map<String, String>? environment,
    bool requireSuccess = true,
  });
}

/// Runs external processes with logging and error handling.
final class ProcessRunner implements ProcessRunnerInterface {
  const ProcessRunner({this.logger});

  /// Logger for process output.
  final Logger? logger;

  @override
  Future<ProcessResult> runStreaming(
    String executable,
    List<String> arguments, {
    Directory? workingDirectory,
    Map<String, String>? environment,
    bool requireSuccess = true,
  }) async {
    logger?.info('Running: $executable ${arguments.join(' ')}');

    final process = await Process.start(
      executable,
      arguments,
      workingDirectory: workingDirectory?.path,
      environment: environment,
    );

    final stdoutBuffer = StringBuffer();
    final stderrBuffer = StringBuffer();
    final stdoutDone = Completer<void>();
    final stderrDone = Completer<void>();

    process.stdout
        .transform(utf8.decoder)
        .listen(
          (chunk) {
            stdoutBuffer.write(chunk);
            final line = chunk.trimRight();
            if (line.isNotEmpty) {
              logger?.info('  $line');
            }
          },
          onDone: () => stdoutDone.complete(),
          onError: stdoutDone.completeError,
          cancelOnError: true,
        );

    process.stderr
        .transform(utf8.decoder)
        .listen(
          (chunk) {
            stderrBuffer.write(chunk);
            final line = chunk.trimRight();
            if (line.isNotEmpty) {
              logger?.warning('  $line');
            }
          },
          onDone: () => stderrDone.complete(),
          onError: stderrDone.completeError,
          cancelOnError: true,
        );

    final exitCode = await process.exitCode;
    await Future.wait([stdoutDone.future, stderrDone.future]);

    if (requireSuccess && exitCode != 0) {
      throw ProcessException(
        executable,
        arguments,
        'Process exited with code $exitCode',
        exitCode,
      );
    }

    return ProcessResult(
      exitCode: exitCode,
      stdout: stdoutBuffer.toString(),
      stderr: stderrBuffer.toString(),
    );
  }
}
