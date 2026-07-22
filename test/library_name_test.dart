import 'package:native_prebuilt/native_prebuilt.dart';
import 'package:test/test.dart';

void main() {
  test('canonical dynamic library names', () {
    expect(
      canonicalDynamicLibraryName(
        const NativeTarget(os: OS.linux, architecture: Architecture.x64),
        'demo',
      ),
      'libdemo.so',
    );
    expect(
      canonicalDynamicLibraryName(
        const NativeTarget(os: OS.macOS, architecture: Architecture.arm64),
        'demo',
      ),
      'libdemo.dylib',
    );
    expect(
      canonicalDynamicLibraryName(
        const NativeTarget(os: OS.windows, architecture: Architecture.x64),
        'demo',
      ),
      'demo.dll',
    );
  });

  test('canonical static library names', () {
    expect(
      canonicalStaticLibraryName(
        const NativeTarget(os: OS.linux, architecture: Architecture.x64),
        'demo',
      ),
      'libdemo.a',
    );
  });

  test('versioned matching', () {
    expect(
      matchesLibraryName(
        'libdemo.so.1.2',
        canonicalName: 'libdemo.so',
        acceptVersionedNames: true,
      ),
      isTrue,
    );
    expect(
      matchesLibraryName(
        'libdemo.so.1.2',
        canonicalName: 'libdemo.so',
        acceptVersionedNames: false,
      ),
      isFalse,
    );
  });
}
