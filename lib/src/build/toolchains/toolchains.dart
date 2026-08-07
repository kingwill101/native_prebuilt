import 'dart:io';

import '../process_runner.dart';

export 'toolchain_registry.dart';

/// Platform toolchain interface for native builds.
abstract interface class PlatformToolchain {
  /// Execute a command with platform-specific configuration.
  Future<void> execute(
    String command,
    List<String> args,
    Directory workingDirectory,
  );
}

/// Android NDK toolchain implementation.
final class AndroidNdkToolchain implements PlatformToolchain {
  const AndroidNdkToolchain({
    required this.ndkDirectory,
    required this.version,
    this.runner,
  });

  final Directory ndkDirectory;
  final String version;
  final ProcessRunner? runner;

  @override
  Future<void> execute(
    String command,
    List<String> args,
    Directory workingDirectory,
  ) async {
    final r = runner ?? ProcessRunner();
    await r.runStreaming(command, args, workingDirectory: workingDirectory);
  }
}

/// Apple SDK toolchain implementation.
final class AppleSdkToolchain implements PlatformToolchain {
  const AppleSdkToolchain({
    required this.sdkDirectory,
    required this.version,
    this.runner,
  });

  final Directory sdkDirectory;
  final String version;
  final ProcessRunner? runner;

  @override
  Future<void> execute(
    String command,
    List<String> args,
    Directory workingDirectory,
  ) async {
    final r = runner ?? ProcessRunner();
    await r.runStreaming(command, args, workingDirectory: workingDirectory);
  }
}

/// MSVC toolchain implementation.
final class MsvcToolchain implements PlatformToolchain {
  const MsvcToolchain({
    required this.visualStudioDirectory,
    required this.version,
    this.runner,
  });

  final Directory visualStudioDirectory;
  final String version;
  final ProcessRunner? runner;

  @override
  Future<void> execute(
    String command,
    List<String> args,
    Directory workingDirectory,
  ) async {
    final r = runner ?? ProcessRunner();
    await r.runStreaming(command, args, workingDirectory: workingDirectory);
  }
}

/// vcpkg toolchain implementation.
final class VcpkgToolchain implements PlatformToolchain {
  const VcpkgToolchain({
    required this.vcpkgRoot,
    required this.triplet,
    this.runner,
  });

  final Directory vcpkgRoot;
  final String triplet;
  final ProcessRunner? runner;

  @override
  Future<void> execute(
    String command,
    List<String> args,
    Directory workingDirectory,
  ) async {
    final r = runner ?? ProcessRunner();
    await r.runStreaming(command, args, workingDirectory: workingDirectory);
  }
}
