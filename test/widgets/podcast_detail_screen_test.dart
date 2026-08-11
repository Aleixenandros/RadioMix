import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:radio_mix/models/podcast.dart';
import 'package:radio_mix/models/podcast_episode.dart';
import 'package:radio_mix/screens/podcast_detail_screen.dart';
import 'package:radio_mix/services/app_network_error.dart';
import 'package:radio_mix/services/playback_coordinator_service.dart';
import 'package:radio_mix/services/playback_progress_service.dart';
import 'package:radio_mix/services/podcast_download_service.dart';
import 'package:radio_mix/services/podcast_service.dart';
import 'package:radio_mix/services/podcast_subscription_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_doubles/fake_services.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PodcastDetailScreen', () {
    late PlaybackProgressService progressService;
    late FakePodcastService fakePodcastService;
    late FakePodcastDownloadService fakeDownloadService;
    late FakePodcastSubscriptionService fakeSubscriptionService;
    late Podcast podcast;
    late PodcastEpisode episode;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      progressService = PlaybackProgressService();
      podcast = Podcast(
        id: 'pod-1',
        title: 'RadioMix Daily',
        artist: 'RadioMix',
        feedUrl: 'https://example.com/feed.xml',
      );
      episode = PodcastEpisode(
        id: 'ep-1',
        title: 'Episode 1',
        audioUrl: 'https://example.com/ep1.mp3',
        duration: const Duration(minutes: 30),
        publishDate: DateTime.now().subtract(const Duration(days: 2)),
      );
      fakePodcastService = FakePodcastService(
        episodesByFeed: {
          podcast.feedUrl!: [episode],
        },
      );
      fakeDownloadService = FakePodcastDownloadService(
        downloads: [
          DownloadedEpisode(
            episodeId: episode.id,
            podcastId: podcast.id,
            title: episode.title,
            podcastTitle: podcast.title,
            audioUrl: episode.audioUrl,
            localPath: '/tmp/ep-1.mp3',
            downloadedAt: DateTime.now(),
            fileSize: 2048,
          ),
        ],
      );
      fakeSubscriptionService = FakePodcastSubscriptionService(
        subscribed: true,
        subscriptions: [podcast],
      );
    });

    testWidgets('renders episode progress and downloaded state',
        (tester) async {
      final progressEntry = PlaybackProgress(
        stationId: 'podcast_ep_${episode.id}',
        position: const Duration(minutes: 1),
        duration: const Duration(minutes: 30),
        lastPlayed: DateTime.now(),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            podcastServiceProvider.overrideWithValue(fakePodcastService),
            podcastDownloadServiceProvider
                .overrideWithValue(fakeDownloadService),
            podcastSubscriptionServiceProvider
                .overrideWithValue(fakeSubscriptionService),
            playbackProgressServiceProvider.overrideWithValue(progressService),
            playbackProgressEntriesProvider.overrideWith(
              (ref) async => [progressEntry],
            ),
          ],
          child: MaterialApp(
            home: PodcastDetailScreen(podcast: podcast),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('RadioMix Daily'), findsOneWidget);
      expect(find.text('SUSCRITO'), findsOneWidget);
      expect(find.text('Episode 1'), findsOneWidget);
      expect(find.byIcon(Icons.download_done), findsWidgets);
    });

    testWidgets('asks to resume and plays downloaded source', (tester) async {
      late FakePlaybackCoordinatorService fakeCoordinator;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            podcastServiceProvider.overrideWithValue(fakePodcastService),
            podcastDownloadServiceProvider
                .overrideWithValue(fakeDownloadService),
            podcastSubscriptionServiceProvider
                .overrideWithValue(fakeSubscriptionService),
            playbackProgressServiceProvider.overrideWithValue(progressService),
            playbackCoordinatorServiceProvider.overrideWith(
              (ref) {
                fakeCoordinator = FakePlaybackCoordinatorService(
                  ref,
                  simulatedProgress: PlaybackProgress(
                    stationId: 'podcast_ep_${episode.id}',
                    position: const Duration(seconds: 42),
                    duration: const Duration(minutes: 30),
                    lastPlayed: DateTime.now(),
                  ),
                );
                return fakeCoordinator;
              },
            ),
          ],
          child: MaterialApp(
            home: PodcastDetailScreen(podcast: podcast),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Episode 1'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      expect(find.text('Continuar reproducción'), findsOneWidget);

      await tester.tap(find.text('CONTINUAR'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      expect(fakeCoordinator.lastResumeBehavior, PodcastResumeBehavior.ask);
      expect(fakeCoordinator.lastResumeDecision, isTrue);
      expect(fakeCoordinator.lastItem?.source, '/tmp/ep-1.mp3');
    });

    testWidgets('renders friendly feed error message', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            podcastServiceProvider.overrideWithValue(fakePodcastService),
            podcastEpisodesProvider(podcast.feedUrl!).overrideWith((ref) async {
              throw const AppNetworkException(
                type: AppNetworkErrorType.timeout,
                message: 'timeout',
              );
            }),
            podcastDownloadServiceProvider
                .overrideWithValue(fakeDownloadService),
            podcastSubscriptionServiceProvider
                .overrideWithValue(fakeSubscriptionService),
            playbackProgressServiceProvider.overrideWithValue(progressService),
          ],
          child: MaterialApp(
            home: PodcastDetailScreen(podcast: podcast),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text(
          'La solicitud tardó demasiado. Revisa tu conexión e inténtalo de nuevo.',
        ),
        findsOneWidget,
      );
      expect(find.text('REINTENTAR'), findsOneWidget);
    });
  });
}
