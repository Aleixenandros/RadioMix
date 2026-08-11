import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/playable_item.dart';
import '../models/radio_station.dart';
import 'app_http_client.dart';
import 'app_audio_handler.dart';
import 'app_audio_error.dart';
import 'app_logger.dart';
import 'app_preferences.dart';
import 'audio_player_engine.dart';
import 'playback_progress_service.dart';

final audioPlayerServiceProvider = Provider<AudioPlayerService>((ref) {
  final service = AudioPlayerService(
    httpClient: ref.read(httpClientProvider),
    playbackProgressService: ref.read(playbackProgressServiceProvider),
    preferencesFactory: sharedPreferencesFactory(ref),
  );
  ref.onDispose(() => service.dispose());
  return service;
});

class CurrentPlayableNotifier extends Notifier<PlayableItem?> {
  @override
  PlayableItem? build() => null;

  void setItem(PlayableItem? item) {
    state = item;
  }
}

final currentPlayableProvider =
    NotifierProvider<CurrentPlayableNotifier, PlayableItem?>(
  CurrentPlayableNotifier.new,
);

final isPlayingProvider = Provider<bool>((ref) {
  final playerState = ref.watch(playerStateProvider).maybeWhen(
        data: (value) => value,
        orElse: () => null,
      );
  return playerState?.playing ??
      ref.watch(audioPlayerServiceProvider).isPlaying;
});

final playerStateProvider = StreamProvider<PlayerState>((ref) {
  final service = ref.watch(audioPlayerServiceProvider);
  return service.playerStateStream;
});

final processingStateProvider = StreamProvider<ProcessingState>((ref) {
  final service = ref.watch(audioPlayerServiceProvider);
  return service.processingStateStream;
});

final recentPlayablesProvider = StreamProvider<List<PlayableItem>>((ref) {
  final service = ref.watch(audioPlayerServiceProvider);
  return service.recentPlayablesStream;
});

class AudioPlayerService {
  static const _appIconAsset = 'assets/icon/icon.png';
  static Future<Uri?>? _cachedAppIconArtworkUri;

  AudioPlayerService({
    required PlaybackProgressService playbackProgressService,
    http.Client? httpClient,
    AudioPlayerEngineFactory? engineFactory,
    SharedPreferencesFactory? preferencesFactory,
    Future<void> Function()? audioSessionInitializer,
    Future<bool> Function()? audioSessionActivator,
    Stream<AudioInterruptionEvent>? interruptionEvents,
    Stream<AudioDevicesChangedEvent>? devicesChangedEvents,
    List<Duration>? interruptionResumeDelays,
    Duration interruptionResumeProbeDelay = const Duration(milliseconds: 250),
  })  : _playbackProgressService = playbackProgressService,
        _httpClient = httpClient ?? http.Client(),
        _engineFactory = engineFactory ?? _defaultEngineFactory,
        _preferencesFactory =
            preferencesFactory ?? SharedPreferences.getInstance,
        _audioSessionInitializer = audioSessionInitializer,
        _audioSessionActivator = audioSessionActivator,
        _interruptionEvents = interruptionEvents,
        _devicesChangedEvents = devicesChangedEvents,
        _interruptionResumeDelays = List.unmodifiable(
          interruptionResumeDelays ??
              const [
                Duration(milliseconds: 250),
                Duration(milliseconds: 750),
                Duration(milliseconds: 1500),
              ],
        ),
        _interruptionResumeProbeDelay = interruptionResumeProbeDelay,
        player = (engineFactory ?? _defaultEngineFactory)() {
    final rawPlayer = player.rawPlayer;
    if (rawPlayer != null) {
      attachPlayerToAppAudioHandler(rawPlayer);
    }
    _bindPlayerStreams(player);
    _publishPlayerSnapshots();
    _init();
  }

  static AudioPlayerEngine _defaultEngineFactory({
    AudioLoadConfiguration? loadConfiguration,
  }) {
    return JustAudioPlayerEngine(loadConfiguration: loadConfiguration);
  }

  AudioPlayerEngine player;
  final PlaybackProgressService _playbackProgressService;
  final http.Client _httpClient;
  final AudioPlayerEngineFactory _engineFactory;
  final SharedPreferencesFactory _preferencesFactory;
  final Future<void> Function()? _audioSessionInitializer;
  final Future<bool> Function()? _audioSessionActivator;
  final Stream<AudioInterruptionEvent>? _interruptionEvents;
  final Stream<AudioDevicesChangedEvent>? _devicesChangedEvents;
  final List<Duration> _interruptionResumeDelays;
  final Duration _interruptionResumeProbeDelay;

  StreamSubscription<AudioInterruptionEvent>? _interruptionSub;
  StreamSubscription<AudioDevicesChangedEvent>? _devicesChangedSub;
  StreamSubscription<PlayerState>? _playerStateSub;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration?>? _durationSub;

  bool _wasPlayingBeforeInterruption = false;
  double? _volumeBeforeDuck;
  int _interruptionGeneration = 0;
  PlayableItem? _interruptedItem;
  Duration? _interruptedPosition;
  Duration _bufferDuration = const Duration(seconds: 2);
  PlayableItem? _currentItem;

  static const int _maxRecent = 10;

  List<PlayableItem> _recentItems = [];
  final _recentController = StreamController<List<PlayableItem>>.broadcast();
  final _playerStateController = StreamController<PlayerState>.broadcast();
  final _processingStateController =
      StreamController<ProcessingState>.broadcast();
  final _positionController = StreamController<Duration>.broadcast();
  final _durationController = StreamController<Duration?>.broadcast();

  final Completer<void> _readyCompleter = Completer<void>();
  bool _disposed = false;

  Stream<List<PlayableItem>> get recentPlayablesStream async* {
    await ready;
    await _loadRecentItems();
    yield _recentItems;
    yield* _recentController.stream;
  }

  Stream<PlayerState> get playerStateStream => _playerStateController.stream;

  Stream<ProcessingState> get processingStateStream =>
      _processingStateController.stream;

  Stream<Duration> get positionStream => _positionController.stream;

  Stream<Duration?> get durationStream => _durationController.stream;

  Future<void> get ready => _readyCompleter.future;

  bool get isReady => _readyCompleter.isCompleted;

  bool get isPlaying => player.playing;

  ProcessingState get processingState => player.processingState;

  double get volume => player.volume;

  Duration? get duration => player.duration;

  Duration get position => player.position;

  Future<SharedPreferences> _prefs() => _preferencesFactory();

  Future<void> _init() async {
    try {
      await _loadBufferPreference();
      await _replacePlayer(_createPlayerWithBuffer());
      await _initAudioSession();
      if (!_readyCompleter.isCompleted) {
        _readyCompleter.complete();
      }
    } catch (error, stackTrace) {
      if (!_readyCompleter.isCompleted) {
        _readyCompleter.completeError(error, stackTrace);
      }
      rethrow;
    }
  }

  Duration get bufferDuration => _bufferDuration;

  int get bufferSeconds => _bufferDuration.inSeconds;

  Future<void> _loadBufferPreference() async {
    final prefs = await _prefs();
    final seconds = prefs.getInt(AppPreferenceKeys.audioBufferSeconds) ?? 2;
    _bufferDuration = Duration(seconds: seconds);
  }

  Future<void> setBufferDuration(int seconds) async {
    await ready;
    AppLogger.info(
      'audio',
      'Actualizando buffer de audio',
      data: {'seconds': seconds},
    );
    _bufferDuration = Duration(seconds: seconds);
    final prefs = await _prefs();
    await prefs.setInt(AppPreferenceKeys.audioBufferSeconds, seconds);

    if (_currentItem != null) {
      final wasPlaying = player.playing;
      await _replacePlayer(_createPlayerWithBuffer());
      if (wasPlaying) {
        await playItem(_currentItem!);
      }
    }
  }

  Future<void> _replacePlayer(AudioPlayerEngine newPlayer) async {
    final previousPlayer = player;
    await _cancelPlayerBindings();
    player = newPlayer;
    final rawPlayer = player.rawPlayer;
    if (rawPlayer != null) {
      attachPlayerToAppAudioHandler(rawPlayer);
    }
    _bindPlayerStreams(player);
    _publishPlayerSnapshots();
    await previousPlayer.dispose();
  }

  AudioPlayerEngine _createPlayerWithBuffer() {
    return _engineFactory(
      loadConfiguration: AudioLoadConfiguration(
        androidLoadControl: AndroidLoadControl(
          minBufferDuration: _bufferDuration,
          maxBufferDuration: _bufferDuration * 3,
          bufferForPlaybackDuration: _bufferDuration,
          bufferForPlaybackAfterRebufferDuration: _bufferDuration,
        ),
        darwinLoadControl: DarwinLoadControl(
          preferredForwardBufferDuration: _bufferDuration,
        ),
      ),
    );
  }

  Future<void> _initAudioSession() async {
    AudioSession? session;
    if (_audioSessionInitializer != null) {
      await _audioSessionInitializer!();
    } else {
      session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration(
        avAudioSessionCategory: AVAudioSessionCategory.playback,
        avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.none,
        avAudioSessionMode: AVAudioSessionMode.defaultMode,
        avAudioSessionRouteSharingPolicy:
            AVAudioSessionRouteSharingPolicy.defaultPolicy,
        avAudioSessionSetActiveOptions: AVAudioSessionSetActiveOptions.none,
        androidAudioAttributes: AndroidAudioAttributes(
          contentType: AndroidAudioContentType.music,
          usage: AndroidAudioUsage.media,
        ),
        androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
        androidWillPauseWhenDucked: false,
      ));
    }

    final interruptionEvents =
        _interruptionEvents ?? session?.interruptionEventStream;
    final devicesChangedEvents =
        _devicesChangedEvents ?? session?.devicesChangedEventStream;

    _interruptionSub = interruptionEvents?.listen((event) async {
      if (event.begin) {
        switch (event.type) {
          case AudioInterruptionType.duck:
            _volumeBeforeDuck ??= player.volume;
            await player.setVolume(_volumeBeforeDuck! * 0.3);
            break;
          case AudioInterruptionType.pause:
          case AudioInterruptionType.unknown:
            _cancelPendingInterruptionResume();
            _wasPlayingBeforeInterruption = player.playing;
            _interruptedItem = _currentItem;
            _interruptedPosition = player.position;
            if (player.playing) {
              await player.pause();
            }
            break;
        }
      } else {
        switch (event.type) {
          case AudioInterruptionType.duck:
            final restoredVolume = _volumeBeforeDuck ?? 1.0;
            _volumeBeforeDuck = null;
            await player.setVolume(restoredVolume);
            break;
          case AudioInterruptionType.pause:
          case AudioInterruptionType.unknown:
            if (_wasPlayingBeforeInterruption) {
              unawaited(
                _resumeAfterInterruption(_interruptionGeneration),
              );
            }
            break;
        }
      }
    });

    _devicesChangedSub = devicesChangedEvents?.listen((event) async {
      if (event.devicesRemoved.isNotEmpty && player.playing) {
        await player.pause();
      }
    });
  }

  Future<void> playStation(
    RadioStation station, {
    Duration? startPosition,
  }) async {
    await playItem(
      PlayableItem.fromRadioStation(station),
      startPosition: startPosition,
    );
  }

  Future<void> playItem(
    PlayableItem item, {
    Duration? startPosition,
  }) async {
    await ready;
    _clearInterruptionState();
    final previousItem = _currentItem;
    if (previousItem != null && previousItem.id != item.id) {
      await _saveProgressForItem(previousItem);
    }
    _currentItem = item;
    AppLogger.info(
      'audio',
      'Iniciando reproducción',
      data: {
        'itemId': item.id,
        'kind': item.kind.name,
        'source': item.source,
        'startPositionMs': startPosition?.inMilliseconds,
      },
    );

    try {
      await _addToRecent(item);
      final sourceUri = await _resolveStreamUri(item.source);
      final artworkUri = await _resolveArtworkUri(item);
      final mediaItem = MediaItem(
        id: item.id,
        title: item.title,
        artist: item.subtitle ?? 'Radio Mix',
        artUri: artworkUri,
        extras: {
          'isPodcast': item.isPodcast,
          'source': sourceUri.toString(),
        },
      );

      setAppAudioMediaInfo(mediaItem);

      await player.stop();
      await player.setSourceUri(sourceUri, tag: mediaItem);

      if (startPosition != null && startPosition > Duration.zero) {
        await player.seek(startPosition);
      }

      await player.play();
      if (item.isPodcast) {
        _startProgressTracking(item);
      } else {
        _stopProgressTracking();
      }
      AppLogger.info(
        'audio',
        'Reproducción iniciada',
        data: {'itemId': item.id, 'resolvedSource': sourceUri.toString()},
      );
    } catch (error, stackTrace) {
      if (error.toString().contains('abort') ||
          error.toString().contains('interrupted')) {
        AppLogger.warning(
          'audio',
          'Reproducción interrumpida por el motor',
          error: error,
          data: {'itemId': item.id},
        );
        return;
      }
      AppLogger.error(
        'audio',
        'Fallo al iniciar reproducción',
        error: error,
        stackTrace: stackTrace,
        data: {'itemId': item.id, 'source': item.source},
      );
      throw AppAudioException.fromError(error, source: item.source);
    }
  }

  Future<Uri?> _resolveArtworkUri(PlayableItem item) async {
    final artworkUri = _resolveOptionalUri(item.artworkUrl);
    if (artworkUri != null) return artworkUri;
    if (!item.isRadio) return null;

    return _cachedAppIconArtworkUri ??= _copyAppIconArtworkToTempFile();
  }

  Future<Uri?> _copyAppIconArtworkToTempFile() async {
    try {
      final data = await rootBundle.load(_appIconAsset);
      final file = File('${Directory.systemTemp.path}/radio_mix_app_icon.png');
      await file.writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        flush: true,
      );
      return file.uri;
    } catch (error, stackTrace) {
      AppLogger.warning(
        'audio',
        'No se pudo preparar el artwork local de fallback',
        error: error,
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  Future<Uri> _resolveStreamUri(String value) async {
    final trimmed = value.trim();
    final parsed = Uri.tryParse(trimmed);

    if (parsed == null) {
      throw const FormatException('URL/archivo de audio no válido');
    }

    if (!parsed.hasScheme && trimmed.startsWith('/')) {
      final file = File(trimmed);
      if (!await file.exists()) {
        throw FileSystemException('Archivo de audio no encontrado', trimmed);
      }
      return Uri.file(file.path);
    }

    if (parsed.scheme == 'file') {
      final file = File.fromUri(parsed);
      if (!await file.exists()) {
        throw FileSystemException('Archivo de audio no encontrado', file.path);
      }
    }

    // Resolver archivos PLS (ej: streams de SHOUTcast)
    if (parsed.path.endsWith('.pls')) {
      return await _resolvePlsUri(parsed) ?? parsed;
    }

    return parsed;
  }

  Future<Uri?> _resolvePlsUri(Uri plsUri) async {
    try {
      final response = await appGet(
        _httpClient,
        plsUri,
        timeout: const Duration(seconds: 10),
      );
      for (final line in response.body.split('\n')) {
        final trimmed = line.trim();
        if (trimmed.toLowerCase().startsWith('file1=')) {
          final streamUrl = trimmed.substring(6).trim();
          final resolved = Uri.tryParse(streamUrl);
          if (resolved != null) {
            AppLogger.info(
              'audio',
              'PLS resuelto a stream final',
              data: {'plsUri': plsUri, 'streamUri': resolved},
            );
          }
          return resolved;
        }
      }
    } catch (error, stackTrace) {
      AppLogger.warning(
        'audio',
        'No se pudo resolver PLS; se mantiene la URL original',
        error: error,
        stackTrace: stackTrace,
        data: {'plsUri': plsUri},
      );
    }
    return null;
  }

  Uri? _resolveOptionalUri(String? value) {
    if (value == null) return null;
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;

    final parsed = Uri.tryParse(trimmed);
    if (parsed == null) return null;
    if (!parsed.hasScheme && trimmed.startsWith('/')) {
      return Uri.file(trimmed);
    }

    return parsed;
  }

  Timer? _progressTimer;
  PlayableItem? _progressItem;

  Future<void> _saveProgressForItem(PlayableItem? item) async {
    if (item == null || !item.isPodcast) return;
    final totalDuration = player.duration;
    if (totalDuration == null || totalDuration <= Duration.zero) return;

    await _playbackProgressService.saveProgress(
      item.id,
      player.position,
      totalDuration,
    );
  }

  void _startProgressTracking(PlayableItem item) {
    _progressTimer?.cancel();
    _progressItem = item;
    _progressTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      if (player.playing) {
        await _saveProgressForItem(item);
      }
    });
  }

  void _stopProgressTracking() {
    _progressTimer?.cancel();
    _progressTimer = null;
    _progressItem = null;
  }

  Future<Duration?> getSavedProgress(String itemId) async {
    await ready;
    final progress = await _playbackProgressService.getProgress(itemId);
    return progress?.position;
  }

  Future<void> _loadRecentItems() async {
    if (_recentItems.isNotEmpty) return;
    final prefs = await _prefs();
    final jsonList =
        prefs.getStringList(AppPreferenceKeys.recentStations) ?? [];
    _recentItems = jsonList
        .map((value) => jsonDecode(value) as Map<String, dynamic>)
        .map(PlayableItem.fromJson)
        .toList();
  }

  Future<void> _addToRecent(PlayableItem item) async {
    _recentItems.removeWhere((recent) => recent.id == item.id);
    _recentItems.insert(0, item);
    if (_recentItems.length > _maxRecent) {
      _recentItems = _recentItems.sublist(0, _maxRecent);
    }
    _recentController.add(List.unmodifiable(_recentItems));
    await _persistRecentItems();
  }

  Future<void> removeFromRecent(String itemId) async {
    _recentItems.removeWhere((item) => item.id == itemId);
    _recentController.add(List.unmodifiable(_recentItems));
    await _persistRecentItems();
  }

  Future<void> _persistRecentItems() async {
    final prefs = await _prefs();
    await prefs.setStringList(
      AppPreferenceKeys.recentStations,
      _recentItems.map((item) => jsonEncode(item.toJson())).toList(),
    );
  }

  Future<void> togglePlayPause() async {
    await ready;
    _cancelPendingInterruptionResume();
    if (player.playing) {
      _wasPlayingBeforeInterruption = false;
      await player.pause();
      await _saveProgressForItem(_currentItem);
    } else {
      _clearInterruptionState();
      await player.play();
    }
  }

  Future<void> stop() async {
    await ready;
    _clearInterruptionState();
    AppLogger.info(
      'audio',
      'Deteniendo reproducción',
      data: {'itemId': _currentItem?.id},
    );
    await _saveProgressForItem(_currentItem ?? _progressItem);
    _stopProgressTracking();
    await player.stop();
  }

  Future<void> setVolume(double volume) async {
    await ready;
    await player.setVolume(volume);
  }

  Future<void> seek(Duration position) async {
    await ready;
    await player.seek(position);
    await _saveProgressForItem(_currentItem ?? _progressItem);
  }

  Future<void> _resumeAfterInterruption(int expectedGeneration) async {
    final item = _interruptedItem;
    final interruptedPosition = _interruptedPosition;
    if (!_wasPlayingBeforeInterruption || item == null) return;

    for (var attempt = 0;
        attempt < _interruptionResumeDelays.length;
        attempt++) {
      final delay = _interruptionResumeDelays[attempt];
      if (delay > Duration.zero) {
        await Future.delayed(delay);
      }
      if (!_canResumeInterruptedPlayback(expectedGeneration, item)) {
        return;
      }

      try {
        final activated = await _activateAudioSession();
        AppLogger.info(
          'audio',
          'Intentando reanudar tras interrupción',
          data: {
            'attempt': attempt + 1,
            'itemId': item.id,
            'kind': item.kind.name,
            'processingState': player.processingState.name,
            'sessionActivated': activated,
          },
        );

        final shouldReloadSource =
            player.processingState == ProcessingState.idle ||
                player.processingState == ProcessingState.completed;

        if (shouldReloadSource) {
          await playItem(
            item,
            startPosition: item.isPodcast ? interruptedPosition : null,
          );
        } else {
          if (item.isPodcast &&
              interruptedPosition != null &&
              interruptedPosition > Duration.zero &&
              player.position.inMilliseconds <= 0) {
            await player.seek(interruptedPosition);
          }
          await player.play();
        }

        if (_interruptionResumeProbeDelay > Duration.zero) {
          await Future.delayed(_interruptionResumeProbeDelay);
        }

        if (player.playing) {
          AppLogger.info(
            'audio',
            'Reanudación tras interrupción completada',
            data: {'attempt': attempt + 1, 'itemId': item.id},
          );
          _clearInterruptionState();
          return;
        }
      } catch (error, stackTrace) {
        AppLogger.warning(
          'audio',
          'Fallo al reanudar tras interrupción',
          error: error,
          stackTrace: stackTrace,
          data: {
            'attempt': attempt + 1,
            'itemId': item.id,
          },
        );
      }
    }

    AppLogger.warning(
      'audio',
      'No se pudo reanudar automáticamente tras la interrupción',
      data: {'itemId': item.id},
    );
    _wasPlayingBeforeInterruption = false;
  }

  bool _canResumeInterruptedPlayback(
      int expectedGeneration, PlayableItem item) {
    if (_disposed) return false;
    if (!_wasPlayingBeforeInterruption) return false;
    if (expectedGeneration != _interruptionGeneration) return false;
    return _currentItem?.id == item.id;
  }

  Future<bool> _activateAudioSession() async {
    if (_audioSessionActivator != null) {
      return _audioSessionActivator!();
    }

    try {
      final session = await AudioSession.instance;
      return await session.setActive(true);
    } catch (error, stackTrace) {
      AppLogger.warning(
        'audio',
        'No se pudo reactivar la sesión de audio',
        error: error,
        stackTrace: stackTrace,
      );
      return false;
    }
  }

  void _cancelPendingInterruptionResume() {
    _interruptionGeneration++;
  }

  void _clearInterruptionState() {
    _cancelPendingInterruptionResume();
    _wasPlayingBeforeInterruption = false;
    _interruptedItem = null;
    _interruptedPosition = null;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _stopProgressTracking();
    _clearInterruptionState();
    _interruptionSub?.cancel();
    _devicesChangedSub?.cancel();
    _cancelPlayerBindings();
    _recentController.close();
    _playerStateController.close();
    _processingStateController.close();
    _positionController.close();
    _durationController.close();
    _httpClient.close();
    player.dispose();
  }

  void _bindPlayerStreams(AudioPlayerEngine targetPlayer) {
    _playerStateSub = targetPlayer.playerStateStream.listen((state) {
      if (_disposed) return;
      _playerStateController.add(state);
      _processingStateController.add(state.processingState);
    });
    _positionSub = targetPlayer.positionStream.listen((position) {
      if (_disposed) return;
      _positionController.add(position);
    });
    _durationSub = targetPlayer.durationStream.listen((duration) {
      if (_disposed) return;
      _durationController.add(duration);
    });
  }

  Future<void> _cancelPlayerBindings() async {
    await _playerStateSub?.cancel();
    await _positionSub?.cancel();
    await _durationSub?.cancel();
    _playerStateSub = null;
    _positionSub = null;
    _durationSub = null;
  }

  void _publishPlayerSnapshots() {
    if (_disposed) return;
    _playerStateController.add(player.playerState);
    _processingStateController.add(player.processingState);
    _positionController.add(player.position);
    _durationController.add(player.duration);
  }
}

typedef AudioPlayerEngineFactory = AudioPlayerEngine Function({
  AudioLoadConfiguration? loadConfiguration,
});
