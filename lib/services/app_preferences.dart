import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppPreferenceKeys {
  const AppPreferenceKeys._();

  static const themeMode = 'theme_mode';
  static const favoriteStations = 'favorite_stations';
  static const podcastSubscriptions = 'podcast_subscriptions';
  static const podcastDownloads = 'podcast_downloads';
  static const audioBufferSeconds = 'audio_buffer_seconds';
  static const recentStations = 'recent_stations';
  static const playbackProgressPrefix = 'playback_progress';
  static const activeRadioProvider = 'active_radio_provider';
  static const activePodcastProvider = 'active_podcast_provider';
  static const shoutcastApiKey = 'shoutcast_api_key';
  static const podcastIndexApiKey = 'podcast_index_api_key';
  static const podcastIndexApiSecret = 'podcast_index_api_secret';

  static String playbackProgress(String itemId) =>
      '${playbackProgressPrefix}_$itemId';
}

typedef SharedPreferencesFactory = Future<SharedPreferences> Function();

final sharedPreferencesProvider = Provider<SharedPreferences?>((ref) => null);

Future<SharedPreferences> readSharedPreferences(Ref ref) async {
  return ref.read(sharedPreferencesProvider) ??
      await SharedPreferences.getInstance();
}

SharedPreferencesFactory sharedPreferencesFactory(Ref ref) {
  final prefs = ref.read(sharedPreferencesProvider);
  return () async => prefs ?? await SharedPreferences.getInstance();
}
