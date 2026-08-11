import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:radio_mix/models/playable_item.dart';
import 'package:radio_mix/models/podcast.dart';
import 'package:radio_mix/models/podcast_episode.dart';
import 'package:radio_mix/screens/player_screen.dart';
import 'package:radio_mix/services/audio_player_service.dart';
import 'package:radio_mix/services/playback_coordinator_service.dart';
import 'package:radio_mix/services/playback_progress_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_doubles/fake_audio_player_engine.dart';
import '../test_doubles/fake_services.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PlayerScreen', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    testWidgets('renders recent podcast items without dismissible assertion',
        (tester) async {
      final recentPodcast = PlayableItem.fromPodcastEpisode(
        episode: PodcastEpisode(
          id: 'episode-1',
          title: 'Episodio reciente',
          audioUrl: 'https://example.com/episode-1.mp3',
        ),
        podcast: Podcast(
          id: 'podcast-1',
          title: 'RadioMix Daily',
          artist: 'RadioMix',
        ),
        source: 'https://example.com/episode-1.mp3',
      );

      final audioService = AudioPlayerService(
        playbackProgressService: PlaybackProgressService(),
        engineFactory: ({loadConfiguration}) => FakeAudioPlayerEngine(),
        audioSessionInitializer: () async {},
      );
      addTearDown(audioService.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            audioPlayerServiceProvider.overrideWithValue(audioService),
            recentPlayablesProvider.overrideWith(
              (ref) => Stream.value([recentPodcast]),
            ),
          ],
          child: const MaterialApp(home: Scaffold(body: PlayerScreen())),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Últimas reproducidas'), findsOneWidget);
      expect(find.text('Episodio reciente'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('shows app icon fallback for radio without artwork',
        (tester) async {
      final audioService = AudioPlayerService(
        playbackProgressService: PlaybackProgressService(),
        engineFactory: ({loadConfiguration}) => FakeAudioPlayerEngine(),
        audioSessionInitializer: () async {},
      );
      addTearDown(audioService.dispose);

      const radio = PlayableItem(
        id: 'radio-1',
        title: 'Radio sin logo',
        source: 'https://example.com/live.mp3',
        subtitle: 'ES',
        kind: PlayableItemKind.radio,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            audioPlayerServiceProvider.overrideWithValue(audioService),
            currentPlayableProvider.overrideWith(
              () => _TestCurrentPlayableNotifier(radio),
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: PlayerScreen(),
            ),
          ),
        ),
      );

      await tester.pump();

      final appIconImages = tester.widgetList<Image>(find.byType(Image)).where(
            (image) =>
                image.image is AssetImage &&
                (image.image as AssetImage).assetName == 'assets/icon/icon.png',
          );
      expect(appIconImages, isNotEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets('keeps restart button enabled after restarting radio',
        (tester) async {
      final audioService = _PlayingAudioPlayerService();
      addTearDown(audioService.dispose);
      late FakePlaybackCoordinatorService fakeCoordinator;

      const radio = PlayableItem(
        id: 'radio-restart',
        title: 'Radio reiniciable',
        source: 'https://example.com/live.mp3',
        kind: PlayableItemKind.radio,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            audioPlayerServiceProvider.overrideWithValue(audioService),
            playbackCoordinatorServiceProvider.overrideWith((ref) {
              fakeCoordinator = FakePlaybackCoordinatorService(ref);
              return fakeCoordinator;
            }),
            currentPlayableProvider.overrideWith(
              () => _TestCurrentPlayableNotifier(radio),
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: PlayerScreen(),
            ),
          ),
        ),
      );

      await tester.pump();

      final restartFinder = find.widgetWithIcon(
        IconButton,
        Icons.restart_alt_rounded,
      );
      final restartButton = tester.widget<IconButton>(restartFinder);
      expect(restartButton.onPressed, isNotNull);

      await tester.tap(restartFinder);
      await tester.pump();
      await tester.pump();

      expect(fakeCoordinator.lastItem?.id, radio.id);
      final restartedButton = tester.widget<IconButton>(restartFinder);
      expect(restartedButton.onPressed, isNotNull);
    });

    testWidgets('keeps restart button enabled while restart is in flight',
        (tester) async {
      final audioService = _PlayingAudioPlayerService();
      addTearDown(audioService.dispose);
      late _PendingPlaybackCoordinatorService coordinator;

      const radio = PlayableItem(
        id: 'radio-buffering',
        title: 'Radio en buffer',
        source: 'https://example.com/buffer.mp3',
        kind: PlayableItemKind.radio,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            audioPlayerServiceProvider.overrideWithValue(audioService),
            playbackCoordinatorServiceProvider.overrideWith((ref) {
              coordinator = _PendingPlaybackCoordinatorService(ref);
              return coordinator;
            }),
            currentPlayableProvider.overrideWith(
              () => _TestCurrentPlayableNotifier(radio),
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: PlayerScreen(),
            ),
          ),
        ),
      );

      await tester.pump();

      final restartFinder = find.widgetWithIcon(
        IconButton,
        Icons.restart_alt_rounded,
      );
      await tester.tap(restartFinder);
      await tester.pump();

      final restartButton = tester.widget<IconButton>(restartFinder);
      expect(restartButton.onPressed, isNotNull);
      expect(coordinator.lastItem?.id, radio.id);

      coordinator.complete();
      await tester.pump();
    });
  });
}

class _TestCurrentPlayableNotifier extends CurrentPlayableNotifier {
  _TestCurrentPlayableNotifier(this.initialItem);

  final PlayableItem initialItem;

  @override
  PlayableItem? build() => initialItem;
}

class _PlayingAudioPlayerService extends AudioPlayerService {
  _PlayingAudioPlayerService()
      : super(
          playbackProgressService: PlaybackProgressService(),
          engineFactory: ({loadConfiguration}) => FakeAudioPlayerEngine(),
          audioSessionInitializer: () async {},
        );

  @override
  Future<void> get ready async {}

  @override
  bool get isPlaying => true;

  @override
  ProcessingState get processingState => ProcessingState.ready;

  @override
  double get volume => 1.0;

  @override
  Duration? get duration => null;

  @override
  Duration get position => Duration.zero;

  @override
  Stream<PlayerState> get playerStateStream =>
      Stream.value(PlayerState(true, ProcessingState.ready));

  @override
  Stream<Duration> get positionStream => const Stream.empty();

  @override
  Stream<List<PlayableItem>> get recentPlayablesStream =>
      Stream.value(const []);

  @override
  Future<void> togglePlayPause() async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> setVolume(double volume) async {}

  @override
  Future<void> dispose() async {}
}

class _PendingPlaybackCoordinatorService extends PlaybackCoordinatorService {
  _PendingPlaybackCoordinatorService(super.ref);

  final Completer<PlaybackRequestResult> _completer =
      Completer<PlaybackRequestResult>();

  PlayableItem? lastItem;

  @override
  Future<PlaybackRequestResult> playItem(
    PlayableItem item, {
    messenger,
    PodcastResumeBehavior podcastResumeBehavior =
        PodcastResumeBehavior.automatic,
    Future<bool?> Function(PlaybackProgress progress)? onRequestResume,
    String? successMessage,
  }) {
    lastItem = item;
    return _completer.future;
  }

  void complete() {
    if (!_completer.isCompleted) {
      _completer.complete(
        const PlaybackRequestResult(
          didStart: true,
          feedbackMessage: 'Reiniciando',
        ),
      );
    }
  }
}
