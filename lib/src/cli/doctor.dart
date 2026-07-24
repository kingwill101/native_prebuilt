import 'package:artisanal/args.dart';

import 'native_prebuilt_config.dart';

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
    final configPath = option('config') as String?;
    if (configPath == null) {
      throw UsageException('doctor requires --config', usage);
    }
    final config = NativePrebuiltConfig.loadFile(configPath);
    io.info('package: ${config.package}');
    io.info('release: ${config.release}');
    io.info('artifacts: ${config.artifacts.length}');
  }
}
