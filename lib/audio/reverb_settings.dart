import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class ReverbSettings {
  const ReverbSettings({
    this.enabled = true,
    this.wet = 0.3,
    this.feedback = 0.78,
    this.damping = 0.4,
    this.tailMs = 1500,
  });

  static const _key = 'claviera.reverb';
  final bool enabled;
  final double wet;
  final double feedback;
  final double damping;
  final int tailMs;

  ReverbSettings copyWith({
    bool? enabled,
    double? wet,
    double? feedback,
    double? damping,
    int? tailMs,
  }) => ReverbSettings(
    enabled: enabled ?? this.enabled,
    wet: wet ?? this.wet,
    feedback: feedback ?? this.feedback,
    damping: damping ?? this.damping,
    tailMs: tailMs ?? this.tailMs,
  );

  Map<String, Object> toMap() => {
    'enabled': enabled,
    'wet': wet,
    'feedback': feedback,
    'damping': damping,
    'tailMs': tailMs,
  };

  static Future<ReverbSettings> load() async {
    final preferences = await SharedPreferences.getInstance();
    final encoded = preferences.getString(_key);
    if (encoded == null) return const ReverbSettings();
    final data = jsonDecode(encoded);
    if (data is! Map ||
        data['enabled'] is! bool ||
        data['wet'] is! num ||
        data['feedback'] is! num ||
        data['damping'] is! num ||
        data['tailMs'] is! int) {
      throw const FormatException('Invalid reverb settings.');
    }
    final wet = (data['wet'] as num).toDouble();
    final feedback = (data['feedback'] as num).toDouble();
    final damping = (data['damping'] as num).toDouble();
    final tailMs = data['tailMs'] as int;
    if (!wet.isFinite ||
        wet < 0 ||
        wet > 1 ||
        !feedback.isFinite ||
        feedback < 0.5 ||
        feedback > 0.9 ||
        !damping.isFinite ||
        damping < 0 ||
        damping > 0.8 ||
        tailMs < 500 ||
        tailMs > 4000) {
      throw const FormatException('Invalid reverb settings.');
    }
    return ReverbSettings(
      enabled: data['enabled'] as bool,
      wet: wet,
      feedback: feedback,
      damping: damping,
      tailMs: tailMs,
    );
  }

  Future<void> save() async {
    final preferences = await SharedPreferences.getInstance();
    if (!await preferences.setString(_key, jsonEncode(toMap()))) {
      throw StateError('Could not save reverb settings.');
    }
  }
}
