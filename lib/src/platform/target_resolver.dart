import 'package:code_assets/code_assets.dart';

import 'native_target.dart';

/// Creates a [NativeTarget] from a `CodeConfig` provided by the build hook.
NativeTarget targetFromCodeConfig(CodeConfig config) {
  return NativeTarget(
    os: config.targetOS,
    architecture: config.targetArchitecture,
    iOSSdk: config.targetOS == OS.iOS ? config.iOS.targetSdk : null,
  );
}

/// Returns a [NativeTarget] for the current host machine.
NativeTarget hostTarget() {
  return NativeTarget(os: OS.current, architecture: Architecture.current);
}
