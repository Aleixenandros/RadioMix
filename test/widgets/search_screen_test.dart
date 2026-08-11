import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:radio_mix/models/podcast.dart';
import 'package:radio_mix/models/radio_station.dart';
import 'package:radio_mix/screens/search_screen.dart';
import 'package:radio_mix/services/app_network_error.dart';
import 'package:radio_mix/services/playback_coordinator_service.dart';
import 'package:radio_mix/services/podcast_service.dart';
import 'package:radio_mix/services/radio_service.dart';

import '../test_doubles/fake_services.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SearchScreen', () {
    testWidgets('renders radio results, toggles favorite and requests playback',
        (tester) async {
      final station = RadioStation(
        id: 'station-1',
        name: 'Rock FM',
        streamUrl: 'https://example.com/live.mp3',
        country: 'ES',
      );
      final fakeRadioService = FakeRadioService();
      final fakePodcastService = FakePodcastService();
      late FakePlaybackCoordinatorService fakeCoordinator;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            radioServiceProvider.overrideWithValue(fakeRadioService),
            podcastServiceProvider.overrideWithValue(fakePodcastService),
            radioSearchResultsProvider('rock').overrideWith((ref) async {
              return [station];
            }),
            playbackCoordinatorServiceProvider.overrideWith(
              (ref) {
                fakeCoordinator = FakePlaybackCoordinatorService(ref);
                return fakeCoordinator;
              },
            ),
          ],
          child: const MaterialApp(home: SearchScreen()),
        ),
      );

      await tester.enterText(
        find.descendant(
          of: find.byType(SearchBar),
          matching: find.byType(EditableText),
        ),
        'rock',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(find.text('Rock FM'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.favorite_border));
      await tester.pumpAndSettle();

      expect(fakeRadioService.addFavoriteCalls, 1);
      expect(find.byIcon(Icons.favorite), findsOneWidget);

      await tester.tap(find.byIcon(Icons.play_arrow));
      await tester.pumpAndSettle();

      expect(fakeCoordinator.lastItem?.id, station.id);
    });

    testWidgets('renders podcast search results on podcasts tab',
        (tester) async {
      final podcast = Podcast(
        id: 'pod-1',
        title: 'RadioMix Daily',
        artist: 'RadioMix',
        feedUrl: '',
      );
      final fakeRadioService = FakeRadioService();
      final fakePodcastService = FakePodcastService();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            radioServiceProvider.overrideWithValue(fakeRadioService),
            podcastServiceProvider.overrideWithValue(fakePodcastService),
            podcastSearchResultsProvider('daily').overrideWith((ref) async {
              return [podcast];
            }),
          ],
          child: const MaterialApp(home: SearchScreen()),
        ),
      );

      await tester.tap(find.text('Podcasts'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.descendant(
          of: find.byType(SearchBar),
          matching: find.byType(EditableText),
        ),
        'daily',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(find.text('RadioMix Daily'), findsOneWidget);
      expect(find.text('RadioMix'), findsOneWidget);
    });

    testWidgets('renders friendly network error for radio search',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            radioServiceProvider.overrideWithValue(FakeRadioService()),
            podcastServiceProvider.overrideWithValue(FakePodcastService()),
            radioSearchResultsProvider('rock').overrideWith((ref) async {
              throw const AppNetworkException(
                type: AppNetworkErrorType.offline,
                message: 'offline',
              );
            }),
          ],
          child: const MaterialApp(home: SearchScreen()),
        ),
      );

      await tester.enterText(
        find.descendant(
          of: find.byType(SearchBar),
          matching: find.byType(EditableText),
        ),
        'rock',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(find.text('No se pudo completar la búsqueda'), findsOneWidget);
      expect(
        find.text('No hay conexión de red disponible en este momento.'),
        findsOneWidget,
      );
      expect(find.text('REINTENTAR'), findsOneWidget);
    });
  });
}
