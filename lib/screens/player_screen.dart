import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import '../models/playable_item.dart';
import '../services/audio_player_service.dart';
import '../services/playback_coordinator_service.dart';
import '../services/playable_item_action_service.dart';
import '../widgets/audio_visualizer.dart';
import '../widgets/volume_control.dart';

class PlayerScreen extends ConsumerStatefulWidget {
  const PlayerScreen({super.key});

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen> {
  static const _appIconAsset = 'assets/icon/icon.png';

  double _volume = 1.0;
  String? _errorMessage;
  PlayableItem? _lastPlayedItem;
  Duration _position = Duration.zero;
  Duration? _duration;
  String? _pendingAutoPlayItemId;
  String? _startingItemId;
  StreamSubscription<Duration>? _positionSubscription;

  @override
  void initState() {
    super.initState();
    final service = ref.read(audioPlayerServiceProvider);
    _volume = service.volume;

    _positionSubscription = service.positionStream.listen((position) {
      if (mounted) {
        setState(() {
          _position = position;
        });
      }
    });
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    super.dispose();
  }

  Future<void> _playItem(PlayableItem item) async {
    if (_startingItemId == item.id) {
      return;
    }
    if (_lastPlayedItem?.id == item.id &&
        ref.read(audioPlayerServiceProvider).isPlaying) {
      return;
    }
    _startingItemId = item.id;
    if (_pendingAutoPlayItemId == item.id) {
      _pendingAutoPlayItemId = null;
    }

    setState(() {
      _errorMessage = null;
    });

    try {
      final service = ref.read(audioPlayerServiceProvider);
      final messenger = ScaffoldMessenger.of(context);
      final result =
          await ref.read(playbackCoordinatorServiceProvider).playItem(
                item,
                messenger: messenger,
                podcastResumeBehavior: PodcastResumeBehavior.automatic,
              );
      if (!result.didStart) {
        setState(() {
          _errorMessage = result.errorMessage;
        });
        return;
      }
      setState(() {
        _lastPlayedItem = item;
        _duration = service.duration;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Error al reproducir: $e';
      });
    } finally {
      if (_startingItemId == item.id) {
        if (mounted) {
          setState(() {
            _startingItemId = null;
          });
        } else {
          _startingItemId = null;
        }
      }
    }
  }

  Future<void> _togglePlayPause() async {
    await ref.read(audioPlayerServiceProvider).togglePlayPause();
  }

  Future<void> _restartCurrentRadio() async {
    final item = ref.read(currentPlayableProvider);
    if (item == null || !item.isRadio) {
      return;
    }

    _startingItemId = item.id;
    setState(() {
      _errorMessage = null;
    });

    try {
      final service = ref.read(audioPlayerServiceProvider);
      final result =
          await ref.read(playbackCoordinatorServiceProvider).playItem(
                item,
                messenger: ScaffoldMessenger.of(context),
                successMessage: 'Reiniciando: ${item.title}',
              );
      if (!result.didStart) {
        setState(() {
          _errorMessage = result.errorMessage;
        });
        return;
      }
      setState(() {
        _lastPlayedItem = item;
        _duration = service.duration;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Error al reiniciar: $e';
      });
    } finally {
      if (_startingItemId == item.id) {
        if (mounted) {
          setState(() {
            _startingItemId = null;
          });
        } else {
          _startingItemId = null;
        }
      }
    }
  }

  Future<void> _seek(Duration position) async {
    await ref.read(audioPlayerServiceProvider).seek(position);
  }

  Future<void> _seekRelative(Duration offset) async {
    final service = ref.read(audioPlayerServiceProvider);
    final duration = service.duration;
    var target = service.position + offset;

    if (target.isNegative) {
      target = Duration.zero;
    }

    if (duration != null &&
        duration.inMilliseconds > 0 &&
        target.compareTo(duration) > 0) {
      target = duration;
    }

    await service.seek(target);
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  bool get _isPodcast => ref.read(currentPlayableProvider)?.isPodcast == true;

  @override
  Widget build(BuildContext context) {
    final currentItem = ref.watch(currentPlayableProvider);
    final service = ref.read(audioPlayerServiceProvider);
    final recentAsync = ref.watch(recentPlayablesProvider);

    if (currentItem != null && currentItem.id != _lastPlayedItem?.id) {
      if (service.isPlaying ||
          service.processingState == ProcessingState.loading ||
          service.processingState == ProcessingState.buffering) {
        _lastPlayedItem = currentItem;
        if (_pendingAutoPlayItemId == currentItem.id) {
          _pendingAutoPlayItemId = null;
        }
      } else if (_pendingAutoPlayItemId != currentItem.id) {
        _pendingAutoPlayItemId = currentItem.id;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          final latestItem = ref.read(currentPlayableProvider);
          if (latestItem?.id != currentItem.id) {
            if (_pendingAutoPlayItemId == currentItem.id) {
              _pendingAutoPlayItemId = null;
            }
            return;
          }
          _playItem(currentItem);
        });
      }
    }

    return SafeArea(
      child: StreamBuilder<PlayerState>(
        initialData: PlayerState(service.isPlaying, service.processingState),
        stream: service.playerStateStream,
        builder: (context, snapshot) {
          final playerState = snapshot.data;
          final isPlaying = playerState?.playing ?? false;
          final processingState = playerState?.processingState;
          final isLoading = processingState == ProcessingState.loading ||
              processingState == ProcessingState.buffering;

          _duration = service.duration;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              children: [
                Container(
                  width: 180,
                  height: 180,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Theme.of(context)
                            .colorScheme
                            .shadow
                            .withValues(alpha: 0.2),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: currentItem?.artworkUrl != null
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(20),
                          child: Image.network(
                            currentItem!.artworkUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                                _buildDefaultIcon(currentItem),
                          ),
                        )
                      : _buildDefaultIcon(currentItem),
                ),
                const SizedBox(height: 24),
                Text(
                  currentItem?.title ?? 'Selecciona una radio',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                  textAlign: TextAlign.center,
                ),
                if (currentItem?.subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    currentItem!.subtitle!,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
                const SizedBox(height: 24),
                if (isPlaying && _errorMessage == null)
                  const AudioVisualizer()
                else if (isLoading)
                  Column(
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 8),
                      Text(
                        'Cargando buffer...',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  )
                else if (_errorMessage != null)
                  Text(
                    _errorMessage!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error),
                    textAlign: TextAlign.center,
                  )
                else
                  Icon(
                    Icons.radio,
                    size: 48,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                const SizedBox(height: 24),
                if (_isPodcast &&
                    _duration != null &&
                    _duration! > Duration.zero) ...[
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest
                          .withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: StreamBuilder<Duration>(
                      stream: service.positionStream,
                      builder: (context, snapshot) {
                        final position = snapshot.data ?? _position;

                        return Column(
                          children: [
                            Slider(
                              value: position.inMilliseconds.toDouble().clamp(
                                    0,
                                    _duration!.inMilliseconds.toDouble(),
                                  ),
                              max: _duration!.inMilliseconds.toDouble(),
                              onChanged: (value) {
                                _seek(Duration(milliseconds: value.toInt()));
                              },
                              activeColor:
                                  Theme.of(context).colorScheme.primary,
                              inactiveColor: Theme.of(context)
                                  .colorScheme
                                  .outline
                                  .withValues(alpha: 0.3),
                            ),
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 16),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    _formatDuration(position),
                                    style:
                                        Theme.of(context).textTheme.bodySmall,
                                  ),
                                  Text(
                                    _formatDuration(_duration!),
                                    style:
                                        Theme.of(context).textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                          ],
                        );
                      },
                    ),
                  ),
                ],
                if (_isPodcast) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton.filledTonal(
                        onPressed: currentItem != null
                            ? () => _seekRelative(
                                  const Duration(seconds: -10),
                                )
                            : null,
                        icon: const Icon(Icons.replay_10),
                        tooltip: 'Atrasar 10 segundos',
                      ),
                      const SizedBox(width: 12),
                      IconButton.filledTonal(
                        onPressed: currentItem != null
                            ? () => _seekRelative(
                                  const Duration(seconds: 30),
                                )
                            : null,
                        icon: const Icon(Icons.forward_30),
                        tooltip: 'Avanzar 30 segundos',
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],
                Wrap(
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    FilledButton.tonalIcon(
                      onPressed: currentItem != null ? _togglePlayPause : null,
                      icon: Icon(
                        isPlaying
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        size: 36,
                      ),
                      label: Text(
                        isPlaying ? 'PAUSAR' : 'REPRODUCIR',
                        style: const TextStyle(fontSize: 16),
                      ),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 14,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),
                      ),
                    ),
                    if (currentItem?.isRadio == true &&
                        (isPlaying || isLoading))
                      IconButton.filledTonal(
                        onPressed: _restartCurrentRadio,
                        icon: const Icon(Icons.restart_alt_rounded, size: 36),
                        tooltip: 'Reiniciar',
                        style: IconButton.styleFrom(
                          padding: const EdgeInsets.all(14),
                        ),
                      ),
                    if (isPlaying || isLoading)
                      IconButton.filled(
                        onPressed: () {
                          ref.read(audioPlayerServiceProvider).stop();
                        },
                        icon: const Icon(Icons.stop_rounded, size: 36),
                        tooltip: 'Detener',
                        style: IconButton.styleFrom(
                          backgroundColor:
                              Theme.of(context).colorScheme.errorContainer,
                          foregroundColor:
                              Theme.of(context).colorScheme.onErrorContainer,
                          padding: const EdgeInsets.all(14),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 20),
                VolumeControl(
                  volume: _volume,
                  onChanged: (value) {
                    setState(() {
                      _volume = value;
                    });
                    service.setVolume(value);
                  },
                ),
                const SizedBox(height: 32),
                _buildRecentSection(
                  recentAsync,
                  currentItem,
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildRecentSection(
    AsyncValue<List<PlayableItem>> recentAsync,
    PlayableItem? currentItem,
  ) {
    return recentAsync.when(
      data: (items) {
        if (items.isEmpty) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.history,
                  size: 20,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Text(
                  'Últimas reproducidas',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ...items.map(
              (item) => _buildRecentTile(item, currentItem),
            ),
          ],
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }

  Widget _buildRecentTile(PlayableItem item, PlayableItem? currentItem) {
    final isActive = currentItem?.id == item.id;
    final canFavorite = item.isRadio;
    final deleteBackground = Container(
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
    );

    return Dismissible(
      key: Key('recent_${item.id}'),
      direction: canFavorite
          ? DismissDirection.horizontal
          : DismissDirection.endToStart,
      background: canFavorite
          ? Container(
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.only(left: 16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.favorite,
                color: Theme.of(context).colorScheme.onPrimary,
              ),
            )
          : deleteBackground,
      secondaryBackground: deleteBackground,
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.startToEnd && canFavorite) {
          await ref.read(playableItemActionServiceProvider).addFavorite(item);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('${item.title} añadida a favoritos')),
            );
          }
          return false;
        }
        return true;
      },
      onDismissed: (_) {
        ref.read(audioPlayerServiceProvider).removeFromRecent(item.id);
      },
      child: Card(
        elevation: isActive ? 2 : 0,
        color: isActive
            ? Theme.of(context).colorScheme.primaryContainer
            : Theme.of(context).colorScheme.surfaceContainerLow,
        margin: const EdgeInsets.only(bottom: 4),
        child: ListTile(
          dense: true,
          leading: item.artworkUrl != null
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    item.artworkUrl!,
                    width: 40,
                    height: 40,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) =>
                        _buildListArtworkFallback(item),
                  ),
                )
              : _buildListArtworkFallback(item),
          title: Text(
            item.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          subtitle: item.subtitle != null
              ? Text(
                  item.subtitle!,
                  style: Theme.of(context).textTheme.bodySmall,
                )
              : null,
          trailing: isActive
              ? Icon(Icons.equalizer,
                  color: Theme.of(context).colorScheme.primary)
              : const Icon(Icons.play_arrow_rounded),
          onTap: () => _playItem(item),
        ),
      ),
    );
  }

  Widget _buildDefaultIcon(PlayableItem? item) {
    if (item?.isRadio == true) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Image.asset(_appIconAsset),
        ),
      );
    }

    return Center(
      child: Icon(
        Icons.radio,
        size: 80,
        color: Theme.of(context).colorScheme.onPrimaryContainer,
      ),
    );
  }

  Widget _buildListArtworkFallback(PlayableItem item) {
    if (item.isRadio) {
      return Image.asset(
        _appIconAsset,
        width: 40,
        height: 40,
        fit: BoxFit.contain,
      );
    }

    return const Icon(Icons.podcasts, size: 28);
  }
}
