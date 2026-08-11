import 'package:flutter_test/flutter_test.dart';
import 'package:radio_mix/models/podcast.dart';
import 'package:radio_mix/models/radio_station.dart';
import 'package:radio_mix/services/podcast_subscription_service.dart';
import 'package:radio_mix/services/radio_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PodcastSubscriptionService', () {
    late PodcastSubscriptionService service;
    final podcast = Podcast(
      id: 'pod-1',
      title: 'RadioMix Daily',
      artist: 'RadioMix',
      feedUrl: 'https://example.com/feed.xml',
    );

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      service = PodcastSubscriptionService();
    });

    test('subscribe stores a podcast only once', () async {
      await service.subscribe(podcast);
      await service.subscribe(podcast);

      final subscriptions = await service.getSubscriptions();

      expect(subscriptions, hasLength(1));
      expect(subscriptions.single.id, podcast.id);
    });

    test('toggleSubscription subscribes and unsubscribes', () async {
      await service.toggleSubscription(podcast);
      expect(await service.isSubscribed(podcast.id), isTrue);

      await service.toggleSubscription(podcast);
      expect(await service.isSubscribed(podcast.id), isFalse);
    });
  });

  group('RadioService local favorites', () {
    late RadioService service;
    final station = RadioStation(
      id: 'station-1',
      name: 'RadioMix FM',
      streamUrl: 'https://example.com/live.mp3',
      country: 'ES',
    );

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      service = RadioService();
    });

    test('addFavorite stores a station only once', () async {
      await service.addFavorite(station);
      await service.addFavorite(station);

      final favorites = await service.getFavorites();

      expect(favorites, hasLength(1));
      expect(favorites.single.id, station.id);
    });

    test('removeFavorite deletes the station from favorites', () async {
      await service.addFavorite(station);

      await service.removeFavorite(station.id);

      expect(await service.getFavorites(), isEmpty);
      expect(await service.isFavorite(station.id), isFalse);
    });
  });
}
