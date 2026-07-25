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

    process.stdout.listen((data) {
      final raw = String.fromCharCodes(data);
      stdoutBuffer.write(raw);
      // Strip trailing newlines to avoid blank lines in log output —
      // the logger adds its own line terminator.
      final line = raw.trimRight();
      if (line.isNotEmpty) {
        logger?.info('  $line');
      }
    });

    process.stderr.listen((data) {
      final raw = String.fromCharCodes(data);
      stderrBuffer.write(raw);
      // Strip trailing newlines to avoid blank lines in log output.
      final line = raw.trimRight();
      if (line.isNotEmpty) {
        logger?.warning('  $line');
      }
    });

    final exitCode = await process.exitCode;

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
