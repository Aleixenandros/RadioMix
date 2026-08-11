import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../models/podcast.dart';
import '../app_http_client.dart';
import '../app_network_error.dart';
import 'podcast_search_provider.dart';

class ItunesProvider implements PodcastSearchProvider {
  ItunesProvider({http.Client? httpClient})
      : _httpClient = httpClient ?? http.Client();

  final http.Client _httpClient;

  @override
  String get id => 'itunes';

  @override
  String get displayName => 'iTunes / Apple Podcasts';

  @override
  bool get requiresApiKey => false;

  @override
  Future<List<Podcast>> searchPodcasts(String query) async {
    if (query.isEmpty) return [];

    try {
      final response = await appGet(
        _httpClient,
        Uri.https('itunes.apple.com', '/search', {
          'term': query,
          'media': 'podcast',
          'limit': '20',
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        final results = data['results'] as List<dynamic>? ?? const [];
        return results.map((j) => Podcast.fromJson(j)).toList();
      }
      return [];
    } catch (error, stackTrace) {
      logAndRethrowAppError(
        'itunes',
        'Fallo al buscar podcasts en iTunes',
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
        Uri.https('itunes.apple.com', '/search', {
          'term': 'podcast',
          'media': 'podcast',
          'sort': 'popular',
          'limit': '20',
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        final results = data['results'] as List<dynamic>? ?? const [];
        return results.map((j) => Podcast.fromJson(j)).toList();
      }
      return [];
    } catch (_) {
      return [];
    }
  }
}
