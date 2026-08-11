import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:radio_mix/main.dart';
import 'package:radio_mix/screens/settings_screen.dart';
import 'package:radio_mix/services/podcast_download_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SettingsScreen', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    testWidgets('renders package info and download size from providers',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            packageInfoProvider.overrideWith((ref) async {
              return PackageInfo(
                appName: 'Radio Mix',
                packageName: 'com.example.radio_mix',
                version: '2.1.0',
                buildNumber: '42',
              );
            }),
            totalDownloadSizeProvider.overrideWith((ref) async => 2048),
          ],
          child: const MaterialApp(home: SettingsScreen()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('Espacio usado'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      expect(find.text('2.0 KB en descargas'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text('Versión'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      expect(find.text('2.1.0+42'), findsOneWidget);
    });

    testWidgets('changes theme from selector', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: SettingsScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(container.read(themeModeProvider), ThemeMode.system);

      await tester.tap(find.text('Tema'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Oscuro'));
      await tester.pumpAndSettle();

      expect(container.read(themeModeProvider), ThemeMode.dark);
      expect(find.text('Oscuro'), findsOneWidget);
    });
  });
}
