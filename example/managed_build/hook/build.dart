/// Managed build hook entry point
///
/// Uses the declarative NativeProject definition with nativePrebuiltBuild.
library;

import 'package:native_prebuilt/hooks.dart';
import 'package:managed_build_example/src/hook/managed_build_project.dart';

Future<void> main(List<String> args) async {
  await nativePrebuiltBuild(args, project: managedBuildProject);
}
