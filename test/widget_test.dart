import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:radio_mix/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('App renders smoke test', (WidgetTester tester) async {
    const fmChannel = MethodChannel('com.radiomix.ralma/fm');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(fmChannel, (call) async => false);

    await tester.pumpWidget(const ProviderScope(child: RadioMixApp()));

    // Verifica que la app carga correctamente
    expect(find.text('Radio Mix'), findsOneWidget);

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(fmChannel, null);
  });
}
