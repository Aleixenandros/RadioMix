import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:radio_mix/models/playable_item.dart';
import 'package:radio_mix/models/podcast.dart';
import 'package:radio_mix/models/podcast_episode.dart';
import 'package:radio_mix/services/audio_player_service.dart';
import 'package:radio_mix/services/playback_coordinator_service.dart';
import 'package:radio_mix/services/playback_progress_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_doubles/fake_audio_player_engine.dart';

class FailingAudioPlayerEngine extends FakeAudioPlayerEngine {
  @override
  Future<void> setSourceUri(Uri uri, {Object? tag}) {
    throw Exception('fallo de prueba');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PlaybackCoordinatorService', () {
    late PlaybackProgressService progressService;
    late List<FakeAudioPlayerEngine> engines;
    late AudioPlayerService audioService;
    late ProviderContainer container;

    PlayableItem buildPodcastItem(String episodeId) {
      return PlayableItem.fromPodcastEpisode(
        episode: PodcastEpisode(
          id: episodeId,
          title: 'Episode $episodeId',
          audioUrl: 'https://example.com/$episodeId.mp3',
        ),
        podcast: Podcast(
          id: 'pod-1',
          title: 'RadioMix Daily',
          artist: 'RadioMix',
        ),
        source: 'https://example.com/$episodeId.mp3',
      );
    }

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      progressService = PlaybackProgressService();
      engines = [];
      audioService = AudioPlayerService(
        playbackProgressService: progressService,
        engineFactory: ({loadConfiguration}) {
          final engine = FakeAudioPlayerEngine();
          engines.add(engine);
          return engine;
        },
        audioSessionInitializer: () async {},
      );
      container = ProviderContainer(
        overrides: [
          audioPlayerServiceProvider.overrideWithValue(audioService),
          playbackProgressServiceProvider.overrideWithValue(progressService),
        ],
      );
    });

    tearDown(() {
      container.dispose();
      audioService.dispose();
    });

    test('automatic resume uses saved podcast progress', () async {
      final coordinator = container.read(playbackCoordinatorServiceProvider);
      final item = buildPodcastItem('ep-1');
      await progressService.saveProgress(
        item.id,
        const Duration(seconds: 42),
        const Duration(minutes: 5),
      );

      final result = await coordinator.playItem(item);

      expect(result.didStart, isTrue);
      expect(result.resumedFrom, const Duration(seconds: 42));
      expect(result.feedbackMessage, contains('Continuando'));
      expect(engines.last.position, const Duration(seconds: 42));
    });

    test('none resume clears saved progress and starts from beginning',
        () async {
      final coordinator = container.read(playbackCoordinatorServiceProvider);
      final item = buildPodcastItem('ep-2');
      await progressService.saveProgress(
        item.id,
        const Duration(minutes: 1),
        const Duration(minutes: 5),
      );

      final result = await coordinator.playItem(
        item,
        podcastResumeBehavior: PodcastResumeBehavior.none,
      );

      expect(result.didStart, isTrue);
      expect(result.resumedFrom, isNull);
      expect(result.feedbackMessage, 'Reproduciendo: ${item.title}');
      expect(await progressService.getProgress(item.id), isNull);
      expect(engines.last.position, Duration.zero);
    });

    test('ask resume can restart from beginning and clear progress', () async {
      final coordinator = container.read(playbackCoordinatorServiceProvider);
      final item = buildPodcastItem('ep-3');
      await progressService.saveProgress(
        item.id,
        const Duration(seconds: 30),
        const Duration(minutes: 5),
      );

      final result = await coordinator.playItem(
        item,
        podcastResumeBehavior: PodcastResumeBehavior.ask,
        onRequestResume: (_) async => false,
      );

      expect(result.didStart, isTrue);
      expect(result.resumedFrom, isNull);
      expect(await progressService.getProgress(item.id), isNull);
    });

    test('returns error result when playback fails', () async {
      final failingService = AudioPlayerService(
        playbackProgressService: progressService,
        engineFactory: ({loadConfiguration}) => FailingAudioPlayerEngine(),
        audioSessionInitializer: () async {},
      );
      final failingContainer = ProviderContainer(
        overrides: [
          audioPlayerServiceProvider.overrideWithValue(failingService),
          playbackProgressServiceProvider.overrideWithValue(progressService),
        ],
      );
      final coordinator =
          failingContainer.read(playbackCoordinatorServiceProvider);
      final item = buildPodcastItem('ep-4');

      final result = await coordinator.playItem(item);

      expect(result.didStart, isFalse);
      expect(result.errorMessage, contains('Error al reproducir'));

      failingContainer.dispose();
      failingService.dispose();
    });
  });
}
