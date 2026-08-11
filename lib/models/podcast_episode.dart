class PodcastEpisode {
  final String id;
  final String title;
  final String? description;
  final String audioUrl;
  final Duration? duration;
  final DateTime? publishDate;
  final String? artworkUrl;

  PodcastEpisode({
    required this.id,
    required this.title,
    this.description,
    required this.audioUrl,
    this.duration,
    this.publishDate,
    this.artworkUrl,
  });

  factory PodcastEpisode.fromJson(Map<String, dynamic> json) {
    return PodcastEpisode(
      id: json['trackId']?.toString() ?? json['episodeGuid'] ?? '',
      title: json['trackName'] ?? json['title'] ?? 'Sin título',
      description: json['description'] ?? json['longDescription'],
      audioUrl: json['episodeUrl'] ?? json['previewUrl'] ?? '',
      duration: json['trackTimeMillis'] != null
          ? Duration(milliseconds: json['trackTimeMillis'])
          : null,
      publishDate: json['releaseDate'] != null
          ? DateTime.tryParse(json['releaseDate'])
          : null,
      artworkUrl: json['artworkUrl600'] ?? json['artworkUrl100'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'audioUrl': audioUrl,
      'duration': duration?.inSeconds,
      'publishDate': publishDate?.toIso8601String(),
      'artworkUrl': artworkUrl,
    };
  }
}
