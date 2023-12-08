import 'exceptions.dart';

/// {@template transformer}
/// Transforms ARB strings to/from format used by [Translator].
/// {@endtemplate}
class Transformer {
  final _openBracket = RegExp(r"(?<!'){");
  final _closeBracket = RegExp(r"(?<!')}");
  final _commaAndAnyTrailingWhitespace = RegExp(r",\s*");

  // expression used to for arb variables
  final _variableExp = RegExp(r'\[_\d*\]');

  // map for storing arb variables
  final _variableMap = <String, String>{};

  // map for storing complex arb prefixes (i.e index, select)
  final _prefixMap = <String, String>{};

  /// Encode the input string into the format to be used by [Translator].
  dynamic encode(String input) => _encodeString(input);

  /// Decode the input string or map from the [Translator] output to proper ARB format.
  String decode(dynamic input) => input is String
      ? _decodeSimpleString(input)
      : _decodeComplexString(input);

  String _decodeSimpleString(String string) {
    // reverse variable list so locations in string are not affected
    // during manipulation
    final variables = _variableExp.allMatches(string).toList().reversed;
    for (final variable in variables) {
      final replacement =
          _variableMap[string.substring(variable.start, variable.end)];
      if (replacement != null) {
        string = string.replaceRange(variable.start, variable.end, replacement);
      }
    }
    return string;
  }

  String _decodeComplexString(Map<String, String> strings) {
    final entries = strings.entries;
    final keyParts = entries.first.key.split('_');
    final prefixMarker = keyParts[keyParts.length - 2];
    final prefix = _prefixMap.entries
        .firstWhere((entry) => entry.value == prefixMarker)
        .key;
    final pieces = entries
        .map((entry) => '${entry.key.split('_').last}{${entry.value}}')
        .reduce((value, element) => '$value $element');
    return '{$prefix, $pieces}';
  }

  dynamic _encodeString(String string) {
    final firstBraceIndex = string.indexOf(_openBracket);
    if (firstBraceIndex < 0) return string;

    if (_openBracket.allMatches(string).length !=
        _closeBracket.allMatches(string).length) {
      throw InvalidFormatException();
    }

    try {
      final firstMatch = string.substring(
          string.indexOf(_openBracket), string.indexOf(_closeBracket) + 1);
      if (firstMatch.substring(1).contains(_openBracket)) {
        return _encodeComplexString(string.substring(1, string.length - 1));
      }

      do {
        final start = string.lastIndexOf(_openBracket);
        final end = string.lastIndexOf(_closeBracket) + 1;
        final variable = string.substring(start, end);
        final replacement = _assignVariable(variable);
        string = string.replaceAll(variable, replacement);
      } while (string.contains(_openBracket));
    } on IndexError catch (_) {
      throw InvalidFormatException();
    }
    return string;
  }

  Map<String, String> _encodeComplexString(String string) {
    final endOfPrefix = string.indexOf(_commaAndAnyTrailingWhitespace,
        string.indexOf(_commaAndAnyTrailingWhitespace) + 1);
    final strings = <String, String>{};
    if (endOfPrefix > 0) {
      final prefix = string.substring(0, endOfPrefix);
      final prefixMarker =
          _prefixMap.putIfAbsent(prefix, () => '${_prefixMap.length}');
      string = string.substring(endOfPrefix + 1).trim();
      do {
        var openIndex = string.indexOf(_openBracket);
        var closeIndex = string.indexOf(_closeBracket);
        final subKey = string.substring(0, openIndex);
        string = string.substring(openIndex);
        openIndex = 0;
        closeIndex -= subKey.length;
        var currentStart = openIndex + 1;
        while (
            string.substring(currentStart, closeIndex).contains(_openBracket)) {
          // arb strings that start with a variable must be treated differently
          if (string[currentStart] == '{') {
            currentStart++;
          } else {
            currentStart = string.indexOf(_openBracket, currentStart + 1) + 1;
          }
          closeIndex = string.indexOf(_closeBracket, closeIndex + 1);
        }
        strings['${prefixMarker}_$subKey'] =
            _encodeString(string.substring(openIndex + 1, closeIndex));
        string = string.substring(closeIndex + 1).trim();
      } while (string.contains(_openBracket));
    } else {
      throw InvalidFormatException();
    }
    return strings;
  }

  String _assignVariable(String value) {
    if (_variableMap.containsValue(value)) {
      return _variableMap.entries
          .firstWhere((entry) => entry.value == value)
          .key;
    }
    final variableName = '[_${_variableMap.length}]';
    _variableMap[variableName] = value;
    return variableName;
  }
}
