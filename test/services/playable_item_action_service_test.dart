import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:radio_mix/models/playable_item.dart';
import 'package:radio_mix/models/podcast.dart';
import 'package:radio_mix/models/podcast_episode.dart';
import 'package:radio_mix/models/radio_station.dart';
import 'package:radio_mix/services/audio_player_service.dart';
import 'package:radio_mix/services/playable_item_action_service.dart';
import 'package:radio_mix/services/playback_progress_service.dart';
import 'package:radio_mix/services/radio_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_doubles/fake_audio_player_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PlayableItemActionService', () {
    late PlaybackProgressService progressService;
    late List<FakeAudioPlayerEngine> engines;
    late AudioPlayerService audioService;
    late ProviderContainer container;

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

    test('play updates current playable and starts playback', () async {
      final actionService = container.read(playableItemActionServiceProvider);
      final item = PlayableItem.fromRadioStation(
        RadioStation(
          id: 'station-1',
          name: 'RadioMix FM',
          streamUrl: 'https://example.com/live.mp3',
        ),
      );

      await actionService.play(item);

      expect(container.read(currentPlayableProvider)?.id, item.id);
      expect(engines.last.lastSourceUri.toString(), item.source);
      expect(engines.last.playCalls, 1);
    });

    test('getSavedProgress returns stored podcast progress only for podcasts',
        () async {
      final actionService = container.read(playableItemActionServiceProvider);
      final podcastItem = PlayableItem.fromPodcastEpisode(
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
      final radioItem = PlayableItem.fromRadioStation(
        RadioStation(
          id: 'station-1',
          name: 'RadioMix FM',
          streamUrl: 'https://example.com/live.mp3',
        ),
      );
      await progressService.saveProgress(
        podcastItem.id,
        const Duration(seconds: 42),
        engines.last.durationValue,
      );

      final podcastProgress = await actionService.getSavedProgress(podcastItem);
      final radioProgress = await actionService.getSavedProgress(radioItem);

      expect(podcastProgress, isNotNull);
      expect(podcastProgress!.position, const Duration(seconds: 42));
      expect(radioProgress, isNull);
    });

    test('clearSavedProgress removes stored podcast progress', () async {
      final actionService = container.read(playableItemActionServiceProvider);
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
      await progressService.saveProgress(
        item.id,
        const Duration(minutes: 1),
        const Duration(minutes: 5),
      );

      await actionService.clearSavedProgress(item);

      expect(await progressService.getProgress(item.id), isNull);
    });

    test('addFavorite persists radio items only', () async {
      final actionService = container.read(playableItemActionServiceProvider);
      final radioItem = PlayableItem.fromRadioStation(
        RadioStation(
          id: 'station-1',
          name: 'RadioMix FM',
          streamUrl: 'https://example.com/live.mp3',
        ),
      );
      final podcastItem = PlayableItem.fromPodcastEpisode(
        episode: PodcastEpisode(
          id: 'ep-3',
          title: 'Episode 3',
          audioUrl: 'https://example.com/ep3.mp3',
        ),
        podcast: Podcast(
          id: 'pod-1',
          title: 'RadioMix Daily',
          artist: 'RadioMix',
        ),
        source: 'https://example.com/ep3.mp3',
      );

      await actionService.addFavorite(radioItem);
      await actionService.addFavorite(podcastItem);

      final favorites = await RadioService().getFavorites();

      expect(favorites.map((station) => station.id), contains('station-1'));
      expect(favorites.map((station) => station.id), isNot(contains('podcast_ep_ep-3')));
    });
  });
}
