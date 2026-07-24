/// Integration test for the legacy CallbackSourceBuilder API.
///
/// This test verifies that the old API pattern continues to work
/// after the new build pipeline was introduced.
library;

import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:code_assets/src/code_assets/config.dart';
import 'package:hooks/hooks.dart';
import 'package:logging/logging.dart';
import 'package:native_prebuilt/native_prebuilt.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test('legacy CallbackSourceBuilder API works end-to-end', () async {
    final fixtureDir = Directory.current
        .parent
        .parent
        .uri
        .resolve('test/fixtures/hook_packages/callback_source_builder')
        .toFilePath();

    final packageDir = Directory(fixtureDir);

    // Track callback invocation
    ResolvedSource? receivedSource;
    BuildInput? receivedInput;
    BuildOutputBuilder? receivedOutput;
    Logger? receivedLogger;

    final builder = CallbackSourceBuilder(
      callback: ({
        required source,
        required input,
        required output,
        required logger,
      }) async {
        receivedSource = source;
        receivedInput = input;
        receivedOutput = output;
        receivedLogger = logger;
      },
    );

    // Create mock BuildInput
    final tempDir = Directory.systemTemp.createTempSync('callback_test_');
    try {
      final source = ResolvedSource(
        directory: tempDir,
        origin: SourceOrigin.local,
      );

      final inputBuilder = BuildInputBuilder()
        ..setupShared(
          packageRoot: packageDir.uri,
          packageName: 'callback_source_fixture',
          outputFile: tempDir.uri.resolve('output.json'),
          outputDirectoryShared: tempDir.uri.resolve('shared/'),
        )
        ..setupBuildInput()
        ..config.setupBuild(linkingEnabled: false)
        ..config.addBuildAssetTypes(['code_asset'])
        ..config.setupCode(
          targetArchitecture: Architecture.x64,
          targetOS: OS.linux,
          linkModePreference: LinkModePreference.dynamic,
        );

      final input = inputBuilder.build();
      final output = BuildOutputBuilder();
      final testLogger = Logger('test');

      await builder.build(
        source: source,
        input: input,
        output: output,
        logger: testLogger,
      );

      // Verify callback was invoked with correct parameters
      expect(receivedSource, same(source),
          reason: 'Source should be passed through');
      expect(receivedInput, same(input),
          reason: 'Input should be passed through');
      expect(receivedOutput, same(output),
          reason: 'Output should be passed through');
      expect(receivedLogger, same(testLogger),
          reason: 'Logger should be passed through');
    } finally {
      tempDir.deleteSync(recursive: true);
    }
  });

  test('legacy HookBuilderSourceBuilder adapter works with factory', () async {
    final fixtureDir = Directory.current
        .parent
        .parent
        .uri
        .resolve('test/fixtures/hook_packages/callback_source_builder')
        .toFilePath();

    final packageDir = Directory(fixtureDir);

    // Track callback invocation
    var builderCalled = false;
    String? receivedPackageName;

    final adapter = HookBuilderSourceBuilder.factory(
      (input) => _MockBuilder(
        onRun: (input, output, logger) {
          builderCalled = true;
          receivedPackageName = input.packageName;
        },
      ),
    );

    // Create mock BuildInput
    final tempDir = Directory.systemTemp.createTempSync('adapter_test_');
    try {
      final source = ResolvedSource(
        directory: tempDir,
        origin: SourceOrigin.local,
      );

      final inputBuilder = BuildInputBuilder()
        ..setupShared(
          packageRoot: packageDir.uri,
          packageName: 'callback_source_fixture',
          outputFile: tempDir.uri.resolve('output.json'),
          outputDirectoryShared: tempDir.uri.resolve('shared/'),
        )
        ..setupBuildInput()
        ..config.setupBuild(linkingEnabled: false)
        ..config.addBuildAssetTypes(['code_asset'])
        ..config.setupCode(
          targetArchitecture: Architecture.x64,
          targetOS: OS.linux,
          linkModePreference: LinkModePreference.dynamic,
        );

      final input = inputBuilder.build();
      final output = BuildOutputBuilder();
      final testLogger = Logger('test');

      await adapter.build(
        source: source,
        input: input,
        output: output,
        logger: testLogger,
      );

      // Verify adapter was invoked correctly
      expect(builderCalled, isTrue,
          reason: 'Builder should have been called');
      expect(receivedPackageName, equals('callback_source_fixture'),
          reason: 'Package name should be passed through');
    } finally {
      tempDir.deleteSync(recursive: true);
    }
  });
}

/// Mock builder for testing.
class _MockBuilder implements Builder {
  _MockBuilder({required this.onRun});

  final void Function(BuildInput input, BuildOutputBuilder output,
      Logger? logger) onRun;

  @override
  Future<void> run({
    required BuildInput input,
    required BuildOutputBuilder output,
    required Logger? logger,
  }) async {
    onRun(input, output, logger);
  }
}
