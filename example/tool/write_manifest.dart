import 'package:native_prebuilt/hooks.dart';

Future<void> main(List<String> args) async {
  await runNativePrebuiltCli(['manifest', 'update', ...args]);
}
