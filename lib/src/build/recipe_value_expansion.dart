import 'package:path/path.dart' as p;

import 'native_build_context.dart';
import '../source/resolved_source.dart';

String expandRecipeValue(
  String value,
  NativeBuildContext context,
  ResolvedSource source,
) {
  final placeholders = <String, String>{
    'source': source.directory.path,
    'work': context.directories.work.path,
    'output': context.directories.output.path,
    'cache': context.directories.cache.path,
  };

  var result = value.replaceAllMapped(RegExp(r'\$\{([^}]+)\}'), (match) {
    final token = match.group(1)!;
    if (token.startsWith('env.')) {
      final name = token.substring(4);
      return context.environment[name] ?? match.group(0)!;
    }
    return placeholders[token] ?? match.group(0)!;
  });

  final envPrefix = RegExp(
    r'^(?:\$\{([A-Za-z_][A-Za-z0-9_]*)\}|\$([A-Za-z_][A-Za-z0-9_]*)|([A-Za-z_][A-Za-z0-9_]*))(.*)$',
  );
  final match = envPrefix.firstMatch(result);
  if (match != null) {
    final name = match.group(1) ?? match.group(2) ?? match.group(3)!;
    final remainder = match.group(4) ?? '';
    if (name.length > 1) {
      final replacement = context.environment[name];
      if (replacement != null && replacement.isNotEmpty) {
        result = remainder.isEmpty
            ? replacement
            : '$replacement$remainder';
      }
    }
  }

  return result;
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
