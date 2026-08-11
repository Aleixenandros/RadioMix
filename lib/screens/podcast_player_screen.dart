import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import '../models/playable_item.dart';
import '../services/audio_player_service.dart';

class PodcastPlayerScreen extends ConsumerStatefulWidget {
  final PlayableItem item;
  const PodcastPlayerScreen({super.key, required this.item});

  @override
  ConsumerState<PodcastPlayerScreen> createState() => _PodcastPlayerScreenState();
}

class _PodcastPlayerScreenState extends ConsumerState<PodcastPlayerScreen> {
  Duration _position = Duration.zero;
  Duration? _duration;
  StreamSubscription<Duration>? _positionSubscription;

  @override
  void initState() {
    super.initState();
    final service = ref.read(audioPlayerServiceProvider);
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

  Future<void> _togglePlayPause() async {
    await ref.read(audioPlayerServiceProvider).togglePlayPause();
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
      return '${hours.toString().padLeft(1, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(1, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final globalItem = ref.watch(currentPlayableProvider);
    final isCurrent = globalItem?.id == widget.item.id;
    final currentItem = isCurrent ? globalItem! : widget.item;
    
    final service = ref.read(audioPlayerServiceProvider);
    
    final colorScheme = Theme.of(context).colorScheme;
    final onSurface = colorScheme.onSurface;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: SafeArea(
        child: StreamBuilder<PlayerState>(
          initialData: PlayerState(service.isPlaying, service.processingState),
          stream: service.playerStateStream,
          builder: (context, snapshot) {
            final playerState = snapshot.data;
            final isPlaying = isCurrent && (playerState?.playing ?? false);
            final processingState = playerState?.processingState;
            final isLoading = !isCurrent || 
                processingState == ProcessingState.loading ||
                processingState == ProcessingState.buffering;

            // Si es el ítem actual, _duration será el real, si no null
            _duration = isCurrent ? service.duration : null;

            return Column(
              children: [
                // App Bar
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        icon: Icon(Icons.keyboard_arrow_down, color: onSurface, size: 30),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                      // El resto de la barra superior está vacío a petición
                      const SizedBox(width: 48), // Spacer para mantener el botón de colapsar alineado
                    ],
                  ),
                ),
                
                // Arte del podcast
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
                    child: Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        color: colorScheme.surfaceContainerHighest,
                      ),
                      child: currentItem.artworkUrl != null
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: Image.network(
                                currentItem.artworkUrl!,
                                fit: BoxFit.cover,
                              ),
                            )
                          : Center(
                              child: Icon(Icons.podcasts, size: 80, color: onSurface.withValues(alpha: 0.54)),
                            ),
                    ),
                  ),
                ),
                
                // Info del episodio
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        currentItem.title,
                        style: TextStyle(
                          color: onSurface,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(Icons.rss_feed, color: onSurface.withValues(alpha: 0.54), size: 16),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              currentItem.subtitle ?? 'Podcast desconocido',
                              style: TextStyle(
                                color: onSurface.withValues(alpha: 0.54),
                                fontSize: 14,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 16),
                
                // Botones Action (Guardar, Descargar, etc.)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0),
                  child: Row(
                    children: [
                      ActionChip(
                        avatar: Icon(Icons.playlist_add, color: onSurface, size: 18),
                        label: Text('Guardar', style: TextStyle(color: onSurface)),
                        backgroundColor: onSurface.withValues(alpha: 0.12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        side: BorderSide.none,
                        onPressed: () {},
                      ),
                      const SizedBox(width: 8),
                      ActionChip(
                        avatar: Icon(Icons.download_rounded, color: onSurface, size: 18),
                        label: Text('Descargar', style: TextStyle(color: onSurface)),
                        backgroundColor: onSurface.withValues(alpha: 0.12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        side: BorderSide.none,
                        onPressed: () {},
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 16),

                // Barra de Progreso
                if (_duration != null && _duration! > Duration.zero) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8.0),
                    child: StreamBuilder<Duration>(
                      initialData: service.position,
                      stream: service.positionStream,
                      builder: (context, snapshot) {
                        final position = snapshot.data ?? _position;
                        return Column(
                          children: [
                            SliderTheme(
                              data: SliderTheme.of(context).copyWith(
                                trackHeight: 4.0,
                                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6.0),
                                overlayShape: const RoundSliderOverlayShape(overlayRadius: 14.0),
                                activeTrackColor: onSurface,
                                inactiveTrackColor: onSurface.withValues(alpha: 0.24),
                                thumbColor: onSurface,
                              ),
                              child: Slider(
                                value: position.inMilliseconds.toDouble().clamp(
                                      0,
                                      _duration!.inMilliseconds.toDouble(),
                                    ),
                                max: _duration!.inMilliseconds.toDouble(),
                                onChanged: (value) {
                                  _seek(Duration(milliseconds: value.toInt()));
                                },
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16.0),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    _formatDuration(position),
                                    style: TextStyle(color: onSurface.withValues(alpha: 0.54), fontSize: 12),
                                  ),
                                  Text(
                                    _formatDuration(_duration!),
                                    style: TextStyle(color: onSurface.withValues(alpha: 0.54), fontSize: 12),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ] else ...[
                  const SizedBox(height: 48), // Padding por defecto si no hay duración
                ],
                
                const SizedBox(height: 8),

                // Controles de Reproducción
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        icon: Text('1x', style: TextStyle(color: onSurface, fontWeight: FontWeight.bold, fontSize: 16)),
                        onPressed: () {},
                      ),
                      IconButton(
                        icon: Icon(Icons.replay_10, color: onSurface, size: 32),
                        onPressed: isCurrent ? () => _seekRelative(const Duration(seconds: -10)) : null,
                      ),
                      Container(
                        width: 70,
                        height: 70,
                        decoration: BoxDecoration(
                          color: onSurface,
                          shape: BoxShape.circle,
                        ),
                        child: IconButton(
                          icon: isLoading 
                            ? CircularProgressIndicator(color: colorScheme.surface)
                            : Icon(
                                isPlaying ? Icons.pause : Icons.play_arrow,
                                color: colorScheme.surface,
                                size: 40,
                              ),
                          onPressed: isCurrent ? _togglePlayPause : null,
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.forward_30, color: onSurface, size: 32),
                        onPressed: isCurrent ? () => _seekRelative(const Duration(seconds: 30)) : null,
                      ),
                      IconButton(
                        icon: Icon(Icons.bedtime_outlined, color: onSurface),
                        onPressed: () {},
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 24),
              ],
            );
          },
        ),
      ),
    );
  }
}
