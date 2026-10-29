import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// What the microphone recorder is doing.
enum RecorderState { idle, recording, paused }

/// Where the player is.
typedef PlayerStatus = ({int position, int duration, bool playing, bool completed});

/// Recording and playing lecture recordings (v1.12.0). The Android side is
/// `AudioPlugin.kt` (+ `RecordingService.kt`); tests use a fake.
abstract interface class AudioBackend {
  /// Whether the microphone may be used; with [ask], asks the user first
  /// when it may not.
  Future<bool> microphonePermission({bool ask = false});

  Future<void> startRecording(String path);
  Future<void> pauseRecording();
  Future<void> resumeRecording();
  Future<void> stopRecording();

  /// The recorder's state and how loud the microphone is (0..1).
  Future<({RecorderState state, double level})> recorderStatus();

  /// Opens [path] for playing; returns its length in ms.
  Future<int> load(String path);
  Future<void> play();
  Future<void> pause();
  Future<void> seek(int ms);
  Future<void> setSpeed(double speed);
  Future<PlayerStatus> playerStatus();

  /// Closes the player.
  Future<void> release();
}

/// `MethodChannel("neatink/audio")`.
class MethodChannelAudioBackend implements AudioBackend {
  const MethodChannelAudioBackend();

  static const MethodChannel _channel = MethodChannel('neatink/audio');

  @override
  Future<bool> microphonePermission({bool ask = false}) async =>
      await _channel.invokeMethod<bool>('permission', {'ask': ask}) ?? false;

  @override
  Future<void> startRecording(String path) => _channel.invokeMethod<void>('startRecording', {'path': path});

  @override
  Future<void> pauseRecording() => _channel.invokeMethod<void>('pauseRecording');

  @override
  Future<void> resumeRecording() => _channel.invokeMethod<void>('resumeRecording');

  @override
  Future<void> stopRecording() => _channel.invokeMethod<void>('stopRecording');

  @override
  Future<({RecorderState state, double level})> recorderStatus() async {
    final m = await _channel.invokeMapMethod<String, Object?>('recorderStatus') ?? const {};
    final state = switch (m['state']) {
      'recording' => RecorderState.recording,
      'paused' => RecorderState.paused,
      _ => RecorderState.idle,
    };
    return (state: state, level: (m['level'] as num?)?.toDouble() ?? 0);
  }

  @override
  Future<int> load(String path) async => await _channel.invokeMethod<int>('load', {'path': path}) ?? 0;

  @override
  Future<void> play() => _channel.invokeMethod<void>('play');

  @override
  Future<void> pause() => _channel.invokeMethod<void>('pause');

  @override
  Future<void> seek(int ms) => _channel.invokeMethod<void>('seek', {'ms': ms});

  @override
  Future<void> setSpeed(double speed) => _channel.invokeMethod<void>('speed', {'speed': speed});

  @override
  Future<PlayerStatus> playerStatus() async {
    final m = await _channel.invokeMapMethod<String, Object?>('playerStatus') ?? const {};
    return (
      position: (m['position'] as num?)?.toInt() ?? 0,
      duration: (m['duration'] as num?)?.toInt() ?? 0,
      playing: m['playing'] == true,
      completed: m['completed'] == true,
    );
  }

  @override
  Future<void> release() => _channel.invokeMethod<void>('release');
}

/// The app's audio. Tests override it.
final audioBackendProvider = Provider<AudioBackend>((ref) => const MethodChannelAudioBackend());
