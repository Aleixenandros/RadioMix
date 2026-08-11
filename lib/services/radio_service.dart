import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/radio_station.dart';
import 'app_http_client.dart';
import 'app_network_error.dart';
import 'app_preferences.dart';
import 'providers/radio_browser_provider.dart';
import 'providers/radio_garden_provider.dart';
import 'providers/radio_search_provider.dart';
import 'providers/shoutcast_provider.dart';

class ActiveRadioProviderNotifier extends Notifier<String> {
  @override
  String build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    final value = prefs?.getString(AppPreferenceKeys.activeRadioProvider);
    if (value != null) return value;
    _load();
    return 'radio_browser';
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(AppPreferenceKeys.activeRadioProvider);
    if (value != null) state = value;
  }

  Future<void> setProvider(String id) async {
    state = id;
    final prefs = await readSharedPreferences(ref);
    await prefs.setString(AppPreferenceKeys.activeRadioProvider, id);
  }
}

final activeRadioProviderIdProvider =
    NotifierProvider<ActiveRadioProviderNotifier, String>(
  ActiveRadioProviderNotifier.new,
);

class ShoutcastApiKeyNotifier extends Notifier<String> {
  @override
  String build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    if (prefs != null) {
      return prefs.getString(AppPreferenceKeys.shoutcastApiKey) ?? '';
    }
    _load();
    return '';
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getString(AppPreferenceKeys.shoutcastApiKey) ?? '';
  }

  Future<void> setKey(String key) async {
    state = key;
    final prefs = await readSharedPreferences(ref);
    await prefs.setString(AppPreferenceKeys.shoutcastApiKey, key);
  }
}

final shoutcastApiKeyProvider =
    NotifierProvider<ShoutcastApiKeyNotifier, String>(
  ShoutcastApiKeyNotifier.new,
);

final activeRadioSearchProvider = Provider<RadioSearchProvider>((ref) {
  final id = ref.watch(activeRadioProviderIdProvider);
  final shoutcastKey = ref.watch(shoutcastApiKeyProvider);
  final httpClient = ref.watch(httpClientProvider);

  return switch (id) {
    'shoutcast' =>
      ShoutcastProvider(apiKey: shoutcastKey, httpClient: httpClient),
    'radio_garden' => RadioGardenProvider(httpClient: httpClient),
    _ => RadioBrowserProvider(httpClient: httpClient),
  };
});

final radioServiceProvider = Provider(
  (ref) => RadioService(
    httpClient: ref.watch(httpClientProvider),
    preferencesFactory: sharedPreferencesFactory(ref),
  ),
);

final favoriteStationsProvider = FutureProvider<List<RadioStation>>((ref) {
  return ref.watch(radioServiceProvider).getFavorites();
});

final radioSearchResultsProvider =
    FutureProvider.autoDispose.family<List<RadioStation>, String>(
  (ref, query) async {
    final trimmedQuery = query.trim();
    if (trimmedQuery.length < 3) return [];

    final stations =
        await ref.watch(activeRadioSearchProvider).searchStations(trimmedQuery);

    final favorites = await ref.read(radioServiceProvider).getFavorites();
    final favoriteIds = favorites.map((f) => f.id).toSet();
    for (final station in stations) {
      station.isFavorite = favoriteIds.contains(station.id);
    }

    return stations;
  },
);

class RadioService {
  RadioService({
    http.Client? httpClient,
    SharedPreferencesFactory? preferencesFactory,
  })  : _httpClient = httpClient ?? http.Client(),
        _preferencesFactory =
            preferencesFactory ?? SharedPreferences.getInstance;

  final http.Client _httpClient;
  final SharedPreferencesFactory _preferencesFactory;

  Future<SharedPreferences> _prefs() => _preferencesFactory();

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
        final stations =
            data.map((json) => RadioStation.fromJson(json)).toList();

        final favorites = await getFavorites();
        final favoriteIds = favorites.map((f) => f.id).toSet();
        for (final station in stations) {
          station.isFavorite = favoriteIds.contains(station.id);
        }

        return stations;
      }
      return [];
    } catch (error, stackTrace) {
      logAndRethrowAppError(
        'radio',
        'Fallo al buscar estaciones',
        error,
        stackTrace,
      );
    }
  }

  Future<List<RadioStation>> getPopularStations() async {
    try {
      final response = await appGet(
        _httpClient,
        Uri.https('de1.api.radio-browser.info', '/json/stations/topvote/10'),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as List<dynamic>;
        return data.map((json) => RadioStation.fromJson(json)).toList();
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  Future<void> addFavorite(RadioStation station) async {
    final prefs = await _prefs();
    final favorites = await getFavorites();

    if (!favorites.any((f) => f.id == station.id)) {
      favorites.add(station);
      await prefs.setString(
        AppPreferenceKeys.favoriteStations,
        json.encode(favorites.map((s) => s.toJson()).toList()),
      );
    }
  }

  Future<void> removeFavorite(String stationId) async {
    final prefs = await _prefs();
    final favorites = await getFavorites();
    favorites.removeWhere((f) => f.id == stationId);

    await prefs.setString(
      AppPreferenceKeys.favoriteStations,
      json.encode(favorites.map((s) => s.toJson()).toList()),
    );
  }

  Future<List<RadioStation>> getFavorites() async {
    final prefs = await _prefs();
    final data = prefs.getString(AppPreferenceKeys.favoriteStations);

    if (data != null) {
      final jsonList = json.decode(data) as List<dynamic>;
      return jsonList.map((json) => RadioStation.fromJson(json)).toList();
    }
    return [];
  }

  Future<bool> isFavorite(String stationId) async {
    final favorites = await getFavorites();
    return favorites.any((f) => f.id == stationId);
  }
}
