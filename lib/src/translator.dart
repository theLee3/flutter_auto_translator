import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:auto_translator/src/exceptions.dart';
import 'package:http/http.dart' as http show Client;

enum _TranslateBackend {
  google('Google', 'translation', 'googleapis.com', '/language/translate/v2'),
  deepL('deepL', 'api', 'deepl.com', '/v2/translate'),
  deepLFree('deepLFree', 'api-free', 'deepl.com', '/v2/translate');

  const _TranslateBackend(this.name, this.subdomain, this.url, this.path);

  final String name;
  final String url;
  final String subdomain;
  final String path;

  Uri getUri([String? apiKey]) => Uri.https(
      '$subdomain.$url', path, apiKey != null ? {'key': apiKey} : null);
}

/// {@template translator}
/// Translates ARB template file via configured cloud translation service.
/// {@endtemplate}
class Translator {
  /// Translates ARB template file via Google Cloud Translate.
  Translator.google(String apiKey)
      : _apiKey = apiKey,
        _translateBackend = _TranslateBackend.google;

  /// Translates ARB template file via DeepL Tranlate.
  Translator.deepL(String apiKey)
      : _apiKey = apiKey,
        _translateBackend = _TranslateBackend.deepL;

  /// Translates ARB template file via DeepL Free Tranlate.
  Translator.deepLFree(String apiKey)
      : _apiKey = apiKey,
        _translateBackend = _TranslateBackend.deepLFree;

  final String _apiKey;
  final _TranslateBackend _translateBackend;

  /// Name of the service used by this translator.
  String get name => _translateBackend.name;

  final _client = http.Client();

  /// Translate values in [toTranslate] from [source] language to [target] language.
  Future<Map<String, String>> translate({
    required Map<String, dynamic> toTranslate,
    required String source,
    required String target,
  }) async {
    final translations = <String, String>{};
    // Google Translate requests are limited to 128 strings & 5k characters,
    // so iterate through in chunks if necessary
    var start = 0;
    while (start < toTranslate.length) {
      final sublist = List.unmodifiable(toTranslate.entries)
          .sublist(start, min(start + 128, toTranslate.length));

      final values = sublist.map<String>((e) => e.value).toList();

      var charCount = values.fold<int>(
          0, (previousValue, element) => previousValue + element.length);
      while (charCount > 5000) {
        sublist.removeLast();
        final removedEntry = values.removeLast();
        charCount -= removedEntry.length;
      }
      List<String>? result;

      switch (_translateBackend) {
        case _TranslateBackend.google:
          result = await _googleTranslate(
            url: _translateBackend.getUri(_apiKey),
            client: _client,
            content: values,
            source: source,
            target: target,
            apiKey: _apiKey,
          );
          break;
        case _TranslateBackend.deepL:
        case _TranslateBackend.deepLFree:
          result = await _deepLTranslate(
            url: _translateBackend.getUri(),
            client: _client,
            content: values,
            source: source,
            target: target,
            apiKey: _apiKey,
          );
          break;
      }

      if (result != null) {
        final keys = List.unmodifiable(sublist.map((e) => e.key));
        for (var i = 0; i < keys.length; i++) {
          translations[keys[i]] =
              _removeAddedWhitespace(result[i], toTranslate[keys[i]], target);
        }
      }
      start += sublist.length;
    }

    return translations;
  }

  Future<List<String>?> _googleTranslate({
    required Uri url,
    required http.Client client,
    required List<String> content,
    required String source,
    required String target,
    required String apiKey,
  }) async {
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
    if (json['error'] != null) {
      throw GoogleTranslateException('\n${json['error']['message']}');
    }

    return json['data']['translations']
        .map((e) => e['translatedText'])
        .toList(growable: false)
        .cast<String>();
  }

  Future<List<String>?> _deepLTranslate({
    required Uri url,
    required http.Client client,
    required List<String> content,
    required String source,
    required String target,
    required String apiKey,
  }) async {
    final response = await client.post(
      url,
      headers: {
        'Authorization': 'DeepL-Auth-Key $apiKey',
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      body: jsonEncode({
        'text': content,
        'target_lang': target,
        'source_lang': source,
        'tag_handling': 'xml',
        'ignore_tags': ['x']
      }),
    );

    if (response.body.isEmpty) return null;

    final json = jsonDecode(utf8.decode(response.bodyBytes));
    if (response.statusCode != 200) {
      throw DeepLTranslateException('\n${json['message']}');
    }

    return json['translations']
        .map((e) => e['text'])
        .toList(growable: false)
        .cast<String>();
  }

  // Google Cloud Translate sometimes introduces whitespace before/after a
  // placeholder, so compare to original and remove it
  String _removeAddedWhitespace(
      String translation, String template, String target) {
    final varExp = RegExp(r'\[_\d*\]');
    final matchesTranslation = List<RegExpMatch>.unmodifiable(
        varExp.allMatches(translation).toList().reversed);
    if (matchesTranslation.isEmpty) return translation;

    final matchesTemplate = List<RegExpMatch>.unmodifiable(
        varExp.allMatches(template).toList().reversed);
    for (var i = 0; i < matchesTranslation.length; i++) {
      // we must work backwards, adjusting ends before starts in order to
      // maintain correct indices
      if (matchesTranslation[i].end < translation.length &&
          translation[matchesTranslation[i].end] == ' ' &&
          matchesTemplate[i].end < template.length &&
          (!RegExp(r'''[.,!?'";:%=\-_\])}\W]''')
                  .hasMatch(template[matchesTemplate[i].end]) ||
              // template[matchesTemplate[i].end] != ' ' ||
              target.startsWith('ja'))) {
        translation = translation.replaceRange(
            matchesTranslation[i].end, matchesTranslation[i].end + 1, '');
      }
      if (matchesTranslation[i].start > 0 &&
          translation[matchesTranslation[i].start - 1] == ' ' &&
          (matchesTemplate[i].start == 0 ||
              template[matchesTemplate[i].start - 1] != ' ' ||
              target.startsWith('ja'))) {
        translation = translation.replaceRange(
            matchesTranslation[i].start - 1, matchesTranslation[i].start, '');
      }
    }
    return translation;
  }
}
