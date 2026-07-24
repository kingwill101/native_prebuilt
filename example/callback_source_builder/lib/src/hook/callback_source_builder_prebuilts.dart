/// Generated prebuilt manifest for callback_source_builder_example
library;

import 'package:native_prebuilt/native_prebuilt.dart';

const callbackSourceBuilderExamplePrebuilts = PrebuiltManifest(
  schemaVersion: 1,
  release: GitHubReleaseSource(
    owner: 'example',
    repository: 'callback_source_builder_example',
    tag: 'v0.1.0',
  ),
  artifacts: {
    'linux-x64': PrebuiltArtifact(
      archiveName: 'callback_source_builder_example-linux-x64.tar.gz',
      archiveSha256: 'PLACEHOLDER_HASH',
      payloadSha256: 'PLACEHOLDER_HASH',
      payload: DynamicLibraryPayload(libraryStem: 'callback_source_builder_example'),
    ),
  },
);
