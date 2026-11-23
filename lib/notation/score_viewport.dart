import 'package:flutter/material.dart';

import '../models/score.dart';
import 'score_painter.dart';

class ScoreViewport extends StatefulWidget {
  const ScoreViewport({
    super.key,
    required this.score,
    required this.selectedEvent,
    required this.selectedPitch,
    this.selectedMeasure,
    this.cursorTick,
    this.playingSegments = const {},
    this.playingPitches = const {},
    this.previewPitch,
    this.previewStaff,
    this.previewDuration = 960,
    this.previewVoice = Voice.v1,
    this.onStart,
    this.onUpdate,
    this.onEnd,
    this.onCancel,
  });

  final Score score;
  final NotationEvent? selectedEvent;
  final int selectedPitch;
  final int? selectedMeasure;
  final int? cursorTick;
  final Set<PlaybackSegment> playingSegments;
  final Map<PlaybackSegment, Set<int>> playingPitches;
  final Pitch? previewPitch;
  final Staff? previewStaff;
  final int previewDuration;
  final Voice previewVoice;
  final void Function(Offset position)? onStart;
  final void Function(Offset position)? onUpdate;
  final void Function(Offset position)? onEnd;
  final VoidCallback? onCancel;

  @override
  State<ScoreViewport> createState() => _ScoreViewportState();
}

class _ScoreViewportState extends State<ScoreViewport> {
  final horizontal = ScrollController();
  final vertical = ScrollController();
  final pointers = <int, Offset>{};
  bool multiTouch = false;

  @override
  void didUpdateWidget(covariant ScoreViewport oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedMeasure != oldWidget.selectedMeasure &&
        widget.selectedMeasure != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !horizontal.hasClients) return;
        final x = ScorePainter.barX(widget.score, widget.selectedMeasure!, 10);
        final viewport = horizontal.position.viewportDimension;
        final width =
            (28 +
                ScorePainter.signatureSpace(
                  widget.score,
                  widget.selectedMeasure!,
                )) *
            10;
        if (x < horizontal.offset || x + width > horizontal.offset + viewport) {
          horizontal.jumpTo(
            (x - 30).clamp(
              horizontal.position.minScrollExtent,
              horizontal.position.maxScrollExtent,
            ),
          );
        }
      });
    }
  }

  void _down(PointerDownEvent event) {
    pointers[event.pointer] = event.position;
    if (pointers.length == 1) {
      multiTouch = false;
      widget.onStart?.call(event.localPosition);
    } else {
      multiTouch = true;
      widget.onCancel?.call();
    }
  }

  void _move(PointerMoveEvent event) {
    if (!pointers.containsKey(event.pointer)) return;
    final delta = event.position - pointers[event.pointer]!;
    pointers[event.pointer] = event.position;
    if (multiTouch) {
      if (pointers.length >= 2) {
        _scroll(horizontal, -delta.dx / pointers.length);
        _scroll(vertical, -delta.dy / pointers.length);
      }
    } else {
      widget.onUpdate?.call(event.localPosition);
    }
  }

  void _scroll(ScrollController controller, double delta) {
    if (!controller.hasClients) return;
    controller.jumpTo(
      (controller.offset + delta).clamp(
        controller.position.minScrollExtent,
        controller.position.maxScrollExtent,
      ),
    );
  }

  void _up(PointerUpEvent event) {
    pointers.remove(event.pointer);
    if (!multiTouch) widget.onEnd?.call(event.localPosition);
    if (pointers.isEmpty) multiTouch = false;
  }

  @override
  void dispose() {
    horizontal.dispose();
    vertical.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const s = 10.0;
    return ColoredBox(
      color: const Color(0xfffaf9f4),
      child: Scrollbar(
        controller: horizontal,
        child: SingleChildScrollView(
          controller: horizontal,
          physics: const NeverScrollableScrollPhysics(),
          scrollDirection: Axis.horizontal,
          child: SingleChildScrollView(
            controller: vertical,
            physics: const NeverScrollableScrollPhysics(),
            child: Listener(
              key: const ValueKey('score-canvas'),
              behavior: HitTestBehavior.opaque,
              onPointerDown: _down,
              onPointerMove: _move,
              onPointerUp: _up,
              onPointerCancel: (event) {
                pointers.remove(event.pointer);
                widget.onCancel?.call();
                if (pointers.isEmpty) multiTouch = false;
              },
              child: SizedBox(
                width: ScorePainter.widthFor(widget.score, s),
                height: ScorePainter.heightFor(s),
                child: ClipRect(
                  child: CustomPaint(
                    painter: ScorePainter(
                      score: widget.score,
                      selectedEvent: widget.selectedEvent,
                      selectedPitch: widget.selectedPitch,
                      selectedMeasure: widget.selectedMeasure,
                      cursorTick: widget.cursorTick,
                      playingSegments: widget.playingSegments,
                      playingPitches: widget.playingPitches,
                      previewPitch: widget.previewPitch,
                      previewStaff: widget.previewStaff,
                      previewDuration: widget.previewDuration,
                      previewVoice: widget.previewVoice,
                      staffSpace: s,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
