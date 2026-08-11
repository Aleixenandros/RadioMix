import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../models/radio_station.dart';
import '../app_http_client.dart';
import '../app_network_error.dart';
import 'radio_search_provider.dart';

class RadioBrowserProvider implements RadioSearchProvider {
  RadioBrowserProvider({http.Client? httpClient})
      : _httpClient = httpClient ?? http.Client();

  final http.Client _httpClient;

  @override
  String get id => 'radio_browser';

  @override
  String get displayName => 'Radio Browser';

  @override
  bool get requiresApiKey => false;

  @override
  Future<List<RadioStation>> searchStations(String query) async {
    if (query.isEmpty) return [];

    try {
      final response = await appGet(
        _httpClient,
        Uri.https('de1.api.radio-browser.info', '/json/stations/search', {
          'name': query,
          'limit': '20',
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as List<dynamic>;
        return data.map((j) => RadioStation.fromJson(j)).toList();
      }
      return [];
    } catch (error, stackTrace) {
      logAndRethrowAppError(
        'radioBrowser',
        'Fallo al buscar estaciones en Radio Browser',
        error,
        stackTrace,
      );
    }
  }

  @override
  Future<List<RadioStation>> getPopularStations() async {
    try {
      final response = await appGet(
        _httpClient,
        Uri.https('de1.api.radio-browser.info', '/json/stations/topvote/10'),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as List<dynamic>;
        return data.map((j) => RadioStation.fromJson(j)).toList();
      }
      return [];
    } catch (_) {
      return [];
    }
  }
}
