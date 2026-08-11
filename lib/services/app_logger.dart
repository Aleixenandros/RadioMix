import 'dart:developer' as developer;

class AppLogger {
  static void info(
    String scope,
    String message, {
    Map<String, Object?>? data,
  }) {
    developer.log(
      _formatMessage(message, data),
      name: 'RadioMix.$scope',
      level: 800,
    );
  }

  static void warning(
    String scope,
    String message, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?>? data,
  }) {
    developer.log(
      _formatMessage(message, data),
      name: 'RadioMix.$scope',
      level: 900,
      error: error,
      stackTrace: stackTrace,
    );
  }

  static void error(
    String scope,
    String message, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?>? data,
  }) {
    developer.log(
      _formatMessage(message, data),
      name: 'RadioMix.$scope',
      level: 1000,
      error: error,
      stackTrace: stackTrace,
    );
  }

  static String _formatMessage(String message, Map<String, Object?>? data) {
    if (data == null || data.isEmpty) {
      return message;
    }

    final fields =
        data.entries.map((entry) => '${entry.key}=${entry.value}').join(' ');
    return '$message [$fields]';
  }
}
