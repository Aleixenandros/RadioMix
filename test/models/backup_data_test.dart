import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:radio_mix/models/backup_data.dart';
import 'package:radio_mix/models/podcast.dart';
import 'package:radio_mix/models/radio_station.dart';

void main() {
  final timestamp = DateTime.utc(2026, 3, 20, 12, 0, 0);
  final station = RadioStation(
    id: 'station-1',
    name: 'RadioMix FM',
    streamUrl: 'https://example.com/live.mp3',
    favicon: 'https://example.com/logo.png',
    country: 'Spain',
    language: 'es',
    tags: const ['rock', 'live'],
    bitrate: 128,
  );
  final podcast = Podcast(
    id: 'pod-1',
    title: 'RadioMix Daily',
    artist: 'RadioMix',
    artworkUrl: 'https://example.com/artwork.png',
    feedUrl: 'https://example.com/feed.xml',
    description: 'Daily updates',
    genre: 'News',
    trackCount: 10,
    releaseDate: DateTime.utc(2026, 3, 1),
  );
  final progress = {
    'stationId': 'podcast_ep_1',
    'position': 45,
    'duration': 300,
    'lastPlayed': timestamp.toIso8601String(),
  };

  group('BackupData', () {
    test('toXmlString and fromXmlString preserve the core data', () {
      final backup = BackupData(
        favoriteStations: [station],
        subscribedPodcasts: [podcast],
        playbackProgress: [progress],
        userPreferences: const {
          'theme_mode': 'dark',
          'audio_buffer_seconds': 20,
        },
        downloadMetadata: const [
          {
            'episodeId': 'ep-1',
            'title': 'Episode 1',
            'fileSize': 1234,
          },
        ],
        timestamp: timestamp,
      );

      final restored = BackupData.fromXmlString(backup.toXmlString());

      expect(restored.timestamp, timestamp);
      expect(restored.favoriteStations, hasLength(1));
      expect(restored.favoriteStations.single.name, station.name);
      expect(restored.favoriteStations.single.tags, station.tags);
      expect(restored.subscribedPodcasts, hasLength(1));
      expect(restored.subscribedPodcasts.single.title, podcast.title);
      expect(
          restored.playbackProgress.single['stationId'], progress['stationId']);
      expect(
          restored.playbackProgress.single['position'], progress['position']);
      expect(restored.userPreferences['theme_mode'], 'dark');
      expect(restored.userPreferences['audio_buffer_seconds'], 20);
      expect(restored.downloadMetadata.single['episodeId'], 'ep-1');
      expect(restored.downloadMetadata.single['fileSize'], 1234);
    });

    test('fromContent supports JSON payloads', () {
      final jsonContent = jsonEncode({
        'version': '1.0',
        'timestamp': timestamp.toIso8601String(),
        'favoriteStations': [station.toJson()],
        'subscribedPodcasts': [podcast.toJson()],
        'playbackProgress': [progress],
        'userPreferences': {'theme_mode': 'light'},
        'downloadMetadata': [
          {'episodeId': 'ep-2'}
        ],
      });

      final restored = BackupData.fromContent(jsonContent);

      expect(restored.favoriteStations.single.streamUrl, station.streamUrl);
      expect(restored.subscribedPodcasts.single.feedUrl, podcast.feedUrl);
      expect(
          restored.playbackProgress.single['duration'], progress['duration']);
      expect(restored.userPreferences['theme_mode'], 'light');
      expect(restored.downloadMetadata.single['episodeId'], 'ep-2');
    });
  });
}
