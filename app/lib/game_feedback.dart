import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'localization.dart';

/// Turn notices are keyed by turn count, rather than board versions: making a
/// guess must never repeat a notice. Completion celebrates the whole lobby.
class GameFeedback extends StatefulWidget {
  const GameFeedback({
    super.key,
    required this.turnKey,
    required this.player,
    required this.active,
    required this.finished,
    required this.canRestart,
    required this.busy,
    required this.onRestart,
    required this.child,
  });
  final String turnKey;
  final String player;
  final bool active, finished, canRestart, busy;
  final VoidCallback onRestart;
  final Widget child;
  @override
  State<GameFeedback> createState() => _GameFeedbackState();
}

class _GameFeedbackState extends State<GameFeedback>
    with SingleTickerProviderStateMixin {
  Timer? _noticeTimer;
  bool _notice = false;
  late final AnimationController _fireworks = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 15),
  );
  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(GameFeedback oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.turnKey != widget.turnKey ||
        oldWidget.active != widget.active ||
        oldWidget.finished != widget.finished) {
      _sync();
    }
  }

  void _sync() {
    _noticeTimer?.cancel();
    _notice = widget.active && !widget.finished;
    if (widget.finished) {
      _notice = false;
      _fireworks.forward(from: 0);
    } else {
      _fireworks.reset();
      if (_notice) {
        _noticeTimer = Timer(const Duration(seconds: 3), () {
          if (mounted) setState(() => _notice = false);
        });
      }
    }
  }

  @override
  void dispose() {
    _noticeTimer?.cancel();
    _fireworks.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = tr(context);
    return Stack(
      children: [
        AbsorbPointer(absorbing: widget.finished, child: widget.child),
        if (!widget.active && !widget.finished)
          Positioned.fill(
            child: IgnorePointer(
              child: ColoredBox(
                color: const Color(0x66777777),
                child: Align(
                  alignment: Alignment.topCenter,
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(l.waitingTurn(widget.player)),
                    ),
                  ),
                ),
              ),
            ),
          ),
        if (_notice)
          Positioned.fill(
            child: GestureDetector(
              key: const ValueKey('turn-notice'),
              behavior: HitTestBehavior.opaque,
              onTap: () {
                _noticeTimer?.cancel();
                setState(() => _notice = false);
              },
              child: ColoredBox(
                color: Colors.black38,
                child: Center(
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        l.yourTurn(widget.player),
                        style: Theme.of(context).textTheme.headlineMedium,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        if (widget.finished) ...[
          const Positioned.fill(
            child: ModalBarrier(dismissible: false, color: Colors.black54),
          ),
          if (!MediaQuery.disableAnimationsOf(context))
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedBuilder(
                  animation: _fireworks,
                  builder: (context, _) =>
                      CustomPaint(painter: _FireworksPainter(_fireworks.value)),
                ),
              ),
            ),
          Center(
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      l.youWon,
                      style: Theme.of(context).textTheme.headlineMedium,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    if (widget.canRestart)
                      FilledButton(
                        onPressed: widget.busy ? null : widget.onRestart,
                        child: Text(l.restartGame),
                      )
                    else
                      Text(l.waitingRestart),
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _FireworksPainter extends CustomPainter {
  _FireworksPainter(this.progress);
  final double progress;
  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0 || progress >= 1) return;
    final seconds = progress * 15;
    const colors = [
      Colors.amberAccent,
      Colors.pinkAccent,
      Colors.cyanAccent,
      Colors.greenAccent,
      Colors.deepOrangeAccent,
      Colors.purpleAccent,
    ];
    // Stagger complete launch/flight/burst sequences. The final burst fades
    // before the fifteen-second celebration ends; no rocket starts mid-air.
    for (int rocket = 0; rocket < 18; rocket++) {
      final random = math.Random(rocket * 7919 + 42);
      final age = seconds - rocket * .72;
      final flight = .9 + random.nextDouble() * .3;
      final burstDuration = 1.25 + random.nextDouble() * .25;
      final start = Offset(
        size.width * (.08 + random.nextDouble() * .84),
        size.height + 12,
      );
      final target = Offset(
        size.width * (.12 + random.nextDouble() * .76),
        size.height * (.10 + random.nextDouble() * .45),
      );
      final control = Offset(
        start.dx + (target.dx - start.dx) * .25,
        size.height * .55,
      );
      final color = colors[rocket % colors.length];
      if (age < 0 || age >= flight + burstDuration) continue;
      if (age < flight) {
        final t = age / flight;
        final tailStart = math.max(0.0, t - .22);
        final trail = Paint()..strokeCap = StrokeCap.round;
        for (int segment = 0; segment < 12; segment++) {
          final a = tailStart + (t - tailStart) * segment / 12;
          final b = tailStart + (t - tailStart) * (segment + 1) / 12;
          trail
            ..color = Color.lerp(
              Colors.deepOrangeAccent,
              color,
              segment / 12,
            )!.withValues(alpha: (segment + 1) / 12 * .85)
            ..strokeWidth = 1 + segment / 6;
          canvas.drawLine(
            _flightPoint(start, control, target, a),
            _flightPoint(start, control, target, b),
            trail,
          );
        }
        final head = _flightPoint(start, control, target, t);
        canvas.drawCircle(
          head,
          6,
          Paint()..color = color.withValues(alpha: .25),
        );
        canvas.drawCircle(head, 2.5, Paint()..color = Colors.white);
        continue;
      }
      final phase = (age - flight) / burstDuration;
      final expansion = 1 - math.pow(1 - phase, 3).toDouble();
      final radius = expansion * math.min(size.width, size.height) * .23;
      final gravity = Offset(0, phase * phase * 55);
      final paint = Paint()
        ..color = color.withValues(alpha: 1 - phase)
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round;
      if (phase < .12) {
        canvas.drawCircle(
          target,
          10 * (1 - phase / .12),
          Paint()..color = Colors.white.withValues(alpha: 1 - phase / .12),
        );
      }
      for (int ray = 0; ray < 36; ray++) {
        final angle = ray * math.pi * 2 / 36;
        final speed = .65 + random.nextDouble() * .35;
        final vector = Offset(math.cos(angle), math.sin(angle));
        final tip = target + vector * radius * speed + gravity;
        canvas.drawLine(
          target + vector * math.max(0.0, radius * speed - 10) + gravity,
          tip,
          paint,
        );
        canvas.drawCircle(tip, 1.5 * (1 - phase), paint);
      }
    }
  }

  Offset _flightPoint(
    Offset start,
    Offset control,
    Offset target,
    double time,
  ) {
    final t = 1 - (1 - time) * (1 - time);
    final inverse = 1 - t;
    return start * (inverse * inverse) +
        control * (2 * inverse * t) +
        target * (t * t);
  }

  @override
  bool shouldRepaint(_FireworksPainter oldDelegate) =>
      progress != oldDelegate.progress;
}
