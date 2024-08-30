/// {@template CustomException}
/// Base class for Auto Translator Exceptions.
/// {@endtemplate}
abstract class CustomException implements Exception {
  /// {@macro CustomException}
  const CustomException([this._message]);

  /// Message representing the error.
  final String? _message;

  /// Generic help message linking to package usage guide.
  String get _helpMessage => ' $helpMessage';

  @override
  String toString() {
    final errorOutput = _message == null ? '' : '$_message';
    return '\nERROR: $runtimeType$errorOutput$_helpMessage';
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
  const InvalidFormatException([key])
      : super('Template ARB file is malformed. Missing '
            'opening or closing curly brace in `$key`.');
}

/// {@template MissingTranslatorKeyException}
/// Thrown when a key has not been provided for a specified translator.
/// {@endtemplate}
class MissingTranslatorKeyException extends CustomException {
  /// {@macro MissingTranslatorKeyException}
  const MissingTranslatorKeyException([message]) : super(message);
}

/// {@template MalformedTranslatorKeyFileException}
/// Thrown when the key file is not formatted correctly.
/// {@endtemplate}
class MalformedTranslatorKeyFileException extends CustomException {
  /// {@macro MalformedTranslatorKeyFileException}
  const MalformedTranslatorKeyFileException()
      : super(
          'The key file must consists of a single string or a json map.',
        );

  @override
  String get _helpMessage =>
      ' See https://pub.dev/packages/auto_translator#3-setup-the-config-files '
      'for more details.';
}

/// {@template GoogleTranslateException}
/// Thrown when an error occurs communicating with Google Cloud Translate.
/// {@endtemplate}
class GoogleTranslateException extends CustomException {
  /// {@macro GoogleTranslateException}
  const GoogleTranslateException([message]) : super(message);

  @override
  String get _helpMessage => ' See API spec at '
      'https://cloud.google.com/translate/docs/reference/rest/v2/translate.';
}

/// {@template DeepLTranslateException}
/// Thrown when an error occurs communicating with DeepL Translate.
/// {@endtemplate}
class DeepLTranslateException extends CustomException {
  /// {@macro DeepLTranslateException}
  const DeepLTranslateException([message]) : super(message);

  @override
  String get _helpMessage => ' See API spec at '
      'https://developers.deepl.com/docs/api-reference/translate/openapi-spec-for-text-translation.';
}

/// {@template UnsupportedTranslatorServiceException}
/// Thrown when an unsupported translator service is specified in the l10n.yaml file.
/// {@endtemplate}
class UnsupportedTranslatorServiceException extends CustomException {
  /// {@macro UnsupportedTranslatorServiceException}
  const UnsupportedTranslatorServiceException([message]) : super(message);
}

/// Generic help message linking to package usage guide.
const helpMessage =
    'Please visit https://pub.dev/packages/auto_translator for usage guide.';
