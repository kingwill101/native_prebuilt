import 'dart:io';

import 'package:artisanal/args.dart';
import 'package:native_prebuilt/native_prebuilt.dart';

Future<void> main(List<String> args) async {
  try {
    await runNativePrebuiltCli(args);
  } catch (error) {
    stderr.writeln(_formatCliError(error));
    exitCode = 1;
  }
}

String _formatCliError(Object error) {
  return switch (error) {
    final UsageException e => [
      e.message,
      if (e.usage.isNotEmpty) e.usage,
    ].join('\n\n'),
    final StateError e => e.message,
    final Object e => e.toString(),
  };
}
