import 'dart:convert';
import 'dart:js_interop';
import 'dart:math';
import '../app/lib/game_engine.dart';
import '../app/lib/game_state_codec.dart';

@JS('globalThis.windowEngine')
external set bridge(JSFunction value);

Map<String, dynamic> execute(Map<String, dynamic> request) {
  final game = request['state'] == null
      ? WindowGameEngine(List<String>.from(request['players']), random: Random.secure())
      : WindowGameEngine.fromState(
          GameStateCodec.decode(Map<Object?, Object?>.from(request['state'])),
          random: Random.secure(),
        );
  final action = request['action'] as Map?;
  if (action != null) {
    if (game.gameEnded) throw StateError('The game has finished.');
    GuessResult? result;
    switch (action['type']) {
      case 'guess':
        final values = action['position'] as List;
        final position = Position(values[0] as int, values[1] as int);
        final option = game.getValidOptionsForCard(position).where(
          (o) => o.orientation.name == action['orientation'],
        ).firstOrNull;
        if (option == null) throw StateError('Invalid card selection.');
        result = game.applyGuess(position, option, GuessType.values.byName(action['guess']));
      case 'confirmSame':
        result = game.confirmSameGuess();
      case 'confirmRemovals':
        if (game.pendingRemovals.isEmpty) throw StateError('No removal is pending.');
        game.confirmRemovals();
      case 'endTurn':
        if (!game.turnCanEnd || game.pendingRemovals.isNotEmpty || game.pendingSamePosition != null) {
          throw StateError('Finish the turn first.');
        }
        game.endTurn();
      default:
        throw StateError('Unknown move.');
    }
    if (result?.invalidReason != null) throw StateError(result!.invalidReason!);
  }
  return {
    'state': GameStateCodec.encode(game.exportState()),
    'publicState': GameStateCodec.encode(game.publicObservation(maxEvents: maxPublicHistoryEvents)),
    'deckSize': game.exportState().deck.length,
    'ended': game.gameEnded,
  };
}

void main() {
  bridge = ((JSString input) {
    try {
      return jsonEncode(execute(Map<String, dynamic>.from(jsonDecode(input.toDart)))).toJS;
    } catch (error) {
      return jsonEncode({'error': error.toString()}).toJS;
    }
  }).toJS;
}
