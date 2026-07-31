import 'package:code_assets/code_assets.dart';
import 'package:liquify/liquify.dart';
import 'package:path/path.dart' as p;

import '../binary/library_name.dart';
import '../manifest/prebuilt_artifact.dart';
import 'native_build_context.dart';
import '../source/resolved_source.dart';

final Liquid _liquid = Liquid();

String expandRecipeValue(
  String value,
  NativeBuildContext context,
  ResolvedSource source,
) {
  return _liquid.renderString(value, _recipeData(context, source));
}

List<String> expandRecipeValues(
  Iterable<String> values,
  NativeBuildContext context,
  ResolvedSource source,
) => values.map((value) => expandRecipeValue(value, context, source)).toList();

List<List<String>> expandRecipeCommands(
  Iterable<List<String>> commands,
  NativeBuildContext context,
  ResolvedSource source,
) => commands
    .map((command) => expandRecipeValues(command, context, source))
    .toList();

Map<String, String> expandRecipeStringMap(
  Map<String, String> values,
  NativeBuildContext context,
  ResolvedSource source,
) => {
  for (final entry in values.entries)
    entry.key: expandRecipeValue(entry.value, context, source),
};

String resolveWorkRelativePath(
  String declaredPath,
  NativeBuildContext context,
  ResolvedSource source,
) {
  final expanded = expandRecipeValue(declaredPath, context, source);
  if (!p.isAbsolute(expanded)) return expanded;

  final normalized = p.normalize(expanded);
  final workRoot = p.normalize(context.directories.work.path);
  if (p.isWithin(workRoot, normalized)) {
    return p.relative(normalized, from: workRoot);
  }
  return p.basename(normalized);
}

Map<String, dynamic> _recipeData(
  NativeBuildContext context,
  ResolvedSource source,
) {
  final target = context.target;
  final libraryStem = context.hook.libraryStem;
  final dynamicName = canonicalDynamicLibraryName(target, libraryStem);
  final staticName = canonicalStaticLibraryName(target, libraryStem);
  final sdk = _sdkName(target);
  final rustTriple = _rustTarget(target);
  final zigTarget = _zigTarget(target);

  final data = <String, dynamic>{
    // Backwards-compatible short forms.
    'source': {
      'path': source.directory.path,
      'root': source.directory.path,
      'origin': source.origin.name,
      'revision': source.revision,
    },
    'work': context.directories.work.path,
    'output': context.directories.output.path,
    'cache': context.directories.cache.path,
    'env': context.environment,
    // Explicit directory namespace for recipes that want to avoid ambiguous
    // short names such as `work` and `output`.
    'directories': {
      'source': source.directory.path,
      'work': context.directories.work.path,
      'output': context.directories.output.path,
      'cache': context.directories.cache.path,
    },
    'target': {
      'label': target.label,
      'os': target.os.name,
      'architecture': target.architecture.name,
      'sdk': sdk,
      'ios_sdk': sdk,
      'is_ios': target.os == OS.iOS,
      'is_android': target.os == OS.android,
      'is_linux': target.os == OS.linux,
      'is_macos': target.os == OS.macOS,
      'is_windows': target.os == OS.windows,
      'rust_triple': rustTriple,
      'rust_target': rustTriple,
      'zig_target': zigTarget,
      'cmake_target': target.label,
    },
    'library': {
      'stem': libraryStem,
      'name': context.hook.linkMode is StaticLinking ? staticName : dynamicName,
      'dynamic_name': dynamicName,
      'static_name': staticName,
      'prefix': _libraryPrefix(target),
      'extension': _libraryExtension(target, context.hook.linkMode),
      'versioned_name': _versionedLibraryName(
        target,
        libraryStem,
        context.options['library_version']?.toString(),
      ),
    },
    'hook': {
      'packageName': context.hook.packageName,
      'package_name': context.hook.packageName,
      'assetName': context.hook.assetName,
      'asset_name': context.hook.assetName,
      'libraryStem': libraryStem,
      'library_stem': libraryStem,
      'linkMode': context.hook.linkMode.toString(),
      'link_mode': context.hook.linkMode.toString(),
    },
    'project': {
      'package': context.hook.packageName,
      'asset_name': context.hook.assetName,
      'library_stem': libraryStem,
    },
    // Values declared under `build.options` are available as `options.*`.
    'options': context.options,
    'variables': const <String, dynamic>{},
  };
  data['variables'] = _resolveVariables(context.variables, data);
  return data;
}

Map<String, dynamic> _resolveVariables(
  Map<String, Object?> input,
  Map<String, dynamic> data,
) {
  var current = <String, dynamic>{...input};
  for (var pass = 0; pass < 16; pass++) {
    final passData = Map<String, dynamic>.from(data)..['variables'] = current;
    final next = <String, dynamic>{
      for (final entry in input.entries)
        entry.key: _expandVariableValue(entry.value, passData),
    };
    if (_deepEquals(current, next)) return next;
    current = next;
  }
  return current;
}

Object? _expandVariableValue(Object? value, Map<String, dynamic> data) {
  return switch (value) {
    String string => _liquid.renderString(string, data),
    Map map => <String, dynamic>{
      for (final entry in map.entries)
        entry.key.toString(): _expandVariableValue(entry.value, data),
    },
    List list => [for (final item in list) _expandVariableValue(item, data)],
    _ => value,
  };
}

bool _deepEquals(Object? left, Object? right) {
  if (left is Map && right is Map) {
    if (left.length != right.length) return false;
    for (final entry in left.entries) {
      if (!right.containsKey(entry.key) ||
          !_deepEquals(entry.value, right[entry.key])) {
        return false;
      }
    }
    return true;
  }
  if (left is List && right is List) {
    return left.length == right.length &&
        Iterable<int>.generate(
          left.length,
        ).every((index) => _deepEquals(left[index], right[index]));
  }
  return left == right;
}

String? _sdkName(NativeTarget target) {
  return switch (target.iOSSdk) {
    IOSSdk.iPhoneOS => 'iphoneos',
    IOSSdk.iPhoneSimulator => 'iphonesimulator',
    null => null,
    _ => null,
  };
}

String _libraryPrefix(NativeTarget target) {
  return switch (target.os) {
    OS.windows => '',
    _ => 'lib',
  };
}

String _versionedLibraryName(
  NativeTarget target,
  String libraryStem,
  String? version,
) {
  if (version == null || version.isEmpty) {
    return canonicalDynamicLibraryName(target, libraryStem);
  }
  return switch (target.os) {
    OS.linux => 'lib$libraryStem.so.$version',
    OS.macOS || OS.iOS => 'lib$libraryStem.$version.dylib',
    OS.windows => '$libraryStem.dll',
    _ => canonicalDynamicLibraryName(target, libraryStem),
  };
}

String? _libraryExtension(NativeTarget target, LinkMode linkMode) {
  final name = canonicalLibraryName(
    target: target,
    libraryStem: 'library',
    payload: linkMode is StaticLinking
        ? const StaticLibraryPayload(libraryStem: 'library')
        : const DynamicLibraryPayload(libraryStem: 'library'),
  );
  final dot = name.lastIndexOf('.');
  return dot == -1 ? null : name.substring(dot);
}

String? _rustTarget(NativeTarget target) {
  final arch = target.architecture;
  return switch (target.os) {
    OS.linux => switch (arch) {
      Architecture.x64 => 'x86_64-unknown-linux-gnu',
      Architecture.arm64 => 'aarch64-unknown-linux-gnu',
      Architecture.arm => 'armv7-unknown-linux-gnueabihf',
      Architecture.ia32 => 'i686-unknown-linux-gnu',
      _ => null,
    },
    OS.macOS => switch (arch) {
      Architecture.x64 => 'x86_64-apple-darwin',
      Architecture.arm64 => 'aarch64-apple-darwin',
      _ => null,
    },
    OS.windows => switch (arch) {
      Architecture.x64 => 'x86_64-pc-windows-msvc',
      Architecture.arm64 => 'aarch64-pc-windows-msvc',
      Architecture.ia32 => 'i686-pc-windows-msvc',
      _ => null,
    },
    OS.android => switch (arch) {
      Architecture.x64 => 'x86_64-linux-android',
      Architecture.arm64 => 'aarch64-linux-android',
      Architecture.arm => 'armv7-linux-androideabi',
      Architecture.ia32 => 'i686-linux-android',
      _ => null,
    },
    OS.iOS => switch ((target.iOSSdk, arch)) {
      (IOSSdk.iPhoneOS, Architecture.arm64) => 'aarch64-apple-ios',
      (IOSSdk.iPhoneSimulator, Architecture.arm64) => 'aarch64-apple-ios-sim',
      (IOSSdk.iPhoneSimulator, Architecture.x64) => 'x86_64-apple-ios',
      _ => null,
    },
    _ => null,
  };
}

String? _zigTarget(NativeTarget target) {
  final arch = target.architecture;
  return switch (target.os) {
    OS.linux => switch (arch) {
      Architecture.x64 => 'x86_64-linux-gnu',
      Architecture.arm64 => 'aarch64-linux-gnu',
      Architecture.arm => 'arm-linux-gnueabihf',
      Architecture.ia32 => 'x86-linux-gnu',
      _ => null,
    },
    OS.macOS => switch (arch) {
      Architecture.x64 => 'x86_64-macos',
      Architecture.arm64 => 'aarch64-macos',
      _ => null,
    },
    OS.windows => switch (arch) {
      Architecture.x64 => 'x86_64-windows-gnu',
      Architecture.arm64 => 'aarch64-windows-gnu',
      Architecture.ia32 => 'x86-windows-gnu',
      _ => null,
    },
    OS.android => switch (arch) {
      Architecture.x64 => 'x86_64-linux-android',
      Architecture.arm64 => 'aarch64-linux-android',
      Architecture.arm => 'arm-linux-androideabi',
      Architecture.ia32 => 'x86-linux-android',
      _ => null,
    },
    OS.iOS => switch ((target.iOSSdk, arch)) {
      (IOSSdk.iPhoneOS, Architecture.arm64) => 'aarch64-ios',
      (IOSSdk.iPhoneSimulator, Architecture.arm64) => 'aarch64-ios-simulator',
      (IOSSdk.iPhoneSimulator, Architecture.x64) => 'x86_64-ios-simulator',
      _ => null,
    },
    _ => null,
  };
}
