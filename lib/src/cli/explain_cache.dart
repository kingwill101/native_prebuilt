import 'dart:io';

import 'package:artisanal/args.dart';
import 'package:path/path.dart' as p;

import '../build/native_project.dart';
import '../cache/build_cache.dart';
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
      throw UsageException('Error: --target is required.', usage);
    }

    final target = parseTarget(targetLabel);
    if (target == null) {
      throw UsageException('Unknown target: $targetLabel', usage);
    }

    final cacheKey = computeCacheKey(project, target);
    final cache = BuildCache(
      projectName: project.name,
      targetLabel: target.label,
      logger: null,
    );

    print('Cache Explanation for ${project.name} on ${target.label}');
    print('=' * 50);
    print('');
    print('Target Key: $cacheKey');
    print('');
    print('Cache Directory: ${cache.cacheDir.path}');
    print('');

    // Check if any cached entries exist
    if (cache.cacheDir.existsSync()) {
      final entries = cache.cacheDir.listSync().whereType<Directory>().toList();
      if (entries.isNotEmpty) {
        print('Cached steps:');
        for (final entry in entries) {
          final stepName = p.basename(entry.path);
          final metaFiles = entry
              .listSync()
              .whereType<File>()
              .where((f) => f.path.endsWith('.json'))
              .toList();
          print('  $stepName: ${metaFiles.length} cached fingerprint(s)');
        }
      } else {
        print('No cached steps found.');
      }
    } else {
      print('No cache directory found.');
    }

    print('');
    print('The cache stores step fingerprints and output paths.');
    print('On cache hit, the step is skipped entirely.');
  }
}
