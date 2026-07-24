import 'dart:io';

import '../process_runner.dart';

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
    // Android-specific build commands
    final ndkBuildArgs = [...args, '--build-dir=build'];
    final r = runner ?? ProcessRunner();
    await r.run('ndk-build', ndkBuildArgs, workingDirectory: workingDirectory);
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
    // Apple-specific build commands
    final xcodeBuildArgs = [
      ...args,
      '-scheme',
      'MyApp',
      '-configuration',
      'Release',
    ];
    final r = runner ?? ProcessRunner();
    await r.run(
      'xcodebuild',
      xcodeBuildArgs,
      workingDirectory: workingDirectory,
    );
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
    // MSVC-specific build commands
    final clArgs = [...args, '/EHsc', '/Fe:output.exe'];
    final r = runner ?? ProcessRunner();
    await r.run('cl', clArgs, workingDirectory: workingDirectory);
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
    // vcpkg-specific build commands
    final vcpkgArgs = [...args, '--triplet', triplet];
    final r = runner ?? ProcessRunner();
    await r.run('vcpkg', vcpkgArgs, workingDirectory: workingDirectory);
  }
}
