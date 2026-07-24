/// Build-hook integration for packages that ship prebuilt native libraries.
///
/// Import this library in your `hook/build.dart` to use
/// [NativeProjectBuilder] and the new build abstraction layer.
library native_prebuilt.hooks;

// Export the new build abstraction layer
export 'package:native_prebuilt/build.dart';

// Export source fallback pipeline
export 'src/source/source.dart';
