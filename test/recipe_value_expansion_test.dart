import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:native_prebuilt/src/build/native_build_context.dart';
import 'package:native_prebuilt/src/build/recipe_value_expansion.dart';
import 'package:native_prebuilt/src/source/resolved_source.dart';
import 'package:test/test.dart';

void main() {
  test('exposes target, library, source, directory, and hook variables', () {
    final context = NativeBuildContext(
      target: NativeTarget(os: OS.linux, architecture: Architecture.x64),
      hook: NativeHookConfiguration(
        packageName: 'demo',
        assetName: 'demo.dart',
        libraryStem: 'demo',
        linkMode: DynamicLoadingBundled(),
      ),
      directories: _directories(),
      toolchains: const ToolchainRegistry(),
      environment: const {'CC': 'clang'},
      options: const {'build_target': 'demo', 'library_version': '1.2.3'},
      variables: const {
        'target_arg': '--target {{ target.rust_target }}',
        'build_command': 'cargo {{ variables.target_arg }}',
        'artifact_path': '{{ source.path }}/{{ library.versioned_name }}',
      },
    );
    final source = ResolvedSource(
      directory: Directory('/tmp/demo-source'),
      origin: SourceOrigin.git,
      revision: 'deadbeef',
    );

    expect(
      expandRecipeValue(
        '{{ target.label }} {{ target.rust_triple }}',
        context,
        source,
      ),
      'linux-x64 x86_64-unknown-linux-gnu',
    );
    expect(
      expandRecipeValue(
        '{{ library.name }} {{ library.static_name }} {{ library.versioned_name }} {{ library.extension }}',
        context,
        source,
      ),
      'libdemo.so libdemo.a libdemo.so.1.2.3 .so',
    );
    expect(
      expandRecipeValue(
        '{{ source.revision }} {{ directories.work }} {{ options.build_target }}',
        context,
        source,
      ),
      'deadbeef /tmp/demo-work demo',
    );
    expect(
      expandRecipeValue(
        '{{ hook.package_name }} {{ target.is_linux }}',
        context,
        source,
      ),
      'demo true',
    );
    expect(
      expandRecipeValue(
        '{{ variables.build_command }} {{ variables.artifact_path }}',
        context,
        source,
      ),
      'cargo --target x86_64-unknown-linux-gnu '
      '/tmp/demo-source/libdemo.so.1.2.3',
    );
  });

  test('exposes iOS SDK and Zig target variables', () {
    final context = NativeBuildContext(
      target: NativeTarget(
        os: OS.iOS,
        architecture: Architecture.arm64,
        iOSSdk: IOSSdk.iPhoneSimulator,
      ),
      hook: NativeHookConfiguration(
        packageName: 'demo',
        assetName: 'demo.dart',
        libraryStem: 'demo',
        linkMode: DynamicLoadingBundled(),
      ),
      directories: _directories(),
      toolchains: const ToolchainRegistry(),
      environment: const {},
    );
    final source = ResolvedSource(
      directory: Directory('/tmp/demo-source'),
      origin: SourceOrigin.cache,
    );

    expect(
      expandRecipeValue(
        '{{ target.sdk }} {{ target.zig_target }} {{ target.rust_target }}',
        context,
        source,
      ),
      'iphonesimulator aarch64-ios-simulator aarch64-apple-ios-sim',
    );
  });
}

NativeBuildDirectories _directories() => NativeBuildDirectories(
  source: Directory('/tmp/demo-source'),
  work: Directory('/tmp/demo-work'),
  output: Directory('/tmp/demo-output'),
  cache: Directory('/tmp/demo-cache'),
);
