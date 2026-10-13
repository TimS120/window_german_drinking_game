import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'room_social.dart';
import 'localization.dart';

class RoomChatPanel extends StatefulWidget {
  const RoomChatPanel({
    super.key,
    required this.sender,
    required this.messages,
    required this.onSend,
    required this.onReact,
    required this.reducedMotion,
    required this.onReducedMotion,
    this.status,
    this.sidePanel = false,
    this.onMinimize,
  });
  final String sender;
  final List<Map<String, dynamic>> messages;
  final Future<void> Function(String) onSend;
  final Future<void> Function(String) onReact;
  final bool reducedMotion;
  final ValueChanged<bool> onReducedMotion;
  final String? status;
  final bool sidePanel;
  final VoidCallback? onMinimize;
  @override
  State<RoomChatPanel> createState() => _RoomChatPanelState();
}

class _RoomChatPanelState extends State<RoomChatPanel> {
  final _text = TextEditingController();
  final _scroll = ScrollController();
  bool _expanded = false;
  bool _sending = false;
  DateTime? _lastReaction;
  DateTime? _lastMessage;
  LocalizedMessage? _error;

  @override
  void didUpdateWidget(RoomChatPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.messages.lastOrNull?['id'] !=
        widget.messages.lastOrNull?['id']) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scroll.hasClients) {
          _scroll.jumpTo(_scroll.position.maxScrollExtent);
        }
      });
    }
  }

  @override
  void dispose() {
    _text.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _text.text.trim();
    if (_sending || text.isEmpty) return;
    if (_lastMessage != null &&
        DateTime.now().difference(_lastMessage!).inMilliseconds < 550) {
      setState(() => _error = (l) => l.waitMessage);
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await widget.onSend(text);
      _lastMessage = DateTime.now();
      if (mounted && _text.text.trim() == text) _text.clear();
    } catch (_) {
      if (mounted) {
        setState(() => _error = (l) => l.messageFailed);
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _react(String emoji) async {
    final now = DateTime.now();
    if (_lastReaction != null &&
        now.difference(_lastReaction!).inMilliseconds < 1000) {
      return;
    }
    _lastReaction = now;
    try {
      await widget.onReact(emoji);
      if (mounted) setState(() => _error = null);
    } catch (_) {
      if (mounted) {
        setState(() => _error = (l) => l.reactionFailed);
      }
    }
  }

  Widget _history() => widget.messages.isEmpty
      ? Align(
          alignment: Alignment.centerLeft,
          child: Text(tr(context).sayHello),
        )
      : ListView.builder(
          controller: _scroll,
          itemCount: widget.messages.length,
          itemBuilder: (context, index) {
            final message = widget.messages[index];
            final time = DateTime.fromMillisecondsSinceEpoch(
              (message['createdAt'] as num).toInt(),
            );
            final clock =
                '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: '$clock  ${message['sender']}: ',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    TextSpan(text: '${message['text']}'),
                  ],
                ),
              ),
            );
          },
        );

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final compact =
          constraints.maxWidth < 700 || MediaQuery.sizeOf(context).height < 600;
      final height = compact ? (_expanded ? 100.0 : 42.0) : 110.0;
      return Material(
        elevation: 8,
        color: Theme.of(context).colorScheme.surfaceContainer,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
          child: Column(
            mainAxisSize: widget.sidePanel
                ? MainAxisSize.max
                : MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Icon(Icons.chat_bubble_outline, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      tr(context).chatTitle(widget.sender),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: widget.reducedMotion
                        ? tr(context).enableReactions
                        : tr(context).reduceReactions,
                    onPressed: () =>
                        widget.onReducedMotion(!widget.reducedMotion),
                    icon: Icon(
                      widget.reducedMotion
                          ? Icons.motion_photos_off
                          : Icons.motion_photos_on,
                      size: 20,
                    ),
                  ),
                  if (widget.onMinimize != null)
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: tr(context).minimizeChat,
                      onPressed: widget.onMinimize,
                      icon: const Icon(Icons.remove),
                    ),
                  if (compact && !widget.sidePanel)
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: _expanded
                          ? tr(context).collapseHistory
                          : tr(context).expandHistory,
                      onPressed: () => setState(() => _expanded = !_expanded),
                      icon: Icon(
                        _expanded ? Icons.expand_more : Icons.expand_less,
                      ),
                    ),
                ],
              ),
              if (widget.sidePanel)
                Expanded(child: _history())
              else
                SizedBox(height: height, child: _history()),
              if (_error != null || widget.status != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _error?.call(tr(context)) ?? widget.status!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontSize: 12,
                    ),
                  ),
                ),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _text,
                      maxLength: 500,
                      minLines: 1,
                      maxLines: 2,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: InputDecoration(
                        hintText: tr(context).messageHint,
                        counterText: '',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: tr(context).sendMessage,
                    onPressed: _sending ? null : _send,
                    icon: const Icon(Icons.send),
                  ),
                ],
              ),
              SizedBox(
                height: 36,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (final emoji in roomEmojis)
                      Tooltip(
                        message: tr(context).releaseEmoji(emoji),
                        child: TextButton(
                          style: TextButton.styleFrom(
                            minimumSize: const Size(42, 32),
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                          ),
                          onPressed: () => _react(emoji),
                          child: Text(
                            emoji,
                            style: const TextStyle(fontSize: 22),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// Local animation only: no animation frames or screen pixels leave the device.
class RoomReactionLayer extends StatelessWidget {
  const RoomReactionLayer({
    super.key,
    required this.reactions,
    required this.reducedMotion,
  });
  final List<Map<String, dynamic>> reactions;
  final bool reducedMotion;
  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: Material(
      type: MaterialType.transparency,
      child: ExcludeSemantics(
        child: Stack(
          children: [
            for (final reaction in reactions)
              Positioned.fill(
                child: _ReactionBurst(
                  key: ValueKey(reaction['id']),
                  reaction: reaction,
                  reducedMotion:
                      reducedMotion || MediaQuery.of(context).disableAnimations,
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

class _ReactionBurst extends StatefulWidget {
  const _ReactionBurst({
    super.key,
    required this.reaction,
    required this.reducedMotion,
  });
  final Map<String, dynamic> reaction;
  final bool reducedMotion;
  @override
  State<_ReactionBurst> createState() => _ReactionBurstState();
}

class _ReactionBurstState extends State<_ReactionBurst>
    with SingleTickerProviderStateMixin {
  late final _animation = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 2),
  )..forward();
  @override
  void dispose() {
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, size) => AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        final t = _animation.value;
        final seed = '${widget.reaction['id']}'.codeUnits.fold(
          0,
          (a, b) => a + b,
        );
        final center = size.maxWidth * (0.2 + (seed % 60) / 100);
        return Opacity(
          opacity: (1 - t * t).clamp(0, 1),
          child: Stack(
            children: [
              for (var i = 0; i < (widget.reducedMotion ? 1 : 5); i++)
                Positioned(
                  left:
                      (center +
                              (i - 2) * 26 +
                              (widget.reducedMotion
                                  ? 0
                                  : math.sin(t * 6 + i) * 20))
                          .clamp(0, math.max(0, size.maxWidth - 48)),
                  bottom: widget.reducedMotion
                      ? size.maxHeight * 0.35
                      : 30 + t * size.maxHeight * (0.55 + i * 0.04),
                  child: Text(
                    '${widget.reaction['emoji']}',
                    style: const TextStyle(
                      fontSize: 42,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ),
              Positioned(
                left: (center - 100).clamp(0, math.max(0, size.maxWidth - 200)),
                bottom: widget.reducedMotion
                    ? size.maxHeight * 0.35 - 24
                    : 15 + t * size.maxHeight * 0.55,
                child: SizedBox(
                  width: 200,
                  child: Text(
                    '${widget.reaction['sender']}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      decoration: TextDecoration.none,
                      shadows: [Shadow(blurRadius: 4, color: Colors.black)],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    ),
  );
}
