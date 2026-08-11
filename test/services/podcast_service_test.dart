import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:radio_mix/services/podcast_service.dart';

void main() {
  group('PodcastService.getEpisodes', () {
    test('parsea RSS con namespaces y usa imagen de feed como fallback',
        () async {
      const rss = '''
<?xml version="1.0" encoding="UTF-8"?>
<rss xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd"
     xmlns:content="http://purl.org/rss/1.0/modules/content/">
  <channel>
    <title>Feed de prueba</title>
    <itunes:image href="https://cdn.example.com/feed.jpg" />
    <item>
      <title>Episodio 1</title>
      <itunes:summary><![CDATA[Resumen largo]]></itunes:summary>
      <pubDate>Fri, 07 Mar 2025 10:30:00 GMT</pubDate>
      <itunes:duration>01:02:03</itunes:duration>
      <enclosure url="https://cdn.example.com/audio-1.mp3" type="audio/mpeg" />
    </item>
    <item>
      <title>Episodio 2</title>
      <content:encoded><![CDATA[Contenido enriquecido]]></content:encoded>
      <pubDate>2025-03-08T12:15:00Z</pubDate>
      <content url="https://cdn.example.com/audio-2.m4a" medium="audio" />
      <itunes:image href="https://cdn.example.com/episode-2.jpg" />
    </item>
  </channel>
</rss>
''';

      final client = MockClient((request) async {
        expect(request.headers['User-Agent'], isNotEmpty);
        return http.Response(
          rss,
          200,
          headers: {'content-type': 'application/rss+xml; charset=utf-8'},
        );
      });

      final service = PodcastService(httpClient: client);
      final episodes =
          await service.getEpisodes('https://example.com/feed.xml');

      expect(episodes, hasLength(2));
      expect(episodes[0].id, 'https://cdn.example.com/audio-1.mp3');
      expect(episodes[0].description, 'Resumen largo');
      expect(
        episodes[0].duration,
        const Duration(hours: 1, minutes: 2, seconds: 3),
      );
      expect(
        episodes[0].publishDate?.toUtc().toIso8601String(),
        '2025-03-07T10:30:00.000Z',
      );
      expect(episodes[0].artworkUrl, 'https://cdn.example.com/feed.jpg');

      expect(episodes[1].id, 'https://cdn.example.com/audio-2.m4a');
      expect(episodes[1].description, 'Contenido enriquecido');
      expect(episodes[1].artworkUrl, 'https://cdn.example.com/episode-2.jpg');
    });

    test('omite entradas sin audio y soporta atom enclosure', () async {
      const atom = '''
<?xml version="1.0" encoding="utf-8"?>
<feed xmlns="http://www.w3.org/2005/Atom">
  <entry>
    <title>Sin audio</title>
    <updated>2025-03-09T08:00:00Z</updated>
  </entry>
  <entry>
    <title>Con audio</title>
    <updated>2025-03-09T08:05:00Z</updated>
    <link rel="enclosure" href="https://cdn.example.com/atom.mp3" type="audio/mpeg" />
  </entry>
</feed>
''';

      final client = MockClient(
        (_) async => http.Response(
          atom,
          200,
          headers: {'content-type': 'application/atom+xml'},
        ),
      );

      final service = PodcastService(httpClient: client);
      final episodes =
          await service.getEpisodes('https://example.com/atom.xml');

      expect(episodes, hasLength(1));
      expect(episodes.single.title, 'Con audio');
      expect(episodes.single.audioUrl, 'https://cdn.example.com/atom.mp3');
    });
  });
}
