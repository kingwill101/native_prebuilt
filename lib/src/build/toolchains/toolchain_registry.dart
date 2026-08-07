import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:path/path.dart' as p;

import '../../platform/native_target.dart';

/// Registry that resolves platform-appropriate binaries for cross-compilation.
///
/// Centralizes NDK / Apple SDK / MSVC discovery that was previously
/// copy-pasted into each recipe's `toolchain_file` / `strip` invocation.
final class NativeToolchainResolver {
  const NativeToolchainResolver();

  /// Resolve a CMake toolchain file for [target], if applicable.
  ///
  /// Returns `null` when no toolchain file is needed or discovery fails.
  String? cmakeToolchainFile(NativeTarget target) {
    if (target.os == OS.android) {
      final ndk = _findAndroidNdk();
      if (ndk == null) return null;
      final candidate = p.join(
        ndk.path,
        'build',
        'cmake',
        'android.toolchain.cmake',
      );
      if (File(candidate).existsSync()) return candidate;
      return null;
    }
    if (target.os == OS.iOS) {
      // Caller should set TOOLCHAIN_FILE to CMake/iOS.cmake relative to
      // source; we only signal that iOS expects a toolchain.
      return null;
    }
    return null;
  }

  /// Resolve the `strip` executable for [target].
  ///
  /// For Android, returns the NDK's `llvm-strip`. For Apple, returns
  /// `xcrun strip` wrapper. Otherwise returns plain `strip` or `llvm-strip`
  /// discovery.
  List<String> stripCommand(NativeTarget target) {
    if (target.os == OS.android) {
      final ndk = _findAndroidNdk();
      if (ndk != null) {
        final hostTag = _ndkHostTag();
        final llvmStrip = p.join(
          ndk.path,
          'toolchains',
          'llvm',
          'prebuilt',
          hostTag,
          'bin',
          'llvm-strip',
        );
        if (File(llvmStrip).existsSync()) return [llvmStrip];
      }
    }
    if (target.os == OS.iOS || target.os == OS.macOS) {
      // Prefer xcrun strip when available.
      return ['xcrun', 'strip'];
    }
    return ['strip'];
  }

  /// Default Android ABI for a native architecture.
  static String androidAbiFor(Architecture arch) => switch (arch) {
        Architecture.arm => 'armeabi-v7a',
        Architecture.arm64 => 'arm64-v8a',
        Architecture.x64 => 'x86_64',
        Architecture.ia32 => 'x86',
        _ => arch.name,
      };

  /// Default OPENSSL root suffix for ABI.
  static String opensslRootForAbi(String abi) => abi;

  Directory? _findAndroidNdk() {
    final candidates = <String?>[
      Platform.environment['ANDROID_NDK_HOME'],
      Platform.environment['ANDROID_NDK'],
      Platform.environment['ANDROID_NDK_ROOT'],
    ];
    for (final pth in candidates) {
      if (pth != null && Directory(pth).existsSync()) return Directory(pth);
    }
    final sdkRoots = <String?>[
      Platform.environment['ANDROID_HOME'],
      Platform.environment['ANDROID_SDK_ROOT'],
      if (Platform.environment['HOME'] != null)
        p.join(Platform.environment['HOME']!, 'Android', 'Sdk'),
    ];
    for (final sdk in sdkRoots) {
      if (sdk == null) continue;
      final ndkDir = Directory(p.join(sdk, 'ndk'));
      if (!ndkDir.existsSync()) continue;
      final versions = ndkDir
          .listSync()
          .whereType<Directory>()
          .toList()
        ..sort((a, b) => b.path.compareTo(a.path));
      if (versions.isNotEmpty) return versions.first;
    }
    return null;
  }

  String _ndkHostTag() {
    if (Platform.isLinux) return 'linux-x86_64';
    if (Platform.isMacOS) return 'darwin-x86_64';
    if (Platform.isWindows) return 'windows-x86_64';
    return 'linux-x86_64';
  }

  /// Whether verbose logging is requested.
  bool get hasAndroidNdk => _findAndroidNdk() != null;
}
