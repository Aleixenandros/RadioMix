import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app_preferences.dart';

final playbackProgressServiceProvider = Provider(
  (ref) => PlaybackProgressService(
    preferencesFactory: sharedPreferencesFactory(ref),
  ),
);

final playbackProgressEntriesProvider =
    FutureProvider<List<PlaybackProgress>>((ref) {
  return ref.watch(playbackProgressServiceProvider).getAllProgress();
});

final playbackProgressByItemProvider =
    FutureProvider.family<PlaybackProgress?, String>((ref, itemId) {
  return ref.watch(playbackProgressServiceProvider).getProgress(itemId);
});

class PlaybackProgress {
  final String stationId;
  final Duration position;
  final Duration? duration;
  final DateTime lastPlayed;

  PlaybackProgress({
    required this.stationId,
    required this.position,
    this.duration,
    required this.lastPlayed,
  });

  Map<String, dynamic> toJson() {
    return {
      'stationId': stationId,
      'position': position.inSeconds,
      'duration': duration?.inSeconds,
      'lastPlayed': lastPlayed.toIso8601String(),
    };
  }

  factory PlaybackProgress.fromJson(Map<String, dynamic> json) {
    return PlaybackProgress(
      stationId: json['stationId'],
      position: Duration(seconds: json['position']),
      duration:
          json['duration'] != null ? Duration(seconds: json['duration']) : null,
      lastPlayed: DateTime.parse(json['lastPlayed']),
    );
  }
}

class PlaybackProgressService {
  PlaybackProgressService({SharedPreferencesFactory? preferencesFactory})
      : _preferencesFactory =
            preferencesFactory ?? SharedPreferences.getInstance;

  final SharedPreferencesFactory _preferencesFactory;

  Future<SharedPreferences> _prefs() => _preferencesFactory();

  Future<void> saveProgress(
      String stationId, Duration position, Duration? duration) async {
    final prefs = await _prefs();
    final progress = PlaybackProgress(
      stationId: stationId,
      position: position,
      duration: duration,
      lastPlayed: DateTime.now(),
    );

    await prefs.setString(
      AppPreferenceKeys.playbackProgress(stationId),
      json.encode(progress.toJson()),
    );
  }

  Future<PlaybackProgress?> getProgress(String stationId) async {
    final prefs = await _prefs();
    final String? data =
        prefs.getString(AppPreferenceKeys.playbackProgress(stationId));

    if (data != null) {
      return PlaybackProgress.fromJson(json.decode(data));
    }
    return null;
  }

  Future<void> clearProgress(String stationId) async {
    final prefs = await _prefs();
    await prefs.remove(AppPreferenceKeys.playbackProgress(stationId));
  }

  Future<List<PlaybackProgress>> getAllProgress() async {
    final prefs = await _prefs();
    final keys = prefs.getKeys().where(
        (key) => key.startsWith(AppPreferenceKeys.playbackProgressPrefix));

    final List<PlaybackProgress> progressList = [];
    for (final key in keys) {
      final String? data = prefs.getString(key);
      if (data != null) {
        progressList.add(PlaybackProgress.fromJson(json.decode(data)));
      }
    }

    // Ordenar por última reproducción
    progressList.sort((a, b) => b.lastPlayed.compareTo(a.lastPlayed));
    return progressList;
  }
}
