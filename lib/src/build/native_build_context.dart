import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:logging/logging.dart';

import '../platform/native_target.dart';
import '../build/toolchains/toolchains.dart';

export '../platform/native_target.dart' show NativeTarget;

/// Platform-specific build configuration for Android.
final class AndroidBuildTarget {
  const AndroidBuildTarget({
    required this.abi,
    required this.requestedApi,
    required this.effectiveApi,
    required this.ndk,
  });

  /// The Android ABI (e.g., `arm64-v8a`, `x86_64`).
  final String abi;

  /// The API level requested by the build.
  final int requestedApi;

  /// The effective API level after resolution.
  final int effectiveApi;

  /// The Android NDK directory.
  final Directory ndk;
}

/// Platform-specific build configuration for Apple platforms.
final class AppleBuildTarget {
  const AppleBuildTarget({
    required this.sdk,
    required this.deploymentTarget,
    required this.architecture,
    required this.isSimulator,
  });

  /// The Apple SDK (e.g., `iphoneos`, `iphonesimulator`, `macosx`).
  final IOSSdk sdk;

  /// The minimum deployment target (e.g., `17.0`).
  final String deploymentTarget;

  /// The target CPU architecture.
  final Architecture architecture;

  /// Whether this is a simulator build.
  final bool isSimulator;
}

/// Platform-specific build configuration for Windows.
final class WindowsBuildTarget {
  const WindowsBuildTarget({
    required this.msvcArchitecture,
    required this.vcpkgTriplet,
  });

  /// The MSVC architecture (e.g., `x64`, `x86`).
  final String msvcArchitecture;

  /// The vcpkg triplet (e.g., `x64-windows`, `x64-windows-static`).
  final String vcpkgTriplet;
}

/// Configuration for a native build.
///
/// Contains all the information needed to compile a native library
/// for a specific target platform.
final class NativeBuildContext {
  const NativeBuildContext({
    required this.target,
    required this.hook,
    required this.directories,
    required this.toolchains,
    required this.environment,
    this.options = const <String, Object?>{},
    this.variables = const <String, Object?>{},
    this.logger,
  });

  /// The target platform to build for.
  final NativeTarget target;

  /// The hook configuration.
  final NativeHookConfiguration hook;

  /// The build directories (source, output, cache, etc.).
  final NativeBuildDirectories directories;

  /// The available toolchains for this build.
  final ToolchainRegistry toolchains;

  /// Environment variables to pass to build tools.
  final Map<String, String> environment;

  /// User-defined recipe values from `build.options`.
  final Map<String, Object?> options;

  /// Shared recipe values from the manifest's `variables` section.
  final Map<String, Object?> variables;

  /// Optional logger for build output.
  final Logger? logger;
}

/// Hook configuration for a native build.
final class NativeHookConfiguration {
  const NativeHookConfiguration({
    required this.packageName,
    required this.assetName,
    required this.libraryStem,
    required this.linkMode,
  });

  /// The Dart package name.
  final String packageName;

  /// The Dart library path that declares the native code asset.
  final String assetName;

  /// The library stem (e.g., `tdjson` for libtdjson.so).
  final String libraryStem;

  /// The link mode (dynamic or static).
  final LinkMode linkMode;
}

/// Directories used during a native build.
final class NativeBuildDirectories {
  const NativeBuildDirectories({
    required this.source,
    required this.output,
    required this.cache,
    required this.work,
  });

  /// The source directory.
  final Directory source;

  /// The output directory for built artifacts.
  final Directory output;

  /// The cache directory for intermediate build results.
  final Directory cache;

  /// The working directory for the build process.
  final Directory work;
}

/// Registry of available platform toolchains.
final class ToolchainRegistry {
  const ToolchainRegistry({
    this.androidNdk,
    this.appleSdk,
    this.msvc,
    this.vcpkg,
  });

  /// The Android NDK toolchain.
  final AndroidNdkToolchain? androidNdk;

  /// The Apple SDK toolchain.
  final AppleSdkToolchain? appleSdk;

  /// The MSVC toolchain.
  final MsvcToolchain? msvc;

  /// The vcpkg toolchain.
  final VcpkgToolchain? vcpkg;
}
