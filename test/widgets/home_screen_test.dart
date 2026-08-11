import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:radio_mix/models/podcast.dart';
import 'package:radio_mix/models/radio_station.dart';
import 'package:radio_mix/screens/home_screen.dart';
import 'package:radio_mix/services/audio_player_service.dart';
import 'package:radio_mix/services/playback_progress_service.dart';
import 'package:radio_mix/services/podcast_download_service.dart';
import 'package:radio_mix/services/podcast_service.dart';
import 'package:radio_mix/services/podcast_subscription_service.dart';
import 'package:radio_mix/services/radio_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_doubles/fake_audio_player_engine.dart';
import '../test_doubles/fake_services.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('HomeScreen', () {
    late PlaybackProgressService progressService;
    late AudioPlayerService audioService;
    late FakeRadioService fakeRadioService;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      progressService = PlaybackProgressService();
      audioService = AudioPlayerService(
        playbackProgressService: progressService,
        engineFactory: ({loadConfiguration}) => FakeAudioPlayerEngine(),
        audioSessionInitializer: () async {},
      );
      fakeRadioService = FakeRadioService(
        searchResults: {
          'favorites': [
            RadioStation(
              id: 'station-1',
              name: 'Rock FM',
              streamUrl: 'https://example.com/live.mp3',
            ),
          ],
        },
      );
    });

    tearDown(() {
      audioService.dispose();
    });

    testWidgets('shows add radio FAB in favorites and hides it on podcasts tab',
        (tester) async {
      final container = ProviderContainer(
        overrides: [
          audioPlayerServiceProvider.overrideWithValue(audioService),
          playbackProgressServiceProvider.overrideWithValue(progressService),
          radioServiceProvider.overrideWithValue(fakeRadioService),
          favoriteStationsProvider.overrideWith((ref) async => const []),
          podcastSubscriptionsProvider.overrideWith(
            (ref) async => <Podcast>[],
          ),
          totalDownloadSizeProvider.overrideWith((ref) async => 0),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: HomeScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Añadir radio'), findsNothing);

      await tester.tap(find.text('Favoritos'));
      await tester.pumpAndSettle();

      expect(find.text('Añadir radio'), findsOneWidget);

      container.read(favoritesTabProvider.notifier).setTab(1);
      await tester.pumpAndSettle();

      expect(find.text('Añadir radio'), findsNothing);
    });

    testWidgets('adds a custom station from home dialog', (tester) async {
      final container = ProviderContainer(
        overrides: [
          audioPlayerServiceProvider.overrideWithValue(audioService),
          playbackProgressServiceProvider.overrideWithValue(progressService),
          radioServiceProvider.overrideWithValue(fakeRadioService),
          favoriteStationsProvider.overrideWith((ref) async => const []),
          podcastSubscriptionsProvider.overrideWith(
            (ref) async => <Podcast>[],
          ),
          podcastServiceProvider.overrideWithValue(FakePodcastService()),
          podcastDownloadServiceProvider
              .overrideWithValue(FakePodcastDownloadService()),
          podcastSubscriptionServiceProvider
              .overrideWithValue(FakePodcastSubscriptionService()),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: HomeScreen()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Favoritos'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Añadir radio'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).at(0), 'Mi Radio');
      await tester.enterText(
        find.byType(TextField).at(1),
        'https://example.com/custom.mp3',
      );
      await tester.tap(find.text('AÑADIR'));
      await tester.pumpAndSettle();

      expect(fakeRadioService.addFavoriteCalls, 1);
      expect(find.text('Mi Radio añadida a favoritos'), findsOneWidget);
    });
  });
}
