import 'dart:io';

import 'package:artisanal/args.dart';

import '../build/native_project.dart';
import 'shared.dart';

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

    final target = parseTarget(targetLabel);
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
