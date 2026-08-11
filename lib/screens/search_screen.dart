import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/podcast.dart';
import '../models/playable_item.dart';
import '../models/radio_station.dart';
import '../services/app_network_error.dart';
import '../services/podcast_service.dart';
import '../services/playback_coordinator_service.dart';
import '../services/radio_service.dart';
import 'podcast_detail_screen.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen>
    with SingleTickerProviderStateMixin {
  static const int _minSearchChars = 3;
  static const Duration _searchDebounceDuration = Duration(milliseconds: 350);

  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;

  String _radioQuery = '';
  String _podcastQuery = '';

  final List<String> _suggestions = [
    'Los 40',
    'Radio Nacional',
    'Cadena SER',
    'COPE',
    'Kiss FM',
    'Europa FM',
    'Rock',
    'Jazz',
    'Noticias',
    'Deportes',
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(_handleTabChange);
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _tabController.removeListener(_handleTabChange);
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _handleTabChange() {
    if (_tabController.indexIsChanging) return;
    final query = _tabController.index == 0 ? _radioQuery : _podcastQuery;
    if (_searchController.text != query) {
      _searchController
        ..text = query
        ..selection = TextSelection.collapsed(offset: query.length);
    }
    setState(() {});
  }

  bool get _isRadioTab => _tabController.index == 0;

  String get _activeQuery => _isRadioTab ? _radioQuery : _podcastQuery;

  bool get _showSuggestions => _activeQuery.isEmpty;

  void _onSearchChanged(String value) {
    setState(() {
      if (_isRadioTab) {
        _radioQuery = value;
      } else {
        _podcastQuery = value;
      }
    });

    _searchDebounce?.cancel();
    _searchDebounce = Timer(_searchDebounceDuration, () {
      _search(value);
    });
  }

  void _search(String query) {
    final trimmedQuery = query.trim();
    setState(() {
      if (_isRadioTab) {
        _radioQuery = trimmedQuery;
      } else {
        _podcastQuery = trimmedQuery;
      }
    });
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
    );
  }

  Future<void> _toggleFavorite(RadioStation station) async {
    final service = ref.read(radioServiceProvider);

    if (station.isFavorite) {
      await service.removeFavorite(station.id);
    } else {
      await service.addFavorite(station);
    }

    setState(() {
      station.isFavorite = !station.isFavorite;
    });
  }

  @override
  Widget build(BuildContext context) {
    final radioResultsAsync =
        ref.watch(radioSearchResultsProvider(_radioQuery));
    final podcastResultsAsync =
        ref.watch(podcastSearchResultsProvider(_podcastQuery));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Buscar'),
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
      body: Column(
        children: [
          // Search Bar
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: SearchBar(
              controller: _searchController,
              hintText: _isRadioTab ? 'Busca radios...' : 'Busca podcasts...',
              leading: const Icon(Icons.search),
              trailing: [
                if (_searchController.text.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      _searchDebounce?.cancel();
                      _searchController.clear();
                      setState(() {
                        if (_isRadioTab) {
                          _radioQuery = '';
                        } else {
                          _podcastQuery = '';
                        }
                      });
                    },
                  ),
              ],
              onSubmitted: _search,
              onChanged: _onSearchChanged,
            ),
          ),

          // Suggestions (solo cuando no hay resultados)
          if (_showSuggestions)
            SizedBox(
              height: 50,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: _suggestions.length,
                itemBuilder: (context, index) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ActionChip(
                      label: Text(_suggestions[index]),
                      onPressed: () {
                        final suggestion = _suggestions[index];
                        _searchController
                          ..text = suggestion
                          ..selection = TextSelection.collapsed(
                              offset: suggestion.length);
                        _search(suggestion);
                      },
                    ),
                  );
                },
              ),
            ),

          // Tabs con resultados
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                // Tab de Radios
                _buildRadiosTab(radioResultsAsync),
                // Tab de Podcasts
                _buildPodcastsTab(podcastResultsAsync),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRadiosTab(AsyncValue<List<RadioStation>> radioResultsAsync) {
    return radioResultsAsync.when(
      data: (radioResults) {
        if (radioResults.isEmpty) {
          final isBelowMinimum =
              _radioQuery.isNotEmpty && _radioQuery.length < _minSearchChars;
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
                  'Busca radios',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  isBelowMinimum
                      ? 'Escribe al menos $_minSearchChars caracteres'
                      : 'Escribe el nombre de una emisora',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.outline,
                      ),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: radioResults.length,
          itemBuilder: (context, index) {
            final station = radioResults[index];
            return Card(
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
                          errorBuilder: (_, __, ___) =>
                              _buildRadioDefaultIcon(),
                        ),
                      )
                    : _buildRadioDefaultIcon(),
                title: Text(
                  station.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  '${station.country ?? 'Desconocido'} • ${station.bitrate?.toStringAsFixed(0) ?? '?'} kbps',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: Icon(
                        station.isFavorite
                            ? Icons.favorite
                            : Icons.favorite_border,
                        color: station.isFavorite ? Colors.red : null,
                      ),
                      onPressed: () => _toggleFavorite(station),
                    ),
                    IconButton(
                      icon: const Icon(Icons.play_arrow),
                      onPressed: () => _playStation(station),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
      loading: () => _radioQuery.length >= _minSearchChars
          ? const Center(child: CircularProgressIndicator())
          : _buildSearchHint(
              icon: Icons.radio_outlined,
              title: 'Busca radios',
              message: _radioQuery.isNotEmpty
                  ? 'Escribe al menos $_minSearchChars caracteres'
                  : 'Escribe el nombre de una emisora',
            ),
      error: (error, _) => _buildSearchError(
        error,
        onRetry: _radioQuery.length >= _minSearchChars
            ? () => ref.invalidate(radioSearchResultsProvider(_radioQuery))
            : null,
      ),
    );
  }

  Widget _buildPodcastsTab(AsyncValue<List<Podcast>> podcastResultsAsync) {
    return podcastResultsAsync.when(
      data: (podcastResults) {
        if (podcastResults.isEmpty) {
          final isBelowMinimum = _podcastQuery.isNotEmpty &&
              _podcastQuery.length < _minSearchChars;
          return _buildSearchHint(
            icon: Icons.podcasts_outlined,
            title: 'Busca podcasts',
            message: isBelowMinimum
                ? 'Escribe al menos $_minSearchChars caracteres'
                : 'Escribe el nombre de un podcast',
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: podcastResults.length,
          itemBuilder: (context, index) {
            final podcast = podcastResults[index];
            return Card(
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
                                width: 80,
                                height: 80,
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
                              const SizedBox(height: 8),
                              Chip(
                                label: Text(
                                  podcast.genre!,
                                  style: const TextStyle(fontSize: 12),
                                ),
                                padding: EdgeInsets.zero,
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
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
            );
          },
        );
      },
      loading: () => _podcastQuery.length >= _minSearchChars
          ? const Center(child: CircularProgressIndicator())
          : _buildSearchHint(
              icon: Icons.podcasts_outlined,
              title: 'Busca podcasts',
              message: _podcastQuery.isNotEmpty
                  ? 'Escribe al menos $_minSearchChars caracteres'
                  : 'Escribe el nombre de un podcast',
            ),
      error: (error, _) => _buildSearchError(
        error,
        onRetry: _podcastQuery.length >= _minSearchChars
            ? () => ref.invalidate(podcastSearchResultsProvider(_podcastQuery))
            : null,
      ),
    );
  }

  Widget _buildSearchHint({
    required IconData icon,
    required String title,
    required String message,
  }) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            size: 64,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            message,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.outline,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchError(
    Object error, {
    VoidCallback? onRetry,
  }) {
    final message = describeAppError(
      error,
      fallback: 'No se pudo completar la búsqueda.',
    );

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.error_outline,
            size: 48,
            color: Theme.of(context).colorScheme.error,
          ),
          const SizedBox(height: 16),
          Text(
            'No se pudo completar la búsqueda',
            style: Theme.of(context).textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ),
          if (onRetry != null) ...[
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('REINTENTAR'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRadioDefaultIcon() {
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
      width: 80,
      height: 80,
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
