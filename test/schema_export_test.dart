import 'dart:io';

import 'package:native_prebuilt/native_prebuilt.dart';
import 'package:native_prebuilt/src/config/schema/build_schema.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test('checked-in schema matches the generated schema', () async {
    final expected = nativePrebuiltSchema.toJson(indent: '  ');
    final checkedInFile = File(
      p.join(Directory.current.path, 'schema', 'native_prebuilt.schema.json'),
    );

    expect(checkedInFile.existsSync(), isTrue);
    expect(checkedInFile.readAsStringSync().trim(), expected.trim());

    final tempDir = await Directory.systemTemp.createTemp(
      'native_prebuilt_schema_',
    );
    try {
      final outputPath = p.join(tempDir.path, 'native_prebuilt.schema.json');
      await runNativePrebuiltCli(['schema', 'export', '--output', outputPath]);
      expect(File(outputPath).readAsStringSync().trim(), expected.trim());
    } finally {
      await tempDir.delete(recursive: true);
    }
  });
}
