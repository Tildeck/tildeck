/// Variables in a snippet: `{{name}}`, filled in when it runs.
final _variable = RegExp(r'\{\{\s*([A-Za-z0-9_.-]+)\s*\}\}');

/// The variables in [command], each once, in the order they appear.
List<String> variablesIn(String command) {
  final seen = <String>{};
  return [
    for (final m in _variable.allMatches(command))
      if (seen.add(m[1]!)) m[1]!,
  ];
}

/// [command] with each variable replaced by its value; one without a value
/// stays as written.
String fillVariables(String command, Map<String, String> values) =>
    command.replaceAllMapped(_variable, (m) => values[m[1]!] ?? m[0]!);
