import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../models/podcast.dart';
import '../app_http_client.dart';
import '../app_network_error.dart';
import 'podcast_search_provider.dart';

class GPodderProvider implements PodcastSearchProvider {
  GPodderProvider({http.Client? httpClient})
      : _httpClient = httpClient ?? http.Client();

  final http.Client _httpClient;

  @override
  String get id => 'gpodder';

  @override
  String get displayName => 'gPodder';

  @override
  bool get requiresApiKey => false;

  @override
  Future<List<Podcast>> searchPodcasts(String query) async {
    if (query.isEmpty) return [];

    try {
      final response = await appGet(
        _httpClient,
        Uri.https('gpodder.net', '/search.json', {'q': query}),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as List<dynamic>;
        return data
            .take(20)
            .map((j) => _podcastFromJson(j))
            .where((p) => p != null)
            .cast<Podcast>()
            .toList();
      }
      return [];
    } catch (error, stackTrace) {
      logAndRethrowAppError(
        'gpodder',
        'Fallo al buscar podcasts en gPodder',
        error,
        stackTrace,
      );
    }
  }

  @override
  Future<List<Podcast>> getPopularPodcasts() async {
    try {
      final response = await appGet(
        _httpClient,
        Uri.https('gpodder.net', '/toplist/20.json'),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as List<dynamic>;
        return data
            .map((j) => _podcastFromJson(j))
            .where((p) => p != null)
            .cast<Podcast>()
            .toList();
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  Podcast? _podcastFromJson(Map<String, dynamic> j) {
    try {
      final feedUrl = j['url'] as String? ?? '';
      if (feedUrl.isEmpty) return null;

      final id = 'gp_${feedUrl.hashCode.abs()}';

      return Podcast(
        id: id,
        title: (j['title'] as String?) ?? 'Sin título',
        artist: (j['author'] as String?) ?? '',
        artworkUrl: (j['logo_url'] as String?),
        feedUrl: feedUrl,
        description: j['description'] as String?,
      );
    } catch (_) {
      return null;
    }
  }
}
