import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:radio_mix/services/playback_progress_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PlaybackProgressService', () {
    late PlaybackProgressService service;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      service = PlaybackProgressService();
    });

    test('saveProgress and getProgress round-trip the stored values', () async {
      await service.saveProgress(
        'podcast_ep_1',
        const Duration(minutes: 12, seconds: 34),
        const Duration(minutes: 48),
      );

      final progress = await service.getProgress('podcast_ep_1');

      expect(progress, isNotNull);
      expect(progress!.stationId, 'podcast_ep_1');
      expect(progress.position, const Duration(minutes: 12, seconds: 34));
      expect(progress.duration, const Duration(minutes: 48));
    });

    test('clearProgress removes a saved entry', () async {
      await service.saveProgress(
        'podcast_ep_2',
        const Duration(minutes: 5),
        const Duration(minutes: 25),
      );

      await service.clearProgress('podcast_ep_2');

      expect(await service.getProgress('podcast_ep_2'), isNull);
    });

    test('getAllProgress returns entries sorted by lastPlayed descending',
        () async {
      SharedPreferences.setMockInitialValues({
        'playback_progress_old': jsonEncode({
          'stationId': 'old',
          'position': 30,
          'duration': 120,
          'lastPlayed': DateTime.utc(2026, 1, 1).toIso8601String(),
        }),
        'playback_progress_new': jsonEncode({
          'stationId': 'new',
          'position': 60,
          'duration': 180,
          'lastPlayed': DateTime.utc(2026, 2, 1).toIso8601String(),
        }),
      });

      service = PlaybackProgressService();

      final all = await service.getAllProgress();

      expect(all.map((item) => item.stationId), ['new', 'old']);
    });
  });
}
