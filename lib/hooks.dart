/// Build-hook integration for packages that ship prebuilt native libraries.
///
/// Import this library in your `hook/build.dart` to use
/// [PrebuiltCodeAssetBuilder], [NativeProjectBuilder], or the convenience
/// [nativePrebuiltBuild] function.
///
/// This library re-exports the core package ([native_prebuilt.dart]),
/// the build orchestration layer ([build.dart]), and the builder
/// utilities ([PrebuiltCodeAssetBuilder], [NativeProjectBuilder]).
library native_prebuilt.hooks;

export 'package:native_prebuilt/native_prebuilt.dart';
export 'package:native_prebuilt/build.dart';

export 'src/builder/prebuilt_code_asset_builder.dart';
export 'src/builder/native_project_builder.dart';
export 'src/source/source.dart';
