import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import '../../models/podcast.dart';
import '../app_http_client.dart';
import '../app_network_error.dart';
import 'podcast_search_provider.dart';

class PodcastIndexProvider implements PodcastSearchProvider {
  PodcastIndexProvider({
    required this.apiKey,
    required this.apiSecret,
    http.Client? httpClient,
  }) : _httpClient = httpClient ?? http.Client();

  final String apiKey;
  final String apiSecret;
  final http.Client _httpClient;

  @override
  String get id => 'podcast_index';

  @override
  String get displayName => 'Podcast Index';

  @override
  bool get requiresApiKey => true;

  @override
  Future<List<Podcast>> searchPodcasts(String query) async {
    if (query.isEmpty) return [];
    if (apiKey.isEmpty || apiSecret.isEmpty) {
      throw Exception(
        'Introduce tu API Key y API Secret de Podcast Index en Configuración > Fuentes de búsqueda',
      );
    }

    try {
      final response = await appGet(
        _httpClient,
        Uri.https('api.podcastindex.org', '/api/1.0/search/byterm', {
          'q': query,
          'max': '20',
        }),
        headers: _authHeaders(),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        final feeds = data['feeds'] as List<dynamic>? ?? const [];
        return feeds.map((j) => _podcastFromFeed(j)).toList();
      }
      return [];
    } catch (error, stackTrace) {
      logAndRethrowAppError(
        'podcastIndex',
        'Fallo al buscar podcasts en Podcast Index',
        error,
        stackTrace,
      );
    }
  }

  @override
  Future<List<Podcast>> getPopularPodcasts() async {
    if (apiKey.isEmpty || apiSecret.isEmpty) return [];

    try {
      final response = await appGet(
        _httpClient,
        Uri.https('api.podcastindex.org', '/api/1.0/podcasts/trending', {
          'max': '20',
          'lang': 'es,en',
        }),
        headers: _authHeaders(),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        final feeds = data['feeds'] as List<dynamic>? ?? const [];
        return feeds.map((j) => _podcastFromFeed(j)).toList();
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  Map<String, String> _authHeaders() {
    final unixTime = (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();
    final hash =
        sha1.convert(utf8.encode('$apiKey$apiSecret$unixTime')).toString();
    return {
      'X-Auth-Key': apiKey,
      'X-Auth-Date': unixTime,
      'Authorization': hash,
    };
  }

  Podcast _podcastFromFeed(Map<String, dynamic> feed) {
    final id = feed['id']?.toString() ?? '';
    String? genre;
    final categories = feed['categories'];
    if (categories is Map && categories.isNotEmpty) {
      genre = categories.values.first?.toString();
    }

    return Podcast(
      id: 'pi_$id',
      title: (feed['title'] as String?) ?? 'Sin título',
      artist: (feed['author'] as String?) ?? 'Desconocido',
      artworkUrl: feed['artwork'] as String?,
      feedUrl: feed['url'] as String?,
      description: feed['description'] as String?,
      genre: genre,
    );
  }
}
