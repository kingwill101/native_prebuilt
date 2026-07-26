import 'dart:io';

import 'package:artisanal/args.dart';
import 'package:path/path.dart' as p;

import '../build/native_project.dart';
import 'shared.dart';

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

    final target = parseTarget(targetLabel);
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
