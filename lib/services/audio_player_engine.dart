import 'package:just_audio/just_audio.dart';

abstract class AudioPlayerEngine {
  AudioPlayer? get rawPlayer;
  bool get playing;
  double get volume;
  Duration get position;
  Duration? get duration;
  ProcessingState get processingState;
  PlayerState get playerState;
  Stream<PlayerState> get playerStateStream;
  Stream<Duration> get positionStream;
  Stream<Duration?> get durationStream;

  Future<void> play();
  Future<void> pause();
  Future<void> stop();
  Future<void> seek(Duration position);
  Future<void> setVolume(double volume);
  Future<void> setSourceUri(Uri uri, {Object? tag});
  Future<void> dispose();
}

class JustAudioPlayerEngine implements AudioPlayerEngine {
  JustAudioPlayerEngine({AudioLoadConfiguration? loadConfiguration})
      : _player = AudioPlayer(audioLoadConfiguration: loadConfiguration);

  final AudioPlayer _player;

  @override
  AudioPlayer get rawPlayer => _player;

  @override
  bool get playing => _player.playing;

  @override
  double get volume => _player.volume;

  @override
  Duration get position => _player.position;

  @override
  Duration? get duration => _player.duration;

  @override
  ProcessingState get processingState => _player.processingState;

  @override
  PlayerState get playerState => _player.playerState;

  @override
  Stream<PlayerState> get playerStateStream => _player.playerStateStream;

  @override
  Stream<Duration> get positionStream => _player.positionStream;

  @override
  Stream<Duration?> get durationStream => _player.durationStream;

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> stop() => _player.stop();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> setVolume(double volume) => _player.setVolume(volume);

  @override
  Future<void> setSourceUri(Uri uri, {Object? tag}) {
    return _player.setAudioSource(
      AudioSource.uri(uri, tag: tag),
    );
  }

  @override
  Future<void> dispose() => _player.dispose();
}
