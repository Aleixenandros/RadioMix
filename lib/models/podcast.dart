class Podcast {
  final String id;
  final String title;
  final String artist;
  final String? artworkUrl;
  final String? feedUrl;
  final String? description;
  final String? genre;
  final int? trackCount;
  final DateTime? releaseDate;

  Podcast({
    required this.id,
    required this.title,
    required this.artist,
    this.artworkUrl,
    this.feedUrl,
    this.description,
    this.genre,
    this.trackCount,
    this.releaseDate,
  });

  factory Podcast.fromJson(Map<String, dynamic> json) {
    return Podcast(
      id: json['collectionId'].toString(),
      title: json['collectionName'] ?? 'Sin título',
      artist: json['artistName'] ?? 'Desconocido',
      artworkUrl: json['artworkUrl600'] ?? json['artworkUrl100'],
      feedUrl: json['feedUrl'],
      description: json['description'],
      genre: json['primaryGenreName'],
      trackCount: json['trackCount'],
      releaseDate: json['releaseDate'] != null
          ? DateTime.tryParse(json['releaseDate'])
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'collectionId': id,
      'collectionName': title,
      'artistName': artist,
      'artworkUrl600': artworkUrl,
      'feedUrl': feedUrl,
      'description': description,
      'primaryGenreName': genre,
      'trackCount': trackCount,
      'releaseDate': releaseDate?.toIso8601String(),
    };
  }
}
