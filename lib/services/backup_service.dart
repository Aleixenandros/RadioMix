import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/backup_data.dart';
import 'app_preferences.dart';
import 'playback_progress_service.dart';
import 'podcast_download_service.dart';
import 'podcast_subscription_service.dart';
import 'radio_service.dart';

final backupServiceProvider = Provider<BackupService>((ref) {
  return BackupService(
    radioService: ref.read(radioServiceProvider),
    podcastSubscriptionService: ref.read(podcastSubscriptionServiceProvider),
    playbackProgressService: ref.read(playbackProgressServiceProvider),
    podcastDownloadService: ref.read(podcastDownloadServiceProvider),
    preferencesFactory: sharedPreferencesFactory(ref),
  );
});

class BackupService {
  BackupService({
    required RadioService radioService,
    required PodcastSubscriptionService podcastSubscriptionService,
    required PlaybackProgressService playbackProgressService,
    PodcastDownloadService? podcastDownloadService,
    SharedPreferencesFactory? preferencesFactory,
  })  : _radioService = radioService,
        _podcastSubscriptionService = podcastSubscriptionService,
        _playbackProgressService = playbackProgressService,
        _podcastDownloadService = podcastDownloadService,
        _preferencesFactory =
            preferencesFactory ?? SharedPreferences.getInstance;

  final RadioService _radioService;
  final PodcastSubscriptionService _podcastSubscriptionService;
  final PlaybackProgressService _playbackProgressService;
  final PodcastDownloadService? _podcastDownloadService;
  final SharedPreferencesFactory _preferencesFactory;

  Future<SharedPreferences> _prefs() => _preferencesFactory();

  Future<BackupData> createBackupData() async {
    final stations = await _radioService.getFavorites();
    final podcasts = await _podcastSubscriptionService.getSubscriptions();
    final allProgress = await _playbackProgressService.getAllProgress();
    final prefs = await _prefs();

    return BackupData(
      favoriteStations: stations,
      subscribedPodcasts: podcasts,
      playbackProgress: allProgress.map((p) => p.toJson()).toList(),
      userPreferences: _collectUserPreferences(prefs),
      downloadMetadata: await _collectDownloadMetadata(),
      timestamp: DateTime.now(),
    );
  }

  Future<File> createBackupFile() async {
    final backup = await createBackupData();
    final tempDir = await getTemporaryDirectory();
    final fileName =
        'radiomix_backup_${_formatTimestamp(backup.timestamp)}.xml';
    final backupFile = File('${tempDir.path}/$fileName');
    await backupFile.writeAsString(backup.toXmlString(), flush: true);
    return backupFile;
  }

  Future<BackupData> loadBackupFromPath(String filePath) async {
    if (filePath.isEmpty) {
      throw const FormatException('No se pudo acceder al archivo seleccionado');
    }

    final file = File(filePath);
    final content = await file.readAsString();
    return BackupData.fromContent(content);
  }

  Future<void> restoreBackup(BackupData backup) async {
    final prefs = await _prefs();
    await prefs.remove(AppPreferenceKeys.favoriteStations);
    await prefs.remove(AppPreferenceKeys.podcastSubscriptions);
    final progressKeys = prefs
        .getKeys()
        .where(
            (key) => key.startsWith(AppPreferenceKeys.playbackProgressPrefix))
        .toList();
    for (final key in progressKeys) {
      await prefs.remove(key);
    }

    for (final station in backup.favoriteStations) {
      await _radioService.addFavorite(station);
    }

    for (final podcast in backup.subscribedPodcasts) {
      await _podcastSubscriptionService.subscribe(podcast);
    }

    for (final progressJson in backup.playbackProgress) {
      final progress = PlaybackProgress.fromJson(progressJson);
      await _playbackProgressService.saveProgress(
        progress.stationId,
        progress.position,
        progress.duration,
      );
    }

    await _restoreUserPreferences(prefs, backup.userPreferences);
  }

  Map<String, dynamic> _collectUserPreferences(SharedPreferences prefs) {
    final values = <String, dynamic>{};
    for (final key in _backupPreferenceKeys) {
      final value = prefs.get(key);
      if (value != null) {
        values[key] = value;
      }
    }
    return values;
  }

  Future<List<Map<String, dynamic>>> _collectDownloadMetadata() async {
    final service = _podcastDownloadService;
    if (service == null) return const [];
    final downloads = await service.getDownloads();
    return downloads.map((download) {
      final json = download.toJson();
      json.remove('localPath');
      return json;
    }).toList();
  }

  Future<void> _restoreUserPreferences(
    SharedPreferences prefs,
    Map<String, dynamic> preferences,
  ) async {
    for (final entry in preferences.entries) {
      if (!_backupPreferenceKeys.contains(entry.key)) continue;
      final value = entry.value;
      if (value == null) {
        await prefs.remove(entry.key);
      } else if (value is int) {
        await prefs.setInt(entry.key, value);
      } else if (value is bool) {
        await prefs.setBool(entry.key, value);
      } else {
        await prefs.setString(entry.key, value.toString());
      }
    }
  }

  static const _backupPreferenceKeys = {
    AppPreferenceKeys.themeMode,
    AppPreferenceKeys.audioBufferSeconds,
    AppPreferenceKeys.activeRadioProvider,
    AppPreferenceKeys.activePodcastProvider,
    AppPreferenceKeys.shoutcastApiKey,
    AppPreferenceKeys.podcastIndexApiKey,
    AppPreferenceKeys.podcastIndexApiSecret,
  };

  String _formatTimestamp(DateTime timestamp) {
    final year = timestamp.year.toString().padLeft(4, '0');
    final month = timestamp.month.toString().padLeft(2, '0');
    final day = timestamp.day.toString().padLeft(2, '0');
    final hour = timestamp.hour.toString().padLeft(2, '0');
    final minute = timestamp.minute.toString().padLeft(2, '0');
    final second = timestamp.second.toString().padLeft(2, '0');
    return '$year$month${day}_$hour$minute$second';
  }
}
