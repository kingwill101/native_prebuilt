import 'package:artisanal/args.dart';

import '../build/native_project.dart';

/// Internal hook command for build hooks.
class HookCommand extends Command<void> {
  HookCommand({required this.project});

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
