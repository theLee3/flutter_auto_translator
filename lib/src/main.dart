import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:auto_translator/src/exceptions.dart';
import 'package:auto_translator/src/spinner.dart';
import 'package:auto_translator/src/transformer.dart';
import 'package:yaml/yaml.dart';

import 'translator.dart';

const _helpFlag = 'help';
const _configOption = 'config-file';
const _verboseFlag = 'verbose';

const _defaultConfigFile = 'l10n.yaml';
const _translatorKey = 'translator';
const _defaultKeyFile = 'translator_keys';

var _verboseOutput = false;

/// Parses arguments from command line, providing help or generating translations.
Future<void> runWithArguments(List<String> arguments) async {
  final parser = ArgParser();
  parser
    ..addFlag(_helpFlag, abbr: 'h', help: 'Usage help', negatable: false)
    ..addFlag(
      _verboseFlag,
      abbr: 'v',
      help: 'Enable verbose output for debugging',
      negatable: false,
    )
    ..addOption(
      _configOption,
      abbr: 'f',
      help: 'Path to config file',
      defaultsTo: _defaultConfigFile,
    );

  if (_verboseOutput) stdout.writeln('Parsing arguments');

  final argResults = parser.parse(arguments);

  if (argResults[_helpFlag]) {
    stdout.writeln(helpMessage);
  } else {
    if (_verboseOutput) stdout.writeln('Determining config file');
    final configFileName = argResults[_configOption] ?? _defaultConfigFile;
    if (_verboseOutput) stdout.writeln('Using config file: configFileName');
    final configFile = File(configFileName);

    if (!configFile.existsSync()) {
      throw ConfigNotFoundException('`$configFile` not found.');
    }

    if (_verboseOutput) {
      stdout.writeln('Reading configuration from $configFileName');
    }
    final yamlString = configFile.readAsStringSync();
    final yamlMap = loadYaml(yamlString);

    if (yamlMap[_translatorKey] is! Map) {
      throw ConfigNotFoundException(
          '`$configFile` is missing `translator` section or it is configured incorrectly.');
    }

    _verboseOutput = argResults[_verboseFlag];

    final Map<String, dynamic> config =
        _mapConfigEntries((yamlMap as Map).entries);
    await _translate(config);
  }
}

Map<String, dynamic> _mapConfigEntries(Iterable<MapEntry> entries) {
  final Map<String, dynamic> config = <String, dynamic>{};
  for (final entry in entries) {
    if (entry.key == _translatorKey) {
      config.addAll(Map<String, dynamic>.from(YamlMap.wrap(entry.value)));
    } else if (entry.value is YamlList) {
      config[entry.key] = (entry.value as YamlList).toList();
    } else {
      config[entry.key] = entry.value;
    }
  }
  if (!config.containsKey('service')) {
    stdout.writeln(
      'No translator service was specified in the yaml file, using Google Cloud Translate.',
    );
    config['service'] = 'Google';
  }
  config.putIfAbsent('key_file', () => _defaultKeyFile);
  return config;
}

Future<void> _translate(Map<String, dynamic> config) async {
  if (_verboseOutput) stdout.writeln('Reading target list');
  final targets = List<String>.from(config['targets'] as List? ?? []);
  if (targets.isEmpty) {
    throw NoTargetsProvidedException(
        'No targets were provided. There\'s nothing to do.');
  }

  final arbDir = config['arb-dir'] as String? ?? 'lib/l10n';
  final templateFilename =
      config['template-arb-file'] as String? ?? 'app_en.arb';
  final Map<String, dynamic> preferTemplateLang =
      config['prefer-lang-templates']?.cast<String, dynamic>() ?? {};
  final preferTranslatorService = <String, dynamic>{};
  for (final entry in Map<String, dynamic>.from(
          config['prefer-service']?.cast<String, dynamic>() ?? {})
      .entries) {
    final service = entry.key.toLowerCase();
    final targets = List<String>.from(entry.value);
    for (final target in targets) {
      preferTranslatorService[target] = service;
    }
  }

  if (!RegExp(r'^[a-zA-Z0-9]+_[a-zA-Z0-9_\-]+\.arb$')
      .hasMatch(templateFilename)) {
    throw NoTargetsProvidedException(
        '[template-arb-file] should be in the format: '
        r'^[a-zA-Z0-9]+_[a-zA-Z0-9_\-]+\.arb$');
  }

  final defaultSource = templateFilename.substring(
      templateFilename.lastIndexOf(('_')) + 1,
      templateFilename.indexOf('.arb'));
  final name = templateFilename.substring(0, templateFilename.lastIndexOf('_'));

  final encoder = JsonEncoder.withIndent('    ');

  if (_verboseOutput) stdout.writeln('Looking for key file');
  if (!File(config['key_file']).existsSync()) {
    // fallback to translator_key file for backwards compatibility
    if (config['key_file'] == _defaultKeyFile &&
        File('translator_key').existsSync()) {
      config['key_file'] = 'translator_key';
    } else {
      throw MissingTranslatorKeyException(
        'Could not find file: ${File(config['key_file']).path}',
      );
    }
  }

  if (_verboseOutput) stdout.writeln('Reading API key(s)');
  final keyFileData = File(config['key_file']).readAsStringSync();
  final apiKeys = <String, String>{};
  // handle simple api key string file for backwards compatibility
  if (!keyFileData.startsWith('{') || !keyFileData.endsWith('}')) {
    apiKeys['default'] = keyFileData;
  } else {
    try {
      final json = jsonDecode(keyFileData) as Map<String, dynamic>;
      for (final entry in json.entries) {
        apiKeys[entry.key.toLowerCase()] = entry.value.toString();
      }
    } catch (error) {
      throw MalformedTranslatorKeyFileException();
    }
  }

  if (_verboseOutput) stdout.writeln('Creating Transformer');
  final transformer = Transformer();

  getTranslator(String name) {
    final apiKey = apiKeys[name] ?? apiKeys['default'];
    switch (name) {
      case 'google':
        if (apiKey == null) {
          throw MissingTranslatorKeyException('No key provided for Google.');
        }
        return Translator.google(apiKey);
      case 'deepl':
        if (apiKey == null) {
          throw MissingTranslatorKeyException('No key provided for DeepL.');
        }
        return Translator.deepL(apiKey);
      default:
        throw UnsupportedTranslatorServiceException(
          '$name is not a valid translator service.',
        );
    }
  }

  final defaultTranslatorService = config['service'].toString().toLowerCase();
  final translators = <String, Translator>{};

  if (_verboseOutput) stdout.writeln('Creating Translator(s)');
  translators[defaultTranslatorService] =
      getTranslator(defaultTranslatorService);
  for (final entry in preferTranslatorService.entries) {
    translators.putIfAbsent(entry.value, () => getTranslator(entry.value));
  }

  // cached templates
  final originalTemplates = <String, Map<String, dynamic>>{};
  final modifiedTemplates = <String, Map<String, dynamic>>{};
  final templateMetadata = <String, Map<String, dynamic>>{};

  // examples to use instead of placeholder variables
  final examples = <String, Map<String, String>>{};

  // sort target order to account for preferred template languages
  for (final preferredTemplate in preferTemplateLang.entries) {
    var targetIndex = targets.indexOf(preferredTemplate.key),
        templateIndex = targets.indexOf(preferredTemplate.value);
    // handle missing templates or targets used in preferred templates map
    if (templateIndex < 0) {
      templateIndex = targets.length;
      targets.add(preferredTemplate.value);
    }
    if (targetIndex < 0) {
      targetIndex = targets.length;
      targets.add(preferredTemplate.key);
    }
    if (templateIndex > targetIndex) {
      targets.insert(targetIndex, targets.removeAt(templateIndex));
    }
  }

  // subtracted from language count to provide number of languages translated to
  var skippedLanguages = 0;

  for (final target in targets) {
    final source = preferTemplateLang[target]?.toString() ?? defaultSource;
    final translatorService = (preferTranslatorService[target]?.toString() ??
        defaultTranslatorService);
    final templatePath = '$arbDir/${name}_$source.arb';
    if (!modifiedTemplates.containsKey(templatePath)) {
      if (_verboseOutput) {
        stdout.writeln('Reading template file: ${name}_$source.arb');
      }
      final templateFile = File(templatePath);
      final template =
          jsonDecode(templateFile.readAsStringSync()) as Map<String, dynamic>;
      templateMetadata[templatePath] = _getArbMetadata(template);
      // pull comments from metadata on first pass
      if (!templateMetadata.containsKey('comments')) {
        templateMetadata['comments'] =
            (Map.from(templateMetadata[templatePath]!)
              ..removeWhere((key, value) => key.startsWith('@')));
      }
      final origTemplate = Map<String, dynamic>.from(template)
        ..removeWhere((key, value) => key.startsWith('@'));
      originalTemplates[templatePath] = origTemplate;
      modifiedTemplates[templatePath] = _buildTemplate(
        Map.from(origTemplate),
        transformer: transformer,
        arbMetadata: templateMetadata[templatePath]!,
        examples: examples,
      );
    }

    final currentArbContent = <String, dynamic>{};
    final translations = <String, String>{};

    if (_verboseOutput) {
      stdout.writeln('Building list of strings to translate to $target');
    }
    final toTranslate =
        Map<String, dynamic>.from(modifiedTemplates[templatePath]!);
    final previousTranslations = <String, String>{};
    final arbFile = File('$arbDir/${name}_$target.arb');
    // var previousTranslationsCount = 0;
    if (arbFile.existsSync()) {
      if (_verboseOutput) {
        stdout.writeln('Handling existing translations and comments.');
      }
      // cast {} to string to handle arb comments
      currentArbContent.addAll(jsonDecode(arbFile.readAsStringSync()));

      final prevTranslationMap = Map.from(currentArbContent)
        ..removeWhere((key, value) => key.startsWith('@'));
      if (_verboseOutput) {
        for (var entry in prevTranslationMap.entries) {
          assert(entry.key is String,
              'Malformed ARB entry: key `${entry.key}` is not a String');
          assert(entry.value is String,
              'Malformed ARB entry: value of key `${entry.key}` is not a String');
        }
      }
      previousTranslations.addAll(prevTranslationMap.cast());
      // do not translate previously translated phrases unless marked [force]
      toTranslate.removeWhere((key, value) {
        if (key.startsWith('@')) {
          key = key.substring(1, key.lastIndexOf(RegExp(r'#.+?#')));
        }
        return previousTranslations.containsKey(key) &&
            !(templateMetadata[templatePath]!['@$key']?['translator']
                    ?['force'] ??
                false);
      });
      // previousTranslationsCount = (Map.from(previousTranslations)
      //       ..removeWhere((key, value) => key.startsWith('@')))
      //     .length;
      if (_verboseOutput && previousTranslations.isNotEmpty) {
        stdout.writeln(
            'Keeping ${previousTranslations.length} existing translations in ${name}_$target.arb');
      }
      translations.addAll(previousTranslations);
    }

    var changesMade = 0;

    final keys = previousTranslations.keys.toList(growable: false);
    for (final key in keys) {
      if (!originalTemplates[templatePath]!.containsKey(key) &&
          !templateMetadata[templatePath]!.containsKey(key) &&
          !templateMetadata['comments']!.values.contains(key)) {
        currentArbContent.remove(key);
        // TODO: what purpose is this serving? previousTranslations not used after this...
        // TODO: why increasing changesMade??
        if (!key.startsWith('@')) previousTranslations.remove(key);
        changesMade++;
      }
    }

    // add ARB comments
    for (final comment in templateMetadata['comments']!.entries) {
      if (!currentArbContent.containsKey(comment.value)) {
        currentArbContent[comment.value] = {};
        changesMade++;
      }
    }

    if (toTranslate.isEmpty) {
      if (templateMetadata[templatePath]!.containsKey('@@locale') &&
          !currentArbContent.containsKey('@@locale')) {
        changesMade++;
      }
      if (changesMade == 0) {
        skippedLanguages++;
        stdout.writeln('No changes to ${name}_$target.arb');
      } else {
        final output = <String, dynamic>{};
        // add target locale identifier if used in template file
        if (templateMetadata[templatePath]!.containsKey('@@locale')) {
          output['@@locale'] = target.replaceAll('-', '_');
        }
        // match entry order to the original template file
        for (final key in originalTemplates[templatePath]!.keys) {
          // add comments from the original template file
          if (templateMetadata['comments']!.containsKey(key)) {
            output[templateMetadata['comments']![key]] = {};
          }
          output[key] = currentArbContent[key];
        }
        // handle a comment at the end of the file
        if (templateMetadata['comments']!.containsKey('{}')) {
          output[templateMetadata['comments']!['{}']] = {};
        }

        arbFile.writeAsStringSync(encoder.convert(output));
        // var stringOutput = encoder.convert(output);
        // final commentExpr = RegExp(r'"@_.*": {}');
        // final matches = commentExpr.allMatches(stringOutput).toList().reversed;
        // for (var match in matches) {
        //   stringOutput = stringOutput.replaceRange(
        //     match.start,
        //     match.end,
        //     '\n  ${stringOutput.substring(match.start, match.end)}',
        //   );
        // }
        // arbFile.writeAsStringSync(stringOutput);

        stdout.writeln(
          'Nothing to translate to $target. $changesMade other '
          '${changesMade == 1 ? 'change' : 'changes'} made.',
        );
      }
      continue;
    }

    final translator = translators[translatorService]!;

    final timer = _verboseOutput
        ? null
        : Timer.periodic(const Duration(milliseconds: 100), (timer) {
            stdout.write(
              'Translating from $source to $target using ${translator.name} ${Spinner(timer.tick)}\r',
            );
          });

    final results = await translator.translate(
      toTranslate: toTranslate,
      source: source,
      target: target,
      verbose: _verboseOutput,
    );
    for (var result in results.entries) {
      // results.updateAll((key, result) {
      var decodedString = transformer.decode(result.value);
      final exampleMatches =
          RegExp(r'<x>.+?<x>').allMatches(decodedString).toList().reversed;
      for (final match in exampleMatches) {
        final example = decodedString.substring(match.start, match.end);
        final exampleMap = examples[example] ?? {};

        // check for entry specific variable, then fallback to default
        final originalVariable = exampleMap[result.key] ?? exampleMap['_'];
        if (originalVariable != null) {
          decodedString = decodedString.replaceRange(
              match.start, match.end, originalVariable);
        } else {
          // handle edge cases where example is translated by the API
          final correction = await translator.translate(
            toTranslate: {'_': example.replaceAll('<x>', '')},
            source: target,
            target: source,
          );
          final key = '<x>${correction['_']?.toLowerCase()}<x>';
          exampleMap.addAll(examples.entries
              .firstWhere(
                  (entry) => entry.key.toLowerCase() == key.toLowerCase(),
                  orElse: () => MapEntry('_', {'_': key}))
              .value);
          final originalVariable = exampleMap[result.key] ?? exampleMap['_'];
          if (originalVariable != null) {
            decodedString = decodedString.replaceRange(
              match.start,
              match.end,
              originalVariable,
            );
          }
        }
      }
      results[result.key] = decodedString;
    }

    translations.addAll(results);

    if (translations.isNotEmpty) {
      final complexEntries =
          List<MapEntry<String, String>>.from(translations.entries)
              .where((entry) => entry.key.startsWith('@'));
      translations.removeWhere((key, value) => key.startsWith('@'));

      final originalKeys = <String>{};
      for (final entry in complexEntries) {
        originalKeys.add(entry.key.substring(1).split('#').first);
      }

      for (final key in originalKeys) {
        final complexParts =
            complexEntries.where((entry) => entry.key.startsWith('@$key#'));
        translations[key] = transformer.decode(Map.fromEntries(complexParts));
      }

      currentArbContent.addAll(translations);

      final output = <String, dynamic>{};
      // add target locale identifier if used in template file
      if (templateMetadata[templatePath]!.containsKey('@@locale')) {
        output['@@locale'] = target.replaceAll('-', '_');
      }
      // match entry order to the original template file
      for (final key in originalTemplates[templatePath]!.keys) {
        // add comments from the original template file
        if (templateMetadata['comments']!.containsKey(key)) {
          output[templateMetadata['comments']![key]] = {};
        }
        if (currentArbContent.containsKey(key)) {
          output[key] = currentArbContent[key];
        }
      }
      // handle a comment at the end of the file
      if (templateMetadata['comments']!.containsKey('{}')) {
        output[templateMetadata['comments']!['{}']] = {};
      }
      arbFile.writeAsStringSync(encoder.convert(output));
      // var stringOutput = encoder.convert(output);
      // final commentExpr = RegExp(r'"@_.*": {}');
      // final matches = commentExpr.allMatches(stringOutput).toList().reversed;
      // for (var match in matches) {
      //   stringOutput = stringOutput.replaceRange(
      //     match.start,
      //     match.end,
      //     '\n  ${stringOutput.substring(match.start, match.end)}',
      //   );
      // }
      // arbFile.writeAsStringSync(stringOutput);
    }

    timer?.cancel();
    // TODO: fix the issue with showing correct translation counts
    // TODO: force & ignores may be the only outlier issues
    final translationsCount =
        toTranslate.length; // translations.length - previousTranslationsCount;
    stdout.writeln('Translated $translationsCount '
        'entr${translationsCount == 1 ? 'y' : 'ies'} from $source to $target using ${translator.name}.');
  }

  final targetsTranslated = targets.length - skippedLanguages;
  if (targetsTranslated == 0) {
    stdout.writeln('No languages translated');
  } else {
    stdout.writeln(
        'Finished translating to $targetsTranslated language${targetsTranslated > 1 ? 's' : ''}.');
  }
}

Map<String, dynamic> _getArbMetadata(Map<String, dynamic> arbTemplate) {
  final metadata = <String, dynamic>{};
  final keysIterator = arbTemplate.keys.iterator;
  while (keysIterator.moveNext()) {
    final key = keysIterator.current;
    if (key.startsWith('@_')) {
      // add key/value in reverse for easy separation & lookup later
      metadata[keysIterator.moveNext() ? keysIterator.current : '{}'] = key;
    } else if (key.startsWith('@')) {
      metadata[key] = arbTemplate[key];
    }
  }
  return metadata;
}

Map<String, dynamic> _buildTemplate(
  Map<String, dynamic> arbTemplate, {
  required Transformer transformer,
  required Map<String, dynamic> arbMetadata,
  required Map<String, Map<String, String>> examples,
}) {
  // remove strings that are marked ignore
  arbTemplate.removeWhere((key, value) =>
      (arbMetadata['@$key']?['translator']?['ignore'] ?? false));

  final entries = List<MapEntry<String, dynamic>>.from(arbTemplate.entries);
  for (final entry in entries) {
    try {
      var entryValue = entry.value as String;
      final Map<String, Map<String, dynamic>> placeholders =
          Map.from(arbMetadata['@${entry.key}']?['placeholders'] ?? {});
      placeholders.removeWhere((key, value) => value['example'] == null);
      for (final placeholder in placeholders.entries) {
        /* The prologue and epilogue are <x> since these tags avoid bugs.
        For instance use of symbols like _'s can lead to the symbol vanishing
        if the placeholder is moved to the beginning of the sentence.
        Similarly '<' on it's own has potential issues of DeepL changing the
        symbol into ⟨ ⟩. However it is possible to specify that <x>
        (or some custom XML-like tags) should be left untouched.
        */
        final key = '<x>${placeholder.value['example']}<x>';
        final value = '{${placeholder.key}}';

        // create a default catch all if example hasn't been used to reduce space
        // complexity when the same placeholder name is used with the same example
        // throughout the ARB file
        final exampleMap = examples[key] ?? {'_': value};
        if (exampleMap['_'] != value) {
          exampleMap[entry.key] = value;
          examples[key] = exampleMap;
        } else {
          examples.putIfAbsent(key, () => exampleMap);
        }

        entryValue = entryValue.replaceAll('{${placeholder.key}}', key);
      }
      final encodedValue = transformer.encode(entryValue);
      if (encodedValue is String) {
        arbTemplate[entry.key] = encodedValue;
      } else {
        arbTemplate.remove(entry.key);
        for (final encodedEntry in (encodedValue as Map).entries) {
          arbTemplate['@${entry.key}#${encodedEntry.key}'] = encodedEntry.value;
        }
      }
    } on InvalidFormatException {
      throw InvalidFormatException(entry.key);
    }
  }

  return arbTemplate;
}
