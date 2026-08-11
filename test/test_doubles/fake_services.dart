import 'package:radio_mix/models/playable_item.dart';
import 'package:radio_mix/models/podcast.dart';
import 'package:radio_mix/models/podcast_episode.dart';
import 'package:radio_mix/models/radio_station.dart';
import 'package:radio_mix/services/playback_coordinator_service.dart';
import 'package:radio_mix/services/playback_progress_service.dart';
import 'package:radio_mix/services/podcast_download_service.dart';
import 'package:radio_mix/services/podcast_service.dart';
import 'package:radio_mix/services/podcast_subscription_service.dart';
import 'package:radio_mix/services/radio_service.dart';

class FakeRadioService extends RadioService {
  FakeRadioService({
    Map<String, List<RadioStation>>? searchResults,
  }) : _searchResults = searchResults ?? {};

  final Map<String, List<RadioStation>> _searchResults;
  final Set<String> favoriteIds = {};
  int addFavoriteCalls = 0;
  int removeFavoriteCalls = 0;

  @override
  Future<List<RadioStation>> searchStations(String query) async {
    return (_searchResults[query] ?? [])
        .map(
          (station) => station.copyWith(
            isFavorite: favoriteIds.contains(station.id),
          ),
        )
        .toList();
  }

  @override
  Future<void> addFavorite(RadioStation station) async {
    addFavoriteCalls++;
    favoriteIds.add(station.id);
  }

  @override
  Future<void> removeFavorite(String stationId) async {
    removeFavoriteCalls++;
    favoriteIds.remove(stationId);
  }

  @override
  Future<List<RadioStation>> getFavorites() async {
    return _searchResults.values
        .expand((stations) => stations)
        .where((station) => favoriteIds.contains(station.id))
        .map((station) => station.copyWith(isFavorite: true))
        .toList();
  }
}

class FakePodcastService extends PodcastService {
  FakePodcastService({
    Map<String, List<Podcast>>? searchResults,
    Map<String, List<PodcastEpisode>>? episodesByFeed,
  })  : _searchResults = searchResults ?? {},
        _episodesByFeed = episodesByFeed ?? {};

  final Map<String, List<Podcast>> _searchResults;
  final Map<String, List<PodcastEpisode>> _episodesByFeed;

  @override
  Future<List<Podcast>> searchPodcasts(String query) async {
    return _searchResults[query] ?? [];
  }

  @override
  Future<List<PodcastEpisode>> getEpisodes(String feedUrl) async {
    return _episodesByFeed[feedUrl] ?? [];
  }
}

class FakePodcastSubscriptionService extends PodcastSubscriptionService {
  FakePodcastSubscriptionService({
    bool subscribed = false,
    List<Podcast>? subscriptions,
  })  : _subscribed = subscribed,
        _subscriptions = subscriptions ?? [];

  bool _subscribed;
  final List<Podcast> _subscriptions;

  @override
  Future<List<Podcast>> getSubscriptions() async {
    return List<Podcast>.from(_subscriptions);
  }

  @override
  Future<void> subscribe(Podcast podcast) async {
    _subscribed = true;
    if (!_subscriptions.any((item) => item.id == podcast.id)) {
      _subscriptions.add(podcast);
    }
  }

  @override
  Future<void> unsubscribe(String podcastId) async {
    _subscribed = false;
    _subscriptions.removeWhere((item) => item.id == podcastId);
  }

  @override
  Future<bool> isSubscribed(String podcastId) async {
    return _subscribed;
  }
}

class FakePodcastDownloadService extends PodcastDownloadService {
  FakePodcastDownloadService({
    List<DownloadedEpisode>? downloads,
  }) : _downloads = downloads ?? [];

  final List<DownloadedEpisode> _downloads;

  @override
  Future<List<DownloadedEpisode>> getDownloads() async {
    return List<DownloadedEpisode>.from(_downloads);
  }

  @override
  Future<DownloadedEpisode?> downloadEpisode({
    required String episodeId,
    required String podcastId,
    required String title,
    required String podcastTitle,
    required String audioUrl,
    String? artworkUrl,
    Function(double)? onProgress,
  }) async {
    if (_downloads.any((download) => download.episodeId == episodeId)) {
      return null;
    }
    final download = DownloadedEpisode(
      episodeId: episodeId,
      podcastId: podcastId,
      title: title,
      podcastTitle: podcastTitle,
      audioUrl: audioUrl,
      artworkUrl: artworkUrl,
      localPath: '/tmp/$episodeId.mp3',
      downloadedAt: DateTime.now(),
      fileSize: 1024,
    );
    _downloads.add(download);
    return download;
  }

  @override
  Future<void> deleteDownload(String episodeId) async {
    _downloads.removeWhere((download) => download.episodeId == episodeId);
  }

  @override
  Future<String?> getLocalPath(String episodeId) async {
    final match = _downloads.where((download) => download.episodeId == episodeId);
    return match.isEmpty ? null : match.first.localPath;
  }

  @override
  Future<int> getTotalDownloadSize() async {
    return _downloads.fold<int>(
      0,
      (total, download) => total + download.fileSize,
    );
  }
}

class FakePlaybackCoordinatorService extends PlaybackCoordinatorService {
  FakePlaybackCoordinatorService(
    super.ref, {
    this.simulatedProgress,
    this.shouldFail = false,
  });

  final PlaybackProgress? simulatedProgress;
  final bool shouldFail;

  PlayableItem? lastItem;
  PodcastResumeBehavior? lastResumeBehavior;
  bool? lastResumeDecision;

  @override
  Future<PlaybackRequestResult> playItem(
    PlayableItem item, {
    messenger,
    PodcastResumeBehavior podcastResumeBehavior =
        PodcastResumeBehavior.automatic,
    Future<bool?> Function(PlaybackProgress progress)? onRequestResume,
    String? successMessage,
  }) async {
    lastItem = item;
    lastResumeBehavior = podcastResumeBehavior;

    if (simulatedProgress != null && onRequestResume != null) {
      lastResumeDecision = await onRequestResume(simulatedProgress!);
    }

    if (shouldFail) {
      return const PlaybackRequestResult(
        didStart: false,
        errorMessage: 'Error al reproducir: fallo de prueba',
      );
    }

    return PlaybackRequestResult(
      didStart: true,
      feedbackMessage: successMessage ?? 'Reproduciendo: ${item.title}',
      resumedFrom: lastResumeDecision == true ? simulatedProgress?.position : null,
    );
  }
}
