import 'dart:async';

import 'package:just_audio/just_audio.dart';
import 'package:radio_mix/services/audio_player_engine.dart';

class FakeAudioPlayerEngine implements AudioPlayerEngine {
  final StreamController<PlayerState> _playerStateController =
      StreamController<PlayerState>.broadcast();
  final StreamController<Duration> _positionController =
      StreamController<Duration>.broadcast();
  final StreamController<Duration?> _durationController =
      StreamController<Duration?>.broadcast();

  Uri? lastSourceUri;
  Object? lastTag;
  int playCalls = 0;
  int stopCalls = 0;
  int disposeCalls = 0;
  Future<void> Function(FakeAudioPlayerEngine engine)? onPlay;
  bool _playing = false;
  double _volume = 1.0;
  Duration _position = Duration.zero;
  final Duration durationValue;
  ProcessingState _processingState = ProcessingState.idle;

  FakeAudioPlayerEngine({
    this.durationValue = const Duration(minutes: 5),
  });

  @override
  AudioPlayer? get rawPlayer => null;

  @override
  bool get playing => _playing;

  @override
  double get volume => _volume;

  @override
  Duration get position => _position;

  @override
  Duration? get duration => durationValue;

  @override
  ProcessingState get processingState => _processingState;

  @override
  PlayerState get playerState => PlayerState(_playing, _processingState);

  @override
  Stream<PlayerState> get playerStateStream => _playerStateController.stream;

  @override
  Stream<Duration> get positionStream => _positionController.stream;

  @override
  Stream<Duration?> get durationStream => _durationController.stream;

  @override
  Future<void> play() async {
    playCalls++;
    if (onPlay != null) {
      await onPlay!(this);
    }
    _playing = true;
    _processingState = ProcessingState.ready;
    _playerStateController.add(playerState);
  }

  @override
  Future<void> pause() async {
    _playing = false;
    _playerStateController.add(playerState);
  }

  @override
  Future<void> stop() async {
    stopCalls++;
    _playing = false;
    _processingState = ProcessingState.idle;
    _playerStateController.add(playerState);
  }

  @override
  Future<void> seek(Duration position) async {
    _position = position;
    _positionController.add(position);
  }

  void setProcessingState(ProcessingState state) {
    _processingState = state;
    _playerStateController.add(playerState);
  }

  @override
  Future<void> setVolume(double volume) async {
    _volume = volume;
  }

  @override
  Future<void> setSourceUri(Uri uri, {Object? tag}) async {
    lastSourceUri = uri;
    lastTag = tag;
    _processingState = ProcessingState.ready;
    _playerStateController.add(playerState);
    _durationController.add(durationValue);
  }

  @override
  Future<void> dispose() async {
    disposeCalls++;
    await _playerStateController.close();
    await _positionController.close();
    await _durationController.close();
  }
}
