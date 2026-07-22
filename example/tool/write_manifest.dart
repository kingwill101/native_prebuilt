import 'package:native_prebuilt/src/cli/native_prebuilt_cli.dart';

Future<void> main(List<String> args) async {
  await runNativePrebuiltCli([
    'manifest',
    'update',
    ...args,
  ]);
}
