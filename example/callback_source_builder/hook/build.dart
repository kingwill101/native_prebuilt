/// CallbackSourceBuilder + CBuilder example
///
/// This demonstrates using native_prebuilt with the SourceBuilder
/// callback pattern combined with CBuilder from native_toolchain_c.
library;

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:native_prebuilt/native_prebuilt.dart';
import 'package:native_toolchain_c/native_toolchain_c.dart';

import '../lib/src/hook/callback_source_builder_prebuilts.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) {
      return;
    }

    // Use native_prebuilt's PrebuiltCodeAssetBuilder for prebuilt resolution
    // with native_toolchain_c's CBuilder as the source fallback
    final sourceBuilder = CBuilder.library(
      name: 'callback_source_builder_example',
      packageName: input.packageName,
      assetName: 'callback_source_builder_example_bindings_generated.dart',
      sources: const ['src/native/example.c'],
    );

    await PrebuiltCodeAssetBuilder(
      assetName: 'callback_source_builder_example_bindings_generated.dart',
      libraryStem: 'callback_source_builder_example',
      manifest: callbackSourceBuilderExamplePrebuilts,
      linkModeResolver: (code) => DynamicLoadingBundled(),
      sourceFallback: SourceFallback(
        sources: [
          LocalSource(paths: const ['.']),
        ],
        builder: CallbackSourceBuilder(
          callback:
              ({
                required source,
                required input,
                required output,
                required logger,
              }) async {
                await sourceBuilder.run(
                  input: input,
                  output: output,
                  logger: logger,
                );
              },
        ),
      ),
    ).run(input: input, output: output, logger: null);
  });
}
