import 'package:artisanal/args.dart';

import '../config/native_prebuilt_config.dart';
import 'cli_config.dart';

class DoctorCommand extends Command<void> {
  DoctorCommand() {
    argParser.addOption('config', abbr: 'c', help: 'Path to YAML config file.');
  }

  @override
  String get name => 'doctor';

  @override
  String get description => 'Validate configuration and io.info a summary.';

  @override
  Future<void> run() async {
    final configFile =
        resolveConfigFile(option('config') as String?) ??
        (throw UsageException(
          'Could not find native_prebuilt.yaml. Pass --config explicitly.',
          usage,
        ));
    final config = await loadNativePrebuiltConfig(configFile);
    io.info(renderDoctorSummary(config));
  }
}

String renderDoctorSummary(NativePrebuiltConfig config) {
  final b = StringBuffer()
    ..writeln('package: ${config.package}')
    ..writeln('release: ${config.release.toReleaseSource()}')
    ..writeln('artifacts: ${config.artifacts.length}');
  for (final entry in config.artifacts.entries) {
    b.writeln(
      '  - ${entry.key}: archive=${entry.value.archive}, payload=${entry.value.payload.type}',
    );
  }
  return b.toString().trimRight();
}
