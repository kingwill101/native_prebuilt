/// Tests for backward compatibility with the legacy CallbackSourceBuilder API.
///
/// This ensures that packages using PrebuiltCodeAssetBuilder with
/// CallbackSourceBuilder continue to work after the new build pipeline
/// was introduced.
library;

import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:code_assets/src/code_assets/config.dart';
import 'package:hooks/hooks.dart';
import 'package:logging/logging.dart';
import 'package:native_prebuilt/native_prebuilt.dart';
import 'package:test/test.dart';

void main() {
  group('HookBuilderSourceBuilder', () {
    test('static constructor creates adapter from builder instance', () async {
      final tempDir = Directory.systemTemp.createTempSync('adapter_test_');
      try {
        final source = ResolvedSource(
          directory: tempDir,
          origin: SourceOrigin.local,
        );

        // Track if builder was called
        var builderCalled = false;

        final adapter = HookBuilderSourceBuilder.static(
          _MockBuilder(
            onRun: (input, output, logger) {
              builderCalled = true;
            },
          ),
        );

        final input = _createMockBuildInput(tempDir);
        final output = BuildOutputBuilder();

        await adapter.build(
          source: source,
          input: input,
          output: output,
          logger: null,
        );

        expect(
          builderCalled,
          isTrue,
          reason: 'Builder should have been called',
        );
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('factory constructor creates adapter from factory function', () async {
      final tempDir = Directory.systemTemp.createTempSync('adapter_test_');
      try {
        final source = ResolvedSource(
          directory: tempDir,
          origin: SourceOrigin.local,
        );

        // Track if builder was called
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

        final input = _createMockBuildInput(tempDir);
        final output = BuildOutputBuilder();

        await adapter.build(
          source: source,
          input: input,
          output: output,
          logger: null,
        );

        expect(
          builderCalled,
          isTrue,
          reason: 'Builder should have been called',
        );
        expect(receivedPackageName, equals('test_package'));
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('forwards logger to builder', () async {
      final tempDir = Directory.systemTemp.createTempSync('adapter_test_');
      try {
        final source = ResolvedSource(
          directory: tempDir,
          origin: SourceOrigin.local,
        );

        // Track if logger was received
        Logger? receivedLogger;

        final adapter = HookBuilderSourceBuilder.static(
          _MockBuilder(
            onRun: (input, output, logger) {
              receivedLogger = logger;
            },
          ),
        );

        final input = _createMockBuildInput(tempDir);
        final output = BuildOutputBuilder();
        final testLogger = Logger('test');

        await adapter.build(
          source: source,
          input: input,
          output: output,
          logger: testLogger,
        );

        expect(receivedLogger, same(testLogger));
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    });
  });

  group('CallbackSourceBuilder', () {
    test('callback is invoked with correct parameters', () async {
      final tempDir = Directory.systemTemp.createTempSync('callback_test_');
      try {
        final source = ResolvedSource(
          directory: tempDir,
          origin: SourceOrigin.local,
        );

        // Track callback invocation
        ResolvedSource? receivedSource;
        BuildInput? receivedInput;
        BuildOutputBuilder? receivedOutput;
        Logger? receivedLogger;

        final builder = CallbackSourceBuilder(
          callback:
              ({
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

        final input = _createMockBuildInput(tempDir);
        final output = BuildOutputBuilder();
        final testLogger = Logger('test');

        await builder.build(
          source: source,
          input: input,
          output: output,
          logger: testLogger,
        );

        expect(receivedSource, same(source));
        expect(receivedInput, same(input));
        expect(receivedOutput, same(output));
        expect(receivedLogger, same(testLogger));
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    });
  });
}

/// Mock builder for testing.
class _MockBuilder implements Builder {
  _MockBuilder({required this.onRun});

  final void Function(
    BuildInput input,
    BuildOutputBuilder output,
    Logger? logger,
  )
  onRun;

  @override
  Future<void> run({
    required BuildInput input,
    required BuildOutputBuilder output,
    required Logger? logger,
  }) async {
    onRun(input, output, logger);
  }
}

/// Creates a mock BuildInput for testing.
BuildInput _createMockBuildInput(Directory packageRoot) {
  final inputBuilder = BuildInputBuilder()
    ..setupShared(
      packageRoot: packageRoot.uri,
      packageName: 'test_package',
      outputFile: packageRoot.uri.resolve('output.json'),
      outputDirectoryShared: packageRoot.uri.resolve('shared/'),
    )
    ..setupBuildInput()
    ..config.setupBuild(linkingEnabled: false)
    ..config.addBuildAssetTypes(['code_asset'])
    ..config.setupCode(
      targetArchitecture: Architecture.x64,
      targetOS: OS.linux,
      linkModePreference: LinkModePreference.dynamic,
    );

  return inputBuilder.build();
}
