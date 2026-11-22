import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/services.dart';

import '../editor/score_editor.dart';
import '../models/score.dart';

class Project {
  const Project({
    required this.name,
    required this.tempo,
    required this.editor,
  });

  final String name;
  final int tempo;
  final ScoreEditor editor;
}

class ProjectCodec {
  static String encode(Project project) {
    final score = project.editor.score;
    return jsonEncode({
      'version': 1,
      'name': project.name,
      'tempo': project.tempo,
      'beats': score.beatsPerMeasure,
      'unit': score.beatUnit,
      'key': score.keySignature,
      'measureCount': project.editor.measureCount,
      'events': [
        for (final voice in Voice.values)
          for (final event in project.editor.eventsFor(voice))
            if (!event.generatedRest)
              {
                'start': event.start,
                'duration': event.duration,
                'voice': event.voice.name,
                'staff': event.staff.name,
                'pitches': [
                  for (final pitch in event.pitches)
                    {
                      'step': pitch.diatonicStep,
                      'midi': pitch.midiNote,
                      'accidental': pitch.accidental.name,
                    },
                ],
              },
      ],
    });
  }

  static Project decode(String source) {
    final raw = jsonDecode(source);
    if (raw is! Map<String, dynamic>) {
      throw const FormatException('Invalid project.');
    }
    int number(Map<String, dynamic> map, String field, int min, int max) {
      final value = map[field];
      if (value is! int || value < min || value > max) {
        throw FormatException('Invalid $field.');
      }
      return value;
    }

    T enumValue<T extends Enum>(List<T> values, Object? value, String field) {
      for (final item in values) {
        if (item.name == value) return item;
      }
      throw FormatException('Invalid $field.');
    }

    if (raw['version'] != 1) {
      throw const FormatException('Unsupported project version.');
    }
    final name = raw['name'];
    if (name is! String || name.trim().isEmpty || name.length > 100) {
      throw const FormatException('Invalid project name.');
    }
    final tempo = number(raw, 'tempo', 30, 240);
    final beats = number(raw, 'beats', 1, 32);
    final unit = number(raw, 'unit', 1, 16);
    if (![1, 2, 4, 8, 16].contains(unit)) {
      throw const FormatException('Invalid beat unit.');
    }
    final key = number(raw, 'key', -7, 7);
    final count = number(raw, 'measureCount', 1, 100000);
    final ticks = beats * ticksPerQuarter * 4 ~/ unit;
    final events = raw['events'];
    if (events is! List) throw const FormatException('Invalid events.');
    final measures = List.generate(count, (_) => <NotationEvent>[]);
    for (final item in events) {
      if (item is! Map<String, dynamic>) {
        throw const FormatException('Invalid event.');
      }
      final start = number(item, 'start', 0, count * ticks - 1);
      final duration = number(item, 'duration', 60, count * ticks - start);
      if (start % 60 != 0 || duration % 60 != 0) {
        throw const FormatException('Invalid event timing.');
      }
      final voice = enumValue(Voice.values, item['voice'], 'voice');
      final staff = enumValue(Staff.values, item['staff'], 'staff');
      final rawPitches = item['pitches'];
      if (rawPitches is! List) throw const FormatException('Invalid pitches.');
      final pitches = <Pitch>[];
      for (final rawPitch in rawPitches) {
        if (rawPitch is! Map<String, dynamic>) {
          throw const FormatException('Invalid pitch.');
        }
        final step = number(rawPitch, 'step', 0, 67);
        final midi = number(rawPitch, 'midi', 0, 127);
        final accidental = enumValue(
          Accidental.values,
          rawPitch['accidental'],
          'accidental',
        );
        pitches.add(
          Pitch(diatonicStep: step, midiNote: midi, accidental: accidental),
        );
      }
      measures[start ~/ ticks].add(
        NotationEvent(
          startTick: start % ticks,
          durationTicks: duration,
          voice: voice,
          staff: staff,
          pitches: pitches,
        ),
      );
    }
    final score = Score(
      title: name,
      beatsPerMeasure: beats,
      beatUnit: unit,
      keySignature: key,
      measures: [for (final events in measures) Measure(events: events)],
    );
    try {
      return Project(name: name, tempo: tempo, editor: ScoreEditor(score));
    } on ArgumentError catch (error) {
      throw FormatException('Invalid score: ${error.message}');
    }
  }
}

class StoredProject {
  const StoredProject(this.id, this.name, this.modified);
  final String id;
  final String name;
  final DateTime modified;
}

class ProjectStore {
  ProjectStore({Future<Directory> Function()? directory})
    : _directory = directory ?? _appDirectory;

  final Future<Directory> Function() _directory;
  static const _channel = MethodChannel('claviera/projects');

  static Future<Directory> _appDirectory() async {
    final path = await _channel.invokeMethod<String>('directory');
    if (path == null || path.isEmpty) {
      throw const FileSystemException('App storage is unavailable.');
    }
    return Directory('$path/projects');
  }

  Future<Directory> _root() async =>
      (await _directory()).create(recursive: true);

  Future<List<StoredProject>> list() async {
    final root = await _root();
    final result = <StoredProject>[];
    await for (final entry in root.list()) {
      if (entry is! File || !entry.path.endsWith('.json')) continue;
      final name = entry.uri.pathSegments.last;
      final project = ProjectCodec.decode(await entry.readAsString());
      result.add(
        StoredProject(
          name.substring(0, name.length - 5),
          project.name,
          (await entry.stat()).modified,
        ),
      );
    }
    result.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return result;
  }

  Future<Project> load(String id) async {
    _validateId(id);
    return ProjectCodec.decode(
      await File('${(await _root()).path}/$id.json').readAsString(),
    );
  }

  Future<String> save(Project project, {String? id}) async {
    final contents = ProjectCodec.encode(project);
    final root = await _root();
    final random = Random.secure();
    id ??=
        '${DateTime.now().microsecondsSinceEpoch}-${random.nextInt(1 << 32)}';
    _validateId(id);
    final file = File('${root.path}/$id.json');
    final temp = File('${root.path}/$id.tmp');
    try {
      await temp.writeAsString(contents, flush: true);
      await temp.rename(file.path);
    } finally {
      if (await temp.exists()) await temp.delete();
    }
    return id;
  }

  void _validateId(String id) {
    if (!RegExp(r'^[0-9]+-[0-9]+$').hasMatch(id)) {
      throw const FormatException('Invalid project identifier.');
    }
  }
}
