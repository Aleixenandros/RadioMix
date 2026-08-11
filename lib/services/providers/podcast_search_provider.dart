import '../../models/podcast.dart';

abstract class PodcastSearchProvider {
  String get id;
  String get displayName;
  bool get requiresApiKey;

  Future<List<Podcast>> searchPodcasts(String query);
  Future<List<Podcast>> getPopularPodcasts();
}
