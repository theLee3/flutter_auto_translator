/// {@template CustomException}
/// Base class for Auto Translator Exceptions.
/// {@endtemplate}
abstract class CustomException implements Exception {
  /// {@macro CustomException}
  const CustomException([this.message]);

  /// Message representing the error.
  final String? message;

  @override
  String toString() {
    final errorOutput = message == null ? '' : ' \n$message';
    return 'ERROR: $runtimeType$errorOutput $helpMessage';
  }
}

/// {@template ConfigNotFoundException}
/// Thrown when `translator` section is not found in `l10n.yaml`.
/// {@endtemplate}
class ConfigNotFoundException extends CustomException {
  /// {@macro ConfigNotFoundException}
  const ConfigNotFoundException([message]) : super(message);
}

/// {@template NoTargetsProvidedException}
/// Thrown when no target languages are provided in the `translator` section
/// of `l10n.yaml`.
/// {@endtemplate}
class NoTargetsProvidedException extends CustomException {
  /// {@macro NoTargetsProvidedException}
  const NoTargetsProvidedException([message]) : super(message);
}

/// {@template InvalidFormatException}
/// Thrown when opening or closing curly braces are missing from a String in
/// the template ARB file.
/// {@endtemplate}
class InvalidFormatException extends CustomException {
  /// {@macro NoTargetsProvidedException}
  const InvalidFormatException([message]) : super(message);
}

/// {@template GoogleTranslateException}
/// Thrown when an eror occurs communicating with Google Cloud Translate.
/// {@endtemplate}
class GoogleTranslateException extends CustomException {
  /// {@macro GoogleTranslateException}
  const GoogleTranslateException([message]) : super(message);
}

/// Generic help message linking to package usage guide.
String get helpMessage =>
    'Please visit https://pub.dev/packages/auto_translator for usage guide.';
