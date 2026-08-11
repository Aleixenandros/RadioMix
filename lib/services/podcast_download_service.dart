import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_http_client.dart';
import 'app_network_error.dart';
import 'app_preferences.dart';

final podcastDownloadServiceProvider = Provider(
  (ref) => PodcastDownloadService(
    httpClient: ref.watch(httpClientProvider),
    preferencesFactory: sharedPreferencesFactory(ref),
  ),
);

final downloadedEpisodesProvider =
    FutureProvider<List<DownloadedEpisode>>((ref) {
  return ref.watch(podcastDownloadServiceProvider).getDownloads();
});

final totalDownloadSizeProvider = FutureProvider<int>((ref) {
  return ref.watch(podcastDownloadServiceProvider).getTotalDownloadSize();
});

class DownloadedEpisode {
  final String episodeId;
  final String podcastId;
  final String title;
  final String podcastTitle;
  final String audioUrl;
  final String? artworkUrl;
  final String localPath;
  final DateTime downloadedAt;
  final int fileSize;

  DownloadedEpisode({
    required this.episodeId,
    required this.podcastId,
    required this.title,
    required this.podcastTitle,
    required this.audioUrl,
    this.artworkUrl,
    required this.localPath,
    required this.downloadedAt,
    required this.fileSize,
  });

  Map<String, dynamic> toJson() {
    return {
      'episodeId': episodeId,
      'podcastId': podcastId,
      'title': title,
      'podcastTitle': podcastTitle,
      'audioUrl': audioUrl,
      'artworkUrl': artworkUrl,
      'localPath': localPath,
      'downloadedAt': downloadedAt.toIso8601String(),
      'fileSize': fileSize,
    };
  }

  factory DownloadedEpisode.fromJson(Map<String, dynamic> json) {
    return DownloadedEpisode(
      episodeId: json['episodeId'],
      podcastId: json['podcastId'],
      title: json['title'],
      podcastTitle: json['podcastTitle'],
      audioUrl: json['audioUrl'],
      artworkUrl: json['artworkUrl'],
      localPath: json['localPath'],
      downloadedAt: DateTime.parse(json['downloadedAt']),
      fileSize: json['fileSize'],
    );
  }
}

class PodcastDownloadService {
  PodcastDownloadService({
    http.Client? httpClient,
    SharedPreferencesFactory? preferencesFactory,
  })  : _httpClient = httpClient ?? http.Client(),
        _preferencesFactory =
            preferencesFactory ?? SharedPreferences.getInstance;

  final http.Client _httpClient;
  final SharedPreferencesFactory _preferencesFactory;
  final Set<String> _inProgress = {};

  Future<SharedPreferences> _prefs() => _preferencesFactory();

  Future<String> get _downloadPath async {
    final dir = await getApplicationDocumentsDirectory();
    final downloadDir = Directory('${dir.path}/podcasts');
    if (!await downloadDir.exists()) {
      await downloadDir.create(recursive: true);
    }
    return downloadDir.path;
  }

  Future<void> _saveDownloads(List<DownloadedEpisode> downloads) async {
    final prefs = await _prefs();
    await prefs.setString(
      AppPreferenceKeys.podcastDownloads,
      json.encode(downloads.map((d) => d.toJson()).toList()),
    );
  }

  Future<List<DownloadedEpisode>> getDownloads() async {
    final prefs = await _prefs();
    final data = prefs.getString(AppPreferenceKeys.podcastDownloads);

    if (data != null) {
      final jsonList = json.decode(data) as List<dynamic>;
      return jsonList.map((json) => DownloadedEpisode.fromJson(json)).toList();
    }
    return [];
  }

  Future<bool> isDownloaded(String episodeId) async {
    final downloads = await getDownloads();
    return downloads.any((d) => d.episodeId == episodeId);
  }

  Future<DownloadedEpisode?> downloadEpisode({
    required String episodeId,
    required String podcastId,
    required String title,
    required String podcastTitle,
    required String audioUrl,
    String? artworkUrl,
    Function(double)? onProgress,
  }) async {
    if (_inProgress.contains(episodeId) || await isDownloaded(episodeId)) {
      return null;
    }

    _inProgress.add(episodeId);
    File? partialFile;

    try {
      final request = http.Request('GET', Uri.parse(audioUrl));
      final response = await appSend(_httpClient, request);

      if (response.statusCode != 200) {
        throw Exception('Servidor devolvió ${response.statusCode}');
      }

      final path = await _downloadPath;
      final episodeHash = md5.convert(utf8.encode(episodeId)).toString();
      final fileName =
          '${episodeHash}_${DateTime.now().millisecondsSinceEpoch}.mp3';
      partialFile = File('$path/$fileName');

      final contentLength = response.contentLength ?? 0;
      var receivedBytes = 0;

      final sink = partialFile.openWrite();
      try {
        await for (final chunk in response.stream) {
          sink.add(chunk);
          receivedBytes += chunk.length;
          if (contentLength > 0 && onProgress != null) {
            onProgress(receivedBytes / contentLength);
          }
        }
      } finally {
        await sink.flush();
        await sink.close();
      }

      final fileSize = await partialFile.length();
      final episode = DownloadedEpisode(
        episodeId: episodeId,
        podcastId: podcastId,
        title: title,
        podcastTitle: podcastTitle,
        audioUrl: audioUrl,
        artworkUrl: artworkUrl,
        localPath: partialFile.path,
        downloadedAt: DateTime.now(),
        fileSize: fileSize,
      );

      final downloads = await getDownloads();
      if (!downloads.any((d) => d.episodeId == episodeId)) {
        downloads.add(episode);
        await _saveDownloads(downloads);
      }

      partialFile = null;
      return episode;
    } catch (error, stackTrace) {
      if (partialFile != null && await partialFile.exists()) {
        await partialFile.delete();
      }
      logAndRethrowAppError(
        'downloads',
        'Fallo al descargar episodio',
        error,
        stackTrace,
      );
    } finally {
      _inProgress.remove(episodeId);
    }
  }

  Future<void> deleteDownload(String episodeId) async {
    final downloads = await getDownloads();
    final download = downloads.firstWhere(
      (d) => d.episodeId == episodeId,
      orElse: () => throw Exception('Download not found'),
    );

    final file = File(download.localPath);
    if (await file.exists()) {
      await file.delete();
    }

    downloads.removeWhere((d) => d.episodeId == episodeId);
    await _saveDownloads(downloads);
  }

  Future<DownloadedEpisode?> getDownloadedEpisode(String episodeId) async {
    final downloads = await getDownloads();
    try {
      return downloads.firstWhere((d) => d.episodeId == episodeId);
    } catch (_) {
      return null;
    }
  }

  Future<String?> getLocalPath(String episodeId) async {
    final download = await getDownloadedEpisode(episodeId);
    return download?.localPath;
  }

  Future<void> deleteDownloadsByIds(List<String> episodeIds) async {
    for (final id in episodeIds) {
      await deleteDownload(id);
    }
  }

  Future<int> deleteOldDownloads(int daysOld) async {
    final downloads = await getDownloads();
    final oldIds = <String>[];

    for (final download in downloads) {
      if (DateTime.now().difference(download.downloadedAt).inDays > daysOld) {
        oldIds.add(download.episodeId);
      }
    }

    await deleteDownloadsByIds(oldIds);
    return oldIds.length;
  }

  Future<void> deleteAllDownloads() async {
    final downloads = await getDownloads();

    for (final download in downloads) {
      final file = File(download.localPath);
      if (await file.exists()) {
        await file.delete();
      }
    }

    final prefs = await _prefs();
    await prefs.remove(AppPreferenceKeys.podcastDownloads);
  }

  Future<int> getTotalDownloadSize() async {
    final downloads = await getDownloads();
    var total = 0;
    for (final download in downloads) {
      total += download.fileSize;
    }
    return total;
  }
}
