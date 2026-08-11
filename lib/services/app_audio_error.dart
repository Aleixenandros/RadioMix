import 'dart:io';

import 'package:just_audio/just_audio.dart';

enum AppAudioErrorKind {
  invalidSource,
  missingFile,
  unsupported,
  interrupted,
  engine,
  unknown,
}

class AppAudioException implements Exception {
  const AppAudioException({
    required this.kind,
    required this.message,
    this.source,
    this.originalError,
  });

  final AppAudioErrorKind kind;
  final String message;
  final String? source;
  final Object? originalError;

  String get userMessage {
    return switch (kind) {
      AppAudioErrorKind.invalidSource =>
        'La fuente de audio no es una URL o archivo válido.',
      AppAudioErrorKind.missingFile =>
        'El archivo de audio ya no está disponible en el dispositivo.',
      AppAudioErrorKind.unsupported =>
        'Este formato o stream de audio no es compatible.',
      AppAudioErrorKind.interrupted =>
        'La reproducción se interrumpió antes de empezar.',
      AppAudioErrorKind.engine => 'El reproductor no pudo abrir este stream.',
      AppAudioErrorKind.unknown =>
        message.isEmpty ? 'No se pudo iniciar el audio.' : message,
    };
  }

  factory AppAudioException.fromError(
    Object error, {
    String? source,
  }) {
    if (error is AppAudioException) return error;
    if (error is FormatException) {
      return AppAudioException(
        kind: AppAudioErrorKind.invalidSource,
        message: error.message,
        source: source,
        originalError: error,
      );
    }
    if (error is FileSystemException) {
      return AppAudioException(
        kind: AppAudioErrorKind.missingFile,
        message: error.message,
        source: source ?? error.path,
        originalError: error,
      );
    }
    if (error is PlayerException) {
      return AppAudioException(
        kind: AppAudioErrorKind.engine,
        message: error.message ?? 'Error del motor de audio',
        source: source,
        originalError: error,
      );
    }
    return AppAudioException(
      kind: AppAudioErrorKind.unknown,
      message: error.toString().replaceFirst(RegExp(r'^Exception:\s*'), ''),
      source: source,
      originalError: error,
    );
  }

  @override
  String toString() => 'AppAudioException($kind, $message)';
}
