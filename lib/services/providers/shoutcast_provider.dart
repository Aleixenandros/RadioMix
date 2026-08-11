import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../models/radio_station.dart';
import '../app_http_client.dart';
import '../app_network_error.dart';
import 'radio_search_provider.dart';

class ShoutcastProvider implements RadioSearchProvider {
  ShoutcastProvider({required this.apiKey, http.Client? httpClient})
      : _httpClient = httpClient ?? http.Client();

  final String apiKey;
  final http.Client _httpClient;

  @override
  String get id => 'shoutcast';

  @override
  String get displayName => 'SHOUTcast';

  @override
  bool get requiresApiKey => true;

  @override
  Future<List<RadioStation>> searchStations(String query) async {
    if (query.isEmpty) return [];
    if (apiKey.isEmpty) {
      throw Exception(
        'Introduce tu API Key de SHOUTcast en Configuración > Fuentes de búsqueda',
      );
    }

    try {
      final response = await appGet(
        _httpClient,
        Uri.https('api.shoutcast.com', '/station/search', {
          'k': apiKey,
          'search': query,
          'f': 'json',
          'limit': '20',
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        final stationList = data['stationlist'];
        if (stationList == null) return [];

        final stations = stationList['station'] as List<dynamic>? ?? const [];
        return stations
            .map((s) => _stationFromJson(s))
            .where((s) => s != null)
            .cast<RadioStation>()
            .toList();
      }
      return [];
    } catch (error, stackTrace) {
      logAndRethrowAppError(
        'shoutcast',
        'Fallo al buscar estaciones en SHOUTcast',
        error,
        stackTrace,
      );
    }
  }

  @override
  Future<List<RadioStation>> getPopularStations() async {
    if (apiKey.isEmpty) return [];

    try {
      final response = await appGet(
        _httpClient,
        Uri.https('api.shoutcast.com', '/station/top', {
          'k': apiKey,
          'f': 'json',
          'limit': '10',
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        final stationList = data['stationlist'];
        if (stationList == null) return [];

        final stations = stationList['station'] as List<dynamic>? ?? const [];
        return stations
            .map((s) => _stationFromJson(s))
            .where((s) => s != null)
            .cast<RadioStation>()
            .toList();
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  RadioStation? _stationFromJson(Map<String, dynamic> s) {
    try {
      final id = s['id']?.toString() ?? '';
      final name = (s['name'] as String?) ?? '';
      if (id.isEmpty || name.isEmpty) return null;

      final streamUrl =
          'https://yp.shoutcast.com/sbin/tunein-station.pls?id=$id';
      final genre = (s['genre'] as String?) ?? '';
      final bitrate = double.tryParse(s['br']?.toString() ?? '');
      final country = s['c'] as String?;
      final logo = s['logo'] as String?;

      return RadioStation(
        id: 'sc_$id',
        name: name,
        streamUrl: streamUrl,
        favicon: logo,
        country: country,
        language: genre,
        tags: genre.isNotEmpty ? genre.split(' ') : [],
        bitrate: bitrate,
      );
    } catch (_) {
      return null;
    }
  }
}
