/// Build-hook integration for packages that ship prebuilt native libraries.
///
/// Import this library in your `hook/build.dart` to use
/// [NativeProjectBuilder] or the convenience [nativePrebuiltBuild]
/// function.
library native_prebuilt.hooks;

export 'package:native_prebuilt/build.dart';

export 'src/source/source.dart';
