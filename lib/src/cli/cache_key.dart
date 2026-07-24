import 'dart:io';

import 'package:artisanal/args.dart';

import '../build/native_project.dart';
import 'shared.dart';

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

    final target = parseTarget(targetLabel);
    if (target == null) {
      print('Unknown target: $targetLabel');
      exit(1);
    }

    // Compute cache key based on project and target
    final cacheKey = computeCacheKey(target);
    print(cacheKey);
  }
}
