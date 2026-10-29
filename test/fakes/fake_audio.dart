import 'package:neatink/audio/audio_channel.dart';

/// A microphone and player that only remember what they were asked.
class FakeAudioBackend implements AudioBackend {
  bool permission = true;
  bool asked = false;
  Object? startError;
  final List<String> calls = [];
  RecorderState recorder = RecorderState.idle;
  double level = 0.4;

  // Player.
  int duration = 60000;
  int position = 0;
  bool playing = false;
  bool completed = false;
  double speed = 1;
  String? loaded;

  @override
  Future<bool> microphonePermission({bool ask = false}) async {
    if (ask) asked = true;
    return permission;
  }

  @override
  Future<void> startRecording(String path) async {
    calls.add('start $path');
    final e = startError;
    if (e != null) throw e;
    recorder = RecorderState.recording;
  }

  @override
  Future<void> pauseRecording() async {
    calls.add('pause');
    recorder = RecorderState.paused;
  }

  @override
  Future<void> resumeRecording() async {
    calls.add('resume');
    recorder = RecorderState.recording;
  }

  @override
  Future<void> stopRecording() async {
    calls.add('stop');
    recorder = RecorderState.idle;
  }

  @override
  Future<({RecorderState state, double level})> recorderStatus() async => (state: recorder, level: level);

  @override
  Future<int> load(String path) async {
    calls.add('load $path');
    loaded = path;
    position = 0;
    return duration;
  }

  @override
  Future<void> play() async {
    calls.add('play');
    playing = true;
    completed = false;
  }

  @override
  Future<void> pause() async {
    calls.add('pause player');
    playing = false;
  }

  @override
  Future<void> seek(int ms) async {
    calls.add('seek $ms');
    position = ms;
  }

  @override
  Future<void> setSpeed(double s) async => speed = s;

  @override
  Future<PlayerStatus> playerStatus() async =>
      (position: position, duration: duration, playing: playing, completed: completed);

  @override
  Future<void> release() async {
    calls.add('release');
    loaded = null;
    playing = false;
  }
}
