import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:native_prebuilt/hooks.dart';
import 'package:native_toolchain_c/native_toolchain_c.dart';

import '../lib/src/hook/demo_prebuilts.g.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) {
      return;
    }

    final sourceBuilder = CBuilder.library(
      name: 'native_prebuilt_example',
      packageName: input.packageName,
      assetName: 'native_prebuilt_example_bindings_generated.dart',
      sources: const ['src/native/demo.c'],
    );

    await PrebuiltCodeAssetBuilder(
      assetName: 'native_prebuilt_example_bindings_generated.dart',
      libraryStem: 'native_prebuilt_example',
      manifest: demoPrebuilts,
      linkModeResolver: (code) => DynamicLoadingBundled(),
      sourceFallback: SourceFallback(
        sources: [LocalSource(paths: const ['.'])],
        builder: CallbackSourceBuilder(
          callback: ({
            required source,
            required input,
            required output,
            required logger,
          }) async {
            await sourceBuilder.run(input: input, output: output, logger: logger);
          },
        ),
      ),
    ).run(input: input, output: output, logger: null);
  });
}
