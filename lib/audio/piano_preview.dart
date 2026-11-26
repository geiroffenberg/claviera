import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'score_playback.dart';

class PianoPreview {
  PianoPreview({required this.onError, MethodChannel? channel, bool? supported})
    : _channel = channel ?? const MethodChannel('claviera/piano_preview'),
      _supported = supported ?? (!kIsWeb && Platform.isAndroid) {
    if (_supported) _channel.setMethodCallHandler(_handleNativeCall);
  }

  static const _scoreTail = Duration(milliseconds: 1500);

  final void Function(String message) onError;
  final MethodChannel _channel;
  final bool _supported;
  Future<bool>? _initialization;
  int? _note;
  int _revision = 0;
  bool _enabled = true;
  bool _disposed = false;
  bool _failed = false;
  Timer? _playbackTimer;
  DateTime? _tailEndsAt;
  bool _playingScore = false;
  void Function()? _onPlaybackFinished;

  Future<void> _handleNativeCall(MethodCall call) async {
    if (call.method == 'playbackError' && _playingScore) {
      stopScore();
      _report(
        call.arguments is String
            ? call.arguments as String
            : 'Score playback failed.',
      );
      final callback = _onPlaybackFinished;
      _onPlaybackFinished = null;
      callback?.call();
    }
  }

  bool get enabled => _enabled;
  bool get playingScore => _playingScore;

  void warmUp() {
    if (_supported && !_disposed && !_failed) {
      unawaited(_initialization ??= _initialize());
    }
  }

  Future<bool> _initialize() async {
    try {
      await _channel.invokeMethod<void>('initialize');
      return true;
    } on PlatformException catch (error) {
      _report(error.message ?? 'Piano preview failed (${error.code}).');
    } on MissingPluginException {
      _report('Piano preview is unavailable on this device.');
    }
    return false;
  }

  void setEnabled(bool value) {
    _enabled = value;
    if (!value) stop();
  }

  void play(int midi) {
    if (!_enabled ||
        !_supported ||
        _disposed ||
        _failed ||
        _playingScore ||
        _note == midi) {
      return;
    }
    _note = midi;
    final revision = ++_revision;
    unawaited(_playWhenReady(midi, revision));
  }

  Future<bool> playScore(
    PlaybackPlan plan, {
    required void Function() onFinished,
  }) async {
    if (_disposed || _failed) return false;
    if (!_supported) {
      _report('Score playback is available on Android only.');
      return false;
    }
    if (plan.durationMs == 0) {
      onError('Add a note or rest before playing.');
      return false;
    }
    stop();
    final revision = ++_revision;
    _playingScore = true;
    _onPlaybackFinished = onFinished;
    try {
      final ready = await (_initialization ??= _initialize());
      if (!ready || _disposed || revision != _revision) {
        if (revision == _revision) _playingScore = false;
        return false;
      }
      if (plan.notes.isNotEmpty) {
        final prepared = await _channel.invokeMethod<bool>('prepareScore');
        if (prepared == null) {
          throw PlatformException(
            code: 'invalid_response',
            message: 'Could not prepare piano playback.',
          );
        }
        if (!prepared || _disposed || revision != _revision) {
          if (revision == _revision) _playingScore = false;
          return false;
        }
      }
      await _channel.invokeMethod<void>('playScore', {
        'notes': plan.notes.map((note) => note.toMap()).toList(),
      });
      if (_disposed || revision != _revision) return false;
      _playbackTimer = Timer(Duration(milliseconds: plan.durationMs), () {
        if (_disposed || revision != _revision) return;
        // The native player ends on its own so the reverb tail keeps ringing.
        _playingScore = false;
        _revision++;
        _playbackTimer = null;
        _tailEndsAt = DateTime.now().add(_scoreTail);
        _onPlaybackFinished = null;
        onFinished();
      });
      return true;
    } on PlatformException catch (error) {
      if (revision == _revision) {
        _playingScore = false;
        _report(error.message ?? 'Score playback failed (${error.code}).');
      }
    } on MissingPluginException {
      if (revision == _revision) {
        _playingScore = false;
        _report('Score playback is unavailable on this device.');
      }
    }
    return false;
  }

  void stopScore() {
    final ringing = _tailEndsAt?.isAfter(DateTime.now()) ?? false;
    if (!_playingScore && !ringing) return;
    _tailEndsAt = null;
    _playingScore = false;
    _revision++;
    _playbackTimer?.cancel();
    _playbackTimer = null;
    unawaited(_stopScore());
  }

  Future<void> _stopScore() async {
    try {
      await _channel.invokeMethod<void>('stopScore');
    } on PlatformException catch (error) {
      _report(
        error.message ?? 'Could not stop score playback (${error.code}).',
      );
    } on MissingPluginException {
      _report('Score playback is unavailable on this device.');
    }
  }

  Future<void> _playWhenReady(int midi, int revision) async {
    try {
      final ready = await (_initialization ??= _initialize());
      if (!ready) return;
      if (_disposed || !_enabled || revision != _revision) return;
      await _channel.invokeMethod<void>('play', {'midi': midi});
    } on PlatformException catch (error) {
      _report(error.message ?? 'Piano preview failed (${error.code}).');
    } on MissingPluginException {
      _report('Piano preview is unavailable on this device.');
    }
  }

  void stop() {
    _revision++;
    final hadNote = _note != null;
    _note = null;
    if (_supported &&
        !_disposed &&
        !_failed &&
        hadNote &&
        _initialization != null) {
      unawaited(_stop());
    }
  }

  Future<void> _stop() async {
    try {
      await _channel.invokeMethod<void>('stop');
    } on PlatformException catch (error) {
      _report(error.message ?? 'Could not stop piano preview (${error.code}).');
    } on MissingPluginException {
      _report('Piano preview is unavailable on this device.');
    }
  }

  void _report(String message) {
    if (_disposed || _failed) return;
    _failed = true;
    onError(message);
  }

  void dispose() {
    stopScore();
    stop();
    _disposed = true;
    if (_supported) _channel.setMethodCallHandler(null);
  }
}
