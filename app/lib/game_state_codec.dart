import 'game_engine.dart';

/// Stable JSON representation shared with the Firebase Cloud Functions.
///
/// Keep this deliberately boring: Firebase Realtime Database stores JSON, not
/// Dart objects.  The function validates every requested mutation and writes a
/// new state version; clients only decode the result.
class GameStateCodec {
  static Map<String, dynamic> encode(GameState state) => <String, dynamic>{
    'players': state.players,
    'currentPlayerIndex': state.currentPlayerIndex,
    'turnStartFaceUp': state.turnStartFaceUp,
    'deck': state.deck,
    'cardGrid': state.cardGrid,
    'faceUp': state.faceUp,
    'pendingRemovals': state.pendingRemovals
        .map((Position p) => <int>[p.row, p.column])
        .toList(),
    'pendingPenalty': state.pendingPenalty,
    'mustSelectAdjacentToHandle': state.mustSelectAdjacentToHandle,
    'turnCanEnd': state.turnCanEnd,
    'pendingSamePosition': state.pendingSamePosition == null
        ? null
        : <int>[
            state.pendingSamePosition!.row,
            state.pendingSamePosition!.column,
          ],
    'stats': <String, dynamic>{
      for (final MapEntry<String, PlayerStats> entry in state.stats.entries)
        entry.key: _encodeStats(entry.value),
    },
  };

  static GameState decode(Map<Object?, Object?> source) {
    final Map<String, dynamic> json = _map(source);
    final Map<String, dynamic> rawStats = _map(json['stats']);
    return GameState(
      players: _strings(json['players']),
      currentPlayerIndex: _int(json['currentPlayerIndex']),
      turnStartFaceUp: _int(json['turnStartFaceUp']),
      deck: _ints(json['deck']),
      cardGrid: _grid(json['cardGrid']),
      faceUp: _boolGrid(json['faceUp']),
      pendingRemovals: _positions(json['pendingRemovals']),
      pendingPenalty: _int(json['pendingPenalty']),
      mustSelectAdjacentToHandle: json['mustSelectAdjacentToHandle'] == true,
      turnCanEnd: json['turnCanEnd'] == true,
      pendingSamePosition: _positionOrNull(json['pendingSamePosition']),
      stats: <String, PlayerStats>{
        for (final MapEntry<String, dynamic> entry in rawStats.entries)
          entry.key: _decodeStats(_map(entry.value)),
      },
    );
  }

  static Map<String, int> _encodeStats(PlayerStats value) => <String, int>{
    'drinks': value.drinks,
    'correct': value.correct,
    'wrong': value.wrong,
    'changedCards': value.changedCards,
    'turns': value.turns,
  };

  static PlayerStats _decodeStats(Map<String, dynamic> value) => PlayerStats(
    drinks: _int(value['drinks']),
    correct: _int(value['correct']),
    wrong: _int(value['wrong']),
    changedCards: _int(value['changedCards']),
    turns: _int(value['turns']),
  );

  static Map<String, dynamic> _map(Object? value) => value is Map
      ? value.map((Object? key, Object? item) => MapEntry('$key', item))
      : <String, dynamic>{};
  static int _int(Object? value) => value is num ? value.toInt() : 0;
  static List<int> _ints(Object? value) => value is List
      ? value.whereType<num>().map((num item) => item.toInt()).toList()
      : <int>[];
  static List<String> _strings(Object? value) => value is List
      ? value.map((Object? item) => '$item').toList()
      : <String>[];

  /// Realtime Database represents a list containing null values as a sparse
  /// numeric-keyed map. Public room snapshots intentionally hide card values,
  /// so always rebuild the fixed Window board shape when reading it.
  static List<List<int?>> _grid(Object? value) => List<List<int?>>.generate(
    windowLayout.length,
    (int row) => List<int?>.generate(windowLayout[row].length, (int column) {
      final Object? item = _indexedValue(_indexedValue(value, row), column);
      return item is num ? item.toInt() : null;
    }),
  );

  static List<List<bool>> _boolGrid(Object? value) => List<List<bool>>.generate(
    windowLayout.length,
    (int row) => List<bool>.generate(
      windowLayout[row].length,
      (int column) => _indexedValue(_indexedValue(value, row), column) == true,
    ),
  );

  static Object? _indexedValue(Object? source, int index) {
    if (source is List) return index < source.length ? source[index] : null;
    if (source is Map) return source[index] ?? source['$index'];
    return null;
  }

  static Set<Position> _positions(Object? value) => value is List
      ? value.map(_positionOrNull).whereType<Position>().toSet()
      : <Position>{};
  static Position? _positionOrNull(Object? value) =>
      value is List && value.length == 2
      ? Position(_int(value[0]), _int(value[1]))
      : null;
}
