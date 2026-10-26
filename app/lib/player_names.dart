/// Normalize accepted names without changing intentional spelling such as
/// McDonald, O'Neill, or mixed-case nicknames. Work by Unicode scalar rather
/// than one UTF-16 code unit, so initials outside the BMP stay intact too.
String capitalizeName(String value) {
  final name = value.trim();
  if (name.isEmpty) return name;
  final first = String.fromCharCode(name.runes.first);
  return first.toUpperCase() + name.substring(first.length);
}

List<String> splitPlayerNames(String value) => value
    .split(',')
    .map(capitalizeName)
    .where((name) => name.isNotEmpty)
    .toList();
