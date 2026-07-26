/// Reusable infrastructure for Dart packages that ship prebuilt native
/// libraries from GitHub or GitLab releases.
///
/// This library provides the core models, download pipeline, cache management,
/// and binary inspection utilities. For build-hook integration, see
/// [package:native_prebuilt/hooks.dart].
library native_prebuilt;

export 'package:code_assets/code_assets.dart' show Architecture, IOSSdk, OS;

export 'src/manifest/prebuilt_manifest.dart';
export 'src/manifest/prebuilt_artifact.dart';
export 'src/manifest/release_source.dart';
export 'src/platform/native_target.dart';
export 'src/platform/target_resolver.dart';
export 'src/binary/binary_inspector.dart';
export 'src/binary/library_name.dart';
export 'src/download/http_downloader.dart';
export 'src/download/retry_policy.dart';
export 'src/archive/archive_reader.dart';
export 'src/archive/archive_entry.dart';
export 'src/cache/artifact_cache.dart';
export 'src/cache/artifact_installer.dart';
export 'src/cache/cache_lock.dart';
export 'src/cache/atomic_file.dart';
export 'src/resolution/prebuilt_resolver.dart';
export 'src/resolution/resolution_result.dart';
export 'src/source/network_policy.dart';
export 'src/source/resolved_source.dart';
export 'src/source/source.dart';
export 'src/source/source_fallback.dart';
export 'src/source/source_preparation.dart';
export 'src/source/source_provider.dart';
export 'src/source/source_specification.dart';
export 'src/source/source_builder.dart';
export 'src/config/build_step_config.dart';

export 'src/cli/shared.dart' show shouldBuildFromSource;
export 'src/cli/cli_config.dart' show detect, resolveConfigFile;

// Export the new build abstraction layer
export 'package:native_prebuilt/build.dart';

// Export builder utilities
export 'src/builder/prebuilt_code_asset_builder.dart';
export 'src/builder/native_project_builder.dart';
