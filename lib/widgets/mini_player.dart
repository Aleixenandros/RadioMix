import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import '../models/playable_item.dart';
import '../screens/podcast_player_screen.dart';
import '../services/audio_player_service.dart';

class MiniPlayer extends ConsumerWidget {
  const MiniPlayer({super.key});

  static const _appIconAsset = 'assets/icon/icon.png';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentItem = ref.watch(currentPlayableProvider);
    final service = ref.read(audioPlayerServiceProvider);

    if (currentItem == null) {
      return const SizedBox.shrink();
    }

    final colorScheme = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: () {
        if (currentItem.isPodcast) {
          showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            useSafeArea: true,
            isDismissible: true,
            enableDrag: true,
            backgroundColor: Theme.of(context).scaffoldBackgroundColor,
            builder: (context) => SizedBox(
              height: MediaQuery.of(context).size.height,
              child: PodcastPlayerScreen(item: currentItem),
            ),
          );
        } else {
          // Si no es un podcast, por ahora no hacemos nada o vamos a la pestaña de reproductor global
        }
      },
      child: Container(
        width: double.infinity,
        color: colorScheme.surfaceContainerHighest,
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Barra de progreso mínima superior
              if (currentItem.isPodcast)
                SizedBox(
                  height: 2,
                  child: StreamBuilder<Duration>(
                    initialData: service.position,
                    stream: service.positionStream,
                    builder: (context, snapshot) {
                      final position = snapshot.data ?? Duration.zero;
                      final duration = service.duration ?? Duration.zero;
                      final progress = duration.inMilliseconds > 0
                          ? position.inMilliseconds / duration.inMilliseconds
                          : 0.0;
                      return LinearProgressIndicator(
                        value: progress.clamp(0.0, 1.0),
                        backgroundColor: Colors.transparent,
                        valueColor:
                            AlwaysStoppedAnimation<Color>(colorScheme.primary),
                      );
                    },
                  ),
                ),
              SizedBox(
                height: 64, // Altura del contenido del mini player
                child: Row(
                  children: [
                    // Imagen
                    if (currentItem.artworkUrl != null)
                      Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: Image.network(
                            currentItem.artworkUrl!,
                            width: 48,
                            height: 48,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                                _ArtworkFallbackContent(item: currentItem),
                          ),
                        ),
                      )
                    else
                      _ArtworkFallback(item: currentItem),

                    // Textos (Título y subtítulo)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8.0),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              currentItem.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: colorScheme.onSurface,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                            if (currentItem.subtitle != null)
                              Text(
                                currentItem.subtitle!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: colorScheme.onSurfaceVariant,
                                  fontSize: 12,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),

                    // Controles
                    StreamBuilder<PlayerState>(
                      initialData: PlayerState(
                          service.isPlaying, service.processingState),
                      stream: service.playerStateStream,
                      builder: (context, snapshot) {
                        final playerState = snapshot.data;
                        final isPlaying = playerState?.playing ?? false;
                        final processingState = playerState?.processingState;
                        final isLoading =
                            processingState == ProcessingState.loading ||
                                processingState == ProcessingState.buffering;

                        return Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: isLoading
                                  ? SizedBox(
                                      width: 24,
                                      height: 24,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: colorScheme.onSurface,
                                      ),
                                    )
                                  : Icon(
                                      isPlaying
                                          ? Icons.pause
                                          : Icons.play_arrow,
                                      color: colorScheme.onSurface,
                                      size: 30,
                                    ),
                              onPressed: service.togglePlayPause,
                            ),
                            const SizedBox(width: 8),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ArtworkFallback extends StatelessWidget {
  const _ArtworkFallback({required this.item});

  final PlayableItem item;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainer,
          borderRadius: BorderRadius.circular(4),
        ),
        clipBehavior: Clip.antiAlias,
        child: _ArtworkFallbackContent(item: item),
      ),
    );
  }
}

class _ArtworkFallbackContent extends StatelessWidget {
  const _ArtworkFallbackContent({required this.item});

  final PlayableItem item;

  @override
  Widget build(BuildContext context) {
    if (item.isRadio) {
      return Padding(
        padding: const EdgeInsets.all(6),
        child: Image.asset(
          MiniPlayer._appIconAsset,
          fit: BoxFit.contain,
        ),
      );
    }

    return Icon(
      Icons.podcasts,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );
  }
}
