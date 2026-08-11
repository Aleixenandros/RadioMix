import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/podcast.dart';
import '../models/playable_item.dart';
import '../models/radio_station.dart';
import '../services/playback_coordinator_service.dart';
import '../services/podcast_subscription_service.dart';
import '../services/radio_service.dart';
import 'home_screen.dart';
import 'podcast_detail_screen.dart';

class FavoritesScreen extends ConsumerStatefulWidget {
  const FavoritesScreen({super.key});

  @override
  ConsumerState<FavoritesScreen> createState() => FavoritesScreenState();
}

class FavoritesScreenState extends ConsumerState<FavoritesScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      setState(() {});
      ref.read(favoritesTabProvider.notifier).setTab(_tabController.index);
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _refreshFavorites() async {
    ref.invalidate(favoriteStationsProvider);
    await ref.read(favoriteStationsProvider.future);
  }

  Future<void> _refreshSubscriptions() async {
    ref.invalidate(podcastSubscriptionsProvider);
    await ref.read(podcastSubscriptionsProvider.future);
  }

  Future<void> _playStation(RadioStation station) async {
    final item = PlayableItem.fromRadioStation(station);
    final messenger = ScaffoldMessenger.of(context);
    await ref.read(playbackCoordinatorServiceProvider).playItem(
          item,
          messenger: messenger,
        );
  }

  void _openPodcastDetail(Podcast podcast) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PodcastDetailScreen(podcast: podcast),
      ),
    ).then((_) => ref.invalidate(podcastSubscriptionsProvider));
  }

  Future<void> _removeFavorite(RadioStation station) async {
    final service = ref.read(radioServiceProvider);
    await service.removeFavorite(station.id);
    ref.invalidate(favoriteStationsProvider);
    if (!mounted) return;

    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${station.name} eliminado de favoritos'),
        duration: const Duration(seconds: 4),
        persist: false,
        action: SnackBarAction(
          label: 'DESHACER',
          onPressed: () async {
            await service.addFavorite(station);
            ref.invalidate(favoriteStationsProvider);
          },
        ),
      ),
    );
  }

  Future<void> _unsubscribe(Podcast podcast) async {
    final service = ref.read(podcastSubscriptionServiceProvider);
    await service.unsubscribe(podcast.id);
    ref.invalidate(podcastSubscriptionsProvider);
    if (!mounted) return;

    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Suscripción cancelada: ${podcast.title}'),
        duration: const Duration(seconds: 4),
        persist: false,
        action: SnackBarAction(
          label: 'DESHACER',
          onPressed: () async {
            await service.subscribe(podcast);
            ref.invalidate(podcastSubscriptionsProvider);
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ScaffoldMessenger(
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Mis Favoritos'),
          centerTitle: true,
          bottom: TabBar(
            controller: _tabController,
            tabs: const [
              Tab(
                icon: Icon(Icons.radio),
                text: 'Radios',
              ),
              Tab(
                icon: Icon(Icons.podcasts),
                text: 'Podcasts',
              ),
            ],
          ),
        ),
        body: TabBarView(
          controller: _tabController,
          children: [
            // Tab de Radios
            _buildRadiosTab(),
            // Tab de Podcasts
            _buildPodcastsTab(),
          ],
        ),
      ),
    );
  }

  Widget _buildRadiosTab() {
    final favoritesAsync = ref.watch(favoriteStationsProvider);

    return favoritesAsync.when(
      data: (favorites) {
        if (favorites.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.radio_outlined,
                  size: 64,
                  color: Theme.of(context).colorScheme.outline,
                ),
                const SizedBox(height: 16),
                Text(
                  'No tienes radios favoritas',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  'Busca y guarda tus radios preferidas',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.outline,
                      ),
                ),
              ],
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: _refreshFavorites,
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: favorites.length,
            itemBuilder: (context, index) {
              final station = favorites[index];
              return Dismissible(
                key: Key(station.id),
                direction: DismissDirection.endToStart,
                background: Container(
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.error,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.delete,
                    color: Theme.of(context).colorScheme.onError,
                  ),
                ),
                confirmDismiss: (_) async {
                  await _removeFavorite(station);
                  return true;
                },
                child: Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: station.favicon != null
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.network(
                              station.favicon!,
                              width: 48,
                              height: 48,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => _buildDefaultIcon(),
                            ),
                          )
                        : _buildDefaultIcon(),
                    title: Text(
                      station.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      station.country ?? 'Desconocido',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.play_circle_fill),
                      iconSize: 32,
                      color: Theme.of(context).colorScheme.primary,
                      onPressed: () => _playStation(station),
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => _buildErrorState(
        'No se pudieron cargar las radios favoritas',
        onRetry: _refreshFavorites,
      ),
    );
  }

  Widget _buildPodcastsTab() {
    final subscriptionsAsync = ref.watch(podcastSubscriptionsProvider);

    return subscriptionsAsync.when(
      data: (subscriptions) {
        if (subscriptions.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.podcasts_outlined,
                  size: 64,
                  color: Theme.of(context).colorScheme.outline,
                ),
                const SizedBox(height: 16),
                Text(
                  'No tienes suscripciones',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  'Suscríbete a podcasts para verlos aquí',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.outline,
                      ),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: () {
                    // Navegar a la pestaña de podcasts
                  },
                  icon: const Icon(Icons.search),
                  label: const Text('Buscar Podcasts'),
                ),
              ],
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: _refreshSubscriptions,
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: subscriptions.length,
            itemBuilder: (context, index) {
              final podcast = subscriptions[index];
              return Dismissible(
                key: Key(podcast.id),
                direction: DismissDirection.endToStart,
                background: Container(
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.error,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.delete,
                    color: Theme.of(context).colorScheme.onError,
                  ),
                ),
                confirmDismiss: (_) async {
                  await _unsubscribe(podcast);
                  return true;
                },
                child: Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: InkWell(
                    onTap: () => _openPodcastDetail(podcast),
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Row(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: podcast.artworkUrl != null
                                ? Image.network(
                                    podcast.artworkUrl!,
                                    width: 60,
                                    height: 60,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) =>
                                        _buildPodcastDefaultIcon(),
                                  )
                                : _buildPodcastDefaultIcon(),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  podcast.title,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium
                                      ?.copyWith(
                                        fontWeight: FontWeight.bold,
                                      ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  podcast.artist,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyMedium
                                      ?.copyWith(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant,
                                      ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (podcast.genre != null) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    podcast.genre!,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(
                                          color:
                                              Theme.of(context).colorScheme.primary,
                                        ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          Icon(
                            Icons.chevron_right,
                            color: Theme.of(context).colorScheme.outline,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => _buildErrorState(
        'No se pudieron cargar las suscripciones',
        onRetry: _refreshSubscriptions,
      ),
    );
  }

  Widget _buildErrorState(
    String message, {
    required Future<void> Function() onRetry,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              size: 48,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: onRetry,
              child: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDefaultIcon() {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(
        Icons.radio,
        color: Theme.of(context).colorScheme.onPrimaryContainer,
      ),
    );
  }

  Widget _buildPodcastDefaultIcon() {
    return Container(
      width: 60,
      height: 60,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(
        Icons.podcasts,
        color: Theme.of(context).colorScheme.onPrimaryContainer,
      ),
    );
  }
}
