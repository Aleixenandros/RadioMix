import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/podcast.dart';
import '../models/podcast_episode.dart';
import '../models/playable_item.dart';
import '../services/app_network_error.dart';
import '../services/playback_coordinator_service.dart';
import '../services/playback_progress_service.dart';
import '../services/podcast_download_service.dart';
import '../services/podcast_service.dart';
import '../services/podcast_subscription_service.dart';
import '../widgets/mini_player.dart';
import 'podcast_player_screen.dart';

class PodcastDetailScreen extends ConsumerStatefulWidget {
  final Podcast podcast;

  const PodcastDetailScreen({
    super.key,
    required this.podcast,
  });

  @override
  ConsumerState<PodcastDetailScreen> createState() =>
      _PodcastDetailScreenState();
}

class _PodcastDetailScreenState extends ConsumerState<PodcastDetailScreen> {
  Future<void> _toggleSubscription() async {
    final subscriptionService = ref.read(podcastSubscriptionServiceProvider);
    final wasSubscribed = await ref
        .read(podcastSubscriptionStateProvider(widget.podcast.id).future);
    await subscriptionService.toggleSubscription(widget.podcast);
    ref.invalidate(podcastSubscriptionStateProvider(widget.podcast.id));
    ref.invalidate(podcastSubscriptionsProvider);
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          wasSubscribed
              ? 'Has cancelado la suscripción a ${widget.podcast.title}'
              : 'Te has suscrito a ${widget.podcast.title}',
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _playEpisode(
    PodcastEpisode episode,
    DownloadedEpisode? downloadedEpisode,
  ) async {
    String audioUrl = downloadedEpisode?.localPath ?? episode.audioUrl;
    String? artworkUrl = widget.podcast.artworkUrl ?? episode.artworkUrl;

    final item = PlayableItem.fromPodcastEpisode(
      episode: episode,
      podcast: widget.podcast,
      source: audioUrl,
      artworkUrl: artworkUrl,
    );

    final messenger = ScaffoldMessenger.of(context);
    
    if (mounted) {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        isDismissible: true,
        enableDrag: true,
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        builder: (context) => SizedBox(
          height: MediaQuery.of(context).size.height,
          child: PodcastPlayerScreen(item: item),
        ),
      );
    }

    ref.read(playbackCoordinatorServiceProvider).playItem(
      item,
      messenger: messenger,
      podcastResumeBehavior: PodcastResumeBehavior.ask,
      onRequestResume: (savedProgress) async {
        if (!mounted) return false;
        return showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Continuar reproducción'),
            content: Text(
              'Has escuchado ${_formatDurationDetailed(savedProgress.position)} de ${_formatDurationDetailed(savedProgress.duration)}. ¿Quieres continuar desde ahí?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('DESDE EL INICIO'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('CONTINUAR'),
              ),
            ],
          ),
        );
      },
      successMessage: downloadedEpisode != null
          ? 'Reproduciendo: ${episode.title} (descargado)'
          : null,
    ).then((_) {
      ref.invalidate(playbackProgressEntriesProvider);
    });
  }

  Future<void> _downloadEpisode(PodcastEpisode episode) async {
    final downloadService = ref.read(podcastDownloadServiceProvider);
    // Mostrar indicador de descarga en segundo plano (SnackBar no bloqueante)
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text('Descargando: ${episode.title}'),
              ),
            ],
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    }

    // Ejecutar descarga en segundo plano sin bloquear la UI
    downloadService
        .downloadEpisode(
      episodeId: episode.id,
      podcastId: widget.podcast.id,
      title: episode.title,
      podcastTitle: widget.podcast.title,
      audioUrl: episode.audioUrl,
      artworkUrl: episode.artworkUrl ?? widget.podcast.artworkUrl,
    )
        .then((downloaded) {
      if (downloaded != null) {
        ref.invalidate(downloadedEpisodesProvider);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('"${episode.title}" descargado'),
              duration: const Duration(seconds: 3),
              persist: false,
              action: SnackBarAction(
                label: 'VER',
                onPressed: () {
                  // Scroll al episodio descargado
                },
              ),
            ),
          );
        }
      } else {
        // null = ya estaba descargado o descarga en curso, no es un error
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('El episodio ya está descargado'),
              duration: Duration(seconds: 2),
            ),
          );
        }
      }
    }).catchError((Object e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(describeAppError(e)),
            duration: const Duration(seconds: 4),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    });
  }

  Future<void> _deleteDownload(String episodeId) async {
    final downloadService = ref.read(podcastDownloadServiceProvider);
    await downloadService.deleteDownload(episodeId);
    ref.invalidate(downloadedEpisodesProvider);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Descarga eliminada'),
        ),
      );
    }
  }

  String _formatDuration(Duration? duration) {
    if (duration == null) return '';
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);

    if (hours > 0) {
      return '${hours}h ${minutes}m';
    } else {
      return '${minutes}m';
    }
  }

  String _formatDurationDetailed(Duration? duration) {
    if (duration == null) return '0:00';
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    } else {
      return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
  }

  String _formatDate(DateTime? date) {
    if (date == null) return '';
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays == 0) {
      return 'Hoy';
    } else if (difference.inDays == 1) {
      return 'Ayer';
    } else if (difference.inDays < 7) {
      return 'Hace ${difference.inDays} días';
    } else if (difference.inDays < 30) {
      return 'Hace ${difference.inDays ~/ 7} semanas';
    } else {
      return '${date.day}/${date.month}/${date.year}';
    }
  }

  /// Obtiene el estado del episodio: 0=nuevo, 1=en progreso, 2=completado
  int _getEpisodeStatus(
    PodcastEpisode episode,
    Map<String, PlaybackProgress?> episodeProgress,
  ) {
    final progress = episodeProgress[episode.id];
    if (progress == null) return 0;

    final duration = progress.duration ?? episode.duration;
    if (duration == null) return 0;

    final percentage =
        progress.position.inMilliseconds / duration.inMilliseconds;

    if (percentage >= 0.95) return 2; // Completado (95% o más)
    if (percentage > 0.05) return 1; // En progreso (más del 5%)
    return 0; // Nuevo
  }

  String _getStatusText(
    int status,
    PodcastEpisode episode,
    Map<String, PlaybackProgress?> episodeProgress,
  ) {
    final progress = episodeProgress[episode.id];

    switch (status) {
      case 2:
        return 'Reproducido';
      case 1:
        if (progress != null && episode.duration != null) {
          final remaining = episode.duration! - progress.position;
          return 'Quedan ${_formatDuration(remaining)}';
        }
        return 'En progreso';
      default:
        return _formatDuration(episode.duration);
    }
  }

  Color _getStatusColor(int status, BuildContext context) {
    switch (status) {
      case 2:
        return Theme.of(context).colorScheme.primary;
      case 1:
        return Theme.of(context).colorScheme.tertiary;
      default:
        return Theme.of(context).colorScheme.outline;
    }
  }

  IconData _getStatusIcon(int status) {
    switch (status) {
      case 2:
        return Icons.check_circle;
      case 1:
        return Icons.play_circle_outline;
      default:
        return Icons.play_circle;
    }
  }

  double _getProgressPercentage(
    PodcastEpisode episode,
    Map<String, PlaybackProgress?> episodeProgress,
  ) {
    final progress = episodeProgress[episode.id];
    if (progress == null || progress.duration == null) return 0.0;

    final percentage =
        progress.position.inMilliseconds / progress.duration!.inMilliseconds;
    return percentage.clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final feedUrl = widget.podcast.feedUrl?.trim() ?? '';
    final episodesAsync = feedUrl.isEmpty
        ? const AsyncValue.data(<PodcastEpisode>[])
        : ref.watch(
            podcastEpisodesProvider(feedUrl),
          );
    final progressEntriesAsync = ref.watch(playbackProgressEntriesProvider);
    final downloadedEpisodesAsync = ref.watch(downloadedEpisodesProvider);
    final isSubscribedAsync =
        ref.watch(podcastSubscriptionStateProvider(widget.podcast.id));
    final downloadedEpisodes = downloadedEpisodesAsync.maybeWhen(
      data: (downloads) => downloads,
      orElse: () => const <DownloadedEpisode>[],
    );
    final downloadedByEpisodeId = {
      for (final download in downloadedEpisodes) download.episodeId: download,
    };
    final progressByStationId = {
      for (final progress in progressEntriesAsync.maybeWhen(
        data: (entries) => entries,
        orElse: () => const <PlaybackProgress>[],
      ))
        progress.stationId: progress,
    };
    final isSubscribed = isSubscribedAsync.maybeWhen(
      data: (value) => value,
      orElse: () => false,
    );

    return Scaffold(
      body: Column(
        children: [
          Expanded(
            child: CustomScrollView(
              slivers: [
                // App Bar con imagen
                SliverAppBar(
                  expandedHeight: 250,
                  pinned: true,
                  flexibleSpace: FlexibleSpaceBar(
                    background: widget.podcast.artworkUrl != null
                        ? Image.network(
                            widget.podcast.artworkUrl!,
                            fit: BoxFit.cover,
                          )
                        : Container(
                            color: Theme.of(context).colorScheme.primaryContainer,
                            child: Icon(
                              Icons.podcasts,
                              size: 100,
                              color: Theme.of(context).colorScheme.onPrimaryContainer,
                            ),
                          ),
                  ),
                  actions: [
                    IconButton(
                      icon: Icon(
                        isSubscribed
                            ? Icons.notifications_active
                            : Icons.notifications_none,
                        color: isSubscribed
                            ? Theme.of(context).colorScheme.primary
                            : null,
                      ),
                      onPressed: _toggleSubscription,
                      tooltip: isSubscribed ? 'Suscrito' : 'Suscribirse',
                    ),
                  ],
                ),

                // Info del podcast
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.podcast.title,
                          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          widget.podcast.artist,
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                color: Theme.of(context).colorScheme.primary,
                              ),
                        ),
                        if (widget.podcast.genre != null) ...[
                          const SizedBox(height: 8),
                          Chip(
                            label: Text(widget.podcast.genre!),
                            backgroundColor:
                                Theme.of(context).colorScheme.secondaryContainer,
                          ),
                        ],
                        const SizedBox(height: 16),
                        // Botón de suscripción destacado
                        FilledButton.icon(
                          onPressed: _toggleSubscription,
                          icon: Icon(isSubscribed ? Icons.check : Icons.add),
                          label: Text(
                            isSubscribed ? 'SUSCRITO' : 'SUSCRIBIRSE',
                          ),
                        ),
                        const Divider(height: 32),
                      ],
                    ),
                  ),
                ),

                // Lista de episodios
                if (feedUrl.isEmpty)
                  const SliverFillRemaining(
                    child: Center(
                      child: Text('Este podcast no tiene feed disponible'),
                    ),
                  )
                else
                  episodesAsync.when(
                    loading: () => const SliverFillRemaining(
                      child: Center(child: CircularProgressIndicator()),
                    ),
                    error: (error, _) => SliverFillRemaining(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 24,
                        ),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(minHeight: 160),
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.error_outline,
                                  size: 48,
                                  color: Theme.of(context).colorScheme.error,
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  describeAppError(
                                    error,
                                    fallback: 'No se pudieron cargar los episodios.',
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 16),
                                FilledButton.icon(
                                  onPressed: () => ref
                                      .invalidate(podcastEpisodesProvider(feedUrl)),
                                  icon: const Icon(Icons.refresh),
                                  label: const Text('REINTENTAR'),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    data: (episodes) {
                      if (episodes.isEmpty) {
                        return const SliverFillRemaining(
                          child: Center(
                            child: Text('No hay episodios disponibles'),
                          ),
                        );
                      }

                      final episodeProgress = {
                        for (final episode in episodes)
                          episode.id: progressByStationId['podcast_ep_${episode.id}'],
                      };
                      return SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final episode = episodes[index];
                            return _buildEpisodeCard(
                              episode,
                              episodeProgress,
                              downloadedByEpisodeId[episode.id],
                            );
                          },
                          childCount: episodes.length,
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),
          const MiniPlayer(),
        ],
      ),
    );
  }

  Widget _buildEpisodeCard(
    PodcastEpisode episode,
    Map<String, PlaybackProgress?> episodeProgress,
    DownloadedEpisode? downloadedEpisode,
  ) {
    final status = _getEpisodeStatus(episode, episodeProgress);
    final progressPercentage = _getProgressPercentage(episode, episodeProgress);
    final statusText = _getStatusText(status, episode, episodeProgress);
    final statusColor = _getStatusColor(status, context);
    final isDownloaded = downloadedEpisode != null;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: InkWell(
        onTap: () => _playEpisode(episode, downloadedEpisode),
        borderRadius: BorderRadius.circular(12),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  // Download/Status button
                  isDownloaded
                      ? Container(
                          width: 50,
                          height: 50,
                          decoration: BoxDecoration(
                            color:
                                Theme.of(context).colorScheme.primaryContainer,
                            shape: BoxShape.circle,
                          ),
                          child: IconButton(
                            icon: const Icon(Icons.download_done),
                            color: Theme.of(context).colorScheme.primary,
                            tooltip: 'Descargado - Tocar para reproducir',
                            onPressed: () =>
                                _playEpisode(episode, downloadedEpisode),
                          ),
                        )
                      : Container(
                          width: 50,
                          height: 50,
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                          ),
                          child: IconButton(
                            icon: Icon(
                              _getStatusIcon(status),
                              color: statusColor,
                              size: 28,
                            ),
                            tooltip: 'Reproducir',
                            onPressed: () =>
                                _playEpisode(episode, downloadedEpisode),
                          ),
                        ),
                  const SizedBox(width: 16),
                  // Info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                episode.title,
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(
                                      fontWeight: FontWeight.bold,
                                    ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (isDownloaded)
                              Padding(
                                padding: const EdgeInsets.only(left: 8),
                                child: Icon(
                                  Icons.download_done,
                                  size: 18,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            // Status badge
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: statusColor.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    status == 2
                                        ? Icons.check
                                        : status == 1
                                            ? Icons.pause_circle
                                            : Icons.schedule,
                                    size: 14,
                                    color: statusColor,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    statusText,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(
                                          color: statusColor,
                                          fontWeight: FontWeight.w500,
                                        ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            // Date
                            Icon(
                              Icons.calendar_today,
                              size: 14,
                              color: Theme.of(context).colorScheme.outline,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _formatDate(episode.publishDate),
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  // Download button
                  if (!isDownloaded)
                    IconButton(
                      icon: const Icon(Icons.download),
                      tooltip: 'Descargar episodio',
                      onPressed: () => _downloadEpisode(episode),
                    )
                  else
                    PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert),
                      onSelected: (value) {
                        if (value == 'delete') {
                          _deleteDownload(episode.id);
                        }
                      },
                      itemBuilder: (context) => [
                        const PopupMenuItem(
                          value: 'delete',
                          child: Row(
                            children: [
                              Icon(Icons.delete),
                              SizedBox(width: 8),
                              Text('Eliminar descarga'),
                            ],
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
            // Progress bar (solo si está en progreso)
            if (status == 1 && progressPercentage > 0) ...[
              LinearProgressIndicator(
                value: progressPercentage,
                backgroundColor:
                    Theme.of(context).colorScheme.surfaceContainerHighest,
                valueColor: AlwaysStoppedAnimation<Color>(statusColor),
                minHeight: 4,
              ),
            ] else if (status == 2) ...[
              Container(
                height: 4,
                color: statusColor.withValues(alpha: 0.3),
              ),
            ] else ...[
              const SizedBox(height: 4),
            ],
          ],
        ),
      ),
    );
  }
}
