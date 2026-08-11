import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:radio_mix/services/app_http_client.dart';
import 'package:radio_mix/services/app_network_error.dart';

void main() {
  test('appGet reintenta un GET transitorio con error 500', () async {
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      if (calls == 1) {
        return http.Response('upstream error', 500);
      }
      return http.Response('ok', 200);
    });

    final response = await appGet(client, Uri.https('example.com', '/ping'));

    expect(response.statusCode, 200);
    expect(calls, 2);
  });

  test('mergeAppHeaders mantiene un user-agent explicito', () {
    final headers = mergeAppHeaders(const {'User-Agent': 'CustomAgent/9.9'});

    expect(headers['User-Agent'], 'CustomAgent/9.9');
    expect(headers['Accept'], isNotEmpty);
  });

  test('appGet clasifica un 429 como rate limited', () async {
    final client = MockClient(
      (_) async => http.Response('too many requests', 429),
    );

    await expectLater(
      () =>
          appGet(client, Uri.https('example.com', '/limited'), maxAttempts: 1),
      throwsA(
        isA<AppNetworkException>().having(
            (error) => error.type, 'type', AppNetworkErrorType.rateLimited),
      ),
    );
  });
}
