import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import 'app_logger.dart';
import 'app_network_error.dart';

const Duration kAppRequestTimeout = Duration(seconds: 12);
const Duration kAppDownloadTimeout = Duration(minutes: 30);
const String kAppUserAgent = 'RadioMix/1.5';

final httpClientProvider = Provider<http.Client>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return client;
});

Future<http.Response> appGet(
  http.Client client,
  Uri uri, {
  Map<String, String>? headers,
  Duration timeout = kAppRequestTimeout,
  int maxAttempts = 2,
}) async {
  final mergedHeaders = mergeAppHeaders(headers);

  for (var attempt = 1; attempt <= maxAttempts; attempt++) {
    try {
      final response =
          await client.get(uri, headers: mergedHeaders).timeout(timeout);
      if (attempt > 1) {
        AppLogger.info(
          'network',
          'GET completado tras reintento',
          data: {
            'attempt': attempt,
            'statusCode': response.statusCode,
            'uri': uri,
          },
        );
      }
      if (!_shouldRetryStatusCode(response.statusCode) ||
          attempt == maxAttempts) {
        if (response.statusCode >= 400) {
          final exception =
              AppNetworkException.fromResponse(response, uri: uri);
          AppLogger.warning(
            'network',
            'GET devolvio error HTTP',
            error: exception,
            data: {
              'attempt': attempt,
              'statusCode': response.statusCode,
              'uri': uri,
            },
          );
          throw exception;
        }
        return response;
      }
      AppLogger.warning(
        'network',
        'Reintentando GET por error transitorio',
        data: {
          'attempt': attempt,
          'statusCode': response.statusCode,
          'uri': uri,
        },
      );
    } on TimeoutException {
      if (attempt == maxAttempts) {
        final exception = AppNetworkException.fromError(
          TimeoutException('Timeout'),
          uri: uri,
        );
        AppLogger.error(
          'network',
          'GET agotado por timeout',
          error: exception,
          data: {'attempt': attempt, 'uri': uri},
        );
        throw exception;
      }
      AppLogger.warning(
        'network',
        'Reintentando GET tras timeout',
        data: {'attempt': attempt, 'uri': uri},
      );
    } on SocketException {
      if (attempt == maxAttempts) {
        final exception = AppNetworkException.fromError(
          const SocketException('Socket error'),
          uri: uri,
        );
        AppLogger.error(
          'network',
          'GET agotado por error de socket',
          error: exception,
          data: {'attempt': attempt, 'uri': uri},
        );
        throw exception;
      }
      AppLogger.warning(
        'network',
        'Reintentando GET tras error de socket',
        data: {'attempt': attempt, 'uri': uri},
      );
    } on http.ClientException {
      if (attempt == maxAttempts) {
        final exception = AppNetworkException.fromError(
          http.ClientException('Client exception'),
          uri: uri,
        );
        AppLogger.error(
          'network',
          'GET agotado por client exception',
          error: exception,
          data: {'attempt': attempt, 'uri': uri},
        );
        throw exception;
      }
      AppLogger.warning(
        'network',
        'Reintentando GET tras client exception',
        data: {'attempt': attempt, 'uri': uri},
      );
    }

    await Future<void>.delayed(Duration(milliseconds: 250 * attempt));
  }

  final exception = AppNetworkException(
    type: AppNetworkErrorType.unknown,
    uri: uri,
    message: 'GET agotado sin respuesta',
  );
  AppLogger.error(
    'network',
    'GET agotado sin respuesta',
    error: exception,
    data: {'uri': uri},
  );
  throw exception;
}

Future<http.StreamedResponse> appSend(
  http.Client client,
  http.BaseRequest request, {
  Duration timeout = kAppDownloadTimeout,
}) async {
  request.headers.addAll(mergeAppHeaders(request.headers));
  try {
    return await client.send(request).timeout(timeout);
  } on Object catch (error, stackTrace) {
    final exception = AppNetworkException.fromError(
      error,
      uri: request.url,
    );
    AppLogger.error(
      'network',
      'Fallo al enviar request',
      error: exception,
      stackTrace: stackTrace,
      data: {'method': request.method, 'uri': request.url},
    );
    throw exception;
  }
}

Map<String, String> mergeAppHeaders(Map<String, String>? headers) {
  final merged = <String, String>{
    'Accept': 'application/json, application/xml, text/xml, */*',
    ...?headers,
  };

  final hasUserAgent = merged.keys.any(
    (key) => key.toLowerCase() == 'user-agent',
  );
  if (!hasUserAgent) {
    merged['User-Agent'] = kAppUserAgent;
  }

  return merged;
}

bool _shouldRetryStatusCode(int statusCode) {
  return statusCode == 408 || statusCode == 429 || statusCode >= 500;
}
