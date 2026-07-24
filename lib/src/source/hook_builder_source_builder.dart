/// Adapter for using existing hooks [Builder] implementations as a [SourceBuilder].
///
/// This allows packages like `native_toolchain_c` to be used with
/// `PrebuiltCodeAssetBuilder` without modification.
///
/// Example with CBuilder:
/// ```dart
/// SourceFallback(
///   sources: [LocalSource(paths: ['.'])],
///   builder: HookBuilderSourceBuilder.factory(
///     (input) => CBuilder.library(
///       name: 'my_package',
///       packageName: input.packageName,
///       assetName: 'src/my_package.dart',
///       sources: const ['src/native/my_package.c'],
///     ),
///   ),
/// )
/// ```
library;

import 'package:hooks/hooks.dart';
import 'package:logging/logging.dart';

import 'resolved_source.dart';
import 'source_builder.dart';

/// Adapter that wraps a hooks [Builder] as a [SourceBuilder].
///
/// This enables existing hooks builders like `CBuilder` or `RustBuilder`
/// to be used with `PrebuiltCodeAssetBuilder`'s source fallback system.
final class HookBuilderSourceBuilder implements SourceBuilder {
  const HookBuilderSourceBuilder({
    required Builder Function(BuildInput input) builderFactory,
  }) : _builderFactory = builderFactory;

  /// Creates a [HookBuilderSourceBuilder] from a factory function.
  ///
  /// Use this when the builder needs access to [BuildInput] at construction time.
  factory HookBuilderSourceBuilder.factory(
    Builder Function(BuildInput input) builderFactory,
  ) {
    return HookBuilderSourceBuilder(builderFactory: builderFactory);
  }

  /// Creates a [HookBuilderSourceBuilder] from a static builder instance.
  ///
  /// Use this when the builder doesn't need values from [BuildInput].
  factory HookBuilderSourceBuilder.static(Builder builder) {
    return HookBuilderSourceBuilder(builderFactory: (_) => builder);
  }

  final Builder Function(BuildInput input) _builderFactory;

  @override
  Future<void> build({
    required ResolvedSource source,
    required BuildInput input,
    required BuildOutputBuilder output,
    required Logger? logger,
  }) {
    return _builderFactory(
      input,
    ).run(input: input, output: output, logger: logger);
  }
}
