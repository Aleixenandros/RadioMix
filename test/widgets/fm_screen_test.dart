import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:radio_mix/models/radio_station.dart';
import 'package:radio_mix/screens/fm_screen.dart';
import 'package:radio_mix/services/playback_coordinator_service.dart';
import 'package:radio_mix/services/radio_service.dart';

import '../test_doubles/fake_services.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('FMScreen plays online preset when hybrid mode has no antenna',
      (tester) async {
    const fmChannel = MethodChannel('com.radiomix.ralma/fm');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(fmChannel, (call) async => false);
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(fmChannel, null);
    });

    late FakePlaybackCoordinatorService fakeCoordinator;
    final fakeRadioService = FakeRadioService(
      searchResults: {
        'Los 40 España': [
          RadioStation(
            id: 'los40',
            name: 'Los 40',
            streamUrl: 'https://example.com/los40.mp3',
          ),
        ],
      },
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          radioServiceProvider.overrideWithValue(fakeRadioService),
          playbackCoordinatorServiceProvider.overrideWith((ref) {
            fakeCoordinator = FakePlaybackCoordinatorService(ref);
            return fakeCoordinator;
          }),
        ],
        child: const MaterialApp(home: FMScreen()),
      ),
    );
    await tester.pump();

    expect(find.text('Híbrido: online disponible'), findsOneWidget);

    await tester.tap(find.text('REPRODUCIR ONLINE'));
    await tester.pump();
    await tester.pump();

    expect(fakeCoordinator.lastItem?.source, 'https://example.com/los40.mp3');
    expect(fakeCoordinator.lastItem?.title, 'Los 40 FM Online');
  });
}
