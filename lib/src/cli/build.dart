import 'dart:io';

import 'package:artisanal/args.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;

import '../build/native_project.dart';
import '../build/native_project_executor.dart';
import '../source/source_fallback.dart';
import 'shared.dart';

/// Thin CLI adapter that delegates to [NativeProjectExecutor].
///
/// Parses CLI arguments and invokes the shared build entry point.
class BuildCommand extends Command<void> {
  BuildCommand({required this.project, this.sourceFallback}) {
    argParser.addOption(
      'target',
      abbr: 't',
      help: 'Target platform (e.g., linux-x64, android-arm64).',
    );
    argParser.addOption(
      'output',
      abbr: 'o',
      help: 'Root output directory for built artifacts.',
      defaultsTo: 'built-library',
    );
    argParser.addFlag(
      'from-source',
      negatable: false,
      help: 'Force building from source, ignoring prebuilts.',
    );
    argParser.addFlag(
      'verbose',
      negatable: false,
      help: 'Enable verbose logging.',
    );
  }

  final NativeProject project;
  final SourceFallback? sourceFallback;

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

    final target = parseTarget(targetLabel);
    if (target == null) {
      print('Unknown target: $targetLabel');
      print(
        'Valid target labels use code_assets OS and Architecture names (for example: linux-x64, macos-arm64, android-ia32).',
      );
      exit(1);
    }

    final outputPath = option('output') as String? ?? 'built-library';
    final forceSource = option('from-source') as bool? ?? false;
    final verbose = option('verbose') as bool? ?? false;

    // Configure logging
    Logger.root.level = verbose ? Level.FINE : Level.INFO;
    Logger.root.onRecord.listen((record) {
      stderr.writeln('[${record.level.name}] ${record.message}');
    });

    final logger = Logger('native_prebuilt.cli');

    // Platform-specific output directory
    final platformDir = '${target.os.name}-${target.architecture.name}';
    final outputDir = Directory(p.join(outputPath, platformDir)).absolute;

    print('Building for ${target.label}...');
    print('Output: ${outputDir.path}');

    // Override prebuilt policy if --from-source is set
    final effectiveProject = forceSource
        ? project.copyWith(prebuiltPolicy: PrebuiltPolicy.forceSourceBuild)
        : project;

    // Create the shared executor and delegate
    final executor = NativeProjectExecutor(
      project: effectiveProject,
      sourceFallback: sourceFallback,
      logger: logger,
    );

    try {
      final result = await executor.build(
        target: target,
        outputDir: outputDir,
        linkMode: project.asset.linkMode,
      );

      print('Build completed successfully.');
      print('Artifacts:');
      for (final artifact in result.artifacts) {
        print('  ${artifact.primary.path} (${artifact.target.label})');
      }
    } catch (e) {
      print('Build failed: $e');
      exit(1);
    }
  }
}
