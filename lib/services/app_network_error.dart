import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'app_audio_error.dart';
import 'app_logger.dart';

enum AppNetworkErrorType {
  timeout,
  offline,
  rateLimited,
  client,
  server,
  transport,
  invalidUrl,
  unknown,
}

class AppNetworkException implements Exception {
  const AppNetworkException({
    required this.type,
    required this.message,
    this.uri,
    this.statusCode,
    this.cause,
  });

  final AppNetworkErrorType type;
  final String message;
  final Uri? uri;
  final int? statusCode;
  final Object? cause;

  bool get isTransient {
    return switch (type) {
      AppNetworkErrorType.timeout => true,
      AppNetworkErrorType.offline => true,
      AppNetworkErrorType.rateLimited => true,
      AppNetworkErrorType.server => true,
      _ => false,
    };
  }

  String get userMessage {
    return switch (type) {
      AppNetworkErrorType.timeout =>
        'La solicitud tardó demasiado. Revisa tu conexión e inténtalo de nuevo.',
      AppNetworkErrorType.offline =>
        'No hay conexión de red disponible en este momento.',
      AppNetworkErrorType.rateLimited =>
        'El servicio remoto ha limitado temporalmente las solicitudes.',
      AppNetworkErrorType.client =>
        'La solicitud al servicio remoto no fue aceptada.',
      AppNetworkErrorType.server =>
        'El servicio remoto devolvió un error temporal.',
      AppNetworkErrorType.transport =>
        'No se pudo completar la conexión con el servicio remoto.',
      AppNetworkErrorType.invalidUrl => 'La URL solicitada no es válida.',
      AppNetworkErrorType.unknown =>
        'Se produjo un error de red no clasificado.',
    };
  }

  @override
  String toString() => userMessage;

  factory AppNetworkException.fromResponse(
    http.Response response, {
    required Uri uri,
  }) {
    final statusCode = response.statusCode;
    final type = switch (statusCode) {
      408 => AppNetworkErrorType.timeout,
      429 => AppNetworkErrorType.rateLimited,
      >= 500 => AppNetworkErrorType.server,
      >= 400 => AppNetworkErrorType.client,
      _ => AppNetworkErrorType.unknown,
    };

    return AppNetworkException(
      type: type,
      uri: uri,
      statusCode: statusCode,
      message: 'HTTP $statusCode en ${uri.host}${uri.path}',
    );
  }

  factory AppNetworkException.fromError(
    Object error, {
    required Uri uri,
  }) {
    if (error is AppNetworkException) {
      return error;
    }
    if (error is TimeoutException) {
      return AppNetworkException(
        type: AppNetworkErrorType.timeout,
        uri: uri,
        cause: error,
        message: 'Timeout al conectar con ${uri.host}${uri.path}',
      );
    }
    if (error is SocketException) {
      return AppNetworkException(
        type: AppNetworkErrorType.offline,
        uri: uri,
        cause: error,
        message: 'Socket error al conectar con ${uri.host}${uri.path}',
      );
    }
    if (error is http.ClientException) {
      return AppNetworkException(
        type: AppNetworkErrorType.transport,
        uri: uri,
        cause: error,
        message: 'Client error al conectar con ${uri.host}${uri.path}',
      );
    }

    return AppNetworkException(
      type: AppNetworkErrorType.unknown,
      uri: uri,
      cause: error,
      message: 'Error no clasificado en ${uri.host}${uri.path}',
    );
  }
}

String describeAppError(
  Object error, {
  String fallback = 'Ha ocurrido un error inesperado.',
}) {
  if (error is AppNetworkException) {
    return error.userMessage;
  }
  if (error is AppAudioException) {
    return error.userMessage;
  }
  if (error is FileSystemException) {
    return error.message.isNotEmpty
        ? error.message
        : 'No se pudo acceder al archivo solicitado.';
  }
  if (error is FormatException) {
    return error.message.isNotEmpty ? error.message : 'Formato no válido.';
  }

  final raw = error.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');
  if (raw.isNotEmpty && raw != 'null') {
    return raw;
  }
  return fallback;
}

Never logAndRethrowAppError(
  String scope,
  String message,
  Object error,
  StackTrace stackTrace,
) {
  AppLogger.error(scope, message, error: error, stackTrace: stackTrace);
  throw Exception(describeAppError(error));
}
