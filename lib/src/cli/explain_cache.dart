import 'dart:io';

import 'package:artisanal/args.dart';

import '../build/native_project.dart';
import 'shared.dart';

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

    final target = parseTarget(targetLabel);
    if (target == null) {
      print('Unknown target: $targetLabel');
      exit(1);
    }

    final cacheKey = computeCacheKey(target);
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
