class RadioStation {
  final String id;
  final String name;
  final String streamUrl;
  final String? favicon;
  final String? country;
  final String? language;
  final List<String> tags;
  final double? bitrate;
  bool isFavorite;

  RadioStation({
    required this.id,
    required this.name,
    required this.streamUrl,
    this.favicon,
    this.country,
    this.language,
    this.tags = const [],
    this.bitrate,
    this.isFavorite = false,
  });

  factory RadioStation.fromJson(Map<String, dynamic> json) {
    return RadioStation(
      id: json['stationuuid'] ?? '',
      name: json['name'] ?? 'Sin nombre',
      streamUrl: json['url_resolved'] ?? json['url'] ?? '',
      favicon: json['favicon']?.toString().isNotEmpty == true
          ? json['favicon']
          : null,
      country: json['country'],
      language: json['language'],
      tags:
          json['tags']
              ?.toString()
              .split(',')
              .where((t) => t.isNotEmpty)
              .toList() ??
          [],
      bitrate: json['bitrate'] != null
          ? (json['bitrate'] as num).toDouble()
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'stationuuid': id,
      'name': name,
      'url_resolved': streamUrl,
      'favicon': favicon,
      'country': country,
      'language': language,
      'tags': tags.join(','),
      'bitrate': bitrate,
    };
  }

  RadioStation copyWith({
    String? id,
    String? name,
    String? streamUrl,
    String? favicon,
    String? country,
    String? language,
    List<String>? tags,
    double? bitrate,
    bool? isFavorite,
  }) {
    return RadioStation(
      id: id ?? this.id,
      name: name ?? this.name,
      streamUrl: streamUrl ?? this.streamUrl,
      favicon: favicon ?? this.favicon,
      country: country ?? this.country,
      language: language ?? this.language,
      tags: tags ?? this.tags,
      bitrate: bitrate ?? this.bitrate,
      isFavorite: isFavorite ?? this.isFavorite,
    );
  }
}

class FMFrequency {
  final double frequency;
  final String? stationName;
  final bool isStrongSignal;

  FMFrequency({
    required this.frequency,
    this.stationName,
    this.isStrongSignal = false,
  });
}
