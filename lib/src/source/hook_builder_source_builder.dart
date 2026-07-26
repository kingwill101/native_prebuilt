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
///     (input, source) => CBuilder.library(
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
    required Builder Function(BuildInput input, ResolvedSource source)
    builderFactory,
  }) : _builderFactory = builderFactory;

  /// Creates a [HookBuilderSourceBuilder] from a factory function.
  ///
  /// The factory receives both [BuildInput] and the resolved [ResolvedSource],
  /// allowing the builder to access the source directory at construction time.
  factory HookBuilderSourceBuilder.factory(
    Builder Function(BuildInput input, ResolvedSource source) builderFactory,
  ) {
    return HookBuilderSourceBuilder(builderFactory: builderFactory);
  }

  /// Creates a [HookBuilderSourceBuilder] from a static builder instance.
  ///
  /// Use this when the builder doesn't need values from [BuildInput] or
  /// [ResolvedSource].
  factory HookBuilderSourceBuilder.static(Builder builder) {
    return HookBuilderSourceBuilder(builderFactory: (_, __) => builder);
  }

  final Builder Function(BuildInput input, ResolvedSource source)
  _builderFactory;

  @override
  Future<void> build({
    required ResolvedSource source,
    required BuildInput input,
    required BuildOutputBuilder output,
    required Logger? logger,
  }) {
    return _builderFactory(
      input,
      source,
    ).run(input: input, output: output, logger: logger);
  }
}
