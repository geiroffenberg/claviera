import '../editor/score_editor.dart';
import '../models/score.dart';

class _Point {
  const _Point(this.tick, this.velocity);
  final int tick;
  final int velocity;
}

class _Ramp {
  const _Ramp(this.start, this.end);
  final _Point start;
  final _Point end;
}

class DynamicsTimeline {
  DynamicsTimeline(ScoreEditor editor) {
    if (editor.pendingHairpin != null) {
      throw StateError('Finish or remove the unfinished hairpin first.');
    }
    final marks = editor.dynamicChanges;
    hasExpression = marks.isNotEmpty || editor.hairpins.isNotEmpty;
    _points.addAll(marks.entries.map((e) => _Point(e.key, e.value.velocity)));
    final hairpins = editor.hairpins.toList()
      ..sort((a, b) => a.start.compareTo(b.start));
    for (final hairpin in hairpins) {
      final start = _Point(hairpin.start, velocityAt(hairpin.start));
      final endTick = hairpin.end!;
      final endMark = marks[endTick];
      final levels = DynamicMark.values.map((mark) => mark.velocity).toList();
      final target =
          endMark?.velocity ??
          (hairpin.kind == HairpinKind.crescendo
              ? levels.where((v) => v > start.velocity).firstOrNull ??
                    levels.last
              : levels.where((v) => v < start.velocity).lastOrNull ??
                    levels.first);
      final inner =
          marks.entries
              .where((e) => e.key > start.tick && e.key < endTick)
              .map((e) => _Point(e.key, e.value.velocity))
              .toList()
            ..sort((a, b) => a.tick.compareTo(b.tick));
      final vertices = [start, ...inner, _Point(endTick, target)];
      for (var i = 1; i < vertices.length; i++) {
        _ramps.add(_Ramp(vertices[i - 1], vertices[i]));
      }
      _points.add(vertices.last);
    }
  }

  late final bool hasExpression;
  final _points = <_Point>[];
  final _ramps = <_Ramp>[];

  int velocityAt(int tick) {
    for (final ramp in _ramps) {
      if (tick >= ramp.start.tick && tick < ramp.end.tick) {
        final fraction =
            (tick - ramp.start.tick) / (ramp.end.tick - ramp.start.tick);
        return (ramp.start.velocity +
                fraction * (ramp.end.velocity - ramp.start.velocity))
            .round();
      }
    }
    var latest = -1;
    var velocity = 80;
    for (final point in _points) {
      if (point.tick <= tick && point.tick >= latest) {
        latest = point.tick;
        velocity = point.velocity;
      }
    }
    return velocity;
  }
}
