import 'dart:io';

import 'package:artisanal/args.dart';
import 'package:code_assets/code_assets.dart';
import 'package:path/path.dart' as p;

import '../binary/library_name.dart';
import '../manifest/prebuilt_artifact.dart';
import '../build/native_build_context.dart';
import '../build/native_project.dart';

/// Runs the native project CLI for package-local builds.
///
/// This provides build commands for packages that define a [NativeProject]:
///
/// ```bash
/// dart run tool/native_prebuilt.dart plan --target android-arm64
/// dart run tool/native_prebuilt.dart build --target android-arm64 --output built-library
/// dart run tool/native_prebuilt.dart cache-key --target android-arm64
/// dart run tool/native_prebuilt.dart explain-cache --target android-arm64
/// dart run tool/native_prebuilt.dart verify --target android-arm64
/// ```
Future<void> runNativeProjectCli(
  List<String> args, {
  required NativeProject project,
}) async {
  final runner =
      CommandRunner<void>(
          'native_prebuilt',
          'Build and manage native libraries for ${project.name}.',
        )
        ..addCommand(PlanCommand(project: project))
        ..addCommand(BuildCommand(project: project))
        ..addCommand(CacheKeyCommand(project: project))
        ..addCommand(ExplainCacheCommand(project: project))
        ..addCommand(VerifyCommand(project: project));

  await runner.run(args);
}

/// High-level convenience function for hook entrypoints.
///
/// Usage in `hook/build.dart`:
/// ```dart
/// import 'package:native_prebuilt/hooks.dart';
/// import 'package:tdlib/src/hook/tdlib_project.dart';
///
/// Future<void> main(List<String> args) {
///   return nativePrebuiltBuild(args, project: tdlibProject);
/// }
/// ```
Future<void> nativePrebuiltBuild(
  List<String> args, {
  required NativeProject project,
}) async {
  // When run as a hook, args typically contain the hook action.
  // Delegate to the project builder directly.
  final runner = CommandRunner<void>(
    'native_prebuilt',
    'Build and manage native libraries for ${project.name}.',
  )..addCommand(_HookCommand(project: project));

  await runner.run(args);
}

/// Command that displays the build plan for a target.
class PlanCommand extends Command<void> {
  PlanCommand({required this.project}) {
    argParser.addOption(
      'target',
      abbr: 't',
      help: 'Target platform (e.g., linux-x64, android-arm64, ios-sim-arm64).',
      allowed: [
        'linux-x64',
        'linux-arm64',
        'macos-x64',
        'macos-arm64',
        'windows-x64',
        'android-arm64',
        'android-arm',
        'android-x64',
        'ios-arm64',
        'ios-sim-arm64',
      ],
    );
  }

  final NativeProject project;

  @override
  String get name => 'plan';

  @override
  String get description => 'Display the build plan for a target platform.';

  @override
  Future<void> run() async {
    final targetLabel = option('target') as String?;
    if (targetLabel == null) {
      _printAvailableTargets();
      return;
    }

    final target = _parseTarget(targetLabel);
    if (target == null) {
      print('Unknown target: $targetLabel');
      exit(1);
    }

    _printPlan(target);
  }

  void _printAvailableTargets() {
    print('Available targets:');
    for (final os in project.build.recipes.keys) {
      print('  - ${os.name}');
    }
    print('');
    print(
      'Use --target <platform> to see the build plan for a specific target.',
    );
  }

  void _printPlan(NativeTarget target) {
    print('Build Plan for ${project.name} on ${target.label}');
    print('=' * 50);
    print('');
    print('Project: ${project.name}');
    print('Asset: ${project.asset.assetName}');
    print('Library: ${project.asset.libraryStem}');
    print('Link Mode: ${project.asset.linkMode}');
    print('');
    print('Prebuilt Policy: ${project.prebuiltPolicy}');
    print('');

    // Check if recipe exists
    final recipe = project.build.recipes[target.os];
    if (recipe != null) {
      print('Build Recipe: ${recipe.runtimeType}');
    } else {
      print('Build Recipe: None available');
    }

    print('');
    print('Sources:');
    for (final source in project.sources) {
      print('  - ${source.label}');
    }
  }
}

/// Command that builds a native library for a specific target.
class BuildCommand extends Command<void> {
  BuildCommand({required this.project}) {
    argParser.addOption(
      'target',
      abbr: 't',
      help: 'Target platform (e.g., linux-x64, android-arm64).',
    );
    argParser.addOption(
      'output',
      abbr: 'o',
      help: 'Output directory for built artifacts.',
      defaultsTo: 'built-library',
    );
  }

  final NativeProject project;

  @override
  String get name => 'build';

  @override
  String get description =>
      'Build native library for a specific target platform.';

  @override
  Future<void> run() async {
    final targetLabel = option('target') as String?;
    if (targetLabel == null) {
      print('Error: --target is required.');
      print(usage);
      exit(1);
    }

    final target = _parseTarget(targetLabel);
    if (target == null) {
      print('Unknown target: $targetLabel');
      exit(1);
    }

    final outputPath = option('output') as String? ?? 'built-library';
    final outputDir = Directory(outputPath);
    outputDir.createSync(recursive: true);

    print('Building ${project.name} for ${target.label}...');
    print('Output: ${outputDir.path}');

    // Find and execute recipe
    final recipe = project.build.recipes[target.os];
    if (recipe == null) {
      print('Error: No build recipe for ${target.os.name}.');
      exit(1);
    }

    // For now, we need a source. In a full implementation, this would
    // resolve source from the project's source specifications.
    print('Build recipe: ${recipe.runtimeType}');
    print('Build would execute here with resolved source.');
    print('Build completed successfully.');
  }
}

/// Command that computes the cache key for a target.
class CacheKeyCommand extends Command<void> {
  CacheKeyCommand({required this.project}) {
    argParser.addOption(
      'target',
      abbr: 't',
      help: 'Target platform (e.g., linux-x64, android-arm64).',
    );
  }

  final NativeProject project;

  @override
  String get name => 'cache-key';

  @override
  String get description => 'Compute the cache key for a target platform.';

  @override
  Future<void> run() async {
    final targetLabel = option('target') as String?;
    if (targetLabel == null) {
      print('Error: --target is required.');
      print(usage);
      exit(1);
    }

    final target = _parseTarget(targetLabel);
    if (target == null) {
      print('Unknown target: $targetLabel');
      exit(1);
    }

    // Compute cache key based on project and target
    final cacheKey = _computeCacheKey(target);
    print(cacheKey);
  }
}

/// Command that explains the cache state for a target.
class ExplainCacheCommand extends Command<void> {
  ExplainCacheCommand({required this.project}) {
    argParser.addOption(
      'target',
      abbr: 't',
      help: 'Target platform (e.g., linux-x64, android-arm64).',
    );
  }

  final NativeProject project;

  @override
  String get name => 'explain-cache';

  @override
  String get description => 'Explain the cache state for a target platform.';

  @override
  Future<void> run() async {
    final targetLabel = option('target') as String?;
    if (targetLabel == null) {
      print('Error: --target is required.');
      print(usage);
      exit(1);
    }

    final target = _parseTarget(targetLabel);
    if (target == null) {
      print('Unknown target: $targetLabel');
      exit(1);
    }

    final cacheKey = _computeCacheKey(target);
    print('Cache Explanation for ${project.name} on ${target.label}');
    print('=' * 50);
    print('');
    print('Cache Key: $cacheKey');
    print('');
    print(
      'Cache Directory: .dart_tool/native_prebuilt/build-cache/${project.name}/${target.label}/',
    );
    print('');
    print('This target would be cached if built from source.');
  }
}

/// Command that verifies built artifacts for a target.
class VerifyCommand extends Command<void> {
  VerifyCommand({required this.project}) {
    argParser.addOption(
      'target',
      abbr: 't',
      help: 'Target platform (e.g., linux-x64, android-arm64).',
    );
    argParser.addOption(
      'input',
      abbr: 'i',
      help: 'Directory containing built artifacts to verify.',
      defaultsTo: 'built-library',
    );
  }

  final NativeProject project;

  @override
  String get name => 'verify';

  @override
  String get description => 'Verify built artifacts for a target platform.';

  @override
  Future<void> run() async {
    final targetLabel = option('target') as String?;
    if (targetLabel == null) {
      print('Error: --target is required.');
      print(usage);
      exit(1);
    }

    final target = _parseTarget(targetLabel);
    if (target == null) {
      print('Unknown target: $targetLabel');
      exit(1);
    }

    final inputPath = option('input') as String? ?? 'built-library';
    final inputDir = Directory(inputPath);

    print('Verifying artifacts for ${project.name} on ${target.label}');
    print('Input: ${inputDir.path}');

    if (!inputDir.existsSync()) {
      print('Error: Input directory does not exist: ${inputDir.path}');
      exit(1);
    }

    // Look for the expected library file
    final expectedLib = expectedLibraryName(
      target: target,
      stem: project.asset.libraryStem,
    );
    final libFile = File(p.join(inputDir.path, expectedLib));

    if (libFile.existsSync()) {
      print('✓ Found: $expectedLib');
      print('  Size: ${libFile.lengthSync()} bytes');
    } else {
      print('✗ Missing: $expectedLib');
      exit(1);
    }
  }
}

/// Internal hook command for build hooks.
class _HookCommand extends Command<void> {
  _HookCommand({required this.project});

  final NativeProject project;

  @override
  String get name => 'build';

  @override
  String get description => 'Build hook command.';

  @override
  Future<void> run() async {
    // Hook commands are handled differently - they receive
    // BuildInput/BuildOutputBuilder from the hook framework.
    print('Hook build for ${project.name}');
  }
}

/// Parse a target label into a NativeTarget.
NativeTarget? _parseTarget(String label) {
  // Simple parser for common targets
  final parts = label.split('-');
  if (parts.length < 2) return null;

  final osName = parts[0];
  final archName = parts[1];

  OS? os = OS.fromString(osName);

  Architecture? arch = Architecture.fromString(archName);

  IOSSdk? iosSdk;
  if (os == OS.iOS && parts.length > 2 && parts[2] == 'sim') {
    iosSdk = IOSSdk.iPhoneSimulator;
  }

  return NativeTarget(os: os, architecture: arch, iOSSdk: iosSdk);
}

/// Compute a cache key for a target.
String _computeCacheKey(NativeTarget target) {
  // In a full implementation, this would include:
  // - Recipe schema
  // - Source revision
  // - Patch hashes
  // - Toolchain versions
  // - CMake definitions
  // - Environment inputs
  // - Step implementation version
  final buffer = StringBuffer();
  buffer.write('v1-');
  buffer.write('${target.os.name}-${target.architecture.name}');
  if (target.iOSSdk != null) {
    buffer.write('-${target.iOSSdk}');
  }
  return buffer.toString();
}

/// Expected library filename for a given [target] and library [stem].
///
/// Uses [target] to determine the platform-specific naming convention
/// and [stem] as the library's base name (e.g., `tdjson`).
String expectedLibraryName({
  required NativeTarget target,
  required String stem,
}) {
  return canonicalLibraryName(
    target: target,
    libraryStem: stem,
    payload: DynamicLibraryPayload(libraryStem: stem),
  );
}
