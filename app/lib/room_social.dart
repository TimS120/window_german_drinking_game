import 'dart:convert';

import 'firebase_room_repository.dart';
import 'firebase_events.dart';
import 'game_engine.dart';
import 'rl_policy.dart';

const roomEmojis = ['😂', '🎉', '❤️', '👍', '😮', '😭', '🍻', '🔥'];

/// Names come from accepted seats, never from an untrusted message sender.
String roomDeviceLabel(
  List<RoomSeat> seats,
  String uid, {
  String Function(int number, String names)? format,
}) {
  final owners = seats
      .map((s) => s.ownerUid)
      .whereType<String>()
      .toSet()
      .toList();
  final names = seats
      .where((s) => s.ownerUid == uid)
      .map((s) => s.name)
      .toList();
  if (names.length == 1) return names.single;
  final number = owners.indexOf(uid) + 1;
  final joinedNames = names.join(', ');
  return format?.call(number, joinedNames) ?? 'Device $number ($joinedNames)';
}

Map<String, dynamic> socialMap(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

class RoomSocialSnapshot {
  RoomSocialSnapshot(Object? value, {this.isFullSnapshot = false})
    : data = socialMap(value);
  final bool isFullSnapshot;
  final Map<String, dynamic> data;
  RoomSocialSnapshot updated(Map<String, dynamic> patch) => RoomSocialSnapshot(
    applyFirebaseEvent(
      data,
      FirebaseEvent('patch', jsonEncode({'path': '/', 'data': patch})),
    ),
  );
  Map<String, dynamic> get turn => socialMap(data['turn']);
  Map<String, dynamic> get activity => socialMap(data['activity']);
  Map<String, dynamic> get reactions => socialMap(data['reactions']);
  List<Map<String, dynamic>> get messages {
    final entries = socialMap(data['messages']).entries.toList()
      ..sort((a, b) {
        final time = ((socialMap(a.value)['createdAt'] as num?) ?? 0).compareTo(
          (socialMap(b.value)['createdAt'] as num?) ?? 0,
        );
        return time != 0 ? time : a.key.compareTo(b.key);
      });
    return entries.map((e) => {...socialMap(e.value), 'id': e.key}).toList();
  }

  Map<String, dynamic> turnFor(OnlineRoom room) {
    final owner = room.seats
        .elementAtOrNull(room.state.currentPlayerIndex)
        ?.ownerUid;
    final direct = socialMap(socialMap(data['turnViews'])[owner]);
    final view = direct['version'] == room.version ? direct : turn;
    return view['version'] == room.version && view['uid'] == owner ? view : {};
  }

  Map<String, dynamic> activityFor(OnlineRoom room) {
    final views =
        socialMap(data['turnViews']).values
            .map(socialMap)
            .where(
              (v) =>
                  v['clicked'] is String &&
                  v['version'] is num &&
                  (v['version'] as num) <= room.version,
            )
            .toList()
          ..sort(
            (a, b) => ((a['createdAt'] as num?) ?? 0).compareTo(
              (b['createdAt'] as num?) ?? 0,
            ),
          );
    final recent = views.lastOrNull;
    if (recent == null ||
        ((activity['createdAt'] as num?) ?? 0) >
            ((recent['createdAt'] as num?) ?? 0)) {
      return activity;
    }
    return {
      'id': recent['eventId'],
      'clicked': recent['clicked'],
      'label': recent['label'],
      'createdAt': recent['createdAt'],
      'player':
          room.seats
              .elementAtOrNull((recent['playerIndex'] as num?)?.toInt() ?? -1)
              ?.name ??
          '',
    };
  }
}

Map<String, dynamic> encodeSharedProposal(AiMoveProposal proposal) => {
  'pass': proposal.action.isPass,
  if (!proposal.action.isPass) ...{
    'row': proposal.action.position!.row,
    'column': proposal.action.position!.column,
    'orientation': proposal.action.orientation!.name,
    'guess': proposal.action.guess!.name,
  },
  'confidence': proposal.confidence,
  'source': proposal.source,
  if (proposal.valueEstimate != null) 'value': proposal.valueEstimate,
  if (proposal.expectedDrinks != null) 'drinks': proposal.expectedDrinks,
  if (proposal.explanation != null) 'explanation': proposal.explanation,
};

AiMoveProposal? decodeSharedProposal(Object? value) {
  try {
    final raw = socialMap(value);
    if (raw.isEmpty) return null;
    return AiMoveProposal(
      action: raw['pass'] == true
          ? const PolicyAction.pass()
          : PolicyAction.guess(
              position: Position(raw['row'] as int, raw['column'] as int),
              orientation: Orientation.values.byName(
                raw['orientation'] as String,
              ),
              guess: GuessType.values.byName(raw['guess'] as String),
            ),
      confidence: (raw['confidence'] as num).toDouble(),
      source: raw['source'] as String,
      valueEstimate: (raw['value'] as num?)?.toDouble(),
      expectedDrinks: (raw['drinks'] as num?)?.toDouble(),
      explanation: raw['explanation'] as String?,
    );
  } catch (_) {
    return null;
  }
}

/// A small host-authoritative delta. Chat history is capped without resending
/// its existing messages, and only the latest reaction per device is retained.
Map<String, dynamic> socialRequestPatch({
  required RoomRequest request,
  required OnlineRoom room,
  required WindowGameEngine game,
  required RoomSocialSnapshot social,
}) {
  if (!room.seats.any((s) => s.ownerUid == request.uid) ||
      request.createdAt == null) {
    return {};
  }
  final action = request.action;
  final sender = roomDeviceLabel(room.seats, request.uid);
  final timestamp = request.createdAt!;
  final patch = <String, dynamic>{};
  if (request.type == 'chat') {
    final text = (action['text'] as String?)?.trim() ?? '';
    if (text.isEmpty || text.length > 500) return {};
    final previous = social.messages
        .where((m) => m['uid'] == request.uid)
        .lastOrNull;
    if (previous != null && timestamp - (previous['createdAt'] as num) < 500) {
      return {};
    }
    patch['messages/${request.id}'] = {
      'uid': request.uid,
      'sender': sender,
      'text': text,
      'createdAt': timestamp,
    };
    final messages = social.messages;
    for (final old in messages.take(
      (messages.length - 99).clamp(0, messages.length),
    )) {
      patch['messages/${old['id']}'] = null;
    }
  } else if (request.type == 'reaction') {
    if (!roomEmojis.contains(action['emoji'])) return {};
    final previous = socialMap(social.reactions[request.uid]);
    if (timestamp - ((previous['createdAt'] as num?) ?? 0) < 1000) return {};
    patch['reactions/${request.uid}'] = {
      'id': request.id,
      'sender': sender,
      'emoji': action['emoji'],
      'createdAt': timestamp,
    };
  } else if (request.type == 'turnUi') {
    if (!room.started ||
        request.expectedVersion != room.version ||
        room.seats
                .elementAtOrNull(game.exportState().currentPlayerIndex)
                ?.ownerUid !=
            request.uid ||
        jsonEncode(action).length > 6000) {
      return {};
    }
    const stages = [
      'idle',
      'comparison',
      'guess',
      'adviser',
      'calculating',
      'suggestion',
    ];
    if (!stages.contains(action['stage'])) return {};
    final stage = action['stage'];
    if (stage == 'comparison' || stage == 'guess') {
      if (action['row'] is! int || action['column'] is! int) return {};
      final position = Position(action['row'], action['column']);
      if (!game.isValidSlot(position)) return {};
      final options = game.getValidOptionsForCard(position);
      if (options.isEmpty ||
          (stage == 'guess' &&
              !options.any(
                (o) => o.orientation.name == action['orientation'],
              ))) {
        return {};
      }
    }
    final proposal = decodeSharedProposal(action['proposal']);
    if (action['proposal'] != null) {
      if (proposal == null ||
          !proposal.confidence.isFinite ||
          proposal.source.length > 100 ||
          (proposal.explanation?.length ?? 0) > 2500) {
        return {};
      }
      if (proposal.action.isPass) {
        if (!game.turnCanEnd) return {};
      } else {
        final position = proposal.action.position!;
        if (!game.isValidSlot(position) ||
            !game
                .getValidOptionsForCard(position)
                .any(
                  (o) =>
                      o.orientation == proposal.action.orientation &&
                      o.guesses.contains(proposal.action.guess),
                )) {
          return {};
        }
      }
    }
    patch['turn'] = {
      'uid': request.uid,
      'version': room.version,
      'stage': stage,
      if (action['row'] != null) 'row': action['row'],
      if (action['column'] != null) 'column': action['column'],
      if (action['orientation'] != null) 'orientation': action['orientation'],
      if (proposal != null) 'proposal': encodeSharedProposal(proposal),
      if (action['method'] == 'rlModel' || action['method'] == 'statistics')
        'method': action['method'],
    };
    final clicked = action['clicked'];
    final label = action['label'];
    if (clicked is String &&
        clicked.length <= 80 &&
        label is String &&
        label.length <= 180) {
      patch['activity'] = {
        'id': request.id,
        'clicked': clicked,
        'label': label,
        'player': game.currentPlayer,
        'createdAt': timestamp,
      };
    }
  }
  return patch;
}
