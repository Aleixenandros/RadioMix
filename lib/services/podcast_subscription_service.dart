import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/podcast.dart';
import 'app_preferences.dart';

final podcastSubscriptionServiceProvider =
    Provider((ref) => PodcastSubscriptionService(
          preferencesFactory: sharedPreferencesFactory(ref),
        ));

final podcastSubscriptionsProvider = FutureProvider<List<Podcast>>((ref) {
  return ref.watch(podcastSubscriptionServiceProvider).getSubscriptions();
});

final podcastSubscriptionStateProvider =
    FutureProvider.family<bool, String>((ref, podcastId) {
  return ref.watch(podcastSubscriptionServiceProvider).isSubscribed(podcastId);
});

class PodcastSubscriptionService {
  PodcastSubscriptionService({SharedPreferencesFactory? preferencesFactory})
      : _preferencesFactory =
            preferencesFactory ?? SharedPreferences.getInstance;

  final SharedPreferencesFactory _preferencesFactory;

  Future<SharedPreferences> _prefs() => _preferencesFactory();

  /// Obtener lista de podcasts suscritos
  Future<List<Podcast>> getSubscriptions() async {
    final prefs = await _prefs();
    final String? data =
        prefs.getString(AppPreferenceKeys.podcastSubscriptions);

    if (data != null) {
      final List<dynamic> jsonList = json.decode(data);
      return jsonList.map((json) => Podcast.fromJson(json)).toList();
    }
    return [];
  }

  /// Suscribirse a un podcast
  Future<void> subscribe(Podcast podcast) async {
    final prefs = await _prefs();
    final subscriptions = await getSubscriptions();

    if (!subscriptions.any((p) => p.id == podcast.id)) {
      subscriptions.add(podcast);
      await prefs.setString(
        AppPreferenceKeys.podcastSubscriptions,
        json.encode(subscriptions.map((p) => p.toJson()).toList()),
      );
    }
  }

  /// Cancelar suscripción
  Future<void> unsubscribe(String podcastId) async {
    final prefs = await _prefs();
    final subscriptions = await getSubscriptions();
    subscriptions.removeWhere((p) => p.id == podcastId);

    await prefs.setString(
      AppPreferenceKeys.podcastSubscriptions,
      json.encode(subscriptions.map((p) => p.toJson()).toList()),
    );
  }

  /// Verificar si está suscrito
  Future<bool> isSubscribed(String podcastId) async {
    final subscriptions = await getSubscriptions();
    return subscriptions.any((p) => p.id == podcastId);
  }

  /// Toggle suscripción
  Future<void> toggleSubscription(Podcast podcast) async {
    final isSubbed = await isSubscribed(podcast.id);
    if (isSubbed) {
      await unsubscribe(podcast.id);
    } else {
      await subscribe(podcast);
    }
  }
}
