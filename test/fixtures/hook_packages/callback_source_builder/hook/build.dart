/// Fixture demonstrating the legacy CallbackSourceBuilder API.
///
/// This fixture validates that the old API pattern continues to work
/// after the new build pipeline was introduced.
import 'package:hooks/hooks.dart';
import 'package:logging/logging.dart';
import 'package:native_prebuilt/native_prebuilt.dart';
import 'package:callback_source_fixture/manifest.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    await PrebuiltCodeAssetBuilder(
      assetName: 'src/fixture.dart',
      libraryStem: 'callback_source_fixture',
      manifest: callbackSourceFixturePrebuilts,
      linkModeResolver: (_) => DynamicLoadingBundled(),
      sourceFallback: SourceFallback(
        sources: [LocalSource(paths: ['.'])],
        builder: CallbackSourceBuilder(
          callback: ({
            required source,
            required input,
            required output,
            required logger,
          }) async {
            // Build from source using native_toolchain_c or similar
            logger?.info('Building from source via CallbackSourceBuilder');
          },
        ),
      ),
    ).run(input: input, output: output, logger: Logger.root);
  });
}
