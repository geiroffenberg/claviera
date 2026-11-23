import '../editor/score_editor.dart';
import '../models/score.dart';

int articulatedEnd(VoiceEvent event) {
  final marks = event.articulations;
  final duration = event.duration;
  final sounding = marks.contains(Articulation.staccatissimo)
      ? (duration / 4).round()
      : marks.contains(Articulation.staccato)
      ? (duration * (marks.contains(Articulation.tenuto) ? .75 : .5)).round()
      : duration;
  return event.start + sounding.clamp(1, duration);
}

int articulatedVelocity(VoiceEvent event, int velocity) {
  final boost = event.articulations.contains(Articulation.marcato)
      ? 24
      : event.articulations.contains(Articulation.accent)
      ? 16
      : 0;
  return (velocity + boost).clamp(1, 127);
}
