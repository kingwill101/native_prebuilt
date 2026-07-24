/// A fake process runner for testing build steps.
///
/// Records all commands that were executed and allows pre-configuring
/// results for expected commands.
library;

import 'dart:collection';
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:native_prebuilt/src/build/process_runner.dart';

/// A fake process runner that records commands and returns pre-configured results.
///
/// This allows testing build steps without actually invoking CMake, compilers,
/// or other external tools.
final class RecordingProcessRunner implements ProcessRunnerInterface {
  RecordingProcessRunner({this.logger});

  final Logger? logger;
  final List<RecordedCommand> _commands = [];
  final Queue<ProcessResult> _results = Queue();

  /// All commands that were executed.
  List<RecordedCommand> get commands => List.unmodifiable(_commands);

  /// Enqueues a result to be returned by the next [run] call.
  void enqueueResult(ProcessResult result) {
    _results.add(result);
  }

  /// Enqueues multiple results.
  void enqueueResults(List<ProcessResult> results) {
    for (final result in results) {
      _results.add(result);
    }
  }

  /// Enqueues a success result (exit code 0).
  void enqueueSuccess({String stdout = '', String stderr = ''}) {
    enqueueResult(ProcessResult(exitCode: 0, stdout: stdout, stderr: stderr));
  }

  /// Enqueues a failure result (non-zero exit code).
  void enqueueFailure({
    int exitCode = 1,
    String stdout = '',
    String stderr = 'Command failed',
  }) {
    enqueueResult(
      ProcessResult(exitCode: exitCode, stdout: stdout, stderr: stderr),
    );
  }

  @override
  Future<ProcessResult> run(
    String executable,
    List<String> arguments, {
    Directory? workingDirectory,
    Map<String, String>? environment,
    bool requireSuccess = true,
  }) async {
    _commands.add(
      RecordedCommand(
        executable: executable,
        arguments: arguments,
        workingDirectory: workingDirectory?.path,
        environment: environment,
      ),
    );

    if (_results.isEmpty) {
      // Default: return success
      return const ProcessResult(exitCode: 0, stdout: '', stderr: '');
    }

    final result = _results.removeFirst();

    if (requireSuccess && !result.isSuccess) {
      throw ProcessException(
        executable,
        arguments,
        'Process exited with code ${result.exitCode}',
        result.exitCode,
      );
    }

    return result;
  }

  @override
  Future<ProcessResult> runStreaming(
    String executable,
    List<String> arguments, {
    Directory? workingDirectory,
    Map<String, String>? environment,
    bool requireSuccess = true,
  }) {
    return run(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      environment: environment,
      requireSuccess: requireSuccess,
    );
  }

  /// Clears all recorded commands and queued results.
  void reset() {
    _commands.clear();
    _results.clear();
  }
}

/// A recorded command execution.
final class RecordedCommand {
  const RecordedCommand({
    required this.executable,
    required this.arguments,
    this.workingDirectory,
    this.environment,
  });

  /// The executable that was invoked.
  final String executable;

  /// The arguments passed to the executable.
  final List<String> arguments;

  /// The working directory, if specified.
  final String? workingDirectory;

  /// The environment variables, if specified.
  final Map<String, String>? environment;

  /// Returns true if this command matches the given executable and contains
  /// the given argument substring.
  bool matches(String executable, {String? argumentSubstring}) {
    if (this.executable != executable) return false;
    if (argumentSubstring == null) return true;
    return arguments.any((a) => a.contains(argumentSubstring));
  }

  /// Returns the full command line as a string.
  String get commandLine {
    final parts = [executable, ...arguments];
    return parts.join(' ');
  }
}
