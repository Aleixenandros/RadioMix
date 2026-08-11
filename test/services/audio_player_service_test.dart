import 'dart:convert';
import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:radio_mix/models/playable_item.dart';
import 'package:radio_mix/models/podcast.dart';
import 'package:radio_mix/models/podcast_episode.dart';
import 'package:radio_mix/models/radio_station.dart';
import 'package:radio_mix/services/audio_player_service.dart';
import 'package:radio_mix/services/playback_progress_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../test_doubles/fake_audio_player_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AudioPlayerService', () {
    late PlaybackProgressService progressService;
    late List<FakeAudioPlayerEngine> engines;

    AudioPlayerService buildService({
      Stream<AudioInterruptionEvent>? interruptionEvents,
      Future<bool> Function()? audioSessionActivator,
      List<Duration>? interruptionResumeDelays,
      Duration interruptionResumeProbeDelay = Duration.zero,
    }) {
      engines = [];
      return AudioPlayerService(
        playbackProgressService: progressService,
        engineFactory: ({loadConfiguration}) {
          final engine = FakeAudioPlayerEngine();
          engines.add(engine);
          return engine;
        },
        audioSessionInitializer: () async {},
        interruptionEvents: interruptionEvents,
        audioSessionActivator: audioSessionActivator,
        interruptionResumeDelays: interruptionResumeDelays,
        interruptionResumeProbeDelay: interruptionResumeProbeDelay,
      );
    }

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      progressService = PlaybackProgressService();
    });

    test('playItem loads source, starts playback and updates recents',
        () async {
      final service = buildService();
      final item = PlayableItem.fromRadioStation(
        RadioStation(
          id: 'station-1',
          name: 'RadioMix FM',
          streamUrl: 'https://example.com/live.mp3',
          country: 'ES',
        ),
      );

      await service.playItem(item);
      final recents = await service.recentPlayablesStream.first;

      expect(engines.last.lastSourceUri.toString(), item.source);
      expect(engines.last.playCalls, 1);
      expect(recents.single.id, item.id);
      expect(recents.single.kind, PlayableItemKind.radio);
      final mediaItem = engines.last.lastTag as MediaItem;
      expect(mediaItem.extras?['source'], item.source);
      service.dispose();
    });

    test('playItem uses app icon artwork fallback for radios without logo',
        () async {
      final service = buildService();
      final item = PlayableItem.fromRadioStation(
        RadioStation(
          id: 'station-no-logo',
          name: 'Radio sin logo',
          streamUrl: 'https://example.com/no-logo.mp3',
          country: 'ES',
        ),
      );

      await service.playItem(item);

      final tag = engines.last.lastTag;
      expect(tag, isA<MediaItem>());
      final mediaItem = tag as MediaItem;
      expect(mediaItem.artUri?.scheme, 'file');
      expect(File.fromUri(mediaItem.artUri!).existsSync(), isTrue);
      service.dispose();
    });

    test('playItem restarts the same radio when called again', () async {
      final service = buildService();
      final item = PlayableItem.fromRadioStation(
        RadioStation(
          id: 'station-restart',
          name: 'RadioMix Restart',
          streamUrl: 'https://example.com/restart.mp3',
          country: 'ES',
        ),
      );

      await service.playItem(item);
      await service.playItem(item);

      expect(engines.last.lastSourceUri.toString(), item.source);
      expect(engines.last.stopCalls, 2);
      expect(engines.last.playCalls, 2);
      service.dispose();
    });

    test('setBufferDuration recreates engine and resumes current item',
        () async {
      final service = buildService();
      final item = PlayableItem.fromRadioStation(
        RadioStation(
          id: 'station-1',
          name: 'RadioMix FM',
          streamUrl: 'https://example.com/live.mp3',
        ),
      );

      await service.playItem(item);
      final activeEngineBeforeBufferChange = engines.last;

      await service.setBufferDuration(10);

      expect(engines.length, 3);
      expect(activeEngineBeforeBufferChange.disposeCalls, 1);
      expect(engines.last.lastSourceUri.toString(), item.source);
      expect(engines.last.playCalls, 1);
      service.dispose();
    });

    test('recent playables read legacy stored radio payloads', () async {
      final station = RadioStation(
        id: 'station-1',
        name: 'RadioMix FM',
        streamUrl: 'https://example.com/live.mp3',
        country: 'ES',
      );
      SharedPreferences.setMockInitialValues({
        'recent_stations': [jsonEncode(station.toJson())],
      });
      final service = buildService();

      final recents = await service.recentPlayablesStream.first;

      expect(recents, hasLength(1));
      expect(recents.single.id, station.id);
      expect(recents.single.title, station.name);
      expect(recents.single.kind, PlayableItemKind.radio);
      service.dispose();
    });

    test('seek saves podcast progress immediately', () async {
      final service = buildService();
      final item = PlayableItem.fromPodcastEpisode(
        episode: PodcastEpisode(
          id: 'ep-1',
          title: 'Episode 1',
          audioUrl: 'https://example.com/ep1.mp3',
        ),
        podcast: Podcast(
          id: 'pod-1',
          title: 'RadioMix Daily',
          artist: 'RadioMix',
        ),
        source: 'https://example.com/ep1.mp3',
      );

      await service.playItem(item);
      await service.seek(const Duration(seconds: 42));
      final progress = await progressService.getProgress(item.id);

      expect(progress, isNotNull);
      expect(progress!.position, const Duration(seconds: 42));
      expect(progress.duration, const Duration(minutes: 5));
      service.dispose();
    });

    test('togglePlayPause saves podcast progress when pausing', () async {
      final service = buildService();
      final item = PlayableItem.fromPodcastEpisode(
        episode: PodcastEpisode(
          id: 'ep-2',
          title: 'Episode 2',
          audioUrl: 'https://example.com/ep2.mp3',
        ),
        podcast: Podcast(
          id: 'pod-1',
          title: 'RadioMix Daily',
          artist: 'RadioMix',
        ),
        source: 'https://example.com/ep2.mp3',
      );

      await service.playItem(item);
      await service.seek(const Duration(minutes: 1, seconds: 5));
      await service.togglePlayPause();
      final progress = await progressService.getProgress(item.id);

      expect(progress, isNotNull);
      expect(progress!.position, const Duration(minutes: 1, seconds: 5));
      expect(progress.duration, const Duration(minutes: 5));
      service.dispose();
    });

    test(
        'reanudacion tras llamada reactiva sesion y recarga podcast si queda idle',
        () async {
      final interruptions =
          StreamController<AudioInterruptionEvent>.broadcast();
      var activationCalls = 0;
      final service = buildService(
        interruptionEvents: interruptions.stream,
        audioSessionActivator: () async {
          activationCalls++;
          return true;
        },
        interruptionResumeDelays: const [Duration.zero],
      );
      final item = PlayableItem.fromPodcastEpisode(
        episode: PodcastEpisode(
          id: 'ep-call',
          title: 'Episode Call',
          audioUrl: 'https://example.com/call.mp3',
        ),
        podcast: Podcast(
          id: 'pod-1',
          title: 'RadioMix Daily',
          artist: 'RadioMix',
        ),
        source: 'https://example.com/call.mp3',
      );

      await service.playItem(item);
      await service.seek(const Duration(seconds: 42));

      interruptions.add(
        AudioInterruptionEvent(true, AudioInterruptionType.pause),
      );
      await pumpEventQueue();
      engines.last.setProcessingState(ProcessingState.idle);

      interruptions.add(
        AudioInterruptionEvent(false, AudioInterruptionType.pause),
      );
      await pumpEventQueue();
      await pumpEventQueue();

      expect(activationCalls, 1);
      expect(engines.last.lastSourceUri.toString(), item.source);
      expect(engines.last.playCalls, 2);
      expect(engines.last.position, const Duration(seconds: 42));

      await interruptions.close();
      service.dispose();
    });
  });
}
