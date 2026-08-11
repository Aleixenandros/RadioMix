import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';

class AppAudioHandler extends BaseAudioHandler {
  AppAudioHandler({AudioPlayer? player}) : _player = player ?? AudioPlayer() {
    _bindPlayerStreams();
  }

  static const restartActionName = 'restart_current_radio';
  static const Duration rewindStep = Duration(seconds: 10);
  static const Duration fastForwardStep = Duration(seconds: 30);
  static final MediaControl restartRadioControl = MediaControl.custom(
    androidIcon: 'drawable/baseline_restart_alt_24',
    label: 'Reiniciar',
    name: restartActionName,
  );
  static const MediaControl rewind10Control = MediaControl(
    androidIcon: 'drawable/baseline_replay_10_24',
    label: 'Atrasar 10s',
    action: MediaAction.rewind,
  );
  static const MediaControl forward30Control = MediaControl(
    androidIcon: 'drawable/baseline_forward_30_24',
    label: 'Avanzar 30s',
    action: MediaAction.fastForward,
  );

  AudioPlayer _player;
  StreamSubscription<PlaybackEvent>? _playbackEventSub;
  StreamSubscription<PlayerState>? _playerStateSub;
  StreamSubscription<Duration?>? _durationSub;
  StreamSubscription<int?>? _currentIndexSub;

  AudioPlayer get player => _player;

  void attachPlayer(AudioPlayer player) {
    if (identical(_player, player)) return;
    _cancelPlayerSubscriptions();
    _player = player;
    _bindPlayerStreams();
    _updateMediaItemFromPlayer();
    _broadcastPlaybackState();
  }

  void setMediaInfo(MediaItem item) {
    mediaItem.add(item);
    _broadcastPlaybackState();
  }

  bool get _isPodcast {
    final item = mediaItem.valueOrNull;
    if (item == null) return false;
    final extrasFlag = item.extras?['isPodcast'] == true;
    return extrasFlag || item.id.startsWith('podcast_');
  }

  bool get _isRadio {
    final item = mediaItem.valueOrNull;
    return item != null && !_isPodcast;
  }

  void _bindPlayerStreams() {
    _playbackEventSub = _player.playbackEventStream.listen((_) {
      _updateMediaItemFromPlayer();
      _broadcastPlaybackState();
    });
    _playerStateSub = _player.playerStateStream.listen((_) {
      _broadcastPlaybackState();
    });
    _durationSub = _player.durationStream.listen((duration) {
      final current = mediaItem.valueOrNull;
      if (current != null && current.duration != duration) {
        mediaItem.add(current.copyWith(duration: duration));
      }
      _broadcastPlaybackState();
    });
    _currentIndexSub = _player.currentIndexStream.listen((_) {
      _updateMediaItemFromPlayer();
      _broadcastPlaybackState();
    });
  }

  void _updateMediaItemFromPlayer() {
    final sequence = _player.sequence;
    final index = _player.currentIndex;
    if (index == null || index < 0 || index >= sequence.length) {
      return;
    }
    final source = sequence[index];
    final tag = source.tag;
    if (tag is MediaItem) {
      final duration = _player.duration;
      if (tag.duration != duration) {
        mediaItem.add(tag.copyWith(duration: duration));
      } else {
        mediaItem.add(tag);
      }
    }
  }

  List<MediaControl> _controlsForCurrentItem() {
    final playing = _player.playing;
    if (_isPodcast) {
      return [
        rewind10Control,
        playing ? MediaControl.pause : MediaControl.play,
        MediaControl.stop,
        forward30Control,
      ];
    }

    return [
      playing ? MediaControl.pause : MediaControl.play,
      restartRadioControl,
      MediaControl.stop,
    ];
  }

  Set<MediaAction> _systemActionsForCurrentItem() {
    if (_isPodcast) {
      return const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
      };
    }
    return const {};
  }

  List<int> _compactActionIndices(List<MediaControl> controls) {
    if (controls.length == 4) {
      return const [0, 1, 3];
    }
    if (controls.length == 3) {
      return const [0, 1, 2];
    }
    if (controls.isEmpty) return const [];
    return const [0];
  }

  void _broadcastPlaybackState() {
    final controls = _controlsForCurrentItem();
    final playerState = _player.playerState;

    playbackState.add(
      playbackState.value.copyWith(
        controls: controls,
        systemActions: _systemActionsForCurrentItem(),
        androidCompactActionIndices: _compactActionIndices(controls),
        processingState: switch (playerState.processingState) {
          ProcessingState.idle => AudioProcessingState.idle,
          ProcessingState.loading => AudioProcessingState.loading,
          ProcessingState.buffering => AudioProcessingState.buffering,
          ProcessingState.ready => AudioProcessingState.ready,
          ProcessingState.completed => AudioProcessingState.completed,
        },
        playing: playerState.playing,
        updatePosition: _player.position,
        bufferedPosition: _player.bufferedPosition,
        speed: _player.speed,
        queueIndex: _player.currentIndex,
      ),
    );
  }

  Future<void> _seekRelative(Duration offset) async {
    var target = _player.position + offset;
    if (target < Duration.zero) target = Duration.zero;
    final total = _player.duration;
    if (total != null && target > total) {
      target = total;
    }
    await _player.seek(target);
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> stop() async {
    await _player.stop();
    _broadcastPlaybackState();
    await super.stop();
  }

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> rewind() => _seekRelative(-rewindStep);

  @override
  Future<void> fastForward() => _seekRelative(fastForwardStep);

  @override
  Future<dynamic> customAction(
    String name, [
    Map<String, dynamic>? extras,
  ]) async {
    if (name == restartActionName && _isRadio) {
      await _restartCurrentRadio();
      return null;
    }
    return super.customAction(name, extras);
  }

  Future<void> _restartCurrentRadio() async {
    final item = mediaItem.valueOrNull;
    final source = item?.extras?['source']?.toString();
    if (item == null || source == null || source.trim().isEmpty) return;

    await _player.stop();
    await _player.setUrl(
      source,
      initialPosition: Duration.zero,
      tag: item,
    );
    await _player.play();
    _broadcastPlaybackState();
  }

  Future<void> disposeHandler() async {
    await _cancelPlayerSubscriptions();
    await _player.dispose();
  }

  Future<void> _cancelPlayerSubscriptions() async {
    await _playbackEventSub?.cancel();
    await _playerStateSub?.cancel();
    await _durationSub?.cancel();
    await _currentIndexSub?.cancel();
    _playbackEventSub = null;
    _playerStateSub = null;
    _durationSub = null;
    _currentIndexSub = null;
  }
}

late final AppAudioHandler appAudioHandler;
late final AudioHandler audioHandler;

Future<void> initAppAudioHandler() async {
  if (_audioHandlerInitialized) return;

  await AudioService.init(
    builder: () {
      appAudioHandler = AppAudioHandler();
      return appAudioHandler;
    },
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.example.radio_mix.audio',
      androidNotificationChannelName: 'Audio playback',
      androidNotificationIcon: 'mipmap/launcher_icon',
      androidNotificationOngoing: true,
      fastForwardInterval: AppAudioHandler.fastForwardStep,
      rewindInterval: AppAudioHandler.rewindStep,
    ),
  ).then((handler) {
    audioHandler = handler;
  });

  _audioHandlerInitialized = true;
}

bool _audioHandlerInitialized = false;

/// Indica si el handler global ya está listo.
bool get isAppAudioHandlerInitialized => _audioHandlerInitialized;

/// Adjunta el player al handler global solo cuando está inicializado.
void attachPlayerToAppAudioHandler(AudioPlayer player) {
  if (!_audioHandlerInitialized) return;
  appAudioHandler.attachPlayer(player);
}

/// Publica información multimedia solo cuando el handler global está listo.
void setAppAudioMediaInfo(MediaItem item) {
  if (!_audioHandlerInitialized) return;
  appAudioHandler.setMediaInfo(item);
}
