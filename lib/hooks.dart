/// Build-hook integration for packages that ship prebuilt native libraries.
///
/// Import this library in your `hook/build.dart` to use
/// [PrebuiltCodeAssetBuilder] and the source fallback pipeline.
library native_prebuilt.hooks;

export 'package:native_prebuilt/native_prebuilt.dart';

export 'src/builder/prebuilt_code_asset_builder.dart';
export 'src/source/source.dart';
