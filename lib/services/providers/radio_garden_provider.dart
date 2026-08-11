import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../models/radio_station.dart';
import '../app_http_client.dart';
import '../app_network_error.dart';
import 'radio_search_provider.dart';

class RadioGardenProvider implements RadioSearchProvider {
  RadioGardenProvider({http.Client? httpClient})
      : _httpClient = httpClient ?? http.Client();

  final http.Client _httpClient;

  @override
  String get id => 'radio_garden';

  @override
  String get displayName => 'Radio Garden';

  @override
  bool get requiresApiKey => false;

  @override
  Future<List<RadioStation>> searchStations(String query) async {
    if (query.isEmpty) return [];

    try {
      final response = await appGet(
        _httpClient,
        Uri.https('radio.garden', '/api/search', {'q': query}),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        final hits = data['hits']?['hits'] as List<dynamic>? ?? const [];
        return hits
            .where((h) => h['_source']?['type'] == 'channel')
            .map((h) => _stationFromHit(h))
            .whereType<RadioStation>()
            .take(20)
            .toList();
      }
      return [];
    } catch (error, stackTrace) {
      logAndRethrowAppError(
        'radioGarden',
        'Fallo al buscar estaciones en Radio Garden',
        error,
        stackTrace,
      );
    }
  }

  @override
  Future<List<RadioStation>> getPopularStations() async {
    return [];
  }

  RadioStation? _stationFromHit(Map<String, dynamic> hit) {
    try {
      final source = hit['_source'] as Map<String, dynamic>? ?? {};
      final page = source['page'] as Map<String, dynamic>? ?? {};

      // El ID está al final de la URL: /listen/station-name/{ID}
      final pageUrl = page['url'] as String? ?? '';
      final id = pageUrl.split('/').lastWhere((s) => s.isNotEmpty, orElse: () => '');
      final name = page['title'] as String? ?? '';
      if (id.isEmpty || name.isEmpty) return null;

      // URL de stream que Radio Garden redirige al stream real (302)
      final streamUrl =
          'https://radio.garden/api/ara/content/listen/$id/channel.mp3';
      final countryMap = page['country'] as Map<String, dynamic>?;
      final country = countryMap?['title'] as String?;
      final subtitle = page['subtitle'] as String? ?? '';

      // Favicon desde el dominio del website de la emisora
      final website = page['website'] as String?;
      final favicon = _faviconFromWebsite(website);

      return RadioStation(
        id: 'rg_$id',
        name: name,
        streamUrl: streamUrl,
        favicon: favicon,
        country: country ?? subtitle,
        tags: [],
      );
    } catch (_) {
      return null;
    }
  }

  String? _faviconFromWebsite(String? website) {
    if (website == null || website.isEmpty) return null;
    final uri = Uri.tryParse(website);
    if (uri == null) return null;
    final domain = uri.host.isNotEmpty ? uri.host : website;
    return 'https://www.google.com/s2/favicons?domain=$domain&sz=64';
  }
}
