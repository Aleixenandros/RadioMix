import 'package:flutter_test/flutter_test.dart';
import 'package:radio_mix/models/playable_item.dart';
import 'package:radio_mix/models/podcast.dart';
import 'package:radio_mix/models/podcast_episode.dart';
import 'package:radio_mix/models/radio_station.dart';

void main() {
  group('PlayableItem', () {
    test('fromRadioStation preserves radio semantics', () {
      final station = RadioStation(
        id: 'station-1',
        name: 'RadioMix FM',
        streamUrl: 'https://example.com/live.mp3',
        favicon: 'https://example.com/logo.png',
        country: 'Spain',
        tags: const ['rock'],
      );

      final item = PlayableItem.fromRadioStation(station);

      expect(item.kind, PlayableItemKind.radio);
      expect(item.isRadio, isTrue);
      expect(item.isPodcast, isFalse);
      expect(item.source, station.streamUrl);
      expect(item.subtitle, station.country);
    });

    test('fromPodcastEpisode preserves podcast semantics', () {
      final podcast = Podcast(
        id: 'pod-1',
        title: 'RadioMix Daily',
        artist: 'RadioMix',
        artworkUrl: 'https://example.com/podcast.png',
      );
      final episode = PodcastEpisode(
        id: 'ep-1',
        title: 'Episode 1',
        audioUrl: 'https://example.com/ep1.mp3',
        artworkUrl: 'https://example.com/ep1.png',
      );

      final item = PlayableItem.fromPodcastEpisode(
        episode: episode,
        podcast: podcast,
        source: episode.audioUrl,
      );

      expect(item.kind, PlayableItemKind.podcast);
      expect(item.isPodcast, isTrue);
      expect(item.id, 'podcast_ep_ep-1');
      expect(item.subtitle, podcast.title);
      expect(item.tags, contains('Podcast'));
    });

    test('toJson and fromJson preserve playable fields', () {
      final item = PlayableItem(
        id: 'podcast_ep_ep-1',
        title: 'Episode 1',
        source: 'https://example.com/ep1.mp3',
        artworkUrl: 'https://example.com/ep1.png',
        subtitle: 'RadioMix Daily',
        tags: const ['Podcast', 'Daily'],
        kind: PlayableItemKind.podcast,
      );

      final restored = PlayableItem.fromJson(item.toJson());

      expect(restored.id, item.id);
      expect(restored.title, item.title);
      expect(restored.source, item.source);
      expect(restored.artworkUrl, item.artworkUrl);
      expect(restored.subtitle, item.subtitle);
      expect(restored.tags, item.tags);
      expect(restored.kind, item.kind);
    });

    test('fromJson supports legacy radio station payloads', () {
      final station = RadioStation(
        id: 'station-1',
        name: 'RadioMix FM',
        streamUrl: 'https://example.com/live.mp3',
        favicon: 'https://example.com/logo.png',
        country: 'Spain',
        tags: const ['rock'],
      );

      final restored = PlayableItem.fromJson(station.toJson());

      expect(restored.id, station.id);
      expect(restored.title, station.name);
      expect(restored.source, station.streamUrl);
      expect(restored.artworkUrl, station.favicon);
      expect(restored.subtitle, station.country);
      expect(restored.kind, PlayableItemKind.radio);
    });
  });
}
