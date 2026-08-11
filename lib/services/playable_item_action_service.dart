import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/playable_item.dart';
import 'audio_player_service.dart';
import 'playback_progress_service.dart';
import 'radio_service.dart';

final playableItemActionServiceProvider =
    Provider<PlayableItemActionService>(PlayableItemActionService.new);

class PlayableItemActionService {
  PlayableItemActionService(this._ref);

  final Ref _ref;

  Future<void> play(
    PlayableItem item, {
    Duration? startPosition,
  }) async {
    _ref.read(currentPlayableProvider.notifier).setItem(item);
    await _ref.read(audioPlayerServiceProvider).playItem(
          item,
          startPosition: startPosition,
        );
  }

  Future<PlaybackProgress?> getSavedProgress(PlayableItem item) async {
    if (!item.isPodcast) return null;
    return _ref.read(playbackProgressServiceProvider).getProgress(item.id);
  }

  Future<void> clearSavedProgress(PlayableItem item) async {
    if (!item.isPodcast) return;
    await _ref.read(playbackProgressServiceProvider).clearProgress(item.id);
  }

  Future<void> addFavorite(PlayableItem item) async {
    if (!item.isRadio) return;
    await _ref.read(radioServiceProvider).addFavorite(item.toRadioStation());
  }
}
