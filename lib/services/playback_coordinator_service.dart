import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/playable_item.dart';
import 'app_logger.dart';
import 'app_network_error.dart';
import 'playable_item_action_service.dart';
import 'playback_progress_service.dart';

enum PodcastResumeBehavior { none, automatic, ask }

class PlaybackRequestResult {
  const PlaybackRequestResult({
    required this.didStart,
    this.feedbackMessage,
    this.errorMessage,
    this.resumedFrom,
  });

  final bool didStart;
  final String? feedbackMessage;
  final String? errorMessage;
  final Duration? resumedFrom;
}

final playbackCoordinatorServiceProvider =
    Provider<PlaybackCoordinatorService>(PlaybackCoordinatorService.new);

class PlaybackCoordinatorService {
  PlayableItemActionService get _actionService =>
      _ref.read(playableItemActionServiceProvider);

  PlaybackCoordinatorService(this._ref);

  final Ref _ref;

  Future<PlaybackRequestResult> playItem(
    PlayableItem item, {
    ScaffoldMessengerState? messenger,
    PodcastResumeBehavior podcastResumeBehavior =
        PodcastResumeBehavior.automatic,
    Future<bool?> Function(PlaybackProgress progress)? onRequestResume,
    String? successMessage,
  }) async {
    try {
      Duration? startPosition;
      PlaybackProgress? savedProgress;

      if (item.isPodcast) {
        savedProgress = await _actionService.getSavedProgress(item);
      }

      if (savedProgress != null && savedProgress.position > Duration.zero) {
        switch (podcastResumeBehavior) {
          case PodcastResumeBehavior.none:
            await _actionService.clearSavedProgress(item);
            break;
          case PodcastResumeBehavior.automatic:
            startPosition = savedProgress.position;
            break;
          case PodcastResumeBehavior.ask:
            final shouldContinue = await onRequestResume?.call(savedProgress);
            if (shouldContinue == true) {
              startPosition = savedProgress.position;
            } else {
              await _actionService.clearSavedProgress(item);
            }
            break;
        }
      }

      await _actionService.play(item, startPosition: startPosition);

      final feedbackMessage = successMessage ??
          (startPosition != null
              ? 'Continuando ${item.title} desde ${_formatDuration(startPosition)}'
              : 'Reproduciendo: ${item.title}');
      if (messenger != null) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(feedbackMessage),
            duration: const Duration(seconds: 2),
          ),
        );
      }

      return PlaybackRequestResult(
        didStart: true,
        feedbackMessage: feedbackMessage,
        resumedFrom: startPosition,
      );
    } catch (error, stackTrace) {
      final errorDetail = describeAppError(
        error,
        fallback: 'No se pudo iniciar la reproducción.',
      );
      final errorMessage = 'Error al reproducir: $errorDetail';
      AppLogger.error(
        'audio',
        'Error coordinando reproducción',
        error: error,
        stackTrace: stackTrace,
        data: {'itemId': item.id, 'source': item.source},
      );
      if (messenger != null) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            duration: const Duration(seconds: 4),
            backgroundColor: messenger.context.colorScheme.error,
          ),
        );
      }
      return PlaybackRequestResult(
        didStart: false,
        errorMessage: errorMessage,
      );
    }
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
}

extension on BuildContext {
  ColorScheme get colorScheme => Theme.of(this).colorScheme;
}
