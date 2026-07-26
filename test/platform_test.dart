import 'package:native_prebuilt/native_prebuilt.dart';
import 'package:test/test.dart';

void main() {
  group('NativeTarget', () {
    test('labels', () {
      expect(
        const NativeTarget(os: OS.linux, architecture: Architecture.x64).label,
        'linux-x64',
      );
      expect(
        const NativeTarget(
          os: OS.macOS,
          architecture: Architecture.arm64,
        ).label,
        'macos-arm64',
      );
      expect(
        const NativeTarget(
          os: OS.iOS,
          architecture: Architecture.arm64,
          iOSSdk: IOSSdk.iPhoneSimulator,
        ).label,
        'ios-sim-arm64',
      );
    });

    test('equality and hashCode', () {
      const a = NativeTarget(os: OS.linux, architecture: Architecture.x64);
      const b = NativeTarget(os: OS.linux, architecture: Architecture.x64);
      const c = NativeTarget(os: OS.linux, architecture: Architecture.arm64);
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
    });
  });

  test('hostTarget returns current host info', () {
    final target = hostTarget();
    expect(target.os.name, isNotEmpty);
    expect(target.architecture.name, isNotEmpty);
  });
}
