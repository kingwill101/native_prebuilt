/// Test utilities for creating hook inputs.
library;

import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:native_prebuilt/native_prebuilt.dart';
import 'package:path/path.dart' as p;

/// Creates a minimal [NativeBuildContext] for testing.
///
/// This is useful for testing builders and resolvers without
/// needing a full hook invocation.
NativeBuildContext createTestContext({
  required Directory workDir,
  OS? targetOS,
  Architecture? targetArchitecture,
}) {
  targetOS ??= _currentOS;
  targetArchitecture ??= switch (targetOS) {
    OS.linux => Architecture.x64,
    OS.macOS => Architecture.arm64,
    OS.windows => Architecture.x64,
    OS.android => Architecture.arm64,
    OS.iOS => Architecture.arm64,
    _ => Architecture.x64,
  };

  return NativeBuildContext(
    target: NativeTarget(os: targetOS, architecture: targetArchitecture),
    hook: NativeHookConfiguration(
      packageName: 'test_package',
      assetName: 'test_asset',
      libraryStem: 'test_lib',
      linkMode: DynamicLoadingBundled(),
    ),
    directories: NativeBuildDirectories(
      source: workDir,
      output: Directory(p.join(workDir.path, 'output'))..createSync(),
      cache: Directory(p.join(workDir.path, 'cache'))..createSync(),
      work: workDir,
    ),
    toolchains: const ToolchainRegistry(),
    environment: {},
  );
}

/// Creates a [ResolvedSource] for testing.
ResolvedSource createTestSource({
  Directory? directory,
  SourceOrigin origin = SourceOrigin.local,
}) {
  return ResolvedSource(
    directory: directory ?? Directory.systemTemp.createTempSync('test_source_'),
    origin: origin,
  );
}

/// Get the current OS from the platform.
OS get _currentOS {
  if (Platform.isLinux) return OS.linux;
  if (Platform.isMacOS) return OS.macOS;
  if (Platform.isWindows) return OS.windows;
  return OS.linux; // Default fallback
}
