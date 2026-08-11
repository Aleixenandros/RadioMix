import 'package:flutter_test/flutter_test.dart';
import 'package:radio_mix/models/backup_data.dart';
import 'package:radio_mix/models/podcast.dart';
import 'package:radio_mix/models/radio_station.dart';
import 'package:radio_mix/services/app_preferences.dart';
import 'package:radio_mix/services/backup_service.dart';
import 'package:radio_mix/services/playback_progress_service.dart';
import 'package:radio_mix/services/podcast_download_service.dart';
import 'package:radio_mix/services/podcast_subscription_service.dart';
import 'package:radio_mix/services/radio_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BackupService', () {
    late BackupService backupService;
    late RadioService radioService;
    late PodcastSubscriptionService podcastSubscriptionService;
    late PlaybackProgressService playbackProgressService;

    final station = RadioStation(
      id: 'station-1',
      name: 'RadioMix FM',
      streamUrl: 'https://example.com/live.mp3',
      country: 'ES',
    );
    final podcast = Podcast(
      id: 'pod-1',
      title: 'RadioMix Daily',
      artist: 'RadioMix',
      feedUrl: 'https://example.com/feed.xml',
    );

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      radioService = RadioService();
      podcastSubscriptionService = PodcastSubscriptionService();
      playbackProgressService = PlaybackProgressService();
      backupService = BackupService(
        radioService: radioService,
        podcastSubscriptionService: podcastSubscriptionService,
        playbackProgressService: playbackProgressService,
        podcastDownloadService: PodcastDownloadService(),
      );
    });

    test('createBackupData collects current local state', () async {
      await radioService.addFavorite(station);
      await podcastSubscriptionService.subscribe(podcast);
      await playbackProgressService.saveProgress(
        'podcast_ep_1',
        const Duration(seconds: 45),
        const Duration(minutes: 5),
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(AppPreferenceKeys.themeMode, 'dark');
      await prefs.setInt(AppPreferenceKeys.audioBufferSeconds, 30);
      await prefs.setString(
          AppPreferenceKeys.activeRadioProvider, 'radio_garden');
      await prefs.setString(
        AppPreferenceKeys.podcastDownloads,
        '[{"episodeId":"ep-1","podcastId":"pod-1","title":"Episode 1",'
        '"podcastTitle":"RadioMix Daily","audioUrl":"https://example.com/ep.mp3",'
        '"localPath":"/tmp/ep.mp3","downloadedAt":"2026-03-20T00:00:00.000Z",'
        '"fileSize":1234}]',
      );

      final backup = await backupService.createBackupData();

      expect(backup.favoriteStations, hasLength(1));
      expect(backup.favoriteStations.single.id, station.id);
      expect(backup.subscribedPodcasts, hasLength(1));
      expect(backup.subscribedPodcasts.single.id, podcast.id);
      expect(backup.playbackProgress, hasLength(1));
      expect(backup.playbackProgress.single['stationId'], 'podcast_ep_1');
      expect(backup.userPreferences[AppPreferenceKeys.themeMode], 'dark');
      expect(backup.userPreferences[AppPreferenceKeys.audioBufferSeconds], 30);
      expect(
        backup.userPreferences[AppPreferenceKeys.activeRadioProvider],
        'radio_garden',
      );
      expect(backup.downloadMetadata.single['episodeId'], 'ep-1');
      expect(backup.downloadMetadata.single.containsKey('localPath'), isFalse);
    });

    test('restoreBackup rewrites favorites, subscriptions and progress',
        () async {
      final backup = BackupData(
        favoriteStations: [station],
        subscribedPodcasts: [podcast],
        playbackProgress: [
          {
            'stationId': 'podcast_ep_1',
            'position': 90,
            'duration': 300,
            'lastPlayed': DateTime.utc(2026, 3, 20).toIso8601String(),
          },
        ],
        userPreferences: const {
          AppPreferenceKeys.themeMode: 'light',
          AppPreferenceKeys.audioBufferSeconds: 15,
        },
        timestamp: DateTime.utc(2026, 3, 20),
      );

      await radioService.addFavorite(
        RadioStation(
          id: 'old-station',
          name: 'Old',
          streamUrl: 'https://example.com/old.mp3',
        ),
      );
      await podcastSubscriptionService.subscribe(
        Podcast(id: 'old-podcast', title: 'Old', artist: 'Old'),
      );

      await backupService.restoreBackup(backup);

      final favorites = await radioService.getFavorites();
      final subscriptions = await podcastSubscriptionService.getSubscriptions();
      final progress =
          await playbackProgressService.getProgress('podcast_ep_1');
      final prefs = await SharedPreferences.getInstance();

      expect(favorites.map((item) => item.id), [station.id]);
      expect(subscriptions.map((item) => item.id), [podcast.id]);
      expect(progress, isNotNull);
      expect(progress!.position, const Duration(seconds: 90));
      expect(progress.duration, const Duration(seconds: 300));
      expect(prefs.getString(AppPreferenceKeys.themeMode), 'light');
      expect(prefs.getInt(AppPreferenceKeys.audioBufferSeconds), 15);
    });
  });
}
