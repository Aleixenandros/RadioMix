import 'dart:convert';

import 'package:xml/xml.dart';

import 'podcast.dart';
import 'radio_station.dart';

class BackupData {
  static const String rootElementName = 'radioMixBackup';

  final List<RadioStation> favoriteStations;
  final List<Podcast> subscribedPodcasts;
  final List<Map<String, dynamic>> playbackProgress;
  final Map<String, dynamic> userPreferences;
  final List<Map<String, dynamic>> downloadMetadata;
  final DateTime timestamp;

  BackupData({
    required this.favoriteStations,
    required this.subscribedPodcasts,
    required this.playbackProgress,
    this.userPreferences = const {},
    this.downloadMetadata = const [],
    required this.timestamp,
  });

  Map<String, dynamic> toJson() {
    return {
      'version': '1.0',
      'timestamp': timestamp.toIso8601String(),
      'favoriteStations': favoriteStations.map((s) => s.toJson()).toList(),
      'subscribedPodcasts': subscribedPodcasts.map((p) => p.toJson()).toList(),
      'playbackProgress': playbackProgress,
      'userPreferences': userPreferences,
      'downloadMetadata': downloadMetadata,
    };
  }

  factory BackupData.fromJson(Map<String, dynamic> json) {
    return BackupData(
      favoriteStations: ((json['favoriteStations'] as List?) ?? const [])
          .map((s) => RadioStation.fromJson(Map<String, dynamic>.from(s)))
          .toList(),
      subscribedPodcasts: ((json['subscribedPodcasts'] as List?) ?? const [])
          .map((p) => Podcast.fromJson(Map<String, dynamic>.from(p)))
          .toList(),
      playbackProgress: ((json['playbackProgress'] as List?) ?? const [])
          .map((p) => Map<String, dynamic>.from(p))
          .toList(),
      userPreferences: Map<String, dynamic>.from(
        (json['userPreferences'] as Map?) ?? const {},
      ),
      downloadMetadata: ((json['downloadMetadata'] as List?) ?? const [])
          .map((item) => Map<String, dynamic>.from(item))
          .toList(),
      timestamp: DateTime.tryParse(json['timestamp']?.toString() ?? '') ??
          DateTime.now(),
    );
  }

  String toXmlString() {
    final builder = XmlBuilder();

    builder.processing('xml', 'version="1.0" encoding="UTF-8"');
    builder.element(
      rootElementName,
      nest: () {
        builder.attribute('version', '2.0');
        builder.attribute('timestamp', timestamp.toIso8601String());

        builder.element(
          'favoriteStations',
          nest: () {
            for (final station in favoriteStations) {
              builder.element(
                'station',
                nest: () {
                  builder.element('id', nest: station.id);
                  builder.element('name', nest: station.name);
                  builder.element('streamUrl', nest: station.streamUrl);
                  builder.element('favicon', nest: station.favicon ?? '');
                  builder.element('country', nest: station.country ?? '');
                  builder.element('language', nest: station.language ?? '');
                  builder.element(
                    'bitrate',
                    nest: station.bitrate?.toString() ?? '',
                  );
                  builder.element(
                    'tags',
                    nest: () {
                      for (final tag in station.tags) {
                        builder.element('tag', nest: tag);
                      }
                    },
                  );
                },
              );
            }
          },
        );

        builder.element(
          'subscribedPodcasts',
          nest: () {
            for (final podcast in subscribedPodcasts) {
              builder.element(
                'podcast',
                nest: () {
                  builder.element('id', nest: podcast.id);
                  builder.element('title', nest: podcast.title);
                  builder.element('artist', nest: podcast.artist);
                  builder.element('artworkUrl', nest: podcast.artworkUrl ?? '');
                  builder.element('feedUrl', nest: podcast.feedUrl ?? '');
                  builder.element('description',
                      nest: podcast.description ?? '');
                  builder.element('genre', nest: podcast.genre ?? '');
                  builder.element(
                    'trackCount',
                    nest: podcast.trackCount?.toString() ?? '',
                  );
                  builder.element(
                    'releaseDate',
                    nest: podcast.releaseDate?.toIso8601String() ?? '',
                  );
                },
              );
            }
          },
        );

        builder.element(
          'playbackProgress',
          nest: () {
            for (final progress in playbackProgress) {
              builder.element(
                'progress',
                nest: () {
                  builder.element(
                    'stationId',
                    nest: progress['stationId']?.toString() ?? '',
                  );
                  builder.element(
                    'position',
                    nest: progress['position']?.toString() ?? '0',
                  );
                  builder.element(
                    'duration',
                    nest: progress['duration']?.toString() ?? '',
                  );
                  builder.element(
                    'lastPlayed',
                    nest: progress['lastPlayed']?.toString() ?? '',
                  );
                },
              );
            }
          },
        );

        builder.element(
          'userPreferences',
          nest: () {
            for (final entry in userPreferences.entries) {
              builder.element(
                'preference',
                nest: () {
                  builder.element('key', nest: entry.key);
                  builder.element('value', nest: entry.value?.toString() ?? '');
                },
              );
            }
          },
        );

        builder.element(
          'downloadMetadata',
          nest: () {
            for (final download in downloadMetadata) {
              builder.element(
                'download',
                nest: () {
                  for (final entry in download.entries) {
                    builder.element(entry.key,
                        nest: entry.value?.toString() ?? '');
                  }
                },
              );
            }
          },
        );
      },
    );

    return builder.buildDocument().toXmlString(pretty: true);
  }

  factory BackupData.fromXmlString(String xmlContent) {
    final document = XmlDocument.parse(xmlContent);
    final root = document.rootElement;

    if (root.name.local != rootElementName) {
      throw const FormatException('Formato XML de backup no valido');
    }

    final stationElements = root
        .findElements('favoriteStations')
        .expand((group) => group.findElements('station'));
    final podcastElements = root
        .findElements('subscribedPodcasts')
        .expand((group) => group.findElements('podcast'));
    final progressElements = root
        .findElements('playbackProgress')
        .expand((group) => group.findElements('progress'));
    final preferenceElements = root
        .findElements('userPreferences')
        .expand((group) => group.findElements('preference'));
    final downloadElements = root
        .findElements('downloadMetadata')
        .expand((group) => group.findElements('download'));

    return BackupData(
      favoriteStations: stationElements.map((stationElement) {
        final name = _elementText(stationElement, 'name');
        final streamUrl = _elementText(stationElement, 'streamUrl');
        return RadioStation(
          id: _elementText(stationElement, 'id'),
          name: name.isEmpty ? 'Sin nombre' : name,
          streamUrl: streamUrl,
          favicon: _nullableText(_elementText(stationElement, 'favicon')),
          country: _nullableText(_elementText(stationElement, 'country')),
          language: _nullableText(_elementText(stationElement, 'language')),
          bitrate: double.tryParse(_elementText(stationElement, 'bitrate')),
          tags: stationElement
              .findElements('tags')
              .expand((tagGroup) => tagGroup.findElements('tag'))
              .map((tagElement) => tagElement.innerText.trim())
              .where((tag) => tag.isNotEmpty)
              .toList(),
        );
      }).toList(),
      subscribedPodcasts: podcastElements.map((podcastElement) {
        final title = _elementText(podcastElement, 'title');
        final artist = _elementText(podcastElement, 'artist');
        return Podcast(
          id: _elementText(podcastElement, 'id'),
          title: title.isEmpty ? 'Sin título' : title,
          artist: artist.isEmpty ? 'Desconocido' : artist,
          artworkUrl: _nullableText(_elementText(podcastElement, 'artworkUrl')),
          feedUrl: _nullableText(_elementText(podcastElement, 'feedUrl')),
          description:
              _nullableText(_elementText(podcastElement, 'description')),
          genre: _nullableText(_elementText(podcastElement, 'genre')),
          trackCount: int.tryParse(_elementText(podcastElement, 'trackCount')),
          releaseDate:
              DateTime.tryParse(_elementText(podcastElement, 'releaseDate')),
        );
      }).toList(),
      playbackProgress: progressElements.map((progressElement) {
        final durationText = _elementText(progressElement, 'duration');
        final lastPlayedText = _elementText(progressElement, 'lastPlayed');
        return {
          'stationId': _elementText(progressElement, 'stationId'),
          'position':
              int.tryParse(_elementText(progressElement, 'position')) ?? 0,
          'duration': durationText.isEmpty ? null : int.tryParse(durationText),
          'lastPlayed': lastPlayedText.isEmpty
              ? DateTime.now().toIso8601String()
              : lastPlayedText,
        };
      }).toList(),
      userPreferences: {
        for (final preferenceElement in preferenceElements)
          if (_elementText(preferenceElement, 'key').isNotEmpty)
            _elementText(preferenceElement, 'key'):
                _coerceScalar(_elementText(preferenceElement, 'value')),
      },
      downloadMetadata: downloadElements.map((downloadElement) {
        return {
          for (final child in downloadElement.childElements)
            child.name.local: _coerceScalar(child.innerText),
        };
      }).toList(),
      timestamp: DateTime.tryParse(root.getAttribute('timestamp') ?? '') ??
          DateTime.now(),
    );
  }

  factory BackupData.fromContent(String content) {
    final trimmed = content.trimLeft();
    if (trimmed.startsWith('<')) {
      return BackupData.fromXmlString(content);
    }
    return BackupData.fromJson(Map<String, dynamic>.from(jsonDecode(content)));
  }

  static String _elementText(XmlElement parent, String name) {
    return parent.getElement(name)?.innerText ?? '';
  }

  static String? _nullableText(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static dynamic _coerceScalar(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return '';
    final intValue = int.tryParse(trimmed);
    if (intValue != null) return intValue;
    return trimmed;
  }
}
