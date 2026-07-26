import 'package:liquify/liquify.dart';
import 'package:path/path.dart' as p;

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
  return <String, dynamic>{
    'source': {'path': source.directory.path},
    'work': context.directories.work.path,
    'output': context.directories.output.path,
    'cache': context.directories.cache.path,
    'env': context.environment,
    'target': {
      'label': context.target.label,
      'os': context.target.os.name,
      'architecture': context.target.architecture.name,
    },
    'hook': {
      'packageName': context.hook.packageName,
      'assetName': context.hook.assetName,
      'libraryStem': context.hook.libraryStem,
      'linkMode': context.hook.linkMode.toString(),
    },
  };
}
