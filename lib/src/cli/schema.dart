import 'dart:io';

import 'package:artisanal/args.dart';
import 'package:path/path.dart' as p;

import '../config/schema/build_schema.dart';

class SchemaCommand extends Command<void> {
  SchemaCommand() {
    addSubcommand(_SchemaExportCommand());
  }

  @override
  String get name => 'schema';

  @override
  String get description => 'Export the native_prebuilt JSON schema.';

  @override
  Future<void> run() async {
    io.info(usage);
  }
}

class _SchemaExportCommand extends Command<void> {
  _SchemaExportCommand() {
    argParser.addOption('output', abbr: 'o', help: 'Output JSON schema file.');
  }

  @override
  String get name => 'export';

  @override
  String get description => 'Write the JSON schema to disk.';

  @override
  Future<void> run() async {
    final outputPath =
        option('output') as String? ??
        p.join(Directory.current.path, 'schema', 'native_prebuilt.schema.json');
    final outputFile = File(outputPath);
    outputFile.parent.createSync(recursive: true);
    outputFile.writeAsStringSync(nativePrebuiltSchema.toJson(indent: '  '));
    io.info('Wrote $outputPath');
  }
}
