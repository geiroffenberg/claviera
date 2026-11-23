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
    final hasArticulations = Voice.values.any(
      (voice) => project.editor
          .eventsFor(voice)
          .any((event) => event.articulations.isNotEmpty),
    );
    final hasOrnaments = Voice.values.any(
      (voice) => project.editor
          .eventsFor(voice)
          .any((event) => event.articulations.any((mark) => mark.isOrnament)),
    );
    return jsonEncode({
      'version': hasOrnaments
          ? 9
          : project.editor.arpeggios.isNotEmpty
          ? 8
          : hasArticulations
          ? 7
          : project.editor.hairpins.isNotEmpty
          ? 6
          : project.editor.dynamicChanges.isNotEmpty
          ? 5
          : project.editor.repeatStarts.isNotEmpty ||
                project.editor.repeatEnds.isNotEmpty
          ? 4
          : project.editor.timeChanges.isNotEmpty ||
                project.editor.keyChanges.isNotEmpty
          ? 3
          : project.editor.tempoChanges.isEmpty
          ? 1
          : 2,
      'name': project.name,
      'tempo': project.tempo,
      'beats': score.beatsPerMeasure,
      'unit': score.beatUnit,
      'key': score.keySignature,
      'measureCount': project.editor.measureCount,
      if (project.editor.arpeggios.isNotEmpty)
        'arpeggios': [
          for (final entry
              in (project.editor.arpeggios.entries.toList()
                ..sort((a, b) => a.key.compareTo(b.key))))
            {'tick': entry.key, 'direction': entry.value.name},
        ],
      if (project.editor.hairpins.isNotEmpty)
        'hairpins': [
          for (final h
              in (project.editor.hairpins.toList()
                ..sort((a, b) => a.start.compareTo(b.start))))
            {
              'start': h.start,
              if (h.end != null) 'end': h.end,
              'kind': h.kind.name,
            },
        ],
      if (project.editor.dynamicChanges.isNotEmpty)
        'dynamics': [
          for (final entry
              in (project.editor.dynamicChanges.entries.toList()
                ..sort((a, b) => a.key.compareTo(b.key))))
            {'tick': entry.key, 'mark': entry.value.name},
        ],
      if (project.editor.repeatStarts.isNotEmpty)
        'repeatStarts': project.editor.repeatStarts.toList()..sort(),
      if (project.editor.repeatEnds.isNotEmpty)
        'repeatEnds': project.editor.repeatEnds.toList()..sort(),
      if (project.editor.tempoChanges.isNotEmpty)
        'tempoChanges': [
          for (final entry
              in (project.editor.tempoChanges.entries.toList()
                ..sort((a, b) => a.key.compareTo(b.key))))
            {'measure': entry.key, 'bpm': entry.value},
        ],
      if (project.editor.timeChanges.isNotEmpty)
        'timeChanges': [
          for (final entry
              in (project.editor.timeChanges.entries.toList()
                ..sort((a, b) => a.key.compareTo(b.key))))
            {
              'measure': entry.key,
              'beats': entry.value.beats,
              'unit': entry.value.unit,
            },
        ],
      if (project.editor.keyChanges.isNotEmpty)
        'keyChanges': [
          for (final entry
              in (project.editor.keyChanges.entries.toList()
                ..sort((a, b) => a.key.compareTo(b.key))))
            {'measure': entry.key, 'key': entry.value},
        ],
      'events': [
        for (final voice in Voice.values)
          for (final event in project.editor.eventsFor(voice))
            if (!event.generatedRest)
              {
                'start': event.start,
                'duration': event.duration,
                'voice': event.voice.name,
                'staff': event.staff.name,
                if (event.articulations.isNotEmpty)
                  'articulations': [
                    for (final mark in Articulation.values)
                      if (event.articulations.contains(mark)) mark.name,
                  ],
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

    final version = raw['version'];
    if (version is! int || version < 1 || version > 9) {
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
    final tempos = <int, int>{};
    if (version == 2 || (version > 2 && raw.containsKey('tempoChanges'))) {
      final changes = raw['tempoChanges'];
      if (changes is! List) {
        throw const FormatException('Invalid tempo changes.');
      }
      for (final change in changes) {
        if (change is! Map<String, dynamic>) {
          throw const FormatException('Invalid tempo change.');
        }
        final measure = number(change, 'measure', 0, count - 1);
        if (tempos.containsKey(measure)) {
          throw const FormatException('Duplicate tempo change.');
        }
        tempos[measure] = number(change, 'bpm', 30, 240);
      }
    }
    final times = <int, TimeSignature>{};
    final keys = <int, int>{};
    if (version >= 3) {
      for (final field in ['timeChanges', 'keyChanges']) {
        final changes = raw[field];
        if (changes == null) continue;
        if (changes is! List) throw FormatException('Invalid $field.');
        for (final change in changes) {
          if (change is! Map<String, dynamic>) {
            throw FormatException('Invalid $field.');
          }
          final measure = number(change, 'measure', 1, count - 1);
          if (field == 'timeChanges') {
            if (times.containsKey(measure)) {
              throw const FormatException('Duplicate time change.');
            }
            final b = number(change, 'beats', 1, 32);
            final u = number(change, 'unit', 1, 16);
            if (![1, 2, 4, 8, 16].contains(u)) {
              throw const FormatException('Invalid beat unit.');
            }
            times[measure] = TimeSignature(b, u);
          } else {
            if (keys.containsKey(measure)) {
              throw const FormatException('Duplicate key change.');
            }
            keys[measure] = number(change, 'key', -7, 7);
          }
        }
      }
    }
    Set<int> repeatMarks(String field) {
      final values = raw[field];
      if (values == null) return {};
      if (values is! List) throw FormatException('Invalid $field.');
      final marks = <int>{};
      for (final value in values) {
        if (value is! int || value < 0 || value >= count || !marks.add(value)) {
          throw FormatException('Invalid $field.');
        }
      }
      return marks;
    }

    final starts = version >= 4 ? repeatMarks('repeatStarts') : <int>{};
    final ends = version >= 4 ? repeatMarks('repeatEnds') : <int>{};
    final layout = Score(
      title: name,
      beatsPerMeasure: beats,
      beatUnit: unit,
      keySignature: key,
      measures: [
        for (var i = 0; i < count; i++)
          Measure(timeSignature: times[i], keySignature: keys[i]),
      ],
    );
    final totalTicks = layout.measureStart(count);
    final arpeggios = List.generate(count, (_) => <int, ArpeggioDirection>{});
    if (version == 8 || (version > 8 && raw.containsKey('arpeggios'))) {
      final marks = raw['arpeggios'];
      if (marks is! List) throw const FormatException('Invalid arpeggios.');
      for (final item in marks) {
        if (item is! Map<String, dynamic>) {
          throw const FormatException('Invalid arpeggio.');
        }
        final tick = number(item, 'tick', 0, totalTicks - 1);
        if (tick % 60 != 0) {
          throw const FormatException('Invalid arpeggio timing.');
        }
        final measure = layout.measureAtTick(tick);
        final offset = tick - layout.measureStart(measure);
        if (arpeggios[measure].containsKey(offset)) {
          throw const FormatException('Duplicate arpeggio.');
        }
        arpeggios[measure][offset] = enumValue(
          ArpeggioDirection.values,
          item['direction'],
          'arpeggio direction',
        );
      }
    }
    final dynamics = List.generate(count, (_) => <int, DynamicMark>{});
    if (version == 5 || (version > 5 && raw.containsKey('dynamics'))) {
      final marks = raw['dynamics'];
      if (marks is! List) throw const FormatException('Invalid dynamics.');
      for (final item in marks) {
        if (item is! Map<String, dynamic>) {
          throw const FormatException('Invalid dynamic.');
        }
        final tick = number(item, 'tick', 0, totalTicks - 1);
        if (tick % 60 != 0) {
          throw const FormatException('Invalid dynamic timing.');
        }
        final measure = layout.measureAtTick(tick);
        final offset = tick - layout.measureStart(measure);
        if (dynamics[measure].containsKey(offset)) {
          throw const FormatException('Duplicate dynamic.');
        }
        dynamics[measure][offset] = enumValue(
          DynamicMark.values,
          item['mark'],
          'dynamic',
        );
      }
    }
    final hairpins = <Hairpin>[];
    if (version == 6 || (version > 6 && raw.containsKey('hairpins'))) {
      final values = raw['hairpins'];
      if (values is! List) throw const FormatException('Invalid hairpins.');
      for (final item in values) {
        if (item is! Map<String, dynamic>) {
          throw const FormatException('Invalid hairpin.');
        }
        final start = number(item, 'start', 0, totalTicks - 1);
        final end = item.containsKey('end')
            ? number(item, 'end', start + 1, totalTicks - 1)
            : null;
        if (start % 60 != 0 || (end != null && end % 60 != 0)) {
          throw const FormatException('Invalid hairpin timing.');
        }
        hairpins.add(
          Hairpin(
            start: start,
            end: end,
            kind: enumValue(HairpinKind.values, item['kind'], 'hairpin kind'),
          ),
        );
      }
      hairpins.sort((a, b) => a.start.compareTo(b.start));
      final pending = hairpins.where((h) => h.end == null).toList();
      final completed = hairpins.where((h) => h.end != null).toList();
      if (pending.length > 1 ||
          (pending.isNotEmpty &&
              completed.any(
                (h) =>
                    pending.single.start >= h.start &&
                    pending.single.start < h.end!,
              ))) {
        throw const FormatException('Overlapping or unfinished hairpins.');
      }
      for (var i = 1; i < completed.length; i++) {
        if (completed[i - 1].end! > completed[i].start) {
          throw const FormatException('Overlapping or unfinished hairpins.');
        }
      }
    }
    final events = raw['events'];
    if (events is! List) throw const FormatException('Invalid events.');
    final measures = List.generate(count, (_) => <NotationEvent>[]);
    for (final item in events) {
      if (item is! Map<String, dynamic>) {
        throw const FormatException('Invalid event.');
      }
      final start = number(item, 'start', 0, totalTicks - 1);
      final duration = number(item, 'duration', 60, totalTicks - start);
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
      final articulations = <Articulation>{};
      if (version >= 7 && item.containsKey('articulations')) {
        final marks = item['articulations'];
        if (marks is! List) {
          throw const FormatException('Invalid articulations.');
        }
        for (final mark in marks) {
          final articulation = enumValue(
            Articulation.values,
            mark,
            'articulation',
          );
          if (version < 9 && articulation.isOrnament) {
            throw const FormatException('Ornaments require project version 9.');
          }
          if (!articulations.add(articulation)) {
            throw const FormatException('Duplicate articulation.');
          }
        }
        if (!validArticulations(articulations, isRest: pitches.isEmpty)) {
          throw const FormatException('Invalid articulations.');
        }
      }
      final measure = layout.measureAtTick(start);
      measures[measure].add(
        NotationEvent(
          startTick: start - layout.measureStart(measure),
          durationTicks: duration,
          voice: voice,
          staff: staff,
          pitches: pitches,
          articulations: articulations,
        ),
      );
    }
    final score = Score(
      title: name,
      beatsPerMeasure: beats,
      beatUnit: unit,
      keySignature: key,
      hairpins: hairpins,
      measures: [
        for (var i = 0; i < measures.length; i++)
          Measure(
            events: measures[i],
            tempo: tempos[i],
            timeSignature: times[i],
            keySignature: keys[i],
            repeatStart: starts.contains(i),
            repeatEnd: ends.contains(i),
            dynamics: dynamics[i],
            arpeggios: arpeggios[i],
          ),
      ],
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
