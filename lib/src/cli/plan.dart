import 'dart:io';

import 'package:artisanal/args.dart';

import '../build/native_build_context.dart';
import '../build/native_project.dart';
import 'shared.dart';

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

    final target = parseTarget(targetLabel);
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

///
