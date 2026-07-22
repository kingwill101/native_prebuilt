## Recommendation

Build this as a **declarative `Builder` implementation with composable lower-level services**, not as a base hook class or mixin.

The public package should provide:

1. `PrebuiltCodeAssetBuilder` — the high-level build-hook integration.
2. `PrebuiltManifest` and `PrebuiltArtifact` — immutable release metadata.
3. `PrebuiltResolver` implementations — override, local cache, GitHub download.
4. `ArtifactInstaller` — download, verify, safely extract, validate, atomically install.
5. `NativeTarget` — canonical platform and ABI resolution.
6. `NativeBinaryInspector` — filename selection and header/architecture validation.
7. A CLI for manifest generation, local downloads, verification, and workflow bootstrapping.
8. Reusable GitHub workflows for the actual CI orchestration.

Your current PTY hook already demonstrates a clean conceptual boundary: resolve link mode and library name, try three prebuilt sources, then call the Rust builder. However, download, extraction, hashing, cache management, local lookup, and asset registration are all embedded in the hook. 

---

# 1. Package structure

I would start with one package rather than prematurely splitting runtime and CLI packages:

```text
native_prebuilt/
├── bin/
│   └── native_prebuilt.dart
├── lib/
│   ├── native_prebuilt.dart
│   ├── hooks.dart
│   └── src/
│       ├── builder/
│       │   ├── prebuilt_code_asset_builder.dart
│       │   ├── resolution_result.dart
│       │   └── fallback_builder.dart
│       ├── manifest/
│       │   ├── prebuilt_manifest.dart
│       │   ├── prebuilt_artifact.dart
│       │   └── release_source.dart
│       ├── platform/
│       │   ├── native_target.dart
│       │   └── target_resolver.dart
│       ├── resolution/
│       │   ├── prebuilt_resolver.dart
│       │   ├── user_define_resolver.dart
│       │   ├── local_prebuilt_resolver.dart
│       │   └── github_release_resolver.dart
│       ├── download/
│       │   ├── http_downloader.dart
│       │   ├── retry_policy.dart
│       │   └── github_release_client.dart
│       ├── archive/
│       │   ├── tar_gz_reader.dart
│       │   └── archive_selector.dart
│       ├── binary/
│       │   ├── binary_inspector.dart
│       │   ├── binary_format.dart
│       │   └── library_name.dart
│       ├── cache/
│       │   ├── artifact_cache.dart
│       │   ├── cache_lock.dart
│       │   └── atomic_file.dart
│       └── cli/
│           ├── manifest_command.dart
│           ├── fetch_command.dart
│           ├── verify_command.dart
│           ├── doctor_command.dart
│           └── workflow_command.dart
├── test/
└── pubspec.yaml
```

Keep `native_prebuilt.dart` free of `hooks` and `code_assets` exports where possible. Then provide `package:native_prebuilt/hooks.dart` for hook-specific APIs. That keeps the manifest, downloader, archive inspection, and CLI utilities usable independently.

A reasonable dependency set would be:

```yaml
dependencies:
  archive: ^4.0.9
  code_assets: ^1.0.0
  crypto: ^3.0.0
  hooks: ^2.0.0
  logging: ^1.0.0
  path: ^1.9.0
```

You could use `package:tar` instead of `archive`; it offers a streaming implementation and explicitly documents the security checks callers must perform for untrusted archive paths. ([Dart packages][1])

Because hook libraries execute in downstream applications, `native_prebuilt`, `hooks`, and `code_assets` must be regular dependencies rather than dev dependencies. ([Dart][2])

---

# 2. Public API

## Manifest model

Use one manifest that contains both artifact naming and hashes. Your current structure separates the platform-to-tarball map from the generated hash map, creating two sources of truth. The artifact map currently contains the filenames, while the generated file repeats those names alongside hashes.  

Suggested model:

```dart
final class PrebuiltManifest {
  const PrebuiltManifest({
    required this.schemaVersion,
    required this.release,
    required this.artifacts,
  });

  final int schemaVersion;
  final ReleaseSource release;
  final Map<String, PrebuiltArtifact> artifacts;
}

final class PrebuiltArtifact {
  const PrebuiltArtifact({
    required this.archiveName,
    required this.archiveSha256,
    required this.payloadSha256,
    required this.payload,
  });

  final String archiveName;

  /// Hash of the downloaded archive, checked before extraction.
  final String archiveSha256;

  /// Hash of the selected native library, checked after extraction.
  final String payloadSha256;

  final ArtifactPayload payload;
}

sealed class ArtifactPayload {
  const ArtifactPayload();
}

final class DynamicLibraryPayload extends ArtifactPayload {
  const DynamicLibraryPayload({
    required this.libraryStem,
    this.acceptVersionedNames = true,
  });

  final String libraryStem;
  final bool acceptVersionedNames;
}

final class StaticLibraryPayload extends ArtifactPayload {
  const StaticLibraryPayload({
    required this.libraryStem,
  });

  final String libraryStem;
}

sealed class ReleaseSource {
  const ReleaseSource();
}

final class GitHubReleaseSource extends ReleaseSource {
  const GitHubReleaseSource({
    required this.owner,
    required this.repository,
    required this.tag,
  });

  final String owner;
  final String repository;
  final String tag;
}
```

### Store two hashes

Your existing generator hashes only the extracted library. 

That verifies the eventual payload, but it happens **after the archive has already been processed by an extractor**. Store:

* `archiveSha256`: verified before parsing or extraction.
* `payloadSha256`: verified after selecting the library.

This protects both the extraction boundary and the final binary.

## Target model

Do not let platform strings spread throughout the package:

```dart
final class NativeTarget {
  const NativeTarget({
    required this.os,
    required this.architecture,
    this.environment,
  });

  final NativeOs os;
  final NativeArchitecture architecture;

  /// Examples: simulator, device, musl, gnu, msvc.
  final String? environment;

  String get label => switch ((os, architecture, environment)) {
    (NativeOs.ios, NativeArchitecture.arm64, 'simulator') =>
      'ios-sim-arm64',
    (NativeOs.linux, NativeArchitecture.x64, 'musl') =>
      'linux-x64-musl',
    _ => [
        os.label,
        if (environment != null) environment,
        architecture.label,
      ].join('-'),
  };
}
```

Provide:

```dart
NativeTarget targetFromCodeConfig(CodeConfig config);
NativeTarget hostTarget();
```

Your current resolver falls back to `enum.toString()` for unknown values. That can silently generate unsupported or unstable labels. 

The shared resolver should instead throw a descriptive `UnsupportedTargetException`.

Plan for distinctions that will matter later:

* Linux glibc versus musl.
* Windows MSVC versus GNU.
* iOS device versus simulator.
* Android `arm` versus `armv7`.
* Static versus dynamic payload.
* WASM as a separate artifact kind, not necessarily a `CodeAsset`.

---

# 3. Build-hook integration

## Implement `Builder`

The official `hooks` API now exposes a `Builder` interface specifically for packages that build, download, or transform assets. Its documentation recommends declarative constructor calls followed by `run`. ([Dart packages][3])

Therefore:

```dart
final class PrebuiltCodeAssetBuilder implements Builder {
  const PrebuiltCodeAssetBuilder({
    required this.assetName,
    required this.libraryStem,
    required this.manifest,
    required this.linkModeResolver,
    this.overrideUserDefine = 'prebuilt_path',
    this.localDirectoryName = '.prebuilt',
    this.fallback,
    this.binaryPolicy = const NativeBinaryPolicy(),
  });

  final String assetName;
  final String libraryStem;
  final PrebuiltManifest manifest;
  final LinkMode Function(CodeConfig config) linkModeResolver;
  final String overrideUserDefine;
  final String localDirectoryName;
  final Builder? fallback;
  final NativeBinaryPolicy binaryPolicy;

  @override
  Future<void> run({
    required BuildInput input,
    required BuildOutputBuilder output,
    required Logger? logger,
  }) async {
    // Resolution and asset registration.
  }
}
```

The core flow should be:

```text
Resolve target and link mode
          │
          ▼
Read user-defined override
          │
          ▼
Search local development prebuilts
          │
          ▼
Look up target in pinned manifest
          │
          ▼
Validate or populate shared cache
          │
          ▼
Copy/link into configuration output directory
          │
          ▼
Register CodeAsset
          │
          ▼
If unresolved, invoke fallback Builder
```

## Consuming PTY hook

That gives PTY something close to:

```dart
import 'package:hooks/hooks.dart';
import 'package:native_prebuilt/hooks.dart';
import 'package:native_toolchain_rust/native_toolchain_rust.dart';
import 'package:portable_pty/src/hook/prebuilt_manifest.g.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    await PrebuiltCodeAssetBuilder(
      assetName: 'portable_pty_bindings_generated.dart',
      libraryStem: 'portable_pty_rs',
      manifest: portablePtyPrebuilts,
      linkModeResolver: portablePtyLinkModeForBuild,
      fallback: const RustBuilder(
        assetName: 'portable_pty_bindings_generated.dart',
      ),
    ).run(input: input, output: output, logger: null);
  });
}
```

For Ghostty:

```dart
fallback: CallbackBuilder(_buildGhosttyFromSource),
```

where:

```dart
typedef BuildCallback = Future<void> Function({
  required BuildInput input,
  required BuildOutputBuilder output,
  required Logger? logger,
});

final class CallbackBuilder implements Builder {
  const CallbackBuilder(this.callback);

  final BuildCallback callback;

  @override
  Future<void> run({
    required BuildInput input,
    required BuildOutputBuilder output,
    required Logger? logger,
  }) =>
      callback(input: input, output: output, logger: logger);
}
```

This allows:

* `RustBuilder` directly.
* Zig code through a callback.
* CMake through another builder.
* A package-specific patching pipeline.
* No dependency from `native_prebuilt` on Rust, Zig, or CMake packages.

## Do not use a custom environment variable

This is the largest issue in the current hook.

The hook currently reads `PORTABLE_PTY_PREBUILT` from `Platform.environment`. 

Modern hooks run in a semi-hermetic environment. The SDK passes through selected toolchain, temporary-directory, and proxy variables, but strips other environment variables. ([Dart][2])

Use:

```yaml
hooks:
  user_defines:
    portable_pty:
      prebuilt_path: /absolute/path/to/libportable_pty_rs.so
```

Then:

```dart
final overrideUri = input.userDefines.path('prebuilt_path');

if (overrideUri != null) {
  output.dependencies.add(overrideUri);
}
```

Registering the file as a dependency causes hook cache invalidation when it changes. ([dart.dev][4])

You can keep environment-variable support in the standalone CLI, but the build hook should use `user_defines`.

---

# 4. Resolver design

Expose the high-level builder, but internally model resolution as strategies:

```dart
abstract interface class PrebuiltResolver {
  Future<ResolvedPrebuilt?> resolve(PrebuiltResolutionContext context);
}

final class PrebuiltResolutionContext {
  const PrebuiltResolutionContext({
    required this.input,
    required this.output,
    required this.target,
    required this.libraryName,
    required this.manifest,
    required this.logger,
  });

  final BuildInput input;
  final BuildOutputBuilder output;
  final NativeTarget target;
  final String libraryName;
  final PrebuiltManifest manifest;
  final Logger? logger;
}
```

Built-in resolvers:

```dart
const [
  UserDefinePrebuiltResolver(),
  LocalPrebuiltResolver(),
  CachedReleaseResolver(),
  GitHubReleaseResolver(),
]
```

Avoid exposing a general-purpose dependency-injection framework. Most consumers should only construct `PrebuiltCodeAssetBuilder`.

Expose resolvers primarily for:

* Testing.
* Non-GitHub artifact stores.
* Company-internal mirrors.
* S3 or Cloudflare R2.
* Vendored package assets.
* Offline-only builds.

---

# 5. Asset manifest generation

## Use a CLI, not annotations or `build_runner`

The correct tool is a CLI command.

Annotations add no real information because:

* Release metadata exists outside the Dart source.
* Generation needs network access.
* It may require GitHub authentication.
* It should run only during the release process.
* It must support verification without rewriting.
* It should be easy to call from CI.

A builder would also blur the boundary between **building a consumer application** and **publishing a new native package release**.

Suggested commands:

```bash
dart run native_prebuilt:cli manifest update \
  --config native_prebuilt.yaml \
  --tag portable_pty-v0.0.6

dart run native_prebuilt:cli manifest verify \
  --config native_prebuilt.yaml

dart run native_prebuilt:cli fetch \
  --config native_prebuilt.yaml \
  --platform linux-x64

dart run native_prebuilt:cli doctor \
  --config native_prebuilt.yaml

dart run native_prebuilt:cli workflow init \
  --config native_prebuilt.yaml
```

Or, once activated:

```bash
native_prebuilt manifest update ...
```

## Configuration file

Use a human-authored release config:

```yaml
schema: 1

package: portable_pty
asset_name: portable_pty_bindings_generated.dart
library_stem: portable_pty_rs

release:
  provider: github
  repository: kingwill101/dart_terminal

artifacts:
  linux-x64:
    archive: pty-linux-x64.tar.gz
    payload:
      type: dynamic_library

  ios-arm64:
    archive: pty-ios-arm64.tar.gz
    payload:
      type: static_library
```

The generated file should look like:

```dart
// Generated by package:native_prebuilt. Do not edit.

import 'package:native_prebuilt/native_prebuilt.dart';

const portablePtyPrebuilts = PrebuiltManifest(
  schemaVersion: 1,
  release: GitHubReleaseSource(
    owner: 'kingwill101',
    repository: 'dart_terminal',
    tag: 'portable_pty-v0.0.6',
  ),
  artifacts: {
    'linux-x64': PrebuiltArtifact(
      archiveName: 'pty-linux-x64.tar.gz',
      archiveSha256: '...',
      payloadSha256: '...',
      payload: DynamicLibraryPayload(
        libraryStem: 'portable_pty_rs',
      ),
    ),
  },
);
```

The generated Dart file still contains only const values. Importing the small manifest model does not cause network, process, or IO code to run.

Your existing generator already supports update and verify modes, which should be retained. 

## Important generator improvements

The current generator continues after an artifact download failure. 

For release metadata generation, missing artifacts should normally fail the entire command. Otherwise, a manifest can be generated with incomplete platform coverage.

Add:

```bash
--allow-missing
```

only for deliberate partial releases.

The generator should also:

* Sort platform entries deterministically.
* Fail on duplicate archive names.
* Fail if the selected binary has the wrong architecture.
* Verify archive and payload hashes.
* Emit the manifest to a temporary file.
* Format it.
* Compare or atomically replace.
* Produce a machine-readable summary for CI.
* Optionally generate SPDX/checksum files.

---

# 6. Download, extraction, and caching pipeline

The shared installer should implement approximately:

```dart
Future<File> installArtifact({
  required Uri uri,
  required PrebuiltArtifact artifact,
  required Directory cacheDirectory,
  required NativeTarget target,
  required String canonicalLibraryName,
});
```

## Recommended algorithm

```text
Acquire cache-key lock
    │
    ├── Cached payload exists?
    │       ├── Validate payload hash
    │       ├── Validate binary header and architecture
    │       └── Return
    │
    ▼
Create unique temporary directory
    │
    ▼
Download archive to *.partial
    │
    ▼
Verify archive SHA-256
    │
    ▼
Read gzip/tar as a stream
    │
    ▼
Select one matching regular-file entry
    │
    ▼
Write selected entry to payload.partial
    │
    ▼
Verify payload SHA-256
    │
    ▼
Validate format and architecture
    │
    ▼
Atomic rename into final cache path
    │
    ▼
Release lock
```

### Do not extract the entire archive

You only need one library.

Stream the tar archive and copy only the selected regular-file entry. This:

* Avoids path traversal.
* Avoids unpacking unrelated files.
* Avoids symlink and hard-link attacks.
* Reduces disk usage.
* Makes archive selection deterministic.
* Works equally on Windows, Linux, and macOS.

`package:tar` warns that callers extracting untrusted archives must reject paths such as `../`, absolute paths, external links, and archive bombs. ([Dart packages][1])

Selecting one regular entry means you can reject all:

* Directories.
* Symlinks.
* Hard links.
* Device entries.
* Absolute names.
* Parent traversal.
* Multiple equally valid libraries.

## Avoid external `tar`, `curl`, and `gh` in hook execution

Your current local-development CLI invokes `curl` and `tar`. 

Your generator invokes `gh` and `tar`. 

Those may remain optional CLI backends, but the reusable core and build hook should be pure Dart. Otherwise:

* Windows users may not have the exact tools.
* PATH behavior differs.
* Error parsing becomes tool-dependent.
* Proxy and certificate behavior differs.
* Testing becomes much harder.
* The build becomes less hermetic.

## Cache key

Do not use only:

```text
platform + release tag
```

The current hook uses that approach. 

Use something like:

```text
v1/
github.com/
owner/
repo/
tag/
platform/
archive-sha256/
canonical-library-name
```

Or hash a canonical descriptor:

```dart
sha256(
  '$schemaVersion\n'
  '$provider\n'
  '$repository\n'
  '$tag\n'
  '$platform\n'
  '$archiveName\n'
  '$archiveSha256\n'
  '$payloadSha256\n'
  '$libraryName',
);
```

This prevents collisions when:

* A tag is accidentally replaced.
* Artifact naming changes.
* The same package has several libraries.
* Extraction logic changes.
* Static and dynamic variants coexist.

## Parallel hook executions

Build hooks may run alongside compilation, and multiple package builds or configurations can contend for the same shared cache. Dart's hook documentation explicitly notes that hooks can perform longer-running operations such as downloads and run in parallel with compilation. ([Dart][2])

Use:

* A per-cache-key lock file.
* A unique temporary directory.
* A final atomic rename.
* Cache validation after acquiring the lock.
* Cleanup of abandoned `.partial` files by age.

Atomic rename alone prevents corrupted final files, but without a lock, multiple processes can wastefully download and extract the same asset.

---

# 7. HTTP implementation gotchas

## Redirect handling

Your current code manually handles only 301 and 302. 

`HttpClientRequest.followRedirects` already defaults to `true` and supports 301, 302, 303, 307, and 308 for GET/HEAD requests. ([Dart API Docs][5])

Use:

```dart
final request = await client.getUrl(uri);
request
  ..followRedirects = true
  ..maxRedirects = 5;
```

Manual handling is only necessary when you need custom authorization behavior or redirect-domain restrictions.

If manually handling redirects:

* Drain the previous response.
* Resolve relative `Location` values with `currentUri.resolve(location)`.
* Impose a redirect limit.
* Reject HTTPS-to-HTTP downgrade.
* Consider an allowed-host policy.

## Proxy support

Your existing use of:

```dart
client.findProxy = HttpClient.findProxyFromEnvironment;
```

is correct. Dart supports `HTTP_PROXY`, `HTTPS_PROXY`, and `NO_PROXY` through this API. ([Dart API Docs][6])

Those proxy variables are among the small set passed into build hooks. ([Dart][2])

## Retry policy

Retry only transient failures:

* `SocketException`
* connection reset
* connection timeout
* HTTP 408
* HTTP 429
* HTTP 500
* HTTP 502
* HTTP 503
* HTTP 504

Do not automatically retry:

* 401
* 403
* 404
* hash mismatch
* malformed archive
* wrong binary architecture

Use bounded exponential backoff with jitter:

```text
attempt 1: immediate
attempt 2: ~300 ms
attempt 3: ~900 ms
attempt 4: ~2.2 s
```

Honor `Retry-After` for 429 and 503, subject to a maximum delay.

Provide configurable:

```dart
final class HttpDownloadPolicy {
  const HttpDownloadPolicy({
    this.maxAttempts = 4,
    this.connectionTimeout = const Duration(seconds: 15),
    this.responseTimeout = const Duration(minutes: 2),
    this.maximumBytes,
  });
}
```

Also impose a maximum archive size where practical. A valid but enormous archive should not be able to fill the user's disk.

## GitHub authentication

Public releases usually need no token, but rate limiting and private repositories may.

Support credentials through:

* A CLI argument or GitHub CLI for release tooling.
* A supported user-defined token only outside hooks.
* A credential-provider callback in the low-level API.

Do not bake GitHub tokens into generated Dart files or cache keys.

---

# 8. Dynamic-library utilities

Expose a policy-driven inspector rather than scattered functions:

```dart
final class NativeBinaryPolicy {
  const NativeBinaryPolicy({
    this.allowVersionedDynamicLibraries = true,
    this.validateFormat = true,
    this.validateArchitecture = true,
  });

  final bool allowVersionedDynamicLibraries;
  final bool validateFormat;
  final bool validateArchitecture;
}

abstract interface class NativeBinaryInspector {
  Future<NativeBinaryInfo> inspect(File file);

  String canonicalName({
    required NativeTarget target,
    required String libraryStem,
    required LinkMode linkMode,
  });

  ArchiveEntryMatch select({
    required Iterable<ArchiveEntryInfo> entries,
    required String canonicalName,
  });
}
```

## Selection order

For `libfoo.so`, select in this order:

1. Exact `libfoo.so`.
2. Exact canonical name inside a nested directory.
3. Versioned `libfoo.so.<numeric-suffix>`.
4. A platform-specific alias explicitly declared by the manifest.
5. Otherwise fail.

Never select `files.first`, which your PTY hash generator currently does for PTY artifacts. 

A tarball might later contain:

* A license file.
* Debug symbols.
* An import library.
* Headers.
* Several architectures.
* Static and dynamic variants.

## Header validation

Support at least:

| Format                   | Signature                         |
| ------------------------ | --------------------------------- |
| ELF                      | `0x7F 45 4C 46`                   |
| PE/COFF                  | `MZ`, followed by valid PE header |
| Mach-O 32/64             | Mach-O magic values               |
| Mach-O fat               | Fat/universal magic values        |
| Unix archive/static `.a` | `!<arch>\n`                       |
| WebAssembly              | `00 61 73 6D`                     |

Go beyond magic bytes where possible:

* ELF: read class, endianness, and `e_machine`.
* Mach-O: read CPU type and subtype.
* PE: read machine type from COFF header.
* Fat Mach-O: ensure the requested architecture exists.
* Static archive: optionally inspect object members.

That catches the common and frustrating case where a correctly named x64 library is downloaded for an arm64 target.

Use `OS.libraryFileName()` from `code_assets` for ordinary canonical naming, then layer versioned-library matching on top. `code_assets` already provides OS-specific library naming support. ([Dart packages][7])

---

# 9. Generic versus package-specific behavior

The package should own **mechanism**, while consumers own **policy and compilation**.

## `native_prebuilt` should own

* Target labeling.
* Manifest model.
* Release URL construction.
* HTTP download.
* Retries and proxies.
* Archive hashing.
* Safe archive reading.
* Library selection.
* Binary validation.
* Persistent cache.
* Local override lookup.
* Atomic installation.
* CodeAsset registration.
* Diagnostics.
* Manifest generation.
* Workflow scaffolding.

## Consumer packages should own

* Rust, Zig, CMake, Meson, or custom source compilation.
* Source checkout details.
* VTE-specific patches.
* Build flags.
* Feature selection.
* Package-specific minimum OS versions.
* Whether static or dynamic linkage is supported.
* Artifact production commands.
* License and notice generation.
* Symbol export configuration.

## Extension points

Use narrow callbacks:

```dart
typedef LinkModeResolver =
    LinkMode Function(CodeConfig config);

typedef ArtifactEligibility =
    bool Function(CodeConfig config, LinkMode linkMode);

typedef ArchiveEntrySelector =
    ArchiveEntryInfo? Function(
      Iterable<ArchiveEntryInfo> entries,
      ArtifactSelectionContext context,
    );
```

For source preparation:

```dart
abstract interface class SourcePreparation {
  Future<void> prepare({
    required BuildInput input,
    required BuildOutputBuilder output,
    required Logger? logger,
  });
}
```

Ghostty could implement:

```dart
final class GhosttySourcePreparation implements SourcePreparation {
  const GhosttySourcePreparation({
    required this.patches,
  });

  final List<String> patches;

  @override
  Future<void> prepare(...) async {
    // Copy source to working directory.
    // Register source and patch files as dependencies.
    // Apply patches idempotently.
  }
}
```

But I would not put patch application into version 1 unless two or more packages genuinely need it. Start with the fallback `Builder` boundary.

---

# 10. Local prebuilt lookup

Make local search configurable, but deterministic.

Suggested order:

1. `hooks.user_defines.<package>.prebuilt_path`
2. Workspace root:
   `.prebuilt/<package>/<tag>/<platform>/<library>`
3. Application/project root:
   `.prebuilt/<package>/<tag>/<platform>/<library>`
4. Package root:
   `.prebuilt/<tag>/<platform>/<library>`
5. Shared hook cache.
6. Download.
7. Source fallback.

Including package and release tag avoids collisions:

```text
.prebuilt/
└── portable_pty/
    └── portable_pty-v0.0.6/
        └── linux-x64/
            └── libportable_pty_rs.so
```

Your current search intelligently checks a monorepo root and then walks possible project roots. 

Extract that idea, but avoid hard-coding the presence of a `pkgs/` directory as the sole monorepo marker. Dart now has formal pub workspaces. Search for:

* A workspace root pubspec.
* The package root.
* The root application pubspec.
* Explicit search roots supplied by configuration.

Also consider moving local downloaded assets under `.dart_tool/native_prebuilt/` rather than `.prebuilt/`. Use `.prebuilt/` only for user-managed development overrides. This separates:

* User-controlled assets.
* Tool-controlled caches.

---

# 11. CI workflow strategy

Use a **hybrid of reusable workflows and a small generator**.

## Primary mechanism: reusable workflows

Composite actions can bundle steps, but they cannot contain jobs or choose runners. Reusable workflows can contain multiple jobs and preserve per-job and per-step logging. ([GitHub Docs][8])

Your build matrix spans:

* Linux.
* macOS.
* Windows.
* Android.
* iOS.
* Potentially WASM.

That requires jobs and runner selection, so the top-level abstraction should be a reusable workflow.

GitHub supports matrix jobs calling reusable workflows. ([GitHub Docs][9])

Recommended central files:

```text
.github/workflows/
├── native-prebuilt-build.yml
├── native-prebuilt-release.yml
└── native-prebuilt-update-manifest.yml
```

### `native-prebuilt-build.yml`

Inputs:

```yaml
on:
  workflow_call:
    inputs:
      target:
        required: true
        type: string
      artifact-name:
        required: true
        type: string
      build-script:
        required: true
        type: string
      setup-profile:
        required: false
        type: string
```

The caller owns the matrix:

```yaml
jobs:
  build:
    strategy:
      matrix:
        include:
          - target: linux-x64
            runner: ubuntu-latest
          - target: macos-arm64
            runner: macos-14
          - target: windows-x64
            runner: windows-latest

    uses: kingwill101/native-prebuilt-workflows/.github/workflows/build.yml@v1
    with:
      target: ${{ matrix.target }}
      artifact-name: pty-${{ matrix.target }}.tar.gz
      build-script: tool/build_prebuilt.dart
```

However, a reusable workflow selects its own runner internally. Since the runner varies by target, either:

1. Pass `runner` as an input and use it in `runs-on`, or
2. Create OS-specific reusable workflows.

Passing runner as an input is generally acceptable for your own trusted workflow definitions.

## Consumer-owned build script

Do not try to parameterize arbitrary Rust/Zig/CMake commands directly into YAML.

Each repository should expose a stable command:

```bash
dart run tool/build_prebuilt.dart --target linux-x64 --output build/artifact
```

The reusable workflow handles:

* Checkout.
* Dart setup.
* Toolchain setup profile.
* Cache restoration.
* Calling the build script.
* Artifact upload.
* Checksums.
* Attestation or provenance if added later.

The consuming build script handles:

* Cargo versus Zig.
* Patches.
* Target triples.
* Native flags.
* Packaging layout.

## Composite actions

Use composite actions only for repeated step groups such as:

* Installing Zig.
* Installing Rust targets.
* Packaging an artifact.
* Validating archive layout.
* Uploading checksums.

They should supplement reusable workflows, not replace them.

## Generator role

Provide:

```bash
native_prebuilt workflow init
native_prebuilt workflow check
```

The generator should create the thin caller workflow and package build-script skeleton. It should not generate hundreds of lines that are then independently maintained.

That gives you:

* Centralized fixes through reusable workflow versions.
* Readable project-local matrices.
* Package-specific target control.
* Easy onboarding for external consumers.
* No large copied workflow files.

Pin reusable workflows to release tags or commit SHAs. GitHub notes that commit SHAs provide the strongest stability and security. ([GitHub Docs][10])

---

# 12. Existing ecosystem patterns

The foundation you should build on is:

* `package:hooks`
* `package:code_assets`
* `Builder`
* `BuildInput.outputDirectoryShared`
* `BuildOutput.dependencies`
* `hooks.user_defines`

The official `Builder` abstraction is almost exactly the missing integration point for your design. ([Dart packages][3])

For source fallbacks:

* `native_toolchain_c` is the official experimental C toolchain package. ([Dart packages][11])
* `native_toolchain_rust` provides a declarative Rust builder and is a suitable fallback adapter. ([Dart packages][12])

There does not appear to be a broadly adopted, toolchain-agnostic package that standardizes GitHub Release download, hash manifests, archive selection, local override lookup, and source fallback for Dart hooks. Current packages generally implement this internally.

For example, `pdf_manipulator` documents essentially the same cached → download → source compile chain, while `server_native` has its own prebuilt release metadata and lookup hierarchy. ([Dart packages][13])

That indicates the problem is real and recurring, while leaving room for `native_prebuilt` to become the shared layer.

Avoid building against the older `native_assets_cli` API. The modern public surface has been split into `hooks` and `code_assets`; current toolchain packages depend on those newer packages. ([Dart packages][14])

---

# 13. Error handling and diagnostics

Use typed exceptions internally:

```dart
sealed class PrebuiltException implements Exception {
  const PrebuiltException(this.message);

  final String message;
}

final class UnsupportedTargetException extends PrebuiltException { ... }
final class ArtifactNotPublishedException extends PrebuiltException { ... }
final class DownloadException extends PrebuiltException { ... }
final class ArchiveHashMismatchException extends PrebuiltException { ... }
final class PayloadHashMismatchException extends PrebuiltException { ... }
final class ArchiveLayoutException extends PrebuiltException { ... }
final class BinaryFormatException extends PrebuiltException { ... }
final class BinaryArchitectureException extends PrebuiltException { ... }
```

The final hook message should explain the resolution chain:

```text
Unable to provide portable_pty for linux-arm64.

Resolution attempts:
  1. User override: not configured
  2. Local prebuilt: not found
     Searched:
       /workspace/.prebuilt/portable_pty/.../libportable_pty_rs.so
  3. Shared cache: missing
  4. GitHub Release:
     portable_pty-v0.0.6 does not contain pty-linux-arm64.tar.gz
  5. Source fallback:
     Rust target aarch64-unknown-linux-gnu is not installed

Possible fixes:
  • Install the Rust target and rebuild.
  • Configure hooks.user_defines.portable_pty.prebuilt_path.
  • Run dart run native_prebuilt:cli fetch --platform linux-arm64.
```

Also expose a structured trace:

```dart
final class ResolutionTrace {
  final List<ResolutionAttempt> attempts;
}
```

This makes unit testing and CLI diagnostics much easier.

---

# 14. Testing strategy

The package should have three levels.

## Pure unit tests

* Platform labels.
* Library name generation.
* Versioned library matching.
* Cache key generation.
* Retry classification.
* GitHub URL construction.
* Manifest rendering.
* ELF/Mach-O/PE header parsing.
* Archive-entry rejection.

## Local HTTP integration tests

Use an in-process `HttpServer` to test:

* Redirect chains.
* 429 plus `Retry-After`.
* Interrupted responses.
* Invalid content length.
* Slow responses.
* Hash mismatches.
* Proxy configuration.
* Maximum download sizes.

## Hook tests

`code_assets` exposes `testCodeBuildHook`, and `hooks` exposes hook testing utilities. ([Dart packages][7])

Test:

* Dynamic bundled asset.
* Static iOS asset.
* User-defined override.
* Shared cache hit.
* Download hit.
* Unsupported platform.
* Source fallback invocation.
* Dependency registration.
* Wrong architecture rejection.

---

# 15. Suggested version-one scope

Keep the first release focused.

## Version 0.1

* `PrebuiltCodeAssetBuilder implements Builder`
* GitHub public release downloads.
* Const generated manifest.
* Archive and payload SHA-256.
* Streaming `.tar.gz` selection.
* ELF, Mach-O, PE, static archive validation.
* `hooks.user_defines` override.
* `.prebuilt` local lookup.
* `outputDirectoryShared` cache.
* Atomic writes and cross-process locking.
* Generic fallback `Builder`.
* `manifest update`, `manifest verify`, and `fetch` CLI commands.
* Unit and hook tests.

## Version 0.2

* Reusable GitHub workflows.
* Workflow initializer.
* Private GitHub repositories.
* Mirror/base-URL support.
* ZIP artifacts.
* WASM payloads.
* Architecture-level header validation.

## Later

* S3/R2 providers.
* Signed manifests.
* Sigstore attestations.
* SBOM generation.
* Source patch helpers.
* Link-hook integration.
* Artifact mirrors and offline bundles.

---

# Direct answers

### 1. What should the public API look like?

A declarative `PrebuiltCodeAssetBuilder implements Builder`, backed by `PrebuiltManifest`, `PrebuiltArtifact`, `NativeTarget`, `ArtifactInstaller`, and optional resolver interfaces.

### 2. Wrapper, mixin, helper, or something else?

Implement the official `Builder` interface. Do not use inheritance or a mixin. Provide lower-level helper functions for advanced use.

### 3. Builder, CLI, or annotations for hashes?

A CLI. It should update and verify a generated const Dart manifest. Do not perform release discovery through `build_runner` or annotations.

### 4. Composite actions, workflow templates, or CLI-generated YAML?

Reusable workflows for jobs and matrices; composite actions for repeated step sequences; CLI generation only for small caller workflows and build-script scaffolding.

### 5. How should generic and package-specific logic be separated?

`native_prebuilt` owns discovery, transport, integrity, caching, extraction, validation, and asset registration. The consuming package supplies target/link policy and a source fallback `Builder`.

### 6. Existing ecosystem patterns?

Build directly on `hooks`, `code_assets`, the official `Builder` abstraction, and toolchain builders such as `native_toolchain_rust` and `native_toolchain_c`. Existing packages demonstrate the same pattern but generally do not expose it as reusable infrastructure.

### 7. Main build-hook gotchas?

The biggest ones are:

* Custom environment variables are stripped; use `hooks.user_defines`.
* Pin immutable tags and hashes; never resolve `latest` during a hook.
* Do not depend on `curl`, `tar`, or `gh`.
* Verify the archive before parsing it.
* Never blindly extract untrusted archives.
* Handle concurrent cache population.
* Validate architecture, not merely filename and hash.
* Register local source, override, and patch files as hook dependencies.
* Keep downloaded/generated outputs in the hook-provided output directories.
* Provide bounded retries, timeouts, and actionable fallback errors.

The design is strong enough to justify a standalone package, and the official `Builder` API now gives it a natural ecosystem-compatible integration point.

[1]: https://pub.dev/packages/tar?utm_source=chatgpt.com "tar | Dart package"
[2]: https://dart.dev/tools/hooks "Hooks"
[3]: https://pub.dev/documentation/hooks/latest/hooks/Builder-class.html "Builder class - hooks library - Dart API"
[4]: https://dart.dev/tools/hooks?utm_source=chatgpt.com "Hooks"
[5]: https://api.dart.dev/dart-io/HttpClientRequest/followRedirects.html?utm_source=chatgpt.com "followRedirects property - HttpClientRequest class - dart:io library - Dart API"
[6]: https://api.dart.dev/dart-io/HttpClient/findProxyFromEnvironment.html?utm_source=chatgpt.com "findProxyFromEnvironment method - HttpClient class - dart:io library - Dart API"
[7]: https://pub.dev/documentation/code_assets/latest/code_assets?utm_source=chatgpt.com "code_assets library - Dart API"
[8]: https://docs.github.com/en/actions/concepts/workflows-and-actions/reusing-workflow-configurations?utm_source=chatgpt.com "Reusing workflow configurations - GitHub Docs"
[9]: https://docs.github.com/en/enterprise-cloud%40latest/actions/how-tos/reuse-automations/reuse-workflows?utm_source=chatgpt.com "Reuse workflows - GitHub Enterprise Cloud Docs"
[10]: https://docs.github.com/en/actions/how-tos/reuse-automations/reuse-workflows?utm_source=chatgpt.com "Reuse workflows - GitHub Docs"
[11]: https://pub.dev/packages/native_toolchain_c?utm_source=chatgpt.com "native_toolchain_c | Dart package"
[12]: https://pub.dev/packages/native_toolchain_rust?utm_source=chatgpt.com "native_toolchain_rust | Dart package"
[13]: https://pub.dev/documentation/pdf_manipulator/latest/index.html?utm_source=chatgpt.com "pdf_manipulator - Dart API docs"
[14]: https://pub.dev/packages/native_toolchain_c/changelog?utm_source=chatgpt.com "native_toolchain_c changelog | Dart package"

