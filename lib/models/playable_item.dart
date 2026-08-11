import 'podcast.dart';
import 'podcast_episode.dart';
import 'radio_station.dart';

enum PlayableItemKind { radio, podcast }

class PlayableItem {
  final String id;
  final String title;
  final String source;
  final String? artworkUrl;
  final String? subtitle;
  final List<String> tags;
  final PlayableItemKind kind;

  const PlayableItem({
    required this.id,
    required this.title,
    required this.source,
    this.artworkUrl,
    this.subtitle,
    this.tags = const [],
    required this.kind,
  });

  bool get isPodcast => kind == PlayableItemKind.podcast;

  bool get isRadio => kind == PlayableItemKind.radio;

  factory PlayableItem.fromJson(Map<String, dynamic> json) {
    if (json.containsKey('stationuuid') ||
        json.containsKey('url_resolved') ||
        json.containsKey('url')) {
      return PlayableItem.fromRadioStation(RadioStation.fromJson(json));
    }

    final rawTags = json['tags'];
    final tags = rawTags is List
        ? rawTags.map((tag) => tag.toString()).toList()
        : rawTags
                  ?.toString()
                  .split(',')
                  .where((tag) => tag.isNotEmpty)
                  .toList() ??
              const <String>[];
    final rawKind = json['kind']?.toString();
    final kind = rawKind == PlayableItemKind.podcast.name
        ? PlayableItemKind.podcast
        : rawKind == PlayableItemKind.radio.name
            ? PlayableItemKind.radio
            : (json['id']?.toString().startsWith('podcast_') == true ||
                    tags.contains('Podcast'))
                ? PlayableItemKind.podcast
                : PlayableItemKind.radio;

    return PlayableItem(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? 'Sin titulo',
      source: json['source']?.toString() ?? '',
      artworkUrl: json['artworkUrl']?.toString(),
      subtitle: json['subtitle']?.toString(),
      tags: tags,
      kind: kind,
    );
  }

  factory PlayableItem.fromRadioStation(RadioStation station) {
    final isPodcast =
        station.id.startsWith('podcast_') || station.tags.contains('Podcast');
    return PlayableItem(
      id: station.id,
      title: station.name,
      source: station.streamUrl,
      artworkUrl: station.favicon,
      subtitle: station.country,
      tags: station.tags,
      kind: isPodcast ? PlayableItemKind.podcast : PlayableItemKind.radio,
    );
  }

  factory PlayableItem.fromPodcastEpisode({
    required PodcastEpisode episode,
    required Podcast podcast,
    required String source,
    String? artworkUrl,
  }) {
    return PlayableItem(
      id: 'podcast_ep_${episode.id}',
      title: episode.title,
      source: source,
      artworkUrl: artworkUrl ?? episode.artworkUrl ?? podcast.artworkUrl,
      subtitle: podcast.title,
      tags: const ['Podcast'],
      kind: PlayableItemKind.podcast,
    );
  }

  RadioStation toRadioStation() {
    return RadioStation(
      id: id,
      name: title,
      streamUrl: source,
      favicon: artworkUrl,
      country: subtitle,
      tags: tags,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'source': source,
      'artworkUrl': artworkUrl,
      'subtitle': subtitle,
      'tags': tags,
      'kind': kind.name,
    };
  }
}
