import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xml/xml.dart';

import '../models/podcast.dart';
import '../models/podcast_episode.dart';
import 'app_http_client.dart';
import 'app_network_error.dart';
import 'app_preferences.dart';
import 'providers/gpodder_provider.dart';
import 'providers/itunes_provider.dart';
import 'providers/podcast_index_provider.dart';
import 'providers/podcast_search_provider.dart';

class ActivePodcastProviderNotifier extends Notifier<String> {
  @override
  String build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    final value = prefs?.getString(AppPreferenceKeys.activePodcastProvider);
    if (value != null) return value;
    _load();
    return 'itunes';
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(AppPreferenceKeys.activePodcastProvider);
    if (value != null) state = value;
  }

  Future<void> setProvider(String id) async {
    state = id;
    final prefs = await readSharedPreferences(ref);
    await prefs.setString(AppPreferenceKeys.activePodcastProvider, id);
  }
}

final activePodcastProviderIdProvider =
    NotifierProvider<ActivePodcastProviderNotifier, String>(
  ActivePodcastProviderNotifier.new,
);

class PodcastIndexApiKeyNotifier extends Notifier<String> {
  @override
  String build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    if (prefs != null) {
      return prefs.getString(AppPreferenceKeys.podcastIndexApiKey) ?? '';
    }
    _load();
    return '';
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getString(AppPreferenceKeys.podcastIndexApiKey) ?? '';
  }

  Future<void> setKey(String key) async {
    state = key;
    final prefs = await readSharedPreferences(ref);
    await prefs.setString(AppPreferenceKeys.podcastIndexApiKey, key);
  }
}

final podcastIndexApiKeyProvider =
    NotifierProvider<PodcastIndexApiKeyNotifier, String>(
  PodcastIndexApiKeyNotifier.new,
);

class PodcastIndexApiSecretNotifier extends Notifier<String> {
  @override
  String build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    if (prefs != null) {
      return prefs.getString(AppPreferenceKeys.podcastIndexApiSecret) ?? '';
    }
    _load();
    return '';
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getString(AppPreferenceKeys.podcastIndexApiSecret) ?? '';
  }

  Future<void> setKey(String key) async {
    state = key;
    final prefs = await readSharedPreferences(ref);
    await prefs.setString(AppPreferenceKeys.podcastIndexApiSecret, key);
  }
}

final podcastIndexApiSecretProvider =
    NotifierProvider<PodcastIndexApiSecretNotifier, String>(
  PodcastIndexApiSecretNotifier.new,
);

final activePodcastSearchProvider = Provider<PodcastSearchProvider>((ref) {
  final id = ref.watch(activePodcastProviderIdProvider);
  final piKey = ref.watch(podcastIndexApiKeyProvider);
  final piSecret = ref.watch(podcastIndexApiSecretProvider);
  final httpClient = ref.watch(httpClientProvider);

  return switch (id) {
    'podcast_index' => PodcastIndexProvider(
        apiKey: piKey,
        apiSecret: piSecret,
        httpClient: httpClient,
      ),
    'gpodder' => GPodderProvider(httpClient: httpClient),
    _ => ItunesProvider(httpClient: httpClient),
  };
});

final podcastServiceProvider = Provider(
  (ref) => PodcastService(httpClient: ref.watch(httpClientProvider)),
);

final podcastSearchResultsProvider =
    FutureProvider.autoDispose.family<List<Podcast>, String>((ref, query) {
  final trimmedQuery = query.trim();
  if (trimmedQuery.length < 3) return [];
  return ref.watch(activePodcastSearchProvider).searchPodcasts(trimmedQuery);
});

final podcastEpisodesProvider =
    FutureProvider.autoDispose.family<List<PodcastEpisode>, String>(
  (ref, feedUrl) {
    final trimmedFeedUrl = feedUrl.trim();
    if (trimmedFeedUrl.isEmpty) {
      return [];
    }
    return ref.watch(podcastServiceProvider).getEpisodes(trimmedFeedUrl);
  },
);

class PodcastService {
  PodcastService({http.Client? httpClient})
      : _httpClient = httpClient ?? http.Client();

  final http.Client _httpClient;

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
        return results.map((json) => Podcast.fromJson(json)).toList();
      }
      return [];
    } catch (error, stackTrace) {
      logAndRethrowAppError(
        'podcast',
        'Fallo al buscar podcasts',
        error,
        stackTrace,
      );
    }
  }

  Future<List<PodcastEpisode>> getEpisodes(String feedUrl) async {
    if (feedUrl.isEmpty) return [];

    try {
      final uri = Uri.tryParse(feedUrl);
      if (uri == null || !uri.hasScheme) {
        throw const FormatException('Feed URL no valido');
      }

      final response = await appGet(
        _httpClient,
        uri,
        headers: const {
          'Accept':
              'application/rss+xml, application/xml, text/xml;q=0.9, */*;q=0.8',
        },
      );

      if (response.statusCode != 200) {
        return [];
      }

      final xmlContent = utf8.decode(response.bodyBytes, allowMalformed: true);
      final document = XmlDocument.parse(xmlContent);
      final channel = _firstDescendantByLocalName(document, 'channel');
      final feedArtworkUrl = _extractFeedArtwork(channel);
      final episodes = <PodcastEpisode>[];

      for (final element in document.descendants.whereType<XmlElement>()) {
        if (!_matchesLocalName(element, const ['item', 'entry'])) {
          continue;
        }

        final episode = _episodeFromElement(element, feedArtworkUrl);
        if (episode != null) {
          episodes.add(episode);
        }
      }

      return episodes;
    } catch (error, stackTrace) {
      logAndRethrowAppError(
        'podcast',
        'Fallo al procesar feed RSS',
        error,
        stackTrace,
      );
    }
  }

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
        return results.map((json) => Podcast.fromJson(json)).toList();
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  PodcastEpisode? _episodeFromElement(XmlElement item, String? feedArtworkUrl) {
    final title =
        _firstNonEmptyChildText(item, const ['title']) ?? 'Sin titulo';
    final description = _firstNonEmptyChildText(
      item,
      const ['summary', 'encoded', 'description', 'subtitle'],
    );
    final audioUrl = _extractAudioUrl(item);
    if (audioUrl == null || audioUrl.isEmpty) {
      return null;
    }

    final pubDateText = _firstNonEmptyChildText(
      item,
      const ['pubdate', 'published', 'updated', 'date'],
    );
    final publishDate = pubDateText != null ? _parseDate(pubDateText) : null;

    return PodcastEpisode(
      id: audioUrl,
      title: title,
      description: description,
      audioUrl: audioUrl,
      duration: _parseDuration(
        _firstNonEmptyChildText(item, const ['duration']),
      ),
      publishDate: publishDate,
      artworkUrl: _extractEpisodeArtwork(item) ?? feedArtworkUrl,
    );
  }

  Duration? _parseDuration(String? duration) {
    if (duration == null || duration.isEmpty) return null;

    try {
      final parts = duration.trim().split(':');
      if (parts.length == 3) {
        return Duration(
          hours: int.parse(parts[0]),
          minutes: int.parse(parts[1]),
          seconds: int.parse(parts[2]),
        );
      }
      if (parts.length == 2) {
        return Duration(
          minutes: int.parse(parts[0]),
          seconds: int.parse(parts[1]),
        );
      }
      if (parts.length == 1) {
        return Duration(seconds: int.parse(parts[0]));
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  DateTime? _parseDate(String dateStr) {
    final trimmed = dateStr.trim();
    if (trimmed.isEmpty) return null;

    final direct = DateTime.tryParse(trimmed);
    if (direct != null) {
      return direct;
    }

    final timestamp = int.tryParse(trimmed);
    if (timestamp != null) {
      final milliseconds = trimmed.length >= 13 ? timestamp : timestamp * 1000;
      return DateTime.fromMillisecondsSinceEpoch(milliseconds);
    }

    try {
      return HttpDate.parse(trimmed);
    } catch (_) {
      return null;
    }
  }

  String? _extractAudioUrl(XmlElement item) {
    for (final child in item.childElements) {
      if (_matchesLocalName(child, const ['enclosure'])) {
        final url = _firstNonEmptyAttribute(child, const ['url', 'href']);
        if (url != null && _looksLikeAudio(child, url)) {
          return url;
        }
      }

      if (_matchesLocalName(child, const ['link'])) {
        final rel = _firstNonEmptyAttribute(child, const ['rel']);
        final url = _firstNonEmptyAttribute(child, const ['href', 'url']);
        if (rel == 'enclosure' && url != null && _looksLikeAudio(child, url)) {
          return url;
        }
      }

      if (_matchesLocalName(child, const ['content'])) {
        final url = _firstNonEmptyAttribute(child, const ['url', 'href']);
        final medium = _firstNonEmptyAttribute(child, const ['medium']);
        if (url != null && (medium == 'audio' || _looksLikeAudio(child, url))) {
          return url;
        }
      }
    }

    return null;
  }

  String? _extractEpisodeArtwork(XmlElement item) {
    for (final child in item.childElements) {
      if (_matchesLocalName(child, const ['image'])) {
        final url = _firstNonEmptyAttribute(child, const ['href', 'url']);
        if (url != null) {
          return url;
        }
      }

      if (_matchesLocalName(child, const ['thumbnail', 'content'])) {
        final medium = _firstNonEmptyAttribute(child, const ['medium']);
        final url = _firstNonEmptyAttribute(child, const ['url', 'href']);
        if (url != null && (medium == null || medium == 'image')) {
          return url;
        }
      }
    }

    return null;
  }

  String? _extractFeedArtwork(XmlElement? channel) {
    if (channel == null) {
      return null;
    }

    for (final child in channel.childElements) {
      if (!_matchesLocalName(child, const ['image'])) {
        continue;
      }

      final directUrl = _firstNonEmptyAttribute(child, const ['href', 'url']);
      if (directUrl != null) {
        return directUrl;
      }

      final nestedUrl = _firstNonEmptyChildText(child, const ['url']);
      if (nestedUrl != null) {
        return nestedUrl;
      }
    }

    return null;
  }

  XmlElement? _firstDescendantByLocalName(XmlNode node, String localName) {
    final expected = localName.toLowerCase();
    for (final element in node.descendants.whereType<XmlElement>()) {
      if (element.name.local.toLowerCase() == expected) {
        return element;
      }
    }
    return null;
  }

  String? _firstNonEmptyChildText(
    XmlElement element,
    Iterable<String> localNames,
  ) {
    for (final child in element.childElements) {
      if (!_matchesLocalName(child, localNames)) {
        continue;
      }

      final value = child.innerText.trim();
      if (value.isNotEmpty) {
        return value;
      }
    }
    return null;
  }

  String? _firstNonEmptyAttribute(
    XmlElement element,
    Iterable<String> localNames,
  ) {
    final expected = localNames.map((name) => name.toLowerCase()).toSet();
    for (final attribute in element.attributes) {
      if (!expected.contains(attribute.name.local.toLowerCase())) {
        continue;
      }

      final value = attribute.value.trim();
      if (value.isNotEmpty) {
        return value;
      }
    }
    return null;
  }

  bool _matchesLocalName(XmlElement element, Iterable<String> localNames) {
    final current = element.name.local.toLowerCase();
    for (final name in localNames) {
      if (current == name.toLowerCase()) {
        return true;
      }
    }
    return false;
  }

  bool _looksLikeAudio(XmlElement element, String url) {
    final type = _firstNonEmptyAttribute(element, const ['type']);
    if (type != null && type.toLowerCase().startsWith('audio/')) {
      return true;
    }

    return _looksLikeAudioUrl(url);
  }

  bool _looksLikeAudioUrl(String url) {
    final lower = url.toLowerCase();
    return lower.contains('.mp3') ||
        lower.contains('.m4a') ||
        lower.contains('.aac') ||
        lower.contains('.ogg') ||
        lower.contains('.wav') ||
        lower.contains('.mp4');
  }
}
