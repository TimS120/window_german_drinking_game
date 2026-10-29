import 'policy_core.dart';

/// Per-position best/second-best cycling; rankings never survive a played move.
class ProposalCycle {
  String? _position;
  String? _method;
  int _rank = 0;
  final _cache = <String, List<AiMoveProposal>>{};

  List<AiMoveProposal>? cached(String position, String method) =>
      position == _position ? _cache[method] : null;

  int nextRank(String position, String method) =>
      position == _position &&
          method == _method &&
          (_cache[method]?.length ?? 0) > 1
      ? 1 - _rank
      : 0;

  AiMoveProposal? accept(
    String position,
    String method,
    List<AiMoveProposal> proposals,
    int requestedRank,
  ) {
    if (position != _position) clear();
    if (proposals.isEmpty) {
      clear();
      return null;
    }
    final pair = proposals.take(2).toList();
    _position = position;
    _cache[method] = List.unmodifiable([
      for (int rank = 0; rank < pair.length; rank++) pair[rank].withRank(rank),
    ]);
    _method = method;
    _rank = requestedRank < pair.length ? requestedRank : 0;
    return _cache[method]![_rank];
  }

  void clear() {
    _position = null;
    _method = null;
    _rank = 0;
    _cache.clear();
  }
}
