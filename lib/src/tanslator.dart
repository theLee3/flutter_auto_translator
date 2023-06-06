import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:auto_translator/auto_translator.dart';
import 'package:http/http.dart' as http;

const _googleApiUrl = 'googleapis.com';
const _translateSubdomain = 'translation';
const _translatePath = '/language/translate/v2';

/// {@template translator}
/// Translates ARB template file according to options set in [_config].
/// {@endtemplate}
class Translator {
  /// {@macro translator}
  Translator(this._config);
  final Map<String, dynamic> _config;

  final _openBracket = RegExp(r"(?<!'){");
  final _closeBracket = RegExp(r"(?<!')}");
  final _anybracket = RegExp(r"{|}|'{|'}");

  // expression for finding variables in complex arb string
  final _complexArbVarExp = RegExp(r'\$\w*');

  // expression used for storing variables in simple arb strings
  final _simpleVarExp = RegExp(r'\[VAR_\d*\]');

  // expression used for storing variables in complex arb strings
  final _complexVarExp = RegExp(r'\[CVAR_\d*\]');

  // map for storing simple arb string variables
  final _variableMap = <String, String>{};

  // map for storing complex arb string variables
  final _complexMap = <String, String>{};

  // cached templates
  final _templates = <String, Map<String, dynamic>>{};
  final Map<dynamic, dynamic> _arbOptions = {};

  /// Translate to all targets using [client].
  Future<void> translate(http.Client client) async {
    final keyFile = File(_config['key_file']);
    final apiKey = keyFile.readAsStringSync();

    final targets = (_config['targets'] as List).cast<String>();
    if (targets.isEmpty) {
      stderr.writeln(NoTargetsProvidedException(
          'No targets were provided in `$configFile`. There\'s nothing for me to do.'));
      exit(1);
    }

    final arbDir = _config['arb-dir'] as String? ?? "lib/l10n";
    final templateFilename = _config['template-arb-file'] as String? ?? "app_en.arb";
    final preferTemplateLang = _config['prefer-lang-templates']?.cast<String, dynamic>() ?? {};

    if (!RegExp(r'^[a-zA-Z0-9]+_[a-zA-Z0-9_\-]+\.arb$').hasMatch(templateFilename)) {
      stderr.writeln(NoTargetsProvidedException(
          'templateFilename should be like: ' + r'^[a-zA-Z0-9]+_[a-zA-Z0-9_\-]+\.arb$'));
      exit(1);
    }

    final source = templateFilename.substring(templateFilename.indexOf(RegExp(r'[-_]')) + 1, templateFilename.indexOf('.arb'));
    final name = templateFilename.substring(0, templateFilename.indexOf(RegExp(r'[-_]')));
    stdout.writeln('Use source language: $source, name: $name, templateFilename: $templateFilename');

    final translations = <String, String>{};
    final encoder = JsonEncoder.withIndent('    ');

    for (final target in targets) {
      var preferLang = preferTemplateLang[target];
      var arbTemplate = await _readTemplateFile(arbDir, name, preferLang ?? source);

      final toTranslate =
          List<MapEntry<String, dynamic>>.from(arbTemplate.entries);
      final arbFile = File('$arbDir/${name}_$target.arb');
      if (arbFile.existsSync()) {
        // do not translate previously translated phrases
        // unless marked force
        final prevTranslations =
            jsonDecode(arbFile.readAsStringSync()).cast<String, String>();
        toTranslate.removeWhere((element) =>
            prevTranslations.containsKey(element.key) &&
            !(_arbOptions['@${element.key}']?['translator']?['force'] ?? false));
        translations.addAll(prevTranslations);
      }

      if (toTranslate.isEmpty) {
        stdout.writeln('No changes to ${name}_$target.arb');
        continue;
      }

      stdout.writeln('Translating ${preferLang ?? source} to $target...');

      // Google Translate requests are limited to 128 strings & 5k characters,
      // so iterate through in chunks if necessary
      var start = 0;
      while (start < toTranslate.length) {
        final sublist =
            toTranslate.sublist(start, min(start + 128, toTranslate.length));

        final values = sublist.map<String>((e) => e.value).toList();

        var charCount = values.fold<int>(
            0, (previousValue, element) => previousValue + element.length);
        while (charCount > 5000) {
          sublist.removeLast();
          final removedEntry = values.removeLast();
          charCount -= removedEntry.length;
        }

        final result = await _translate(
          client: client,
          content: values,
          source: source,
          target: target,
          apiKey: apiKey,
        );
        if (result != null) {
          final keys = sublist.map((e) => e.key).toList();
          for (var i = 0; i < keys.length; i++) {
            final translatedString =
                _removeAddedWhitespace(result[i], arbTemplate[keys[i]]);
            translations[keys[i]] = _decodeString(translatedString);
          }
        }
        start += sublist.length;
      }

      if (translations.isNotEmpty) {
        // if the ARB file exists, match entry order to the template file
        final output = arbFile.existsSync()
            ? {for (var key in arbTemplate.keys) key: translations[key]}
            : translations;
        arbFile.writeAsStringSync(encoder.convert(output));
      }

      stdout.writeln('Translated ${preferLang ?? source} to $target.');
    }

    stdout.writeln('done.');
    exit(0);
  }

  Future<Map<String, dynamic>> _readTemplateFile(String arbDir, String name, String lang) async {
    var path = '$arbDir/${name}_${lang}.arb';
    final templateFile = File(path);
    if (_templates[path] != null) return _templates[path]!;

    final arbTemplate = jsonDecode(templateFile.readAsStringSync()) as Map<String, dynamic>;

    // copy string metadata over from template, then remove from template
    final _arbOptions = Map.from(arbTemplate)
      ..removeWhere((key, value) => !key.startsWith('@'));
    arbTemplate.removeWhere((key, value) => key.startsWith('@'));

    // remove strings that are marked ignore
    arbTemplate.removeWhere((key, value) =>
    (_arbOptions['@$key']?['translator']?['ignore'] ?? false));

    for (final entry in arbTemplate.entries) {
      arbTemplate[entry.key] = _encodeString(entry);
    }

    return _templates[path] = arbTemplate;
  }

  Future<List<String>?> _translate({
    required http.Client client,
    required List<String> content,
    required String source,
    required String target,
    required String apiKey,
  }) async {
    final url = Uri.https(
        '$_translateSubdomain.$_googleApiUrl', _translatePath, {'key': apiKey});
    final response = await client.post(
      url,
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      body: jsonEncode({
        'q': content,
        'source': source,
        'target': target,
        'format': 'text',
      }),
    );

    if (response.body.isEmpty) return null;
    final json = jsonDecode(response.body);
    // stdout.write('auto_translate url: $url, content: $content, source: $source, target: $target, response: ${json}');
    if (json['error'] != null) {
      stderr.writeln(GoogleTranslateException('\n${json['error']['message']}'));
      exit(1);
    }
    return json['data']['translations']
        .map((e) => e['translatedText'])
        .toList()
        .cast<String>();
  }

  // Google Cloud Translate sometimes introduces whitespace before a closing
  // curly brace, so compare to original and remove it
  String _removeAddedWhitespace(String translation, String template) {
    final matchesTranslation =
        _anybracket.allMatches(translation).toList(growable: false);
    if (matchesTranslation.isEmpty) return translation;

    final matchesTemplate =
        _anybracket.allMatches(template).toList(growable: false);
    var result = translation;
    for (var i = 0; i < matchesTranslation.length; i++) {
      if (matchesTranslation[i].start > 0 &&
          translation[matchesTranslation[i].start - 1] == ' ' &&
          template[matchesTemplate[i].start - 1] != '') {
        result = result.replaceRange(
            matchesTranslation[i].start - 1, matchesTranslation[i].start, '');
      }
    }
    return result;
  }

  String _decodeString(String string) => string.startsWith(_complexVarExp)
      ? _decodeComplexString(string)
      : _decodeSimpleString(string);

  String _decodeSimpleString(String string) {
    // reverse variable list so locations in string are not affected
    // during manipulation
    final variables = _simpleVarExp.allMatches(string).toList().reversed;
    for (final variable in variables) {
      final replacement =
          _variableMap[string.substring(variable.start, variable.end)];
      if (replacement != null) {
        string = string.replaceRange(variable.start, variable.end, replacement);
      }
    }
    return string;
  }

  String _decodeComplexString(String string) {
    final variables = _complexVarExp.allMatches(string).toList().reversed;
    for (final variable in variables) {
      var replacement =
          _complexMap[string.substring(variable.start, variable.end)];
      if (replacement != null && replacement.isNotEmpty) {
        // some language translations (i.e. Japanese) may remove spaces
        // that are part of the arb spacing, so correct for those changes
        if (replacement[0] != '\$' &&
            variable.start != 0 &&
            string[variable.start - 1] != ' ') {
          replacement = ' $replacement';
        }
        string = string.replaceRange(variable.start, variable.end, replacement);
      }
    }
    return '{$string}';
  }

  String _encodeString(MapEntry<String, dynamic> entry) {
    String string = entry.value;
    final firstBraceIndex = string.indexOf(_openBracket);
    if (firstBraceIndex < 0) return string;

    if (_openBracket.allMatches(string).length !=
        _closeBracket.allMatches(string).length) {
      throw InvalidFormatException(entry.key);
    }

    try {
      final firstMatch = string.substring(
          string.indexOf(_openBracket), string.indexOf(_closeBracket) + 1);
      if (firstMatch.substring(1).contains(_openBracket)) {
        return _encodeComplexString(string.substring(1, string.length - 1));
      }

      final variables = <String>[];
      var adjustedString = string;
      do {
        final start = adjustedString.lastIndexOf(_openBracket);
        final end = adjustedString.lastIndexOf(_closeBracket) + 1;
        variables.add(adjustedString.substring(start, end));
        adjustedString = adjustedString.substring(0, start);
      } while (adjustedString.contains(_openBracket));

      for (final variable in variables) {
        final replacement = _createVariable(variable);
        string = string.replaceFirst(variable, replacement);
      }
    } on IndexError catch (_) {
      throw InvalidFormatException(entry.key);
    }

    return string;
  }

  String _encodeComplexString(String string) {
    final prefix =
        string.substring(0, string.indexOf(',', string.indexOf(',') + 1) + 1);
    final replacementPrefix = _createComplexVariable(prefix);
    string = string.replaceFirst(prefix, replacementPrefix);
    final complexStrings = string
        .substring(replacementPrefix.length, string.length - 1)
        .trim()
        .split(_closeBracket);
    for (final complexString in complexStrings) {
      final parts = complexString.trim().split(_openBracket);
      final name = parts[0];
      string =
          string.replaceFirst('$name{', '${_createComplexVariable(name)}{');
    }
    final variables = _complexArbVarExp.allMatches(string).toList().reversed;
    for (final variable in variables) {
      final replacement = _createComplexVariable(
          string.substring(variable.start, variable.end));
      string = string.replaceRange(variable.start, variable.end, replacement);
    }
    return string;
  }

  String _createVariable(String value) {
    final variableName = '[VAR_${_variableMap.length}]';
    _variableMap[variableName] = value;
    return variableName;
  }

  String _createComplexVariable(String value) {
    final variableName = '[CVAR_${_complexMap.length}]';
    _complexMap[variableName] = value;
    return variableName;
  }
}
