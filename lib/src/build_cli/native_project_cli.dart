import 'package:artisanal/args.dart';

import '../build/native_project.dart';
import '../cli/hook.dart';

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
  )..addCommand(HookCommand(project: project));

  await runner.run(args);
}
